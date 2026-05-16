#' Fit a chain ladder projection on the prem (exposure) triangle
#'
#' @description
#' Project cumulative prem across the cohort x development grid with
#' a chain ladder estimator. Two variance recursions are supported:
#'
#' \describe{
#'   \item{`"ed"` (default)}{Additive recursion. Empirically more robust
#'     on long-projection prem triangles -- the multiplicative
#'     scaling of the classical CL recursion can blow up under cohort-wise
#'     heterogeneity (regime changes in premium, channel changes,
#'     amendments). See `dev/prem_projection.qmd`.}
#'   \item{`"cl"`}{Mack (1993) multiplicative recursion. Point projection
#'     identical to ED; only the SE accumulation differs.}
#' }
#'
#' Both methods share the same point estimate -- self-weighted ED on
#' prem is mathematically equivalent to chain ladder on the same
#' column (`f_k = 1 + g_k`). The only operational difference is how
#' cumulative variance is propagated forward.
#'
#' @param x A `"Triangle"` object. The standardized `"prem"` column
#'   is used as the projection target.
#' @param method One of `"ed"` (default) or `"cl"`.
#' @param alpha Numeric scalar controlling the variance structure passed
#'   through to [fit_ata()]. Default `1`.
#' @param sigma_method Sigma extrapolation method. One of `"locf"`
#'   (default), `"min_last2"`, or `"loglinear"`.
#' @param regime Optional regime specification (prem side). Accepts
#'   four input types:
#'   \describe{
#'     \item{`NULL` (default)}{No regime filter.}
#'     \item{`Regime` object}{Use as-is. Typically built via
#'       [detect_regime()] or [regime_at()].}
#'     \item{`"auto"`}{Detect regime internally via
#'       `detect_regime(x, target = "lr")` on the input triangle.}
#'     \item{Function / closure}{A user-supplied
#'       `function(tri) -> Regime` for deferred custom-config detection.}
#'   }
#'   Pre-change cohorts (cohorts before the resolved `Regime`'s change
#'   date) are excluded from prem factor estimation.
#' @param recent Optional positive integer; recent calendar-diagonal
#'   filter for the underlying ATA fit. Default `NULL`.
#' @param tail Logical; whether to apply a tail factor. Default `FALSE`.
#' @param conf_level Confidence level for analytical CI on the prem
#'   projection (`prem_ci_lo`, `prem_ci_hi`). Default `0.95`.
#' @param bootstrap Bootstrap configuration. Five forms accepted:
#'   \describe{
#'     \item{`NULL` (default)}{Auto-resolved by `method`: bootstrap for
#'       `"ed"`, analytical for `"cl"`. Same behavior as the legacy
#'       `bootstrap = NULL` shape.}
#'     \item{`TRUE` / `FALSE`}{Back-compat with the legacy logical arg.
#'       `TRUE` triggers `bootstrap = "auto"`; `FALSE` disables.}
#'     \item{`"auto"`}{Internal `bootstrap()` call on the premium triangle
#'       with defaults `(type = "parametric", process = "normal",
#'       target = "prem")`.}
#'     \item{`BootstrapTriangle`}{Pre-built object from `bootstrap()`.
#'       Must have `meta$target == "prem"`.}
#'     \item{Function `function(tri) -> BootstrapTriangle`}{Lazy spec
#'       invoked on the input Triangle (leakage-safe for `backtest()`).}
#'   }
#'   Regardless of `method`, the bootstrap path uses CL recursion --
#'   premium's self-anchor makes ED and CL algebraically equivalent
#'   (`g_k = f_k - 1`, `sigma^2_g = sigma^2_f`).
#' @param B Integer number of bootstrap replicates. Used only when
#'   `bootstrap` resolves to `"auto"`. Default `999`.
#' @param seed Optional integer seed for reproducible bootstrap. Default
#'   `NULL`.
#'
#' @return An object of class `"PremiumFit"` (a list with the same
#'   structure as `CLFit`). Components: `selected`, `full`, `data`,
#'   plus attribute `premium_method`. The `$full` data.table uses
#'   role-specific column names (`prem_obs`, `prem_proj`,
#'   `incr_prem_proj`, `prem_proc_se`, `prem_param_se`,
#'   `prem_total_se`, `prem_proc_cv`, `prem_param_cv`,
#'   `prem_total_cv`, `prem_ci_lo`, `prem_ci_hi`). Under
#'   `bootstrap = TRUE`, `prem_ci_lo` / `prem_ci_hi` are bootstrap
#'   quantiles and `prem_total_se` / `prem_total_cv` are derived from
#'   the simulation SD; the analytical proc/param decomposition is
#'   retained as diagnostic.
#'
#' @seealso [fit_cl()], [fit_ed()], [fit_lr()], [as_triangle()].
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
#'   premium  = "incr_prem"
#' )
#'
#' # ED-additive recursion (default; robust on long projections)
#' pf <- fit_premium(tri)
#' summary(pf)
#'
#' # CL-multiplicative recursion (Mack)
#' pf_cl <- fit_premium(tri, method = "cl")
#' }
#'
#' @export
fit_premium <- function(x,
                        method       = c("ed", "cl"),
                        alpha        = 1,
                        regime       = NULL,
                        sigma_method = c("locf", "min_last2", "loglinear"),
                        recent       = NULL,
                        tail         = FALSE,
                        conf_level   = 0.95,
                        bootstrap    = NULL,
                        B            = 999,
                        seed         = NULL) {

  .assert_triangle_input(x, "fit_premium()")
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

  # Run chain ladder underneath (Mack-style SE). Point estimate is
  # identical for both methods; ED only differs in SE accumulation.
  # Uses the standardized `"prem"` column on the Triangle.
  cl_fit <- fit_cl(
    x,
    method       = "mack",
    target       = "prem",
    alpha        = alpha,
    sigma_method = sigma_method,
    recent       = recent,
    regime       = regime,
    tail         = tail
  )

  if (method == "ed") {
    cl_fit$full <- .ed_replace_se(cl_fit$full, cl_fit$selected, x)
  }

  # Rename target_* columns to role-specific prem_* names on $full.
  grp <- attr(x, "groups")
  if (is.null(grp)) grp <- character(0)

  cl_fit$full <- .prem_rename_full(cl_fit$full, grp, conf_level)

  # Bootstrap path (Phase 2 — new pipeline). Overwrites prem_ci_lo /
  # prem_ci_hi / prem_total_se / prem_total_cv from the Triangle-level
  # bootstrap + per-replicate CL refit + Stage 2 process noise. The
  # analytical proc/param decomposition (prem_proc_se / prem_param_se)
  # is preserved as a diagnostic and not overwritten.
  boots <- .resolve_bootstrap(
    bootstrap, x,
    B       = B,
    seed    = seed,
    type    = "parametric",
    process = "normal",
    target  = "prem",
    alpha   = alpha
  )

  if (!is.null(boots)) {
    refit  <- .boot_refit(x, boots, method = "cl", alpha = alpha)
    # `.boot_refit()` now returns cell_real (chain-propagated process
    # noise baked in via the boots$meta$process distribution). Skip the
    # legacy `.boot_add_process_noise()` per-cell pass-through.
    se     <- .boot_summarize_se(refit, grp = grp)

    # Map worker-generic target_* names to role-specific prem_* names.
    data.table::setnames(se,
      c("target_proj", "target_total_se", "target_total_cv",
        "target_ci_lo", "target_ci_hi"),
      c("prem_proj_boot", "prem_total_se_boot", "prem_total_cv_boot",
        "prem_ci_lo_boot", "prem_ci_hi_boot"))
    se[, c("target_proc_se", "target_param_se") := NULL]

    cl_fit$full <- merge(cl_fit$full,
                         se[, .SD, .SDcols = c(grp, "cohort", "dev",
                                                "prem_ci_lo_boot",
                                                "prem_ci_hi_boot",
                                                "prem_total_se_boot",
                                                "prem_total_cv_boot")],
                         by = c(grp, "cohort", "dev"), all.x = TRUE,
                         sort = FALSE)

    # Overwrite the analytical CI/SE columns for projected cells. Observed
    # cells (cell_proc_var = 0 across reps) keep the analytical 0-SE since
    # the bootstrap output for them is degenerate.
    # Only override SE/CI for non-observed cells. Observed cells keep
    # their analytical SE = 0 (the value is known); under residual
    # bootstrap, the alt observed cells get perturbed and would otherwise
    # produce a spurious nonzero SE.
    is_proj <- cl_fit$full$is_observed == FALSE
    cl_fit$full[is_proj & is.finite(prem_ci_lo_boot),    prem_ci_lo    := prem_ci_lo_boot]
    cl_fit$full[is_proj & is.finite(prem_ci_hi_boot),    prem_ci_hi    := prem_ci_hi_boot]
    cl_fit$full[is_proj & is.finite(prem_total_se_boot), prem_total_se := prem_total_se_boot]
    cl_fit$full[is_proj & is.finite(prem_total_cv_boot), prem_total_cv := prem_total_cv_boot]
    cl_fit$full[, c("prem_ci_lo_boot", "prem_ci_hi_boot",
                     "prem_total_se_boot", "prem_total_cv_boot") := NULL]
  }

  cl_fit$ci_type   <- if (!is.null(boots)) "bootstrap" else "analytical"
  cl_fit$bootstrap <- if (!is.null(boots))
                       list(B = boots$meta$B, seed = boots$meta$seed) else NULL

  # Usage map. Premium has no maturity concept (g_k -> 0), so we
  # bypass `.build_usage()`'s 2-pass detection and call
  # `.compute_triangle_usage()` directly with the pre-filter triangle.
  prem_usage <- .compute_triangle_usage(
    x,
    recent  = recent,
    regime  = regime,
    holdout = NULL
  )
  data.table::setattr(prem_usage, "regime",  regime)
  data.table::setattr(prem_usage, "recent",  recent)
  data.table::setattr(prem_usage, "holdout", NULL)
  data.table::setattr(prem_usage, "m_k",     NULL)
  data.table::setattr(prem_usage, "m_k_dt",  NULL)
  cl_fit$usage <- prem_usage

  cl_fit$regime                  <- regime
  attr(cl_fit, "premium_method") <- method
  attr(cl_fit, "conf_level")     <- conf_level
  class(cl_fit) <- c("PremiumFit", class(cl_fit))
  cl_fit
}


