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
#' @param x A `"Triangle"` object.
#' @param target Column to project. Default `"premium"`. Accepts bare
#'   column reference (NSE) or string.
#' @param method One of `"ed"` (default) or `"cl"`.
#' @param alpha Numeric scalar controlling the variance structure passed
#'   through to [fit_ata()]. Default `1`.
#' @param sigma_method Sigma extrapolation method. One of `"locf"`
#'   (default), `"min_last2"`, or `"loglinear"`.
#' @param recent Optional positive integer; recent calendar-diagonal
#'   filter for the underlying ATA fit. Default `NULL`.
#' @param tail Logical; whether to apply a tail factor. Default `FALSE`.
#'
#' @return An object of class `"PremiumFit"` (a list with the same
#'   structure as `CLFit`). Components: `selected`, `full`, `data`,
#'   plus attributes `premium_method` and `target`.
#'
#' @seealso [fit_cl()], [fit_ed()], [fit_lr()], [build_triangle()].
#'
#' @examples
#' \dontrun{
#' data(experience)
#' tri <- build_triangle(experience[coverage == "SUR"], group_var = coverage)
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
                        target       = "premium",
                        method       = c("ed", "cl"),
                        alpha        = 1,
                        sigma_method = c("locf", "min_last2", "loglinear"),
                        recent       = NULL,
                        regime_break = NULL,
                        tail         = FALSE) {

  .assert_triangle_input(x, "fit_premium()")
  method       <- match.arg(method)
  sigma_method <- match.arg(sigma_method)

  tgt_var <- .capture_names(x, !!rlang::enquo(target))
  if (length(tgt_var) != 1L)
    stop("`target` must resolve to exactly one column.", call. = FALSE)

  # Run chain ladder underneath (Mack-style SE). Point estimate is
  # identical for both methods; ED only differs in SE accumulation.
  cl_fit <- fit_cl(
    x,
    method       = "mack",
    loss_var     = tgt_var,
    alpha        = alpha,
    sigma_method = sigma_method,
    recent       = recent,
    regime_break = regime_break,
    tail         = tail
  )

  if (method == "ed") {
    cl_fit$full <- .ed_replace_se(cl_fit$full, cl_fit$selected, x)
  }

  attr(cl_fit, "premium_method") <- method
  attr(cl_fit, "target")         <- tgt_var
  class(cl_fit) <- c("PremiumFit", class(cl_fit))
  cl_fit
}


#' Replace CL multiplicative SE with ED additive SE on a CLFit's `$full`
#'
#' @description
#' Point projection (`value_proj`) is preserved -- it is identical under
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
#'   `cohort`, `dev`, `value_obs`, `value_proj`).
#' @param selected The `$selected` data.table (must contain `f_selected`,
#'   `sigma2`, `f_var`).
#' @param triangle The original `Triangle` (for `group_var` attribute).
#'
#' @return Updated `full` data.table with `proc_se2`, `param_se2`,
#'   `total_se2`, `proc_se`, `param_se`, `se_proj`, `proc_cv`,
#'   `param_cv`, `cv_proj` columns rebuilt under the ED recursion.
#'
#' @keywords internal
.ed_replace_se <- function(full, selected, triangle) {
  full <- data.table::copy(.ensure_dt(full))
  selected <- .ensure_dt(selected)

  grp_var <- attr(triangle, "group_var")
  if (is.null(grp_var)) grp_var <- character(0)

  f  <- selected$f_selected
  s2 <- selected$sigma2
  fv <- selected$f_var

  data.table::setorder(full, cohort, dev)
  full[, .is_obs := !is.na(value_obs)]

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

  by_cols <- c(grp_var, "cohort")
  full[, c("proc_se2", "param_se2") := {
    r <- ed_one_cohort(dev, .is_obs, value_proj)
    list(r$proc, r$par)
  }, by = by_cols]

  full[, total_se2 := proc_se2 + param_se2]
  full[, proc_se  := sqrt(pmax(proc_se2, 0))]
  full[, param_se := sqrt(pmax(param_se2, 0))]
  full[, se_proj  := sqrt(pmax(total_se2, 0))]
  full[, proc_cv  := data.table::fifelse(
    is.finite(value_proj) & value_proj != 0,
    proc_se / value_proj, NA_real_)]
  full[, param_cv := data.table::fifelse(
    is.finite(value_proj) & value_proj != 0,
    param_se / value_proj, NA_real_)]
  full[, cv_proj  := data.table::fifelse(
    is.finite(value_proj) & value_proj != 0,
    se_proj / value_proj, NA_real_)]

  # Mask observed cells
  full[.is_obs == TRUE, `:=`(
    proc_se2  = NA_real_, param_se2 = NA_real_, total_se2 = NA_real_,
    proc_se   = NA_real_, param_se  = NA_real_, se_proj   = NA_real_,
    proc_cv   = NA_real_, param_cv  = NA_real_, cv_proj   = NA_real_
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
  target <- attr(x, "target")
  cat("PremiumFit\n")
  cat("  target       :", target, "\n")
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
  out[, .(cohort, ultimate = value_proj,
          se_ultimate = se_proj,
          cv_ultimate = cv_proj)]
}
