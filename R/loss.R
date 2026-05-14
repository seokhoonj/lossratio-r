#' Fit a loss projection on a Triangle
#'
#' @description
#' Project cumulative loss across the cohort x development grid. Three
#' methods are supported via `method`:
#'
#' \describe{
#'   \item{`"sa"` (default)}{Stage-adaptive. Exposure-driven (ED) before
#'     the maturity point, chain ladder (CL) after.}
#'   \item{`"ed"`}{Pure exposure-driven (additive) across all dev
#'     periods.}
#'   \item{`"cl"`}{Pure Mack chain ladder (multiplicative).}
#' }
#'
#' This function is the *loss-side* counterpart to [fit_premium()] in
#' the role-specific dispatcher layer (see `ARCHITECTURE.md`). It owns
#' loss projection only -- premium projection is delegated to
#' [fit_premium()] (called internally when `premium_fit = NULL`), and
#' the loss-ratio composition with delta method is handled by [fit_lr()].
#'
#' @param x A `"Triangle"` object. The standardized `"loss"` and
#'   `"premium"` columns are used (`build_triangle()` produces these).
#' @param method One of `"sa"` (default), `"ed"`, or `"cl"`.
#' @param alpha Variance-structure exponent for the loss fit. Default `1`.
#' @param regime Optional regime specification applied to both loss-side
#'   and premium-side estimation. Accepts four input types:
#'   \describe{
#'     \item{`NULL` (default)}{No regime filter.}
#'     \item{`Regime` object}{Use as-is. Typically built via
#'       [detect_regime()] or [regime_at()].}
#'     \item{`"auto"`}{Detect regime internally via `detect_regime(x)` on
#'       the input triangle.}
#'     \item{Function / closure}{A user-supplied function taking the
#'       triangle and returning a `Regime` object (or `NULL`).}
#'   }
#'   Behavior depends on `method`: SA uses a hybrid 2-pass filter (cohort
#'   cut for the ED phase, calendar-diagonal wedge for the CL phase);
#'   ED/CL use a simple cohort cut. The same resolved `Regime` is applied
#'   to the internal `fit_premium()` call -- callers needing an
#'   asymmetric loss/premium split should use [fit_lr()] instead.
#' @param premium_fit Optional pre-built `PremiumFit` (from
#'   [fit_premium()]) supplying the premium projection. When `NULL`,
#'   `fit_loss()` calls `fit_premium()` internally using
#'   `premium_method`, `premium_alpha`, and the resolved `regime`.
#' @param premium_method One of `"cl"` (default) or `"ed"`. Used only
#'   when `premium_fit = NULL`. The default matches the historical
#'   `fit_lr()` premium choice.
#' @param premium_alpha Variance-structure exponent for the premium fit.
#'   Default `1`.
#' @param sigma_method Sigma extrapolation. One of `"locf"` (default),
#'   `"min_last2"`, `"loglinear"`.
#' @param recent Optional positive integer; calendar-diagonal filter.
#' @param maturity Optional maturity specification. Accepts four input
#'   types:
#'   \describe{
#'     \item{`NULL`}{No maturity filter. SA mode requires a maturity, so
#'       this disables only ED / CL modes.}
#'     \item{`Maturity` object}{Use as-is. Typically built via
#'       [detect_maturity()] or [maturity_at()].}
#'     \item{`"auto"` (default)}{Detect maturity internally via
#'       `detect_maturity(x)` on the input triangle.}
#'     \item{Function / closure}{A user-supplied function taking the
#'       triangle and returning a `Maturity` object (e.g. from
#'       [maturity_spec()]) for deferred custom-config detection.}
#'   }
#' @param conf_level Confidence level for analytical CI on the loss
#'   projection (`loss_ci_lower`, `loss_ci_upper`). Default `0.95`.
#'
#' @return An object of class `"LossFit"`. List with components:
#'   `full`, `proj`, `maturity`, `loss_ata_fit`, `premium_ata_fit`,
#'   `premium_fit`, `ed`, `factor`, `selected`, plus metadata.
#'
#' @section Internal columns:
#' `$full` retains internal parameter columns (`g_selected`, `g_sigma2`,
#' `g_var`, `f_selected`, `f_sigma2`, `f_var`, `last_obs`) so that
#' [fit_lr()] can run bootstrap CI on top without re-fitting. Standalone
#' callers see them as implementation columns.
#'
#' @seealso [fit_premium()], [fit_lr()], [fit_cl()], [fit_ed()].
#'
#' @examples
#' \dontrun{
#' data(experience)
#' tri <- build_triangle(
#'   experience[coverage == "SUR"],
#'   groups   = "coverage",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "loss_incr",
#'   premium  = "premium_incr"
#' )
#'
#' lf    <- fit_loss(tri)                    # SA (default)
#' lf_ed <- fit_loss(tri, method = "ed")
#' lf_cl <- fit_loss(tri, method = "cl")
#' }
#'
#' @export
fit_loss <- function(x,
                     method         = c("sa", "ed", "cl"),
                     alpha          = 1,
                     regime         = NULL,
                     premium_fit    = NULL,
                     premium_method = c("cl", "ed"),
                     premium_alpha  = 1,
                     sigma_method   = c("locf", "min_last2", "loglinear"),
                     recent         = NULL,
                     maturity       = "auto",
                     conf_level     = 0.95) {

  .assert_triangle_input(x, "fit_loss()")
  method         <- match.arg(method)
  sigma_method   <- match.arg(sigma_method)
  premium_method <- match.arg(premium_method)

  if (!is.null(premium_fit) && !inherits(premium_fit, "PremiumFit"))
    stop("`premium_fit` must be a PremiumFit object or NULL.",
         call. = FALSE)

  if (!is.numeric(conf_level) || length(conf_level) != 1L ||
      is.na(conf_level) || conf_level <= 0 || conf_level >= 1)
    stop("`conf_level` must be a single numeric value in (0, 1).",
         call. = FALSE)

  # Resolve regime input (NULL / Regime / "auto" / function) -> NULL or Regime
  regime <- .resolve_regime(regime, x)

  # Resolve maturity input (NULL / Maturity / "auto" / function) -> NULL or Maturity
  maturity <- .resolve_maturity(maturity, x)

  # 1) Triangle structural attrs ----------------------------------------
  # Apply maturity-group rebucket up-front so all downstream code
  # (filter capture of `grp`, fit_ata, .apply_*_filter, projection joins)
  # sees a consistent partition. fit_ata's own rebucket becomes a no-op
  # via setequal short-circuit in .rebucket_triangle_groups.
  if (!is.null(maturity)) {
    m_groups <- attr(maturity, "groups")
    if (is.null(m_groups)) {
      stat_cols <- c("change", "ata_from", "ata_link", "mean", "median", "wt",
                     "cv", "f", "f_se", "rse", "sigma", "n_obs", "n_valid",
                     "n_inf", "n_nan", "valid_ratio")
      m_groups <- setdiff(names(maturity), stat_cols)
    }
    data_groups <- attr(x, "groups")
    if (is.null(data_groups)) data_groups <- character(0)
    if (length(m_groups) > 0L && !setequal(m_groups, data_groups)) {
      x <- .rebucket_triangle_groups(x, m_groups)
    }
  }

  # Triangle is guaranteed to carry standardized `loss` / `premium`
  # columns (build_triangle convention).
  grp <- attr(x, "groups")
  coh <- attr(x, "cohort")
  dev <- attr(x, "dev")

  if (is.null(grp)) grp <- character(0)

  if (length(coh) != 1L)
    stop("`x` must contain exactly one `cohort`.", call. = FALSE)
  if (length(dev) != 1L)
    stop("`x` must contain exactly one `dev`.", call. = FALSE)

  # preserve pre-filter triangle for downstream `$usage` annotation
  x_full      <- data.table::copy(x)
  # preserve original user input — nullified below for SA hybrid path
  regime_user <- regime
  recent_user <- recent

  # 2) SA hybrid filter (loss-side, 2-pass maturity) ---------------------
  if (!is.null(regime)) {
    cd <- .resolve_regime_change_date(regime, by = grp)

    if (!is.null(cd) && method == "sa") {
      pre_loss_fit <- fit_ata(
        x,
        target       = "loss",
        alpha        = alpha,
        sigma_method = sigma_method,
        maturity     = maturity
      )
      m_dt <- pre_loss_fit$maturity

      if (is.null(m_dt) || nrow(m_dt) == 0L) {
        warning(
          "regime: cannot detect maturity; falling back to ",
          "simple cohort cut.", call. = FALSE
        )
        x <- .apply_regime_filter(
          x, regime,
          grp = grp,
          coh = "cohort",
          dev = "dev"
        )
        regime <- NULL
      } else {
        # Per-group `m_k` for SA hybrid: each group uses its own
        # maturity (ED/CL boundary). With multi-group `regime`, this
        # means a group with a fast maturity (small k*) only cuts its
        # narrow ED region, retaining pre-break CL data for factor
        # estimation. (Earlier `max(k*)` fallback over-cut
        # fast-maturing groups.)
        m_k_vec <- m_dt$change

        dev_split_arg <- if (length(grp) > 0L &&
                             length(unique(m_k_vec)) > 1L) {
          m_k_dt <- m_dt[, c(grp, "change"), with = FALSE]
          data.table::setnames(m_k_dt, "change", "dev_split")
          m_k_dt
        } else {
          max(m_k_vec, na.rm = TRUE)
        }

        x <- .apply_regime_filter(
          x, regime,
          grp       = grp,
          coh       = "cohort", dev = "dev",
          dev_split = dev_split_arg
        )
        if (!is.null(recent)) {
          x <- .apply_recent_filter(
            x, recent,
            grp       = grp,
            coh       = "cohort", dev = "dev",
            dev_split = dev_split_arg
          )
          recent <- NULL
        }
        regime <- NULL
      }
    }
    # method = "ed"/"cl": leave regime for fit_ata/fit_intensity
  }

  # 3) resolve premium_fit -----------------------------------------------
  # fit_loss is single-role -- the same regime applies to the internal
  # premium fit. Asymmetric loss/premium splits live at fit_lr().
  if (is.null(premium_fit)) {
    premium_fit <- fit_premium(
      x,
      method       = premium_method,
      alpha        = premium_alpha,
      sigma_method = sigma_method,
      regime       = regime_user
    )
  }
  # Wrap as ATAFit-shaped object for downstream .expand_grid / join paths.
  premium_ata_fit <- structure(
    list(
      selected     = premium_fit$selected,
      link         = premium_fit$link,
      data         = premium_fit$data,
      method       = "mack",
      alpha        = premium_alpha,
      sigma_method = sigma_method,
      maturity     = NULL
    ),
    class = "ATAFit"
  )

  # 4) loss ATA + Mack f_var ---------------------------------------------
  loss_ata_fit <- fit_ata(
    x,
    target       = "loss",
    alpha        = alpha,
    sigma_method = sigma_method,
    recent       = recent,
    regime       = regime,
    maturity     = maturity
  )
  loss_ata_fit$selected <- .mack_f_var(
    ata_fit = loss_ata_fit,
    alpha   = alpha
  )

  # 5) ED intensities g_k + Mack g_var -----------------------------------
  intensity_fit <- fit_intensity(
    x,
    target       = "loss",
    exposure     = "premium",
    alpha        = alpha,
    sigma_method = sigma_method,
    recent       = recent,
    regime       = regime
  )
  ed_fit <- list(
    method       = "mack",
    link         = intensity_fit$link,
    factor       = intensity_fit$factor,
    selected     = intensity_fit$selected,
    alpha        = alpha,
    sigma_method = sigma_method,
    recent       = recent,
    regime       = regime
  )
  class(ed_fit) <- "EDFit"
  ed_fit$selected <- .mack_g_var(ed_fit = ed_fit, alpha = alpha)

  # 6) maturity point per group ------------------------------------------
  maturity <- loss_ata_fit$maturity

  # 7) expand triangle to full projection grid --------------------------
  full <- .expand_grid(
    triangle        = x,
    ed_fit          = ed_fit,
    premium_ata_fit = premium_ata_fit,
    target          = "loss",
    exposure        = "premium"
  )

  # 8) join ED factors (g_selected, g_sigma2, g_var) --------------------
  ed_cols <- c(grp, "ata_from", "g_selected", "sigma2", "g_var")
  ed_sel  <- ed_fit$selected[, .SD, .SDcols = ed_cols]
  data.table::setnames(ed_sel, "ata_from", "dev")
  data.table::setnames(ed_sel, "sigma2", "g_sigma2")
  full <- ed_sel[full, on = c(grp, "dev")]

  # 9) join CL factors (f_selected, f_sigma2, f_var) --------------------
  cl_cols <- c(grp, "ata_from", "f_selected", "sigma2", "f_var")
  cl_sel  <- loss_ata_fit$selected[, .SD, .SDcols = cl_cols]
  data.table::setnames(cl_sel, "ata_from", "dev")
  data.table::setnames(cl_sel, "sigma2", "f_sigma2")
  full <- cl_sel[full, on = c(grp, "dev")]

  # 10) maturity join per group -----------------------------------------
  if (!is.null(maturity)) {
    m_join <- .ensure_dt(maturity)
    m_keep <- c(grp, "ata_from")
    m_join <- m_join[, .SD, .SDcols = intersect(m_keep, names(m_join))]
    data.table::setnames(m_join, "ata_from", "maturity_from")

    if (length(grp)) {
      full <- m_join[full, on = grp]
    } else {
      if (nrow(m_join) == 1L) {
        full[, ("maturity_from") := m_join$maturity_from[1L]]
      } else {
        full[, ("maturity_from") := NA_real_]
      }
    }
  } else {
    full[, ("maturity_from") := NA_real_]
  }

  # 11) last_obs per cohort ---------------------------------------------
  full[, ("last_obs") := {
    idx <- which(is.finite(loss_obs))
    if (length(idx)) max(idx) else 0L
  }, by = c(grp, "cohort")]

  # 12) loss point projection -------------------------------------------
  full[, ("loss_proj") := .sa_proj(
    loss_obs      = loss_obs,
    premium_proj  = premium_proj,
    g_selected    = g_selected,
    f_selected    = f_selected,
    maturity_from = maturity_from[1L],
    method        = method
  ), by = c(grp, "cohort")]

  # 13) loss variance (process + parameter) ----------------------------
  full[, `:=`(
    loss_proc_se2  = .sa_proc_var(
      loss_proj     = loss_proj,
      premium_proj  = premium_proj,
      g_sigma2      = g_sigma2,
      f_sigma2      = f_sigma2,
      f_selected    = f_selected,
      last_obs      = last_obs[1L],
      maturity_from = maturity_from[1L],
      alpha         = alpha,
      method        = method
    ),
    loss_param_se2 = .sa_param_var(
      loss_proj     = loss_proj,
      premium_proj  = premium_proj,
      g_var         = g_var,
      f_var         = f_var,
      f_selected    = f_selected,
      last_obs      = last_obs[1L],
      maturity_from = maturity_from[1L],
      method        = method
    )
  ), by = c(grp, "cohort")]

  # 14) total loss variance and SE -------------------------------------
  full[, ("loss_total_se2") := loss_proc_se2 + loss_param_se2]

  full[, `:=`(
    loss_proc_se  = sqrt(loss_proc_se2),
    loss_param_se = sqrt(loss_param_se2),
    loss_total_se = sqrt(loss_total_se2)
  )]

  full[, ("loss_total_cv") := data.table::fifelse(
    is.finite(loss_proj) & loss_proj != 0,
    loss_total_se / abs(loss_proj), NA_real_
  )]

  # 15) analytical CI on loss only ------------------------------------
  z_alpha <- stats::qnorm((1 + conf_level) / 2)
  full[, `:=`(
    loss_ci_lower = pmax(0, loss_proj - z_alpha * loss_total_se),
    loss_ci_upper = loss_proj + z_alpha * loss_total_se
  )]

  # 16) incremental projections (loss + premium) ----------------------
  full[, ("loss_incr_proj") := loss_proj - data.table::shift(loss_proj, 1L, fill = 0),
       by = c(grp, "cohort")]
  full[, ("premium_incr_proj") := premium_proj - data.table::shift(premium_proj, 1L, fill = 0),
       by = c(grp, "cohort")]

  # 17) $proj: NA-mask observed cells (loss-side columns only) --------
  proj    <- data.table::copy(full)
  na_cols <- c(
    "loss_proj", "premium_proj",
    "loss_incr_proj", "premium_incr_proj",
    "loss_proc_se2", "loss_param_se2", "loss_total_se2",
    "loss_proc_se",  "loss_param_se",  "loss_total_se",
    "loss_total_cv",
    "loss_ci_lower", "loss_ci_upper"
  )
  proj[is_observed == TRUE, (na_cols) := NA_real_]

  # 18) assemble LossFit ----------------------------------------------
  # NOTE: $full retains internal columns (g_selected, g_sigma2, g_var,
  # f_selected, f_sigma2, f_var, last_obs) so that fit_lr can run
  # bootstrap CI without re-fitting. fit_lr drops them after bootstrap.
  out <- list(
    call            = match.call(),
    data            = x,
    groups          = grp,
    cohort          = coh,
    dev             = dev,
    full            = full,
    proj            = proj,
    maturity        = maturity,
    loss_ata_fit    = loss_ata_fit,
    premium_ata_fit = premium_ata_fit,
    premium_fit     = premium_fit,
    ed              = ed_fit$link,
    factor          = ed_fit$factor,
    selected        = ed_fit$selected,
    method          = method,
    alpha           = alpha,
    sigma_method    = sigma_method,
    recent          = recent_user,
    regime          = regime_user,
    conf_level      = conf_level
  )

  class(out) <- "LossFit"
  out
}