#' Rename target_* columns to prem_* and add incr/CI columns
#'
#' @description
#' Translates the worker (`fit_cl`) output's `target_*` columns to the
#' dispatcher's role-specific `prem_*` names. Also derives
#' `incr_prem_proj` (per-cohort first difference of `prem_proj`) and
#' analytical CI bounds (`prem_ci_lo`, `prem_ci_hi`) from
#' `prem_proj` +/- z * `prem_total_se`.
#'
#' @keywords internal
.prem_rename_full <- function(full, grp, conf_level) {
  full <- data.table::copy(.copy_dt(full))

  rename_map <- c(
    target_obs       = "prem_obs",
    target_proj      = "prem_proj",
    incr_target_proj = "incr_prem_proj",
    target_proc_se2  = "prem_proc_se2",
    target_param_se2 = "prem_param_se2",
    target_total_se2 = "prem_total_se2",
    target_proc_se   = "prem_proc_se",
    target_param_se  = "prem_param_se",
    target_total_se  = "prem_total_se",
    target_proc_cv   = "prem_proc_cv",
    target_param_cv  = "prem_param_cv",
    target_total_cv  = "prem_total_cv"
  )
  present <- intersect(names(rename_map), names(full))
  if (length(present)) {
    data.table::setnames(full, present, unname(rename_map[present]))
  }

  # Derive incremental projection if not already present.
  if (!"incr_prem_proj" %in% names(full)) {
    by_cols <- c(grp, "cohort")
    full[, ("incr_prem_proj") := prem_proj -
           data.table::shift(prem_proj, 1L, fill = 0),
         by = by_cols]
  }

  # Analytical CI: prem_proj +/- z * prem_total_se (lower clipped at 0).
  z_alpha <- stats::qnorm((1 + conf_level) / 2)
  full[, `:=`(
    prem_ci_lo = pmax(0, prem_proj - z_alpha * prem_total_se),
    prem_ci_hi = prem_proj + z_alpha * prem_total_se
  )]

  full[]
}


