#' Fit a chain ladder projection on the premium (exposure) triangle
#'
#' @description
#' Project cumulative premium across the cohort x development grid with
#' a chain ladder estimator. Two variance recursions are supported:
#'
#' \describe{
#'   \item{`"ed"` (default)}{Additive recursion. Empirically more robust
#'     on long-projection premium triangles -- the multiplicative
#'     scaling of the classical CL recursion can blow up under cohort-wise
#'     heterogeneity (regime breaks in premium, channel changes,
#'     amendments). See `dev/premium_projection.qmd`.}
#'   \item{`"cl"`}{Mack (1993) multiplicative recursion. Point projection
#'     identical to ED; only the SE accumulation differs.}
#' }
#'
#' Both methods share the same point estimate -- self-weighted ED on
#' premium is mathematically equivalent to chain ladder on the same
#' column (`f_k = 1 + g_k`). The only operational difference is how
#' cumulative variance is propagated forward.
#'
#' @param x A `"Triangle"` object. The standardized `"premium"` column
#'   is used as the projection target.
#' @param method One of `"ed"` (default) or `"cl"`.
#' @param alpha Numeric scalar controlling the variance structure passed
#'   through to [fit_ata()]. Default `1`.
#' @param sigma_method Sigma extrapolation method. One of `"locf"`
#'   (default), `"min_last2"`, or `"loglinear"`.
#' @param recent Optional positive integer; recent calendar-diagonal
#'   filter for the underlying ATA fit. Default `NULL`.
#' @param regime_break Optional cohort cutoff for a regime break (premium
#'   side). `NULL` (default), a `Date`/character, a vector (uses the
#'   latest), or a `Regime` object. Pre-break cohorts are excluded from
#'   premium factor estimation.
#' @param tail Logical; whether to apply a tail factor. Default `FALSE`.
#' @param conf_level Confidence level for analytical CI on the premium
#'   projection (`premium_ci_lower`, `premium_ci_upper`). Default `0.95`.
#'
#' @return An object of class `"PremiumFit"` (a list with the same
#'   structure as `CLFit`). Components: `selected`, `full`, `data`,
#'   plus attribute `premium_method`. The `$full` data.table uses
#'   role-specific column names (`premium_obs`, `premium_proj`,
#'   `premium_incr_proj`, `premium_proc_se`, `premium_param_se`,
#'   `premium_total_se`, `premium_proc_cv`, `premium_param_cv`,
#'   `premium_total_cv`, `premium_ci_lower`, `premium_ci_upper`).
#'
#' @seealso [fit_cl()], [fit_ed()], [fit_lr()], [build_triangle()].
#'
#' @examples
#' \dontrun{
#' data(experience)
#' tri <- build_triangle(experience[coverage == "SUR"], groups = coverage)
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
                        sigma_method = c("locf", "min_last2", "loglinear"),
                        recent       = NULL,
                        regime_break = NULL,
                        tail         = FALSE,
                        conf_level   = 0.95) {

  .assert_triangle_input(x, "fit_premium()")
  method       <- match.arg(method)
  sigma_method <- match.arg(sigma_method)

  if (!is.numeric(conf_level) || length(conf_level) != 1L ||
      is.na(conf_level) || conf_level <= 0 || conf_level >= 1)
    stop("`conf_level` must be a single numeric value in (0, 1).",
         call. = FALSE)

  # Run chain ladder underneath (Mack-style SE). Point estimate is
  # identical for both methods; ED only differs in SE accumulation.
  # Uses the standardized `"premium"` column on the Triangle.
  cl_fit <- fit_cl(
    x,
    method       = "mack",
    target       = "premium",
    alpha        = alpha,
    sigma_method = sigma_method,
    recent       = recent,
    regime_break = regime_break,
    tail         = tail
  )

  if (method == "ed") {
    cl_fit$full <- .ed_replace_se(cl_fit$full, cl_fit$selected, x)
  }

  # Rename target_* columns to role-specific premium_* names on $full.
  grp <- attr(x, "group_var")
  if (is.null(grp)) grp <- character(0)

  cl_fit$full <- .premium_rename_full(cl_fit$full, grp, conf_level)

  attr(cl_fit, "premium_method") <- method
  attr(cl_fit, "conf_level")     <- conf_level
  class(cl_fit) <- c("PremiumFit", class(cl_fit))
  cl_fit
}