#' Print method for `LossFit`
#' @param x A `LossFit` object.
#' @param ... Unused.
#' @export
print.LossFit <- function(x, ...) {
  grp <- x$groups
  if (is.null(grp)) grp <- character(0)

  cat("<LossFit>\n")
  cat("method       :", x$method,       "\n")
  cat("alpha        :", x$alpha,        "\n")
  cat("sigma_method :", x$sigma_method, "\n")
  cat("recent       :",
      if (!is.null(x$recent)) x$recent else "all", "\n")
  cat("regime       :")
  if (is.null(x$regime)) {
    cat(" none\n")
  } else if (inherits(x$regime, "Regime")) {
    cat("\n"); print(x$regime)
  } else {
    cat(" ", format(x$regime), "\n", sep = "")
  }

  if (!is.null(x$maturity) && nrow(x$maturity)) {
    mat <- .ensure_dt(x$maturity)
    if (length(grp)) {
      grp_txt <- vapply(seq_len(nrow(mat)), function(i)
        paste(mat[i, grp, with = FALSE], collapse = "/"), character(1L))
      rows <- .format_record_table(
        list(
          label = sprintf("maturity[%s]", grp_txt),
          value = sprintf(": %d", mat$change)
        ),
        justify = c("left", "left"),
        sep     = " "
      )
      for (row in rows) cat(row, "\n", sep = "")
    } else {
      cat("maturity     :", mat$change[1L], "\n")
    }
  }

  if (length(grp)) {
    cat("groups       :", paste(grp, collapse = ", "), "\n")
  } else {
    cat("groups       : none\n")
  }

  cat("n_cohorts    :", length(unique(x$full$cohort)), "\n")
  invisible(x)
}


