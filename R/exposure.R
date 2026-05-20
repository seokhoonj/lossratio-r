#' Fit a chain ladder projection on the exposure triangle
#'
#' @description
#' Project cumulative exposure across the cohort x development grid with
#' a chain ladder estimator. Two variance recursions are supported:
#'
#' \describe{
#'   \item{`"ed"` (default)}{Additive recursion. Empirically more robust
#'     on long-projection exposure triangles -- the multiplicative
#'     scaling of the classical CL recursion can blow up under cohort-wise
#'     heterogeneity (regime changes in premium, channel changes,
#'     amendments). See `dev/exposure_projection.qmd`.}
#'   \item{`"cl"`}{Mack (1993) multiplicative recursion. Point projection
#'     identical to ED; only the SE accumulation differs.}
#' }
#'
#' Both methods share the same point estimate -- self-weighted ED on
#' exposure is mathematically equivalent to chain ladder on the same
#' column (`f_k = 1 + g_k`). The only operational difference is how
#' cumulative variance is propagated forward.
#'
#' @param x A `"Triangle"` object. The standardized `"exposure"` column
#'   is used as the projection metric.
#' @param method One of `"ed"` (default) or `"cl"`.
#' @param alpha Numeric scalar controlling the variance structure passed
#'   through to [fit_ata()]. Default `1`.
#' @inheritParams fit_ata
#' @param regime Optional regime specification (exposure side). Accepts
#'   four input types:
#'   \describe{
#'     \item{`NULL` (default)}{No regime filter.}
#'     \item{`Regime` object}{Use as-is. Typically built via
#'       [detect_regime()] or [regime_at()].}
#'     \item{`"auto"`}{Detect regime internally via
#'       `detect_regime(x, loss = "ratio")` on the input triangle.}
#'     \item{Function / closure}{A user-supplied
#'       `function(tri) -> Regime` for deferred custom-config detection.}
#'   }
#'   Pre-change cohorts (cohorts before the resolved `Regime`'s change
#'   date) are excluded from exposure factor estimation.
#' @param recent Optional positive integer; recent calendar-diagonal
#'   filter for the underlying ATA fit. Default `NULL`.
#' @param tail Logical; whether to apply a tail factor. Default `FALSE`.
#' @param conf_level Confidence level for analytical CI on the exposure
#'   projection (`exposure_ci_lo`, `exposure_ci_hi`). Default `0.95`.
#' @param bootstrap Bootstrap configuration. Five forms accepted:
#'   \describe{
#'     \item{`NULL` (default)}{Auto-resolved by `method`: bootstrap for
#'       `"ed"`, analytical for `"cl"`. Same behavior as the legacy
#'       `bootstrap = NULL` shape.}
#'     \item{`TRUE` / `FALSE`}{Back-compat with the legacy logical arg.
#'       `TRUE` triggers `bootstrap = "auto"`; `FALSE` disables.}
#'     \item{`"auto"`}{Internal `bootstrap()` call on the exposure triangle
#'       with defaults `(type = "analytical", process = "normal",
#'       target = "exposure")`.}
#'     \item{`BootstrapTriangle`}{Pre-built object from `bootstrap()`.
#'       Must have `meta$target == "exposure"`.}
#'     \item{Function `function(tri) -> BootstrapTriangle`}{Lazy spec
#'       invoked on the input Triangle (leakage-safe for `backtest()`).}
#'   }
#'   Regardless of `method`, the bootstrap path uses CL recursion --
#'   exposure's self-anchor makes ED and CL algebraically equivalent
#'   (`g_k = f_k - 1`, `sigma^2_g = sigma^2_f`).
#' @param B Integer number of bootstrap replicates. Used only when
#'   `bootstrap` resolves to `"auto"`. Default `999L`.
#' @param seed Optional integer seed for reproducible bootstrap. Default
#'   `NULL`.
#'
#' @return An object of class `"ExposureFit"` (a list with the same
#'   structure as `CLFit`). Components: `selected`, `full`, `data`,
#'   plus attribute `exposure_method`. The `$full` data.table uses
#'   role-specific column names (`exposure_obs`, `exposure_proj`,
#'   `incr_exposure_proj`, `exposure_proc_se`, `exposure_param_se`,
#'   `exposure_total_se`, `exposure_proc_cv`, `exposure_param_cv`,
#'   `exposure_total_cv`, `exposure_ci_lo`, `exposure_ci_hi`). Under
#'   `bootstrap = TRUE`, `exposure_ci_lo` / `exposure_ci_hi` are bootstrap
#'   quantiles and `exposure_total_se` / `exposure_total_cv` are derived
#'   from the simulation SD; the analytical proc/param decomposition is
#'   retained as diagnostic.
#'
#' @seealso [fit_cl()], [fit_ed()], [fit_ratio()], [as_triangle()].
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
#' # ED-additive recursion (default; robust on long projections)
#' pf <- fit_exposure(tri)
#' summary(pf)
#'
#' # CL-multiplicative recursion (Mack)
#' pf_cl <- fit_exposure(tri, method = "cl")
#' }
#'
#' @export
fit_exposure <- function(x,
                         method       = c("ed", "cl"),
                         alpha        = 1,
                         regime       = NULL,
                         sigma_method = c("locf", "min_last2", "loglinear",
                                          "mack", "none"),
                         recent       = NULL,
                         tail         = FALSE,
                         conf_level   = 0.95,
                         bootstrap    = NULL,
                         B            = 999L,
                         seed         = NULL) {

  # data.table NSE bindings for R CMD check
  exposure_total_se <- exposure_total_cv <- exposure_ci_lo <- exposure_ci_hi <- NULL
  exposure_proj_boot <- exposure_param_se_boot <- exposure_proc_se_boot <- NULL
  exposure_total_se_boot <- exposure_total_cv_boot <- NULL
  exposure_ci_lo_boot <- exposure_ci_hi_boot <- NULL

  .assert_triangle_input(x, "fit_exposure()")
  method       <- match.arg(method)
  sigma_method <- match.arg(sigma_method)

  if (!is.numeric(conf_level) || length(conf_level) != 1L ||
      is.na(conf_level) || conf_level <= 0 || conf_level >= 1)
    stop("`conf_level` must be a single numeric value in (0, 1).",
         call. = FALSE)

  # Legacy back-compat: NULL maps to method-dependent default (ED ->
  # bootstrap, CL -> analytical). All other shapes flow through
  # `.resolve_bootstrap()` below.
  if (is.null(bootstrap)) {
    bootstrap <- if (method == "ed") "auto" else FALSE
  }
  if (!is.numeric(B) || length(B) != 1L || is.na(B) || B < 1L)
    stop("`B` must be a single positive integer.", call. = FALSE)
  B <- as.integer(B)

  # Resolve regime input (NULL / Regime / "auto" / function) -> NULL or Regime
  regime <- .resolve_regime(regime, x)

  grp <- attr(x, "groups")
  if (is.null(grp)) grp <- character(0)

  # 1) Worker call. Both CL and ED methods share the same exposure point
  # estimate (mathematically equivalent: g_k on self-projected exposure
  # collapses to f_k - 1). The two methods differ only in the variance
  # accumulation, which `.exposurefit_augment()` overlays for method = "ed".
  result <- fit_cl(
    x,
    method       = "mack",
    loss         = "exposure",
    alpha        = alpha,
    sigma_method = sigma_method,
    recent       = recent,
    regime       = regime,
    tail         = tail
  )

  # 2) Augment $full: variance overlay (method = "ed"), loss_* -> exposure_*
  # column rename, analytical CI bounds.
  result <- .exposurefit_augment(result, x, method, grp, conf_level)

  # 3) Bootstrap overlay (when requested). Replaces analytical SE / CI on
  # projected cells with empirical bootstrap values from the dedicated
  # exposure-side BootstrapTriangle.
  result <- .exposurefit_bootstrap(
    result, x, grp,
    bootstrap   = bootstrap,
    B           = B,
    seed        = seed,
    alpha       = alpha
  )

  # 4) Usage map. Exposure has no maturity concept (g_k -> 0), so we
  # bypass `.build_usage()`'s 2-pass detection and call
  # `.compute_triangle_usage()` directly with the pre-filter triangle.
  exposure_usage <- .compute_triangle_usage(
    x,
    recent  = recent,
    regime  = regime,
    holdout = NULL
  )
  data.table::setattr(exposure_usage, "regime",  regime)
  data.table::setattr(exposure_usage, "recent",  recent)
  data.table::setattr(exposure_usage, "holdout", NULL)
  data.table::setattr(exposure_usage, "m_k",     NULL)
  data.table::setattr(exposure_usage, "m_k_grid",  NULL)
  result$usage <- exposure_usage

  result$regime                   <- regime
  attr(result, "exposure_method") <- method
  attr(result, "conf_level")      <- conf_level
  class(result) <- c("ExposureFit", class(result))
  result
}


