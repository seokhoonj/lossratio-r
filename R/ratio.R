#' Fit loss ratio projection model
#'
#' @description
#' Unified interface for loss ratio projection from a `"Triangle"` object.
#' Three projection methods are available:
#'
#' \describe{
#'   \item{`"ed"` (default)}{Exposure-driven for all development periods.
#'     All future increments are \eqn{g_k \cdot C^P_k}. Unconditional
#'     safe baseline -- no maturity dependency, robust under early-dev
#'     ATA volatility.}
#'   \item{`"cl"`}{Chain ladder for all development periods.
#'     Equivalent to the classical Mack (1993) recursion.}
#'   \item{`"sa"`}{Stage-adaptive composition: ED before maturity, CL
#'     after maturity. Requires maturity detection (2-pass), uses age-to-
#'     age factors only once they have stabilised.
#'     \itemize{
#'       \item Before maturity: age-to-age factors are volatile, so
#'         exposure-driven projection
#'         \eqn{\Delta C^L = g_k \cdot C^P_k} anchors the estimate
#'         to exposure volume.
#'       \item After maturity: age-to-age factors are stable, so
#'         chain ladder projection
#'         \eqn{C^L_{k+1} = f_k \cdot C^L_k} preserves the cohort's
#'         observed level.
#'     }}
#' }
#'
#' In all cases, exposure is projected forward using chain ladder:
#' \deqn{\hat{C}^P_{i,k+1} = f^P_k \cdot \hat{C}^P_{i,k}}
#'
#' This function is the *composition* layer over [fit_loss()] and
#' [fit_exposure()]: it delegates loss projection to `fit_loss()`,
#' retrieves the embedded `ExposureFit`, and composes the loss-ratio
#' point + variance via the delta method (`se_method = "fixed"` or
#' `"delta"`). See `ARCHITECTURE.md` for the layered design.
#'
#' @param x An object of class `"Triangle"`. The standardized `"loss"`
#'   and `"exposure"` columns are used (`as_triangle()` produces these).
#' @param method One of `"ed"` (default), `"cl"`, or `"sa"`.
#' @param loss_alpha Numeric scalar controlling the variance structure for
#'   loss estimation. Default is `1`.
#' @param loss_regime Optional regime specification for the loss-side
#'   filter. Accepts four input types:
#'   \describe{
#'     \item{`NULL` (default)}{No regime filter.}
#'     \item{`Regime` object}{Use as-is. Typically built via
#'       [detect_regime()] or [regime_at()].}
#'     \item{`"auto"`}{Detect regime internally via `detect_regime(x)` on
#'       the input triangle.}
#'     \item{Function / closure}{A user-supplied function taking the
#'       triangle and returning a `Regime` object (or `NULL`).}
#'   }
#'   Behavior depends on `method`:
#'   \describe{
#'     \item{`"sa"`}{Hybrid filter. Pre-change cohorts are dropped only for
#'       development periods at or before the maturity point (ED phase);
#'       post-maturity (CL) cells use the `recent`-diagonal window across
#'       all cohorts. This preserves CL stability while protecting the ED
#'       intensities from a regime change.}
#'     \item{`"ed"`, `"cl"`}{Simple cohort cut: all cohorts strictly before
#'       the change date are excluded from estimation.}
#'   }
#' @param exposure_method One of `"cl"` (default) or `"ed"`. Forwarded to
#'   [fit_exposure()] when constructing the exposure projection.
#' @param exposure_alpha Numeric scalar for exposure chain ladder. Default
#'   is `1`.
#' @param exposure_regime Exposure-side regime specification. Same four
#'   input types as `loss_regime` (`NULL` / `Regime` / `"auto"` / function).
#'   Default `NULL` -- exposure is fit on the full triangle independently
#'   of `loss_regime` (no lazy default). Set explicitly when the regime
#'   shift affects exposure accrual too.
#' @inheritParams fit_ata
#' @param recent Optional positive integer for estimation window.
#'   Default is `NULL`.
#' @param maturity Optional maturity specification. Accepts four input
#'   types:
#'   \describe{
#'     \item{`NULL`}{No maturity filter. Disables SA-mode switch detection.}
#'     \item{`Maturity` object}{Use as-is. Typically built via
#'       [detect_maturity()] or [maturity_at()].}
#'     \item{`"auto"` (default)}{Detect maturity internally via
#'       `detect_maturity(x)` on the input triangle.}
#'     \item{Function / closure}{A user-supplied function taking the
#'       triangle and returning a `Maturity` object (e.g. from
#'       [maturity_spec()]) for deferred custom-config detection.}
#'   }
#'   When `method = "sa"`, this also determines the switch point between
#'   ED and CL phases.
#' @param se_method Method for computing `ratio_se = SE(L/P)`. One of:
#'   \describe{
#'     \item{`"fixed"` (default)}{Premium treated as fixed (non-random).
#'       \eqn{\mathrm{SE}(L/P) = \mathrm{SE}(L) / P}. Strictly, this is
#'       the delta method with `Var(P) = 0` and `Cov(L,P) = 0`, i.e., a
#'       degenerate case under the assumption that exposure is known.}
#'     \item{`"delta"`}{Full delta method including exposure uncertainty
#'       and the loss-exposure correlation `rho`:
#'       \deqn{\mathrm{Var}(L/P) \approx \frac{\mathrm{Var}(L)}{P^2}
#'         + \frac{L^2 \mathrm{Var}(P)}{P^4}
#'         - \frac{2 \rho L \mathrm{SE}(L) \mathrm{SE}(P)}{P^3}}
#'     }
#'   }
#' @param rho Numeric scalar in `(-1, 1)`; assumed correlation between
#'   ultimate loss and ultimate exposure. Only used when
#'   `se_method = "delta"`. Default is `0.95`, matching the strong
#'   positive correlation typically observed between cumulative loss
#'   and cumulative exposure in long-tail health portfolios (analogous
#'   to the paid/incurred correlation used in Munich chain ladder).
#' @param conf_level Confidence level used for `ratio_ci_lo`/`ratio_ci_hi`
#'   in the cohort summary. Default is `0.95`.
#' @param bootstrap Bootstrap configuration. Five forms accepted:
#'   \describe{
#'     \item{`NULL` (default)}{Auto-resolved by `method`: bootstrap for
#'       `"sa"`/`"ed"`, analytical for `"cl"`. Matches legacy behavior.}
#'     \item{`TRUE` / `FALSE`}{Back-compat with the legacy logical arg.
#'       `TRUE` triggers `"auto"`; `FALSE` disables.}
#'     \item{`"auto"`}{Internal `bootstrap()` call on the loss triangle
#'       with defaults `(type = "analytical", process = "normal",
#'       target = "loss")`.}
#'     \item{`BootstrapTriangle`}{Pre-built object from `bootstrap()`.
#'       Must have `meta$target == "loss"`.}
#'     \item{Function `function(tri) -> BootstrapTriangle`}{Lazy spec
#'       invoked on the input Triangle (leakage-safe for `backtest()`).}
#'   }
#'   Premium is held at observed values during the bootstrap (loss-only
#'   convention). `ratio_se` is recomputed from the bootstrap-derived
#'   `loss_total_se` via `.compute_ratio_se()`, combined with the
#'   exposure-side SE per `se_method` (`"fixed"` ignores exposure SE;
#'   `"delta"` uses `exposure_total_se` from the inner `fit_exposure()`
#'   plus `rho` correlation).
#' @param B Integer number of bootstrap replications. Used only when
#'   `bootstrap` resolves to `"auto"`. Default is `999`.
#' @param seed Optional integer seed for reproducible bootstrap.
#'   Default is `NULL`.
#'
#' @return An object of class `"RatioFit"`.
#'
#' @seealso [fit_loss()], [fit_exposure()], [as_triangle()],
#'   [as_link()], [fit_ata()], [fit_ed()], [detect_maturity()]
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
#' # Stage-adaptive (default): ED before maturity, CL after
#' ratio_sa <- fit_ratio(tri, method = "sa")
#' summary(ratio_sa)
#' plot(ratio_sa)
#'
#' # Pure exposure-driven for all development periods
#' ratio_ed <- fit_ratio(tri, method = "ed")
#'
#' # Pure chain ladder (Mack-style) for all development periods
#' ratio_cl <- fit_ratio(tri, method = "cl")
#' }
#'
#' @export
fit_ratio <- function(x,
                      method          = c("ed", "cl", "sa"),
                      loss_alpha      = 1,
                      loss_regime     = NULL,
                      exposure_method = c("cl", "ed"),
                      exposure_alpha  = 1,
                      exposure_regime = NULL,
                      sigma_method    = c("locf", "min_last2", "loglinear",
                                          "mack", "none"),
                      recent          = NULL,
                      maturity        = "auto",
                      se_method       = c("fixed", "delta"),
                      rho             = 0.95,
                      conf_level      = 0.95,
                      bootstrap       = NULL,
                      B               = 999,
                      seed            = NULL) {

  # data.table NSE bindings for R CMD check
  loss_proj <- exposure_proj <- loss_total_se <- exposure_total_se <- NULL
  ratio_proj <- ratio_se <- is_observed <- NULL
  loss_param_se <- loss_proc_se <- loss_total_cv <- NULL
  loss_ci_lo <- loss_ci_hi <- NULL
  loss_proj_boot <- loss_param_se_boot <- loss_proc_se_boot <- NULL
  loss_total_se_boot <- loss_total_cv_boot <- NULL
  loss_ci_lo_boot <- loss_ci_hi_boot <- NULL

  .assert_triangle_input(x, "fit_ratio()")
  sigma_method    <- match.arg(sigma_method)
  method          <- match.arg(method)
  se_method       <- match.arg(se_method)
  exposure_method <- match.arg(exposure_method)

  # Resolve 4-type regime inputs (NULL / Regime / "auto" / function).
  # Independent NULL defaults -- no lazy chaining between loss and exposure.
  loss_regime     <- .resolve_regime(loss_regime, x)
  exposure_regime <- .resolve_regime(exposure_regime, x)

  # Resolve 4-type maturity input (NULL / Maturity / "auto" / function).
  maturity <- .resolve_maturity(maturity, x)

  # Legacy back-compat: NULL maps to method-dependent default (SA/ED ->
  # bootstrap, CL -> analytical). All other shapes flow through
  # `.resolve_bootstrap()` later.
  if (is.null(bootstrap)) {
    bootstrap <- if (method %in% c("sa", "ed")) "auto" else FALSE
  }
  if (!is.numeric(B) || length(B) != 1L || is.na(B) || B < 1L)
    stop("`B` must be a single positive integer.", call. = FALSE)
  B <- as.integer(B)

  if (!is.numeric(rho) || length(rho) != 1L || is.na(rho) ||
      rho <= -1 || rho >= 1)
    stop("`rho` must be a single numeric value in (-1, 1).", call. = FALSE)

  if (!is.numeric(conf_level) || length(conf_level) != 1L ||
      is.na(conf_level) || conf_level <= 0 || conf_level >= 1)
    stop("`conf_level` must be a single numeric value in (0, 1).",
         call. = FALSE)

  # 1) build exposure_fit independently with `exposure_regime` ---------
  # fit_ratio is the composition layer where loss-side and exposure-side
  # may carry distinct regimes. We construct the exposure_fit here using
  # `exposure_regime`, then hand it to fit_loss via `exposure_fit = ...`
  # so fit_loss's own (single-role) `regime` does not override the
  # exposure-side cut.
  # Explicit bootstrap = FALSE: fit_ratio drives its own loss/ratio bootstrap
  # composition; the inner exposure_fit is treated as a fixed projection
  # (exposure uncertainty is not propagated unless `se_method = "delta"`).
  exposure_fit <- fit_exposure(
    x,
    method       = exposure_method,
    alpha        = exposure_alpha,
    sigma_method = sigma_method,
    regime       = exposure_regime,
    bootstrap    = FALSE
  )

  # 2) delegate loss-side projection to fit_loss() -----------------------
  # Pass the pre-built exposure_fit so fit_loss reuses it; `regime` is
  # the loss-side filter (SA hybrid + factor estimation).
  loss_fit <- fit_loss(
    x               = x,
    method          = method,
    alpha           = loss_alpha,
    regime          = loss_regime,
    exposure_fit    = exposure_fit,
    exposure_method = exposure_method,
    exposure_alpha  = exposure_alpha,
    sigma_method    = sigma_method,
    recent          = recent,
    maturity        = maturity,
    conf_level      = conf_level,
    bootstrap       = FALSE
  )

  grp <- loss_fit$groups
  coh <- loss_fit$cohort
  dev <- loss_fit$dev
  # exposure_fit already constructed above; reuse it directly.
  exposure_ata_fit <- loss_fit$exposure_ata_fit

  full <- data.table::copy(loss_fit$full)

  # 3) exposure variance join from exposure_fit$full (se_method = "delta") -
  # Take the role-specific exposure_* columns directly from the dispatcher
  # output -- no `exp_*` intermediary aliasing.
  if (se_method == "delta") {
    pf_full <- .copy_dt(exposure_fit$full)
    pf_keep_keys <- intersect(c(grp, "cohort", "dev"), names(pf_full))
    pf_cols <- c(pf_keep_keys, "exposure_total_se", "exposure_total_cv")
    pf_cols <- intersect(pf_cols, names(pf_full))
    pf_join <- pf_full[, .SD, .SDcols = pf_cols]
    # only join the SE-side columns; `exposure_obs`, `exposure_proj`,
    # `incr_exposure_proj` already live on `full` (computed inside
    # fit_loss).
    full <- pf_join[full, on = pf_keep_keys]
  }

  # 4) loss ratio point projection -------------------------------------
  full[, ("ratio_proj") := data.table::fifelse(
    is.finite(loss_proj) & is.finite(exposure_proj) & exposure_proj != 0,
    loss_proj / exposure_proj,
    NA_real_
  )]

  # 5) ratio_se via delta method ---------------------------------------
  full[, ("ratio_se") := .compute_ratio_se(
    loss        = loss_proj,
    exposure    = exposure_proj,
    loss_se     = loss_total_se,
    exposure_se = if (se_method == "delta") exposure_total_se else NULL,
    method      = se_method,
    rho         = rho
  )]

  full[, ("ratio_cv") := data.table::fifelse(
    is.finite(ratio_proj) & ratio_proj != 0,
    ratio_se / abs(ratio_proj), NA_real_
  )]

  # 6) analytical CI for ratio (loss CI already on $full from fit_loss) -
  z_alpha <- stats::qnorm((1 + conf_level) / 2)

  full[, `:=`(
    ratio_ci_lo = pmax(0, ratio_proj - z_alpha * ratio_se),
    ratio_ci_hi = ratio_proj + z_alpha * ratio_se
  )]

  ci_type <- "analytical"

  # 7) bootstrap CI (optional, overwrites analytical CI columns) -------
  # Wrap-only path: bootstrap() already produces a precomputed
  # cohort x dev `$summary` with full Pythagorean SE decomposition
  # (`mean_proj`, `param_se`, `proc_se`, `total_se`, `total_cv` plus
  # `ci_lo` / `ci_hi` when quantile_ci = TRUE). The fit just maps
  # those columns into its own `$full` schema and recomputes `ratio_se`
  # from the bootstrap-derived `loss_total_se`. No per-replicate refit
  # loop here -- that work was done once inside bootstrap()'s C kernel.
  boots <- .resolve_bootstrap(
    bootstrap, x,
    B           = B,
    seed        = seed,
    type        = "analytical",
    process     = "normal",
    target      = "loss",
    alpha       = loss_alpha,
    quantile_ci = TRUE,
    keep_pseudo = FALSE   # fit_ratio only reads $summary -- long-format
                          # pseudo_triangles is unused under the wrap-only
                          # path, so skip its build for the speed +
                          # memory win.
  )

  if (!is.null(boots)) {
    bsum <- data.table::copy(boots$summary)
    # Rename to the fit_ratio column convention so the merge / override
    # below uses the same names as the analytical path.
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

    # Only override projection columns on non-observed cells. Observed
    # cells keep their analytical SE = 0 -- the bootstrap perturbation
    # of the upper triangle is a tool for parameter uncertainty, not a
    # claim about observed cell variability.
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

    # Recompute ratio_se from bootstrap-derived loss_total_se. Under
    # `se_method = "delta"`, this combines with `exposure_total_se`
    # (analytic from the inner fit_exposure) and `rho` to capture the
    # full ratio variance. Under `"fixed"`, exposure is treated as known
    # and ratio_se = loss_total_se / exposure_proj.
    full[, ("ratio_se") := .compute_ratio_se(
      loss        = loss_proj,
      exposure    = exposure_proj,
      loss_se     = loss_total_se,
      exposure_se = if (se_method == "delta") exposure_total_se else NULL,
      method      = se_method,
      rho         = rho
    )]
    full[, ("ratio_cv") := data.table::fifelse(
      is.finite(ratio_proj) & ratio_proj != 0,
      ratio_se / abs(ratio_proj), NA_real_
    )]
    full[, `:=`(
      ratio_ci_lo = pmax(0, ratio_proj - z_alpha * ratio_se),
      ratio_ci_hi = ratio_proj + z_alpha * ratio_se
    )]

    ci_type <- "bootstrap"
  }

  # 8) drop intermediate columns ---------------------------------------
  # Only SA leaves these columns on its $full (so fit_ratio can run
  # bootstrap CI on top without re-fitting). CL / ED / BF / CC workers
  # drop them internally -- guard with intersect() so the dispatcher path
  # for non-SA methods doesn't error.
  drop_cols <- intersect(
    c("g_sel", "g_sigma2", "g_var",
      "f_sel", "f_sigma2", "f_var",
      "last_obs"),
    names(full)
  )
  if (length(drop_cols)) full[, (drop_cols) := NULL]

  # 9) ratio incremental projection ------------------------------------
  full[, ("incr_ratio_proj") := data.table::fifelse(
    is.finite(incr_loss_proj) & is.finite(incr_exposure_proj) & incr_exposure_proj > 0,
    incr_loss_proj / incr_exposure_proj, NA_real_
  )]

  # 10) proj: NA-mask observed cells -----------------------------------
  proj    <- data.table::copy(full)
  na_cols <- c(
    "loss_proj", "exposure_proj", "ratio_proj",
    "incr_loss_proj", "incr_exposure_proj", "incr_ratio_proj",
    "loss_proc_se2", "loss_param_se2", "loss_total_se2",
    "loss_proc_se",  "loss_param_se",  "loss_total_se",
    "loss_total_cv", "ratio_se",       "ratio_cv",
    "ratio_ci_lo", "ratio_ci_hi", "loss_ci_lo", "loss_ci_hi"
  )
  if (se_method == "delta") {
    na_cols <- c(na_cols, "exposure_total_se", "exposure_total_cv")
  }
  na_cols <- intersect(na_cols, names(proj))
  proj[is_observed == TRUE, (na_cols) := NA_real_]

  # 12) assemble RatioFit ----------------------------------------------
  out <- list(
    call             = match.call(),
    data             = loss_fit$data,
    groups           = grp,
    cohort           = coh,
    dev              = dev,
    full             = full,
    proj             = proj,
    summary          = NULL,
    ed               = loss_fit$ed,
    factor           = loss_fit$factor,
    selected         = loss_fit$selected,
    loss_ata_fit     = loss_fit$loss_ata_fit,
    exposure_ata_fit = exposure_ata_fit,
    maturity         = loss_fit$maturity,
    method           = method,
    ci_type          = ci_type,
    bootstrap        = if (!is.null(boots))
                         list(B = boots$meta$B, seed = boots$meta$seed)
                       else NULL,
    loss_alpha       = loss_alpha,
    exposure_alpha   = exposure_alpha,
    se_method        = se_method,
    rho              = rho,
    conf_level       = conf_level,
    sigma_method     = sigma_method,
    recent           = loss_fit$recent,
    loss_regime      = loss_fit$regime,
    exposure_regime  = exposure_regime,
    usage            = loss_fit$usage
  )

  class(out) <- "RatioFit"

  out <- .ratio_summary(out)

  out
}