#' Summary method for `LossFit`
#'
#' @description
#' Per-cohort ultimate loss, SE, and CV.
#'
#' @param object A `LossFit` object.
#' @param ... Unused.
#' @export
summary.LossFit <- function(object, ...) {
  grp <- object$groups
  if (is.null(grp)) grp <- character(0)

  full <- .ensure_dt(object$full)
  by_cols <- c(grp, "cohort")
  out <- full[, .SD[which.max(dev)], by = by_cols]
  keep <- c(by_cols, "loss_proj", "loss_total_se", "loss_total_cv")
  out <- out[, .SD, .SDcols = keep]
  data.table::setnames(out,
    c("loss_proj", "loss_total_se", "loss_total_cv"),
    c("ultimate",  "ultimate_se",   "ultimate_cv"))
  out[]
}


# Projection helpers --------------------------------------------------------

#' Hybrid point projection for a single cohort
#'
#' @description
#' Internal helper that projects cumulative loss:
#'
#' \itemize{
#'   \item \strong{sa (stage-adaptive)}: ED before maturity, CL after.
#'   \item \strong{ed}: ED for all periods.
#'   \item \strong{cl}: CL for all periods.
#' }
#'
#' @param loss_obs Numeric vector of observed cumulative loss.
#' @param premium_proj Numeric vector of projected cumulative exposure.
#' @param g_selected Numeric vector of ED intensities.
#' @param f_selected Numeric vector of CL factors.
#' @param maturity_from Numeric scalar; switch point. `NA` = no switch.
#' @param method One of `"sa"`, `"ed"`, or `"cl"`.
#'
#' @return A numeric vector with projected cumulative loss.
#'
#' @keywords internal
.sa_proj <- function(loss_obs,
                     premium_proj,
                     g_selected,
                     f_selected,
                     maturity_from,
                     method = "sa") {

  n        <- length(loss_obs)
  last_obs <- max(which(is.finite(loss_obs)), 0L)

  if (last_obs == 0L || last_obs == n) return(loss_obs)

  v <- loss_obs

  # determine switch point
  mat <- if (method == "sa" && is.finite(maturity_from)) {
    maturity_from
  } else if (method == "cl") {
    0   # always CL
  } else {
    Inf # always ED
  }

  for (i in seq(last_obs + 1L, n)) {
    k <- i - 1L
    v_prev <- v[i - 1L]

    if (!is.finite(v_prev)) next

    if (k < mat) {
      # ED phase: additive, exposure-driven
      g_now <- g_selected[k]
      e_now <- premium_proj[k]

      if (is.finite(g_now) && is.finite(e_now)) {
        v[i] <- v_prev + g_now * e_now
      }
    } else {
      # CL phase: multiplicative, loss-driven
      f_now <- f_selected[k]

      if (is.finite(f_now)) {
        v[i] <- f_now * v_prev
      }
    }
  }

  v
}