#' Replace CL multiplicative SE with ED additive SE on a CLFit's `$full`
#'
#' @description
#' Point projection (`target_proj`) is preserved -- it is identical under
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
#'   `cohort`, `dev`, `target_obs`, `target_proj`).
#' @param selected The `$selected` data.table (must contain `f_sel`,
#'   `sigma2`, `f_var`).
#' @param triangle The original `Triangle` (for `groups` attribute).
#'
#' @return Updated `full` data.table with `target_proc_se2`,
#'   `target_param_se2`, `target_total_se2`, `target_proc_se`,
#'   `target_param_se`, `target_total_se`, `target_proc_cv`,
#'   `target_param_cv`, `target_total_cv` columns rebuilt under the ED
#'   recursion (column names match the upstream `fit_cl` worker
#'   convention; the dispatcher renames them to `prem_*` afterwards).
#'
#' @keywords internal
.ed_replace_se <- function(full, selected, triangle) {
  full <- data.table::copy(.copy_dt(full))
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
  full[, (".is_obs") := !is.na(target_obs)]

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
  full[, c("target_proc_se2", "target_param_se2") := {
    r <- ed_one_cohort(dev, .is_obs, target_proj)
    list(r$proc, r$par)
  }, by = by_cols]

  full[, ("target_total_se2") := target_proc_se2 + target_param_se2]
  full[, ("target_proc_se")   := sqrt(pmax(target_proc_se2, 0))]
  full[, ("target_param_se")  := sqrt(pmax(target_param_se2, 0))]
  full[, ("target_total_se")  := sqrt(pmax(target_total_se2, 0))]
  full[, ("target_proc_cv")   := data.table::fifelse(
    is.finite(target_proj) & target_proj != 0,
    target_proc_se / target_proj, NA_real_)]
  full[, ("target_param_cv") := data.table::fifelse(
    is.finite(target_proj) & target_proj != 0,
    target_param_se / target_proj, NA_real_)]
  full[, ("target_total_cv") := data.table::fifelse(
    is.finite(target_proj) & target_proj != 0,
    target_total_se / target_proj, NA_real_)]

  # Mask observed cells
  full[.is_obs == TRUE,
       c("target_proc_se2", "target_param_se2", "target_total_se2",
         "target_proc_se",  "target_param_se",  "target_total_se",
         "target_proc_cv",  "target_param_cv",  "target_total_cv") :=
       rep(list(NA_real_), 9L)]

  full[, (".is_obs") := NULL]
  full[]
}


#' Print method for `PremiumFit`
#' @param x A `PremiumFit` object.
#' @param ... Unused.
#' @export
print.PremiumFit <- function(x, ...) {
  grp    <- x$groups
  if (is.null(grp)) grp <- character(0)
  method <- attr(x, "premium_method")

  static_labels <- c("method", "alpha", "sigma_method", "recent", "regime",
                     "ci_type", "groups", "n_cohorts", "n_links")
  lw  <- max(nchar(static_labels))
  pad <- function(label) formatC(label, width = lw, flag = "-")

  cat("<PremiumFit>\n")
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


#' Summary method for `PremiumFit`
#' @param object A `PremiumFit` object.
#' @param ... Unused.
#' @export
summary.PremiumFit <- function(object, ...) {
  grp <- object$groups
  if (is.null(grp)) grp <- character(0)

  full <- .copy_dt(object$full)
  by_cols <- c(grp, "cohort")
  out <- full[, .SD[which.max(dev)], by = by_cols]
  keep <- c(by_cols, "prem_proj", "prem_total_se", "prem_total_cv")
  out <- out[, .SD, .SDcols = keep]
  data.table::setnames(out, "prem_proj", "prem_ult")
  out[]
}