#' Print an `RatioFit` object
#'
#' @param x An object of class `"RatioFit"`.
#' @param ... Unused.
#'
#' @method print RatioFit
#' @export
print.RatioFit <- function(x, ...) {

  grp <- x$groups
  if (is.null(grp)) grp <- character(0)

  # Maturity labels (dynamic -- width depends on group string lengths).
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

  static_labels <- c("method", "loss_alpha", "exposure_alpha", "se_method",
                     "rho", "conf_level", "ci_type", "sigma_method",
                     "recent", "loss_regime", "exposure_regime",
                     "groups", "periods")
  lw  <- max(nchar(c(static_labels, mat_labels)))
  pad <- function(label) formatC(label, width = lw, flag = "-")

  cat("<RatioFit>\n")
  cat(pad("method"),         ":", x$method,         "\n")
  cat(pad("loss_alpha"),     ":", x$loss_alpha,     "\n")
  cat(pad("exposure_alpha"), ":", x$exposure_alpha, "\n")
  cat(pad("se_method"),      ":", x$se_method,      "\n")
  if (identical(x$se_method, "delta")) {
    cat(pad("rho"),          ":", x$rho,            "\n")
  }
  cat(pad("conf_level"),     ":", x$conf_level,     "\n")
  if (!is.null(x$ci_type)) {
    cat(pad("ci_type"),      ":", x$ci_type,
        if (!is.null(x$bootstrap))
          sprintf(" (B = %d, seed = %s)", x$bootstrap$B,
                  if (is.null(x$bootstrap$seed)) "NULL" else x$bootstrap$seed)
        else "",
        "\n")
  }
  cat(pad("sigma_method"),   ":", x$sigma_method,   "\n")
  cat(pad("recent"),         ":",
      if (!is.null(x$recent)) x$recent else "all", "\n")
  cat(pad("loss_regime"),    ":")
  if (is.null(x$loss_regime)) {
    cat(" none\n")
  } else if (inherits(x$loss_regime, "Regime")) {
    cat("\n"); print(x$loss_regime)
  } else {
    cat(" ", format(x$loss_regime), "\n", sep = "")
  }
  cat(pad("exposure_regime"), ":")
  if (is.null(x$exposure_regime)) {
    cat(" none\n")
  } else if (inherits(x$exposure_regime, "Regime")) {
    cat("\n"); print(x$exposure_regime)
  } else {
    cat(" ", format(x$exposure_regime), "\n", sep = "")
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

  cat(pad("periods"), ":", nrow(x$summary), "\n")

  invisible(x)
}


#' Summary method for `RatioFit`
#'
#' @param object An object of class `"RatioFit"`.
#' @param ... Unused.
#'
#' @return A `data.table` with one row per cohort.
#'
#' @method summary RatioFit
#' @export
summary.RatioFit <- function(object, ...) {
  object$summary
}


# SE helper -----------------------------------------------------------------

#' Loss ratio SE: `ratio_se = SE(L/P)`
#'
#' @description
#' Ratio-specific internal helper. Two variants:
#'
#' \describe{
#'   \item{`"fixed"` (default)}{Premium treated as fixed (non-random).
#'     \eqn{\mathrm{SE}(L/P) = \mathrm{SE}(L) / P}. Strictly a degenerate
#'     case of the delta method with `Var(P) = 0` and `Cov(L,P) = 0`.}
#'   \item{`"delta"`}{First-order Taylor (delta method) including exposure
#'     uncertainty and loss-exposure correlation `rho`:
#'     \eqn{\mathrm{Var}(L/P) \approx (\mathrm{SE}(L)/P)^2 +
#'       (L \cdot \mathrm{SE}(P) / P^2)^2 -
#'       2 \rho L \mathrm{SE}(L) \mathrm{SE}(P) / P^3}.
#'     The variance is clipped at zero before the square root (high `rho`
#'     can drive the linearised estimate negative).}
#' }
#'
#' Not exported; called only by [fit_ratio()]. The `"fixed"` branch
#' encodes the actuarial assumption that earned premium is known (not
#' estimated), so this helper is *not* a generic ratio-SE utility.
#'
#' @param loss Ultimate loss vector (`L`).
#' @param exposure Ultimate exposure vector (`E`).
#' @param loss_se `SE(L)`.
#' @param exposure_se `SE(P)`. Unused for `"fixed"`; may be `NULL`.
#' @param method One of `"fixed"` (default) or `"delta"`.
#' @param rho Loss-exposure correlation in `(-1, 1)`. Used only for
#'   `"delta"`. Default `0.95`.
#'
#' @return A numeric vector the same length as `loss`.
#'
#' @keywords internal
.compute_ratio_se <- function(loss,
                              exposure,
                              loss_se,
                              exposure_se = NULL,
                              method      = c("fixed", "delta"),
                              rho         = 0.95) {

  method <- match.arg(method)

  if (method == "fixed") {
    return(data.table::fifelse(
      is.finite(loss_se) & is.finite(exposure) & exposure != 0,
      loss_se / exposure, NA_real_
    ))
  }

  # delta: first-order Taylor with exposure variance + correlation
  ratio_var <- (loss_se / exposure)^2 +
               (loss * exposure_se / exposure^2)^2 -
               2 * rho * loss * loss_se * exposure_se / exposure^3
  se <- sqrt(pmax(ratio_var, 0))
  bad <- !is.finite(loss)    | !is.finite(exposure) |
         !is.finite(loss_se) | !is.finite(exposure_se) |
         exposure <= 0
  se[bad] <- NA_real_
  se
}


# Summary ------------------------------------------------------------------

#' Summarise an `RatioFit` object by cohort
#'
#' @param x An object of class `"RatioFit"`.
#'
#' @return The input object with `$summary` set.
#'
#' @keywords internal
.ratio_summary <- function(x) {

  .assert_class(x, "RatioFit")

  grp        <- x$groups
  coh        <- x$cohort
  full       <- x$full
  se_method  <- x$se_method
  rho        <- x$rho
  conf_level <- x$conf_level
  z_alpha    <- stats::qnorm((1 + conf_level) / 2)

  latest_obs <- full[is_observed == TRUE, .SD[.N], by = c(grp, "cohort")]
  ult        <- full[, .SD[.N],                    by = c(grp, "cohort")]
  agg <- latest_obs[ult, on = c(grp, "cohort")]

  agg[, `:=`(
    latest        = loss_obs,
    loss_ult      = i.loss_proj,
    reserve       = i.loss_proj - loss_obs,
    exposure_ult  = i.exposure_proj,
    ratio_latest  = data.table::fifelse(
      is.finite(exposure_obs) & exposure_obs != 0,
      loss_obs / exposure_obs, NA_real_
    ),
    ratio_ult     = i.ratio_proj,
    maturity_from = maturity_from,
    loss_proc_se  = i.loss_proc_se,
    loss_param_se = i.loss_param_se,
    loss_total_se = i.loss_total_se,
    loss_total_cv = data.table::fifelse(
      is.finite(i.loss_proj) & i.loss_proj != 0,
      i.loss_total_se / abs(i.loss_proj), NA_real_
    ),
    ratio_se      = i.ratio_se,
    ratio_cv      = i.ratio_cv,
    ratio_ci_lo   = i.ratio_ci_lo,
    ratio_ci_hi   = i.ratio_ci_hi
  )]

  keep_cols <- c(
    grp, "cohort",
    "latest", "loss_ult", "reserve", "exposure_ult",
    "ratio_latest", "ratio_ult", "maturity_from",
    "loss_proc_se", "loss_param_se", "loss_total_se", "loss_total_cv",
    "ratio_se", "ratio_cv",
    "ratio_ci_lo", "ratio_ci_hi"
  )

  if (se_method == "delta") {
    agg[, `:=`(
      exposure_total_se = i.exposure_total_se,
      exposure_total_cv = i.exposure_total_cv
    )]

    agg[, ("ratio_var") := ratio_se^2]

    agg[, `:=`(
      pct_loss     = data.table::fifelse(
        is.finite(ratio_var) & ratio_var > 0,
        (i.loss_total_se / i.exposure_proj)^2 / ratio_var * 100, NA_real_
      ),
      pct_exposure = data.table::fifelse(
        is.finite(ratio_var) & ratio_var > 0,
        (i.loss_proj * i.exposure_total_se / i.exposure_proj^2)^2 /
          ratio_var * 100, NA_real_
      ),
      pct_cov      = data.table::fifelse(
        is.finite(ratio_var) & ratio_var > 0,
        -2 * rho * i.loss_proj * i.loss_total_se * i.exposure_total_se /
          i.exposure_proj^3 / ratio_var * 100, NA_real_
      )
    )]

    agg[, ("ratio_var") := NULL]

    keep_cols <- c(keep_cols,
                   "exposure_total_se", "exposure_total_cv",
                   "pct_loss", "pct_exposure", "pct_cov")
  }

  x$summary <- agg[, .SD, .SDcols = keep_cols]

  x
}