#' Hybrid process variance for a single cohort
#'
#' @description
#' Internal helper for process variance:
#'
#' \itemize{
#'   \item ED phase (additive):
#'     \eqn{\text{proc}_{k+1} = \text{proc}_k
#'       + g_{\sigma^2,k} \cdot (C^P_k)^\alpha}
#'   \item CL phase (multiplicative, Mack):
#'     \eqn{\text{proc}_{k+1} = f_k^2 \cdot \text{proc}_k
#'       + f_{\sigma^2,k} \cdot (C^L_k)^\alpha}
#' }
#'
#' @keywords internal
.sa_proc_var <- function(loss_proj,
                         premium_proj,
                         g_sigma2,
                         f_sigma2,
                         f_selected,
                         last_obs,
                         maturity_from,
                         alpha  = 1,
                         method = "sa") {

  n    <- length(loss_proj)
  proc <- numeric(n)

  if (last_obs == n) return(proc)

  mat <- if (method == "sa" && is.finite(maturity_from)) {
    maturity_from
  } else if (method == "cl") {
    0
  } else {
    Inf
  }

  for (i in seq(last_obs + 1L, n)) {
    k <- i - 1L

    if (k < mat) {
      # ED phase: additive variance
      s2  <- g_sigma2[k]
      e_k <- premium_proj[k]

      proc[i] <- proc[i - 1L]
      if (is.finite(s2) && is.finite(e_k) && e_k > 0) {
        proc[i] <- proc[i] + s2 * e_k^alpha
      }
    } else {
      # CL phase: multiplicative variance (Mack)
      f_k <- f_selected[k]
      s2  <- f_sigma2[k]
      v_k <- loss_proj[k]

      if (!is.finite(f_k)) { proc[i] <- proc[i - 1L]; next }

      proc[i] <- f_k^2 * proc[i - 1L]
      if (is.finite(s2) && is.finite(v_k) && v_k > 0) {
        proc[i] <- proc[i] + s2 * v_k^alpha
      }
    }
  }

  proc
}