#' Augment a CL worker result into the ExposureFit `$full` schema
#'
#' @description
#' Applies (1) the ED-variance overlay when `method = "ed"`, (2) the
#' `loss_*` -> `exposure_*` column rename, and (3) the analytical CI
#' bounds. Mirrors the `.lossfit_augment()` helper in `R/loss.R`.
#'
#' @param result A `CLFit` from `fit_cl(loss = "exposure", ...)`.
#' @param x The original `Triangle`.
#' @param method One of `"cl"` / `"ed"`.
#' @param grp Character vector of group columns.
#' @param conf_level Confidence level for analytical CI bounds.
#'
#' @return The augmented `CLFit` with `$full` carrying `exposure_*` columns.
#'
#' @keywords internal
.exposurefit_augment <- function(result, x, method, grp, conf_level) {
  if (identical(method, "ed")) {
    result$full <- .apply_ed_variance(result$full, result$selected, x)
  }
  result$full <- .exposure_rename_full(result$full, grp, conf_level)
  result
}


#' Overlay bootstrap SE / CI onto an ExposureFit `$full`
#'
#' @description
#' Calls `.resolve_bootstrap()` to optionally build a `BootstrapTriangle`
#' on the exposure target, then maps its summary columns onto the
#' projected cells of `result$full`. Sets `result$ci_type` and a thin
#' `result$bootstrap` metadata list. Mirrors `.lossfit_bootstrap()` in
#' `R/loss.R`.
#'
#' @param result An augmented exposure fit (post `.exposurefit_augment()`).
#' @param x The original `Triangle`.
#' @param grp Character vector of group columns.
#' @param bootstrap,B,seed,alpha Forwarded to `.resolve_bootstrap()`.
#'
#' @return The updated fit with bootstrap CI overlaid on `$full` and
#'   `ci_type` / `bootstrap` slots set.
#'
#' @keywords internal
.exposurefit_bootstrap <- function(result, x, grp,
                                   bootstrap, B, seed, alpha) {
  exposure_total_se <- exposure_total_cv <- exposure_ci_lo <- exposure_ci_hi <- NULL
  exposure_proj_boot <- exposure_param_se_boot <- exposure_proc_se_boot <- NULL
  exposure_total_se_boot <- exposure_total_cv_boot <- NULL
  exposure_ci_lo_boot <- exposure_ci_hi_boot <- NULL

  boots <- .resolve_bootstrap(
    bootstrap, x,
    B           = B,
    seed        = seed,
    type        = "analytical",
    process     = "normal",
    target      = "exposure",
    alpha       = alpha,
    quantile_ci = TRUE,
    keep_pseudo = FALSE
  )

  if (!is.null(boots)) {
    bsum <- data.table::copy(boots$summary)
    data.table::setnames(
      bsum,
      c("mean_proj", "param_se", "proc_se", "total_se", "total_cv"),
      c("exposure_proj_boot", "exposure_param_se_boot", "exposure_proc_se_boot",
        "exposure_total_se_boot", "exposure_total_cv_boot")
    )
    has_ci <- all(c("ci_lo", "ci_hi") %in% names(bsum))
    if (has_ci) {
      data.table::setnames(bsum, c("ci_lo", "ci_hi"),
                                  c("exposure_ci_lo_boot", "exposure_ci_hi_boot"))
    }

    result$full <- merge(result$full, bsum,
                         by = c(grp, "cohort", "dev"), all.x = TRUE,
                         sort = FALSE)

    is_proj <- result$full$is_observed == FALSE
    result$full[is_proj & is.finite(exposure_total_se_boot), exposure_total_se := exposure_total_se_boot]
    result$full[is_proj & is.finite(exposure_total_cv_boot), exposure_total_cv := exposure_total_cv_boot]
    if (has_ci) {
      result$full[is_proj & is.finite(exposure_ci_lo_boot), exposure_ci_lo := exposure_ci_lo_boot]
      result$full[is_proj & is.finite(exposure_ci_hi_boot), exposure_ci_hi := exposure_ci_hi_boot]
    }
    drop_boot <- c("exposure_proj_boot", "exposure_param_se_boot",
                    "exposure_proc_se_boot", "exposure_total_se_boot",
                    "exposure_total_cv_boot")
    if (has_ci) drop_boot <- c(drop_boot, "exposure_ci_lo_boot", "exposure_ci_hi_boot")
    result$full[, (drop_boot) := NULL]
  }

  result$ci_type   <- if (!is.null(boots)) "bootstrap" else "analytical"
  result$bootstrap <- if (!is.null(boots))
                       list(B = boots$meta$B, seed = boots$meta$seed) else NULL
  result
}


