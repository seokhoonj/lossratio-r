#' Fit stage-adaptive (SA) loss projection on a Triangle
#'
#' @description
#' Project cumulative loss across the cohort x development grid using the
#' *stage-adaptive* (SA) method: ED before the maturity point, CL after.
#' SA composes both projection paradigms anchored on a per-group maturity
#' switch -- a 2-pass fit (maturity detection via `fit_ata()`, then the
#' SA projection itself).
#'
#' SA is a worker -- standalone, no internal method dispatch. The
#' role-specific entry point [fit_loss()] dispatches `method = "sa"` to
#' this function; users can also call `fit_sa()` directly.
#'
#' @param x A `"Triangle"` object. The standardized `"loss"` and
#'   `"exposure"` columns are used (`as_triangle()` produces these).
#' @param loss Cumulative loss column name. Default `"loss"`.
#' @param exposure Cumulative exposure column name. Default `"exposure"`.
#' @param alpha Variance-structure exponent for the loss fit. Default `1`.
#' @param exposure_fit Optional pre-built `ExposureFit` supplying the
#'   exposure projection. When `NULL`, `fit_sa()` calls [fit_exposure()]
#'   internally using `exposure_method`, `exposure_alpha`, and the
#'   resolved `regime`.
#' @param exposure_method One of `"cl"` (default) or `"ed"`. Used only
#'   when `exposure_fit = NULL`.
#' @param exposure_alpha Variance-structure exponent for the exposure fit.
#'   Default `1`.
#' @inheritParams fit_ata
#' @param recent Optional positive integer; calendar-diagonal filter.
#' @param regime Optional regime specification (loss-side). Accepts the
#'   standard 4-type dispatch (`NULL` / `Regime` / `"auto"` / function).
#'   In SA mode the resolved regime drives the hybrid 2-pass filter
#'   (cohort cut for the ED phase, calendar-diagonal wedge for the CL
#'   phase).
#' @param maturity Maturity specification. Default `"auto"`. Accepts the
#'   standard 4-type dispatch (`NULL` / `Maturity` / `"auto"` / function).
#'   SA requires a maturity -- `NULL` disables SA entirely (use ED or
#'   CL directly in that case).
#' @param tail Logical or numeric; tail factor for the CL phase.
#'   Forwarded to the internal exposure fit when relevant.
#' @param conf_level Confidence level for the analytical CI on the loss
#'   projection. Default `0.95`.
#' @param bootstrap Bootstrap configuration (NULL / TRUE / FALSE /
#'   "auto" / `BootstrapTriangle` / lazy function). Default `NULL`
#'   resolves to `"auto"` (residual bootstrap) for SA.
#' @param B Integer number of bootstrap replicates. Default `999`.
#' @param seed Optional integer seed.
#' @param type Bootstrap process type. Default `"parametric"`. (Only used
#'   when `bootstrap = "auto"`.)
#'
#' @return An object of class `"SAFit"`. List with components mirroring
#'   `LossFit`: `full`, `proj`, `maturity`, `loss_ata_fit`,
#'   `exposure_ata_fit`, `exposure_fit`, `ed`, `factor`, `selected`, plus
#'   metadata (`method = "sa"`, `alpha`, `sigma_method`, `recent`,
#'   `regime`, `conf_level`, `ci_type`, `bootstrap`, `usage`).
#'
#' @seealso [fit_loss()], [fit_cl()], [fit_ed()], [fit_ratio()].
#'
#' @examples
#' \dontrun{
#' data(experience)
#' tri <- as_triangle(
#'   experience[coverage == "surgery"],
#'   groups   = "coverage",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "incr_loss",
#'   exposure = "incr_exposure"
#' )
#'
#' sa <- fit_sa(tri)
#' summary(sa)
#' }
#'
#' @export
fit_sa <- function(x,
                   loss            = "loss",
                   exposure        = "exposure",
                   alpha           = 1,
                   exposure_fit    = NULL,
                   exposure_method = c("cl", "ed"),
                   exposure_alpha  = 1,
                   sigma_method    = c("locf", "min_last2", "loglinear",
                                       "mack", "none"),
                   recent          = NULL,
                   regime          = NULL,
                   maturity        = "auto",
                   tail            = FALSE,
                   conf_level      = 0.95,
                   bootstrap       = NULL,
                   B               = 999L,
                   seed            = NULL,
                   type            = c("parametric", "nonparametric",
                                       "analytical")) {

  # data.table NSE bindings for R CMD check
  loss_param_se <- loss_proc_se <- loss_total_se <- loss_total_cv <- NULL
  loss_ci_lo <- loss_ci_hi <- NULL
  loss_proj_boot <- loss_param_se_boot <- loss_proc_se_boot <- NULL
  loss_total_se_boot <- loss_total_cv_boot <- NULL
  loss_ci_lo_boot <- loss_ci_hi_boot <- NULL
  loss_obs <- exposure_proj <- g_sel <- f_sel <- maturity_from <- NULL
  loss_proj <- g_sigma2 <- f_sigma2 <- f_var <- g_var <- last_obs <- NULL
  loss_proc_se2 <- loss_param_se2 <- loss_total_se2 <- is_observed <- NULL

  .assert_triangle_input(x, "fit_sa()")
  sigma_method    <- match.arg(sigma_method)
  exposure_method <- match.arg(exposure_method)
  if (!missing(type)) type <- match.arg(type)

  if (!is.null(exposure_fit) && !inherits(exposure_fit, "ExposureFit"))
    stop("`exposure_fit` must be an ExposureFit object or NULL.",
         call. = FALSE)

  if (!is.numeric(alpha) || length(alpha) != 1L ||
      is.na(alpha) || !is.finite(alpha))
    stop("`alpha` must be a single finite numeric value.", call. = FALSE)
  if (!is.numeric(exposure_alpha) || length(exposure_alpha) != 1L ||
      is.na(exposure_alpha) || !is.finite(exposure_alpha))
    stop("`exposure_alpha` must be a single finite numeric value.",
         call. = FALSE)
  if (!is.numeric(conf_level) || length(conf_level) != 1L ||
      is.na(conf_level) || conf_level <= 0 || conf_level >= 1)
    stop("`conf_level` must be a single numeric value in (0, 1).",
         call. = FALSE)

  # Default: bootstrap for SA.
  if (is.null(bootstrap)) bootstrap <- "auto"
  if (!is.numeric(B) || length(B) != 1L || is.na(B) || B < 1L)
    stop("`B` must be a single positive integer.", call. = FALSE)
  B <- as.integer(B)

  # Resolve regime + maturity (NULL / object / "auto" / function)
  regime   <- .resolve_regime(regime, x)
  maturity <- .resolve_maturity(maturity, x)

  # Apply maturity-group rebucket up-front so all downstream code sees a
  # consistent partition.
  if (!is.null(maturity)) {
    m_groups <- attr(maturity, "groups")
    if (is.null(m_groups)) {
      stat_cols <- c("change", "ata_from", "ata_link", "mean", "median", "wt",
                     "cv", "f", "f_se", "rse", "sigma", "n_cohorts", "n_valid",
                     "n_inf", "n_nan", "valid_ratio")
      m_groups <- setdiff(names(maturity), stat_cols)
    }
    data_groups <- attr(x, "groups")
    if (is.null(data_groups)) data_groups <- character(0)
    if (length(m_groups) > 0L && !setequal(m_groups, data_groups)) {
      x <- .rebucket_triangle_groups(x, m_groups)
    }
  }

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
  regime_user <- regime
  recent_user <- recent

  # SA hybrid filter (loss-side, 2-pass maturity) ---------------------
  if (!is.null(regime)) {
    cd <- .resolve_regime_change_date(regime, by = grp)

    if (!is.null(cd)) {
      pre_loss_fit <- fit_ata(
        x,
        loss         = "loss",
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
  }

  # Resolve exposure_fit ----------------------------------------------
  # Worker-layer dispatch: call fit_cl directly on the exposure column
  # (mirror fit_ed pattern) rather than fit_exposure (a dispatcher) to
  # avoid the upward worker -> dispatcher dependency. If the caller
  # supplied a pre-built exposure_fit (ExposureFit class from a
  # composer-layer caller like fit_ratio), we accept it as-is.
  if (is.null(exposure_fit)) {
    grp_local <- attr(x, "groups")
    if (is.null(grp_local)) grp_local <- character(0)
    exposure_fit <- fit_cl(
      x,
      method       = "mack",
      loss         = "exposure",
      alpha        = exposure_alpha,
      sigma_method = sigma_method,
      regime       = regime_user
    )
    # Apply exposure-side variance overlay when exposure_method = "ed"
    # (mirror fit_exposure behaviour for variance recursion choice).
    if (identical(exposure_method, "ed")) {
      exposure_fit$full <- .apply_ed_variance(exposure_fit$full,
                                              exposure_fit$selected, x)
    }
    exposure_fit$full <- .exposure_rename_full(exposure_fit$full,
                                               grp_local,
                                               conf_level = 0.95)
    class(exposure_fit) <- c("ExposureFit", class(exposure_fit))
  }
  exposure_ata_fit <- structure(
    list(
      selected     = exposure_fit$selected,
      link         = exposure_fit$link,
      data         = exposure_fit$data,
      method       = "mack",
      alpha        = exposure_alpha,
      sigma_method = sigma_method,
      maturity     = NULL
    ),
    class = "ATAFit"
  )

  # Loss ATA + Mack f_var ----------------------------------------------
  loss_ata_fit <- fit_ata(
    x,
    loss         = "loss",
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

  # ED intensities g_k + Mack g_var ------------------------------------
  intensity_fit <- fit_intensity(
    x,
    loss         = "loss",
    exposure     = "exposure",
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
  class(ed_fit) <- c("EDFit", "list")
  ed_fit$selected <- .ed_g_var(ed_fit, alpha = alpha)

  # Maturity point per group -------------------------------------------
  maturity <- loss_ata_fit$maturity

  # Expand to full projection grid -------------------------------------
  full <- .expand_grid(
    triangle         = x,
    ed_fit           = ed_fit,
    exposure_ata_fit = exposure_ata_fit,
    loss             = "loss",
    exposure         = "exposure"
  )

  has_seg_ed <- "segment_id" %in% names(ed_fit$selected)
  has_seg_cl <- "segment_id" %in% names(loss_ata_fit$selected)

  # Join ED factors ----------------------------------------------------
  ed_cols <- c(grp, "ata_from",
               if (has_seg_ed) "segment_id",
               "g_sel", "sigma2", "g_var")
  ed_sel  <- ed_fit$selected[, .SD, .SDcols = ed_cols]
  data.table::setnames(ed_sel, "ata_from", "dev")
  data.table::setnames(ed_sel, "sigma2", "g_sigma2")
  full <- ed_sel[full,
                 on = c(grp, "dev", if (has_seg_ed) "segment_id")]

  # Join CL factors ----------------------------------------------------
  cl_cols <- c(grp, "ata_from",
               if (has_seg_cl) "segment_id",
               "f_sel", "sigma2", "f_var")
  cl_sel  <- loss_ata_fit$selected[, .SD, .SDcols = cl_cols]
  data.table::setnames(cl_sel, "ata_from", "dev")
  data.table::setnames(cl_sel, "sigma2", "f_sigma2")
  full <- cl_sel[full,
                 on = c(grp, "dev", if (has_seg_cl) "segment_id")]

  # Maturity join per group --------------------------------------------
  if (!is.null(maturity)) {
    m_join <- .copy_dt(maturity)
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

  # last_obs per cohort ------------------------------------------------
  full[, ("last_obs") := {
    idx <- which(is.finite(loss_obs))
    if (length(idx)) max(idx) else 0L
  }, by = c(grp, "cohort")]

  # Loss point projection (SA) -----------------------------------------
  full[, ("loss_proj") := .sa_proj(
    loss_obs      = loss_obs,
    exposure_proj = exposure_proj,
    g_sel         = g_sel,
    f_sel         = f_sel,
    maturity_from = maturity_from[1L]
  ), by = c(grp, "cohort")]

  # Loss variance (process + parameter) --------------------------------
  full[, `:=`(
    loss_proc_se2  = .sa_proc_var(
      loss_proj     = loss_proj,
      exposure_proj = exposure_proj,
      g_sigma2      = g_sigma2,
      f_sigma2      = f_sigma2,
      f_sel         = f_sel,
      last_obs      = last_obs[1L],
      maturity_from = maturity_from[1L],
      alpha         = alpha
    ),
    loss_param_se2 = .sa_param_var(
      loss_proj     = loss_proj,
      exposure_proj = exposure_proj,
      g_var         = g_var,
      f_var         = f_var,
      f_sel         = f_sel,
      last_obs      = last_obs[1L],
      maturity_from = maturity_from[1L]
    )
  ), by = c(grp, "cohort")]

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

  # Analytical CI on loss ----------------------------------------------
  z_alpha <- stats::qnorm((1 + conf_level) / 2)
  full[, `:=`(
    loss_ci_lo = pmax(0, loss_proj - z_alpha * loss_total_se),
    loss_ci_hi = loss_proj + z_alpha * loss_total_se
  )]

  # Bootstrap overwrite (optional) -------------------------------------
  boots <- .resolve_bootstrap(
    bootstrap, x_full,
    B           = B,
    seed        = seed,
    type        = "analytical",
    process     = "normal",
    target      = "loss",
    alpha       = alpha,
    quantile_ci = TRUE,
    keep_pseudo = FALSE
  )

  if (!is.null(boots)) {
    bsum <- data.table::copy(boots$summary)
    data.table::setnames(
      bsum,
      c("mean_proj", "param_se", "proc_se", "total_se", "total_cv"),
      c("loss_proj_boot", "loss_param_se_boot", "loss_proc_se_boot",
        "loss_total_se_boot", "loss_total_cv_boot")
    )
    has_ci <- all(c("ci_lo", "ci_hi") %in% names(bsum))
    if (has_ci) {
      data.table::setnames(bsum, c("ci_lo", "ci_hi"),
                                  c("loss_ci_lo_boot", "loss_ci_hi_boot"))
    }

    full <- merge(full, bsum,
                  by = c(grp, "cohort", "dev"),
                  all.x = TRUE, sort = FALSE)

    is_proj <- full$is_observed == FALSE
    full[is_proj & is.finite(loss_param_se_boot), loss_param_se := loss_param_se_boot]
    full[is_proj & is.finite(loss_proc_se_boot),  loss_proc_se  := loss_proc_se_boot]
    full[is_proj & is.finite(loss_total_se_boot), loss_total_se := loss_total_se_boot]
    full[is_proj & is.finite(loss_total_cv_boot), loss_total_cv := loss_total_cv_boot]
    if (has_ci) {
      full[is_proj & is.finite(loss_ci_lo_boot), loss_ci_lo := loss_ci_lo_boot]
      full[is_proj & is.finite(loss_ci_hi_boot), loss_ci_hi := loss_ci_hi_boot]
    }
    drop_boot <- c("loss_proj_boot", "loss_param_se_boot",
                    "loss_proc_se_boot", "loss_total_se_boot",
                    "loss_total_cv_boot")
    if (has_ci) drop_boot <- c(drop_boot, "loss_ci_lo_boot", "loss_ci_hi_boot")
    full[, (drop_boot) := NULL]
  }

  # Incremental projections --------------------------------------------
  full[, ("incr_loss_proj") := loss_proj -
         data.table::shift(loss_proj, 1L, fill = 0),
       by = c(grp, "cohort")]
  full[, ("incr_exposure_proj") := exposure_proj -
         data.table::shift(exposure_proj, 1L, fill = 0),
       by = c(grp, "cohort")]

  # proj: NA-mask observed cells ---------------------------------------
  proj    <- data.table::copy(full)
  na_cols <- c(
    "loss_proj", "exposure_proj",
    "incr_loss_proj", "incr_exposure_proj",
    "loss_proc_se2", "loss_param_se2", "loss_total_se2",
    "loss_proc_se",  "loss_param_se",  "loss_total_se",
    "loss_total_cv",
    "loss_ci_lo", "loss_ci_hi"
  )
  proj[is_observed == TRUE, (na_cols) := NA_real_]

  # Usage map ----------------------------------------------------------
  usage <- .build_usage(
    x_full,
    regime   = regime_user,
    recent   = recent_user,
    holdout  = NULL,
    maturity = maturity,
    metric   = "loss"
  )

  # Assemble SAFit -----------------------------------------------------
  out <- list(
    call             = match.call(),
    data             = x,
    method           = "sa",
    groups           = grp,
    cohort           = coh,
    dev              = dev,
    loss             = "loss",
    exposure         = "exposure",
    full             = full,
    proj             = proj,
    summary          = NULL,
    maturity         = maturity,
    loss_ata_fit     = loss_ata_fit,
    exposure_ata_fit = exposure_ata_fit,
    exposure_fit     = exposure_fit,
    ed               = ed_fit$link,
    factor           = ed_fit$factor,
    selected         = ed_fit$selected,
    alpha            = alpha,
    sigma_method     = sigma_method,
    recent           = recent_user,
    regime           = regime_user,
    conf_level       = conf_level,
    ci_type          = if (!is.null(boots)) "bootstrap" else "analytical",
    bootstrap        = if (!is.null(boots))
                         list(B = boots$meta$B, seed = boots$meta$seed)
                       else NULL,
    usage            = usage
  )

  class(out) <- c("SAFit", "list")
  out
}


#' Print method for `SAFit`
#'
#' @param x A `SAFit` object.
#' @param ... Unused.
#'
#' @method print SAFit
#' @export
print.SAFit <- function(x, ...) {
  grp <- x$groups
  if (is.null(grp)) grp <- character(0)

  mat_labels <- character(0)
  if (!is.null(x$maturity) && nrow(x$maturity)) {
    if (length(grp)) {
      grp_txt <- vapply(seq_len(nrow(x$maturity)), function(i)
        paste(x$maturity[i, grp, with = FALSE], collapse = "/"),
        character(1L))
      mat_labels <- sprintf("maturity[%s]", grp_txt)
    } else {
      mat_labels <- "maturity"
    }
  }

  static_labels <- c("method", "alpha", "sigma_method", "recent", "regime",
                     "ci_type", "groups", "n_cohorts")
  lw  <- max(nchar(c(static_labels, mat_labels)))
  pad <- function(label) formatC(label, width = lw, flag = "-")

  cat("<SAFit>\n")
  cat(pad("method"),       ":", x$method,       "\n")
  cat(pad("alpha"),        ":", x$alpha,        "\n")
  cat(pad("sigma_method"), ":", x$sigma_method, "\n")
  cat(pad("recent"),       ":",
      if (!is.null(x$recent)) x$recent else "all", "\n")
  cat(pad("regime"),       ":")
  if (is.null(x$regime)) {
    cat(" none\n")
  } else if (inherits(x$regime, "Regime")) {
    cat("\n"); print(x$regime)
  } else {
    cat(" ", format(x$regime), "\n", sep = "")
  }

  if (!is.null(x$ci_type)) {
    cat(pad("ci_type"), ":", x$ci_type,
        if (!is.null(x$bootstrap))
          sprintf(" (B = %d, seed = %s)", x$bootstrap$B,
                  if (is.null(x$bootstrap$seed)) "NULL" else x$bootstrap$seed)
        else "",
        "\n")
  }

  if (length(mat_labels)) {
    mat <- .copy_dt(x$maturity)
    for (i in seq_along(mat_labels)) {
      cat(pad(mat_labels[i]), ":", mat$change[i], "\n")
    }
  }

  if (length(grp)) {
    cat(pad("groups"), ":", paste(grp, collapse = ", "), "\n")
  } else {
    cat(pad("groups"), ": none\n", sep = "")
  }

  cat(pad("n_cohorts"), ":", length(unique(x$full$cohort)), "\n")
  invisible(x)
}


#' Summary method for `SAFit`
#'
#' @description
#' Per-cohort ultimate loss, SE, and CV.
#'
#' @param object A `SAFit` object.
#' @param ... Unused.
#'
#' @method summary SAFit
#' @export
summary.SAFit <- function(object, ...) {
  grp <- object$groups
  if (is.null(grp)) grp <- character(0)

  full <- .copy_dt(object$full)
  by_cols <- c(grp, "cohort")
  out <- full[, .SD[which.max(dev)], by = by_cols]
  keep <- c(by_cols, "loss_proj", "loss_total_se", "loss_total_cv")
  out <- out[, .SD, .SDcols = keep]
  data.table::setnames(out, "loss_proj", "loss_ult")
  out[]
}


# Projection helpers --------------------------------------------------------

#' Stage-adaptive (SA) point projection for a single cohort
#'
#' @description
#' Internal helper that projects cumulative loss with the SA rule:
#' ED phase before maturity (`k < maturity_from`), CL phase after.
#'
#' Originally lived in `R/loss.R` -- moved to `R/sa.R` alongside `fit_sa()`
#' in Phase 4a.
#'
#' @param loss_obs Numeric vector of observed cumulative loss.
#' @param exposure_proj Numeric vector of projected cumulative exposure.
#' @param g_sel Numeric vector of ED intensities.
#' @param f_sel Numeric vector of CL factors.
#' @param maturity_from Numeric scalar; switch point. `NA` means
#'   ED-only (no switch).
#'
#' @return A numeric vector with projected cumulative loss.
#'
#' @keywords internal
.sa_proj <- function(loss_obs,
                     exposure_proj,
                     g_sel,
                     f_sel,
                     maturity_from) {

  n        <- length(loss_obs)
  last_obs <- max(which(is.finite(loss_obs)), 0L)

  if (last_obs == 0L || last_obs == n) return(loss_obs)

  v <- loss_obs

  mat <- if (is.finite(maturity_from)) maturity_from else Inf

  for (i in seq(last_obs + 1L, n)) {
    k <- i - 1L
    v_prev <- v[i - 1L]

    if (!is.finite(v_prev)) next

    if (k < mat) {
      # ED phase: additive
      g_now <- g_sel[k]
      e_now <- exposure_proj[k]
      if (is.finite(g_now) && is.finite(e_now)) {
        v[i] <- v_prev + g_now * e_now
      }
    } else {
      # CL phase: multiplicative
      f_now <- f_sel[k]
      if (is.finite(f_now)) {
        v[i] <- f_now * v_prev
      }
    }
  }

  v
}


#' Stage-adaptive process variance for a single cohort
#'
#' @description
#' ED phase (additive): `proc_{k+1} = proc_k + g_sigma2_k * (C^P_k)^alpha`.
#' CL phase (Mack):     `proc_{k+1} = f_k^2 * proc_k + f_sigma2_k * (C^L_k)^alpha`.
#'
#' @keywords internal
.sa_proc_var <- function(loss_proj,
                         exposure_proj,
                         g_sigma2,
                         f_sigma2,
                         f_sel,
                         last_obs,
                         maturity_from,
                         alpha = 1) {

  n    <- length(loss_proj)
  proc <- numeric(n)

  if (last_obs == n) return(proc)

  mat <- if (is.finite(maturity_from)) maturity_from else Inf

  for (i in seq(last_obs + 1L, n)) {
    k <- i - 1L

    if (k < mat) {
      s2  <- g_sigma2[k]
      e_k <- exposure_proj[k]

      proc[i] <- proc[i - 1L]
      if (is.finite(s2) && is.finite(e_k) && e_k > 0) {
        proc[i] <- proc[i] + s2 * e_k^alpha
      }
    } else {
      f_k <- f_sel[k]
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


#' Stage-adaptive parameter variance for a single cohort
#'
#' @description
#' ED phase: `param_{k+1} = param_k + (C^P_k)^2 * Var(g_k)`.
#' CL phase: `param_{k+1} = f_k^2 * param_k + (C^L_k)^2 * Var(f_k)`.
#'
#' @keywords internal
.sa_param_var <- function(loss_proj,
                          exposure_proj,
                          g_var,
                          f_var,
                          f_sel,
                          last_obs,
                          maturity_from) {

  n     <- length(loss_proj)
  param <- numeric(n)

  if (last_obs == n) return(param)

  mat <- if (is.finite(maturity_from)) maturity_from else Inf

  for (i in seq(last_obs + 1L, n)) {
    k <- i - 1L

    if (k < mat) {
      gv  <- g_var[k]
      e_k <- exposure_proj[k]

      param[i] <- param[i - 1L]
      if (is.finite(gv) && is.finite(e_k)) {
        param[i] <- param[i] + e_k^2 * gv
      }
    } else {
      f_k  <- f_sel[k]
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