#' Hybrid parameter variance for a single cohort
#'
#' @description
#' Internal helper for parameter variance:
#'
#' \itemize{
#'   \item ED phase:
#'     \eqn{\text{param}_{k+1} = \text{param}_k
#'       + (C^P_k)^2 \cdot \mathrm{Var}(\hat{g}_k)}
#'   \item CL phase:
#'     \eqn{\text{param}_{k+1} = f_k^2 \cdot \text{param}_k
#'       + (C^L_k)^2 \cdot \mathrm{Var}(\hat{f}_k)}
#' }
#'
#' @keywords internal
.sa_param_var <- function(loss_proj,
                          premium_proj,
                          g_var,
                          f_var,
                          f_selected,
                          last_obs,
                          maturity_from,
                          method = "sa") {

  n     <- length(loss_proj)
  param <- numeric(n)

  if (last_obs == n) return(param)

  mat <- if (method == "sa" && is.finite(maturity_from)) {
    maturity_from
  } else if (method == "cl") {
    0
  } else {
    Inf
  }

  for (i in seq(last_obs + 1L, n)) {
    k <- i - 1L

    if (k < mat) {
      # ED phase: additive
      gv  <- g_var[k]
      e_k <- premium_proj[k]

      param[i] <- param[i - 1L]
      if (is.finite(gv) && is.finite(e_k)) {
        param[i] <- param[i] + e_k^2 * gv
      }
    } else {
      # CL phase: multiplicative (Mack)
      f_k  <- f_selected[k]
      fv   <- f_var[k]
      v_k  <- loss_proj[k]

      if (!is.finite(f_k)) { param[i] <- param[i - 1L]; next }

      param[i] <- f_k^2 * param[i - 1L]
      if (is.finite(fv) && is.finite(v_k)) {
        param[i] <- param[i] + v_k^2 * fv
      }
    }
  }

  param
}