#' Rename loss_* columns to exposure_* and add incr/CI columns
#'
#' @description
#' Translates the worker (`fit_cl`) output's `loss_*` columns to the
#' dispatcher's role-specific `exposure_*` names. Also derives
#' `incr_exposure_proj` (per-cohort first difference of `exposure_proj`)
#' and analytical CI bounds (`exposure_ci_lo`, `exposure_ci_hi`) from
#' `exposure_proj` +/- z * `exposure_total_se`.
#'
#' @keywords internal
.exposure_rename_full <- function(full, grp, conf_level) {
  full <- .copy_dt(full)

  rename_map <- c(
    loss_obs       = "exposure_obs",
    loss_proj      = "exposure_proj",
    incr_loss_proj = "incr_exposure_proj",
    loss_proc_se2  = "exposure_proc_se2",
    loss_param_se2 = "exposure_param_se2",
    loss_total_se2 = "exposure_total_se2",
    loss_proc_se   = "exposure_proc_se",
    loss_param_se  = "exposure_param_se",
    loss_total_se  = "exposure_total_se",
    loss_proc_cv   = "exposure_proc_cv",
    loss_param_cv  = "exposure_param_cv",
    loss_total_cv  = "exposure_total_cv"
  )
  present <- intersect(names(rename_map), names(full))
  if (length(present)) {
    data.table::setnames(full, present, unname(rename_map[present]))
  }

  # Derive incremental projection if not already present.
  if (!"incr_exposure_proj" %in% names(full)) {
    by_cols <- c(grp, "cohort")
    full[, ("incr_exposure_proj") := exposure_proj -
           data.table::shift(exposure_proj, 1L, fill = 0),
         by = by_cols]
  }

  # Analytical CI: exposure_proj +/- z * exposure_total_se (lower clipped at 0).
  z_alpha <- stats::qnorm((1 + conf_level) / 2)
  full[, `:=`(
    exposure_ci_lo = pmax(0, exposure_proj - z_alpha * exposure_total_se),
    exposure_ci_hi = exposure_proj + z_alpha * exposure_total_se
  )]

  full[]
}


