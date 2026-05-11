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
#' @param loss_regime_break Optional cohort cutoff for the loss-side regime
#'   break. `NULL` (default), a `Date`/character coercible to Date, a vector
#'   of dates (uses the latest), or a `Regime` object. Behavior depends on
#'   `method`: SA uses a hybrid 2-pass filter (cohort cut for ED phase,
#'   calendar-diagonal wedge for CL phase); ED/CL use a simple cohort cut.
#' @param premium_fit Optional pre-built `PremiumFit` (from
#'   [fit_premium()]) supplying the premium projection. When `NULL`,
#'   `fit_loss()` calls `fit_premium()` internally using
#'   `premium_method`, `premium_alpha`, and `premium_regime_break`.
#' @param premium_method One of `"cl"` (default) or `"ed"`. Used only
#'   when `premium_fit = NULL`. The default matches the historical
#'   `fit_lr()` premium choice.
#' @param premium_alpha Variance-structure exponent for the premium fit.
#'   Default `1`.
#' @param premium_regime_break Premium-side regime break. Defaults to
#'   `loss_regime_break` (loss-side and premium-side share a cutoff unless
#'   explicitly separated).
#' @param sigma_method Sigma extrapolation. One of `"locf"` (default),
#'   `"min_last2"`, `"loglinear"`.
#' @param recent Optional positive integer; calendar-diagonal filter.
#' @param maturity_args A named list forwarded to [detect_maturity()],
#'   or `NULL` (default) to skip maturity filtering. SA auto-defaults to
#'   `list()`.
#' @param conf_level Confidence level for analytical CI on the loss
#'   projection (`loss_ci_lower`, `loss_ci_upper`). Default `0.95`.
#'
#' @return An object of class `"LossFit"`. List with components:
#'   `full`, `pred`, `maturity`, `loss_ata_fit`, `premium_ata_fit`,
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
#' tri <- build_triangle(experience[coverage == "SUR"], group_var = coverage)
#'
#' lf    <- fit_loss(tri)                    # SA (default)
#' lf_ed <- fit_loss(tri, method = "ed")
#' lf_cl <- fit_loss(tri, method = "cl")
#' }
#'
#' @export
fit_loss <- function(x,
                     method               = c("sa", "ed", "cl"),
                     alpha                = 1,
                     loss_regime_break    = NULL,
                     premium_fit          = NULL,
                     premium_method       = c("cl", "ed"),
                     premium_alpha        = 1,
                     premium_regime_break = loss_regime_break,
                     sigma_method         = c("locf", "min_last2", "loglinear"),
                     recent               = NULL,
                     maturity_args        = NULL,
                     conf_level           = 0.95) {

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

  # sa requires maturity detection; default to list() if not supplied
  if (method == "sa" && is.null(maturity_args)) {
    maturity_args <- list()
  }

  # 1) standardized columns + Triangle structural attrs ------------------
  # Triangle is guaranteed to carry standardized `loss` / `premium`
  # columns (build_triangle convention). No need to accept column args.
  l_var <- "loss"
  p_var <- "premium"

  grp_var <- attr(x, "group_var")
  coh_var <- attr(x, "cohort_var")
  dev_var <- attr(x, "dev_var")

  if (is.null(grp_var)) grp_var <- character(0)

  if (length(coh_var) != 1L)
    stop("`x` must contain exactly one `cohort_var`.", call. = FALSE)
  if (length(dev_var) != 1L)
    stop("`x` must contain exactly one `dev_var`.", call. = FALSE)

  # preserve original user input — nullified below for SA hybrid path
  loss_regime_break_user <- loss_regime_break
  recent_user            <- recent

  # 2) SA hybrid filter (loss-side, 2-pass maturity) ---------------------
  if (!is.null(loss_regime_break)) {
    bd <- .resolve_break_date(loss_regime_break)

    if (!is.null(bd) && method == "sa") {
      pre_loss_fit <- fit_ata(
        x,
        target        = l_var,
        alpha         = alpha,
        sigma_method  = sigma_method,
        maturity_args = maturity_args
      )
      mat_dt <- pre_loss_fit$maturity

      if (is.null(mat_dt) || nrow(mat_dt) == 0L) {
        warning(
          "loss_regime_break: cannot detect maturity; falling back to ",
          "simple cohort cut.", call. = FALSE
        )
        x <- .apply_break_filter(
          x, loss_regime_break,
          group_var  = grp_var,
          cohort_var = "cohort",
          dev_var    = "dev"
        )
        loss_regime_break <- NULL
      } else {
        mat_k <- mat_dt$ata_to
        if (length(unique(mat_k)) > 1L) {
          warning(
            "loss_regime_break: maturity differs across groups; using max mat_k.",
            call. = FALSE
          )
        }
        mat_k <- max(mat_k)

        x <- .apply_break_filter(
          x, loss_regime_break,
          group_var  = grp_var,
          cohort_var = "cohort", dev_var = "dev",
          dev_split  = mat_k
        )
        if (!is.null(recent)) {
          x <- .apply_recent_filter(
            x, recent,
            group_var  = grp_var,
            cohort_var = "cohort", dev_var = "dev",
            dev_split  = mat_k
          )
          recent <- NULL
        }
        loss_regime_break <- NULL
      }
    }
    # method = "ed"/"cl": leave loss_regime_break for fit_ata/fit_intensity
  }

  # 3) resolve premium_fit -----------------------------------------------
  if (is.null(premium_fit)) {
    premium_fit <- fit_premium(
      x,
      method       = premium_method,
      alpha        = premium_alpha,
      sigma_method = sigma_method,
      regime_break = premium_regime_break
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
    target        = l_var,
    alpha         = alpha,
    sigma_method  = sigma_method,
    recent        = recent,
    regime_break  = loss_regime_break,
    maturity_args = maturity_args
  )
  loss_ata_fit$selected <- .mack_f_var(
    ata_fit = loss_ata_fit,
    alpha   = alpha
  )

  # 5) ED intensities g_k + Mack g_var -----------------------------------
  intensity_fit <- fit_intensity(
    x,
    target       = l_var,
    exposure     = p_var,
    alpha        = alpha,
    sigma_method = sigma_method,
    recent       = recent,
    regime_break = loss_regime_break
  )
  ed_fit <- list(
    method       = "mack",
    link         = intensity_fit$link,
    factor       = intensity_fit$factor,
    selected     = intensity_fit$selected,
    alpha        = alpha,
    sigma_method = sigma_method,
    recent       = recent,
    regime_break = loss_regime_break
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
    target_var      = l_var,
    exposure_var    = p_var
  )

  # 8) join ED factors (g_selected, g_sigma2, g_var) --------------------
  ed_cols <- c(grp_var, "ata_from", "g_selected", "sigma2", "g_var")
  ed_sel  <- ed_fit$selected[, .SD, .SDcols = ed_cols]
  data.table::setnames(ed_sel, "ata_from", "dev")
  data.table::setnames(ed_sel, "sigma2", "g_sigma2")
  full <- ed_sel[full, on = c(grp_var, "dev")]

  # 9) join CL factors (f_selected, f_sigma2, f_var) --------------------
  cl_cols <- c(grp_var, "ata_from", "f_selected", "sigma2", "f_var")
  cl_sel  <- loss_ata_fit$selected[, .SD, .SDcols = cl_cols]
  data.table::setnames(cl_sel, "ata_from", "dev")
  data.table::setnames(cl_sel, "sigma2", "f_sigma2")
  full <- cl_sel[full, on = c(grp_var, "dev")]

  # 10) maturity join per group -----------------------------------------
  if (!is.null(maturity)) {
    mat_join <- .ensure_dt(maturity)
    mat_keep <- c(grp_var, "ata_from")
    mat_join <- mat_join[, .SD, .SDcols = intersect(mat_keep, names(mat_join))]
    data.table::setnames(mat_join, "ata_from", "maturity_from")

    if (length(grp_var)) {
      full <- mat_join[full, on = grp_var]
    } else {
      if (nrow(mat_join) == 1L) {
        full[, maturity_from := mat_join$maturity_from[1L]]
      } else {
        full[, maturity_from := NA_real_]
      }
    }
  } else {
    full[, maturity_from := NA_real_]
  }

  # 11) last_obs per cohort ---------------------------------------------
  full[, last_obs := {
    idx <- which(is.finite(loss_obs))
    if (length(idx)) max(idx) else 0L
  }, by = c(grp_var, "cohort")]

  # 12) loss point projection -------------------------------------------
  full[, loss_proj := .sa_proj(
    loss_obs      = loss_obs,
    premium_proj  = premium_proj,
    g_selected    = g_selected,
    f_selected    = f_selected,
    maturity_from = maturity_from[1L],
    method        = method
  ), by = c(grp_var, "cohort")]

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
  ), by = c(grp_var, "cohort")]

  # 14) total loss variance and SE -------------------------------------
  full[, loss_total_se2 := loss_proc_se2 + loss_param_se2]

  full[, `:=`(
    loss_proc_se  = sqrt(loss_proc_se2),
    loss_param_se = sqrt(loss_param_se2),
    loss_total_se = sqrt(loss_total_se2)
  )]

  full[, loss_total_cv := data.table::fifelse(
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
  full[, loss_incr_proj := loss_proj - data.table::shift(loss_proj, 1L, fill = 0),
       by = c(grp_var, "cohort")]
  full[, premium_incr_proj := premium_proj - data.table::shift(premium_proj, 1L, fill = 0),
       by = c(grp_var, "cohort")]

  # 17) $pred: NA-mask observed cells (loss-side columns only) --------
  pred    <- data.table::copy(full)
  na_cols <- c(
    "loss_proj", "premium_proj",
    "loss_incr_proj", "premium_incr_proj",
    "loss_proc_se2", "loss_param_se2", "loss_total_se2",
    "loss_proc_se",  "loss_param_se",  "loss_total_se",
    "loss_total_cv",
    "loss_ci_lower", "loss_ci_upper"
  )
  pred[is_observed == TRUE, (na_cols) := NA_real_]

  # 18) assemble LossFit ----------------------------------------------
  # NOTE: $full retains internal columns (g_selected, g_sigma2, g_var,
  # f_selected, f_sigma2, f_var, last_obs) so that fit_lr can run
  # bootstrap CI without re-fitting. fit_lr drops them after bootstrap.
  out <- list(
    call              = match.call(),
    data              = x,
    group_var         = grp_var,
    cohort_var        = coh_var,
    dev_var           = dev_var,
    full              = full,
    pred              = pred,
    maturity          = maturity,
    loss_ata_fit      = loss_ata_fit,
    premium_ata_fit   = premium_ata_fit,
    premium_fit       = premium_fit,
    ed                = ed_fit$link,
    factor            = ed_fit$factor,
    selected          = ed_fit$selected,
    method            = method,
    alpha             = alpha,
    sigma_method      = sigma_method,
    recent            = recent_user,
    loss_regime_break = .resolve_break_date(loss_regime_break_user),
    maturity_args     = maturity_args,
    conf_level        = conf_level
  )

  class(out) <- "LossFit"
  out
}


#' Print method for `LossFit`
#' @param x A `LossFit` object.
#' @param ... Unused.
#' @export
print.LossFit <- function(x, ...) {
  grp_var <- x$group_var
  if (is.null(grp_var)) grp_var <- character(0)

  cat("<LossFit>\n")
  cat("method            :", x$method,       "\n")
  cat("alpha             :", x$alpha,        "\n")
  cat("sigma_method      :", x$sigma_method, "\n")
  cat("recent            :",
      if (!is.null(x$recent)) x$recent else "all", "\n")
  cat("loss_regime_break :",
      if (!is.null(x$loss_regime_break)) format(x$loss_regime_break) else "none", "\n")

  if (!is.null(x$maturity) && nrow(x$maturity)) {
    mat <- .ensure_dt(x$maturity)
    if (length(grp_var)) {
      for (i in seq_len(nrow(mat))) {
        grp_txt <- paste(mat[i, grp_var, with = FALSE], collapse = "/")
        cat(sprintf("maturity[%s] : %s\n", grp_txt, mat$ata_to[i]))
      }
    } else {
      cat("maturity     :", mat$ata_to[1L], "\n")
    }
  }

  if (length(grp_var)) {
    cat("groups       :", paste(grp_var, collapse = ", "), "\n")
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
  grp_var <- object$group_var
  if (is.null(grp_var)) grp_var <- character(0)

  full <- .ensure_dt(object$full)
  by_cols <- c(grp_var, "cohort")
  out <- full[, .SD[which.max(dev)], by = by_cols]
  keep <- c(by_cols, "loss_proj", "loss_total_se", "loss_total_cv")
  out <- out[, .SD, .SDcols = keep]
  data.table::setnames(out,
    c("loss_proj", "loss_total_se", "loss_total_cv"),
    c("ultimate",  "se_ultimate",   "cv_ultimate"))
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
                         target_var,
                         exposure_var) {

  grp_var <- attr(triangle, "group_var")

  if (is.null(grp_var)) grp_var <- character(0)

  raw <- .ensure_dt(triangle)

  obs <- raw[, .(
    loss_obs    = .SD[[target_var]],
    premium_obs = .SD[[exposure_var]]
  ), by = c(grp_var, "cohort", "dev")]

  max_dev_ed   <- max(ed_fit$selected$ata_to, na.rm = TRUE)
  max_dev_prem <- max(premium_ata_fit$selected$ata_to, na.rm = TRUE)
  max_dev      <- max(max_dev_ed, max_dev_prem)

  full <- unique(obs[, .SD, .SDcols = c(grp_var, "cohort")])
  full <- full[, .(dev = seq_len(max_dev)), by = c(grp_var, "cohort")]

  full <- obs[full, on = c(grp_var, "cohort", "dev")]
  data.table::setorderv(full, c(grp_var, "cohort", "dev"))

  full[, is_observed := is.finite(loss_obs)]

  prem_sel <- premium_ata_fit$selected[
    , .SD,
    .SDcols = c(grp_var, "ata_from", "f_selected")
  ]
  data.table::setnames(prem_sel, c("ata_from", "f_selected"),
                       c("dev", "f_exposure"))
  full <- prem_sel[full, on = c(grp_var, "dev")]

  full[, premium_proj := .cl_proj(
    target_obs = premium_obs,
    f_selected = f_exposure
  ), by = c(grp_var, "cohort")]

  full[, f_exposure := NULL]
  full
}