#' Rename target_* columns to premium_* and add incr/CI columns
#'
#' @description
#' Translates the worker (`fit_cl`) output's `target_*` columns to the
#' dispatcher's role-specific `premium_*` names. Also derives
#' `premium_incr_proj` (per-cohort first difference of `premium_proj`) and
#' analytical CI bounds (`premium_ci_lower`, `premium_ci_upper`) from
#' `premium_proj` +/- z * `premium_total_se`.
#'
#' @keywords internal
.premium_rename_full <- function(full, grp, conf_level) {
  full <- data.table::copy(.ensure_dt(full))

  rename_map <- c(
    target_obs       = "premium_obs",
    target_proj      = "premium_proj",
    target_incr_proj = "premium_incr_proj",
    target_proc_se2  = "premium_proc_se2",
    target_param_se2 = "premium_param_se2",
    target_total_se2 = "premium_total_se2",
    target_proc_se   = "premium_proc_se",
    target_param_se  = "premium_param_se",
    target_total_se  = "premium_total_se",
    target_proc_cv   = "premium_proc_cv",
    target_param_cv  = "premium_param_cv",
    target_total_cv  = "premium_total_cv"
  )
  present <- intersect(names(rename_map), names(full))
  if (length(present)) {
    data.table::setnames(full, present, unname(rename_map[present]))
  }

  # Derive incremental projection if not already present.
  if (!"premium_incr_proj" %in% names(full)) {
    by_cols <- c(grp, "cohort")
    full[, premium_incr_proj := premium_proj -
           data.table::shift(premium_proj, 1L, fill = 0),
         by = by_cols]
  }

  # Analytical CI: premium_proj +/- z * premium_total_se (lower clipped at 0).
  z_alpha <- stats::qnorm((1 + conf_level) / 2)
  full[, `:=`(
    premium_ci_lower = pmax(0, premium_proj - z_alpha * premium_total_se),
    premium_ci_upper = premium_proj + z_alpha * premium_total_se
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
#' @param selected The `$selected` data.table (must contain `f_selected`,
#'   `sigma2`, `f_var`).
#' @param triangle The original `Triangle` (for `group_var` attribute).
#'
#' @return Updated `full` data.table with `target_proc_se2`,
#'   `target_param_se2`, `target_total_se2`, `target_proc_se`,
#'   `target_param_se`, `target_total_se`, `target_proc_cv`,
#'   `target_param_cv`, `target_total_cv` columns rebuilt under the ED
#'   recursion (column names match the upstream `fit_cl` worker
#'   convention; the dispatcher renames them to `premium_*` afterwards).
#'
#' @keywords internal
.ed_replace_se <- function(full, selected, triangle) {
  full <- data.table::copy(.ensure_dt(full))
  selected <- .ensure_dt(selected)

  grp <- attr(triangle, "group_var")
  if (is.null(grp)) grp <- character(0)

  f  <- selected$f_selected
  s2 <- selected$sigma2
  fv <- selected$f_var

  data.table::setorder(full, cohort, dev)
  full[, .is_obs := !is.na(target_obs)]

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

  full[, target_total_se2 := target_proc_se2 + target_param_se2]
  full[, target_proc_se  := sqrt(pmax(target_proc_se2, 0))]
  full[, target_param_se := sqrt(pmax(target_param_se2, 0))]
  full[, target_total_se := sqrt(pmax(target_total_se2, 0))]
  full[, target_proc_cv  := data.table::fifelse(
    is.finite(target_proj) & target_proj != 0,
    target_proc_se / target_proj, NA_real_)]
  full[, target_param_cv := data.table::fifelse(
    is.finite(target_proj) & target_proj != 0,
    target_param_se / target_proj, NA_real_)]
  full[, target_total_cv := data.table::fifelse(
    is.finite(target_proj) & target_proj != 0,
    target_total_se / target_proj, NA_real_)]

  # Mask observed cells
  full[.is_obs == TRUE, `:=`(
    target_proc_se2  = NA_real_, target_param_se2 = NA_real_,
    target_total_se2 = NA_real_,
    target_proc_se   = NA_real_, target_param_se  = NA_real_,
    target_total_se  = NA_real_,
    target_proc_cv   = NA_real_, target_param_cv  = NA_real_,
    target_total_cv  = NA_real_
  )]

  full[, .is_obs := NULL]
  full[]
}


#' Print method for `PremiumFit`
#' @param x A `PremiumFit` object.
#' @param ... Unused.
#' @export
print.PremiumFit <- function(x, ...) {
  method <- attr(x, "premium_method")
  cat("PremiumFit\n")
  cat("  variance     :", switch(method,
    ed = "ED-additive recursion",
    cl = "CL-multiplicative recursion (Mack)"), "\n")
  cat("  n_cohorts    :", length(unique(x$full$cohort)), "\n")
  cat("  n_links      :", nrow(x$selected), "\n")
  invisible(x)
}


#' Summary method for `PremiumFit`
#' @param object A `PremiumFit` object.
#' @param ... Unused.
#' @export
summary.PremiumFit <- function(object, ...) {
  full <- as.data.table(object$full)
  out <- full[, .SD[which.max(dev)], by = cohort]
  out[, .(cohort,
          ultimate    = premium_proj,
          se_ultimate = premium_total_se,
          cv_ultimate = premium_total_cv)]
}