#' Apply the ED additive variance recursion to a CL worker's `$full`
#'
#' @description
#' Point projection (`loss_proj`) is preserved -- it is identical under
#' both CL and self-weighted ED. Only the variance accumulation differs:
#'
#' \itemize{
#'   \item CL recursion: `proc_{k+1} = f^2 * proc_k + sigma^2 * C_k`
#'     (multiplicative scaling -- prior variance amplified by f^2 each
#'     step).
#'   \item ED recursion: `proc_{k+1} = proc_k + sigma^2 * C_k` (additive
#'     -- prior variance carried forward unchanged).
#' }
#'
#' Both share the same per-link `sigma^2` and `f_var` (= `Var(f_hat_k)`)
#' estimates. The recursion is per (group, cohort).
#'
#' @param full The `$full` data.table from a `CLFit` (must contain
#'   `cohort`, `dev`, `loss_obs`, `loss_proj`).
#' @param selected The `$selected` data.table (must contain `f_sel`,
#'   `sigma2`, `f_var`).
#' @param triangle The original `Triangle` (for `groups` attribute).
#'
#' @return Updated `full` data.table with `loss_proc_se2`,
#'   `loss_param_se2`, `loss_total_se2`, `loss_proc_se`,
#'   `loss_param_se`, `loss_total_se`, `loss_proc_cv`,
#'   `loss_param_cv`, `loss_total_cv` columns rebuilt under the ED
#'   recursion (column names match the upstream `fit_cl` worker
#'   convention; the dispatcher renames them to `exposure_*` afterwards).
#'
#' @keywords internal
.apply_ed_variance <- function(full, selected, triangle) {
  full <- .copy_dt(full)
  selected <- .copy_dt(selected)

  # Suppress R CMD check NOTEs for `data.table` temp columns referenced
  # bare inside `j` expressions later in this function.
  .is_obs <- NULL

  grp <- attr(triangle, "groups")
  if (is.null(grp)) grp <- character(0)

  f  <- selected$f_sel
  s2 <- selected$sigma2
  fv <- selected$f_var

  data.table::setorder(full, cohort, dev)
  full[, (".is_obs") := !is.na(loss_obs)]

  ed_one_cohort <- function(.dev, .obs, .vp) {
    K     <- length(.dev)
    proc  <- numeric(K)
    par   <- numeric(K)
    l_obs <- if (any(.obs)) max(.dev[.obs]) else NA_integer_

    if (!is.finite(l_obs)) return(list(proc = proc, par = par))

    for (i in seq_len(K - 1L)) {
      k <- .dev[i]                # source dev (link from k -> k+1)
      Cpk <- .vp[i]
      if (k < l_obs) {
        next
      }
      if (k >= length(s2) + 1L) {
        proc[i + 1L] <- proc[i]
        par[i + 1L]  <- par[i]
        next
      }
      proc[i + 1L] <- proc[i]
      par[i + 1L]  <- par[i]
      if (is.finite(s2[k]) && is.finite(Cpk) && Cpk > 0) {
        proc[i + 1L] <- proc[i + 1L] + s2[k] * Cpk
      }
      if (is.finite(fv[k]) && is.finite(Cpk)) {
        par[i + 1L] <- par[i + 1L] + (Cpk ^ 2) * fv[k]
      }
    }
    list(proc = proc, par = par)
  }

  by_cols <- c(grp, "cohort")
  full[, c("loss_proc_se2", "loss_param_se2") := {
    r <- ed_one_cohort(dev, .is_obs, loss_proj)
    list(r$proc, r$par)
  }, by = by_cols]

  full[, ("loss_total_se2") := loss_proc_se2 + loss_param_se2]
  full[, ("loss_proc_se")   := sqrt(pmax(loss_proc_se2, 0))]
  full[, ("loss_param_se")  := sqrt(pmax(loss_param_se2, 0))]
  full[, ("loss_total_se")  := sqrt(pmax(loss_total_se2, 0))]
  full[, ("loss_proc_cv")   := data.table::fifelse(
    is.finite(loss_proj) & loss_proj != 0,
    loss_proc_se / loss_proj, NA_real_)]
  full[, ("loss_param_cv") := data.table::fifelse(
    is.finite(loss_proj) & loss_proj != 0,
    loss_param_se / loss_proj, NA_real_)]
  full[, ("loss_total_cv") := data.table::fifelse(
    is.finite(loss_proj) & loss_proj != 0,
    loss_total_se / loss_proj, NA_real_)]

  # Mask observed cells
  full[.is_obs == TRUE,
       c("loss_proc_se2", "loss_param_se2", "loss_total_se2",
         "loss_proc_se",  "loss_param_se",  "loss_total_se",
         "loss_proc_cv",  "loss_param_cv",  "loss_total_cv") :=
       rep(list(NA_real_), 9L)]

  full[, (".is_obs") := NULL]
  full[]
}