#' Expand a `Triangle` object to a full projection grid
#'
#' @keywords internal
.expand_grid <- function(triangle,
                         ed_fit,
                         premium_ata_fit,
                         target,
                         exposure) {

  grp <- attr(triangle, "groups")

  if (is.null(grp)) grp <- character(0)

  raw <- .ensure_dt(triangle)

  obs <- raw[, .(
    loss_obs    = .SD[[target]],
    premium_obs = .SD[[exposure]]
  ), by = c(grp, "cohort", "dev")]

  max_dev_ed   <- max(ed_fit$selected$ata_to, na.rm = TRUE)
  max_dev_prem <- max(premium_ata_fit$selected$ata_to, na.rm = TRUE)
  max_dev      <- max(max_dev_ed, max_dev_prem)

  full <- unique(obs[, .SD, .SDcols = c(grp, "cohort")])
  full <- full[, .(dev = seq_len(max_dev)), by = c(grp, "cohort")]

  full <- obs[full, on = c(grp, "cohort", "dev")]
  data.table::setorderv(full, c(grp, "cohort", "dev"))

  full[, ("is_observed") := is.finite(loss_obs)]

  # Attach segment_id when either side of the projection was fitted
  # segment_wise. ED loss-side regime is on ed_fit; premium-side regime
  # is on premium_ata_fit. If both are segment_wise they share the same
  # Regime in practice (fit_ed passes its regime down to fit_cl), so
  # one assignment is sufficient.
  has_seg_ed   <- "segment_id" %in% names(ed_fit$selected)
  has_seg_prem <- "segment_id" %in% names(premium_ata_fit$selected)
  if (has_seg_ed || has_seg_prem) {
    reg <- if (has_seg_ed) ed_fit$regime else premium_ata_fit$regime
    grp_dt <- if (length(grp)) full[, grp, with = FALSE] else NULL
    full[, ("segment_id") := .assign_segment(cohort, reg, grp_dt)]
  }

  prem_cols <- c(grp, "ata_from",
                 if (has_seg_prem) "segment_id",
                 "f_selected")
  prem_sel <- premium_ata_fit$selected[, .SD, .SDcols = prem_cols]
  data.table::setnames(prem_sel, c("ata_from", "f_selected"),
                       c("dev", "f_exposure"))
  full <- prem_sel[full,
                   on = c(grp, "dev", if (has_seg_prem) "segment_id")]

  full[, ("premium_proj") := .cl_proj(
    target_obs = premium_obs,
    f_selected = f_exposure
  ), by = c(grp, "cohort")]

  full[, ("f_exposure") := NULL]
  full
}