#' Print method for `ExposureFit`
#' @param x An `ExposureFit` object.
#' @param ... Unused.
#' @export
print.ExposureFit <- function(x, ...) {
  grp    <- x$groups
  if (is.null(grp)) grp <- character(0)
  method <- attr(x, "exposure_method")

  static_labels <- c("method", "alpha", "sigma_method", "recent", "regime",
                     "ci_type", "groups", "n_cohorts", "n_links")
  lw  <- max(nchar(static_labels))
  pad <- function(label) formatC(label, width = lw, flag = "-")

  cat("<ExposureFit>\n")
  cat(pad("method"),       ":", method,         "\n")
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

  if (length(grp)) {
    cat(pad("groups"), ":", paste(grp, collapse = ", "), "\n")
  } else {
    cat(pad("groups"), ": none\n", sep = "")
  }

  cat(pad("n_cohorts"), ":", length(unique(x$full$cohort)), "\n")
  cat(pad("n_links"),   ":", nrow(x$selected),              "\n")
  invisible(x)
}


#' Summary method for `ExposureFit`
#' @param object An `ExposureFit` object.
#' @param ... Unused.
#' @export
summary.ExposureFit <- function(object, ...) {
  grp <- object$groups
  if (is.null(grp)) grp <- character(0)

  full <- .copy_dt(object$full)
  by_cols <- c(grp, "cohort")
  out <- full[, .SD[which.max(dev)], by = by_cols]
  keep <- c(by_cols, "exposure_proj", "exposure_total_se", "exposure_total_cv")
  out <- out[, .SD, .SDcols = keep]
  data.table::setnames(out, "exposure_proj", "exposure_ult")
  out[]
}
