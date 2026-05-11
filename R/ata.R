# Age-to-age summary ------------------------------------------------------

#' Internal: summarise age-to-age factor statistics from a `Link` table
#'
#' @description
#' Compute group-wise summary statistics for age-to-age factors from an
#' object of class `"Link"`. This helper backs the `summary.Link()`
#' dispatcher when `model = "ata"`. It serves two purposes:
#'
#' \enumerate{
#'   \item \strong{Diagnostics}: provides descriptive statistics
#'     (`mean`, `median`, `wt`, `cv`) that help the user assess the
#'     stability and consistency of observed ata factors across cohorts.
#'   \item \strong{Estimation}: fits a no-intercept weighted least squares
#'     model per ata link to produce the WLS-estimated factor (`f`), its
#'     standard error (`f_se`), relative standard error (`rse`), and Mack
#'     sigma (`sigma`). These are used downstream by
#'     [detect_maturity()] and [fit_ata()].
#' }
#'
#' @section Relationship between `wt` and `f`:
#' Both `wt` and `f` are weighted averages of the observed ata factors,
#' but they differ in how weights are assigned and which observations
#' are included:
#'
#' \describe{
#'   \item{`wt`}{Volume-weighted mean:
#'     \eqn{wt = \sum C_{i,k+1} / \sum C_{i,k}}.
#'     Computed from all rows where `target_from` and `target_to` are
#'     finite, including rows where either value is zero.
#'     Independent of `alpha`.}
#'   \item{`f`}{WLS-estimated factor. Only rows where `target_from > 0`
#'     are used, since `target_from = 0` causes numerical issues in the
#'     WLS weights (\eqn{w = value\_from^{\alpha}}). When `alpha = 2`,
#'     `f` and `wt` are numerically equivalent (assuming no zero
#'     `target_from` rows). When `alpha \ne 2`, they diverge.}
#' }
#'
#' Therefore `wt` and `f` can differ for two reasons:
#' \enumerate{
#'   \item \strong{Zero exclusion}: rows with `target_from = 0` are
#'     included in `wt` but excluded from `f`. This typically affects
#'     early development periods where some cohorts have not yet accumulated
#'     any claims.
#'   \item \strong{Alpha effect}: when `alpha \ne 2`, the WLS weights
#'     differ from the volume weights used in `wt`, leading to different
#'     estimates. Comparing `wt` and `f` can help diagnose whether the
#'     choice of `alpha` materially affects the estimated factor.
#' }
#'
#' @section Weights:
#' When the input `"Link"` object contains a `weight` column (added by
#' [build_link()] when `weight` is supplied), that column is
#' automatically used as the WLS weight in place of `target_from`. This
#' is useful when `target = "lr"`, where `target_from` carries no
#' exposure information and an external exposure variable such as `premium`
#' should be used instead.
#'
#' @section Coefficient of variation (`cv`):
#' The coefficient of variation is defined as:
#' \deqn{cv = \frac{SD(f_k)}{\bar{f}_k}}
#' where \eqn{f_k} are the individual observed ata values for link
#' \eqn{k} and \eqn{\bar{f}_k} is their arithmetic mean. The `cv`
#' reflects the relative spread of observed factors across cohorts,
#' regardless of the exposure scale. It is used by
#' [detect_maturity()] as one of the criteria for determining the
#' maturity point.
#'
#' @section Relative standard error (`rse`):
#' The relative standard error is defined as:
#' \deqn{rse = \frac{SE(\hat{f}_k)}{\hat{f}_k}}
#' where \eqn{SE(\hat{f}_k)} is the standard error of the
#' WLS-estimated factor. Unlike `cv`, which treats all cohorts equally,
#' `rse` gives more weight to cohorts with larger exposures (via the
#' WLS weights). A small `rse` indicates that the WLS estimate is
#' precise, which tends to occur when: (1) there are many cohorts,
#' (2) exposures are large, and (3) the observed ata values are
#' consistent across cohorts.
#'
#' @param object An object of class `"Link"`, typically produced by
#'   [build_link()].
#' @param alpha Numeric scalar controlling the variance structure in the
#'   WLS fit. Default is `1`.
#' @param digits Number of decimal places to round numeric columns.
#'   Default is `3`. Pass `NULL` to skip rounding.
#' @param ... Additional arguments passed to the internal WLS estimation.
#'
#' @return A `data.table` with class `"ATASummary"` containing one row
#'   per ata link:
#'   \describe{
#'     \item{`ata_from`, `ata_to`, `ata_link`}{Link identifiers.}
#'     \item{`mean`}{Arithmetic mean of observed ata factors.}
#'     \item{`median`}{Median of observed ata factors.}
#'     \item{`wt`}{Volume-weighted mean:
#'       \eqn{\sum C_{i,k+1} / \sum C_{i,k}}, independent of `alpha`.}
#'     \item{`cv`}{Coefficient of variation of observed ata factors
#'       (\eqn{SD / mean}). Used by [detect_maturity()] to assess
#'       stability.}
#'     \item{`f`}{WLS-estimated factor. Equals `wt` when `alpha = 2`
#'       and no zero `target_from` rows are present.}
#'     \item{`f_se`}{Standard error of the WLS-estimated factor.}
#'     \item{`rse`}{Relative standard error of the WLS-estimated factor
#'       (\eqn{f\_se / f}).}
#'     \item{`sigma`}{Mack sigma (residual standard deviation from the
#'       WLS fit). Used in Mack variance estimation.}
#'     \item{`n_obs`}{Total number of observations for the link.}
#'     \item{`n_valid`}{Number of finite ata values.}
#'     \item{`n_inf`}{Number of infinite ata values.}
#'     \item{`n_nan`}{Number of NaN ata values.}
#'     \item{`valid_ratio`}{Proportion of finite ata values
#'       (\eqn{n\_valid / n\_obs}).}
#'   }
#'
#' @seealso [build_link()], [summary.Link()], [detect_maturity()],
#'   [fit_ata()]
#'
#' @keywords internal
.summarize_link_ata <- function(object,
                                alpha  = 1,
                                digits = 3,
                                ...) {

  .assert_class(object, "Link")

  grp_var <- attr(object, "group_var")
  if (is.null(grp_var)) grp_var <- character(0)

  dt <- .ensure_dt(object)

  grp_link_var <- c(grp_var, "ata_from", "ata_to", "ata_link")

  # 1) descriptive statistics -------------------------------------------
  ds <- dt[, {
    vals <- ata[is.finite(ata)]
    vf   <- target_from
    vt   <- target_to
    m    <- mean(vals)

    .(
      mean        = m,
      median      = stats::median(vals),
      wt          = sum(vt, na.rm = TRUE) / sum(vf, na.rm = TRUE),
      cv          = stats::sd(vals, na.rm = TRUE) / m,
      n_obs       = .N,
      n_valid     = sum(is.finite(ata)),
      n_inf       = sum(is.infinite(ata)),
      n_nan       = sum(is.nan(ata))
    )
  }, by = grp_link_var]

  ds[, valid_ratio := n_valid / n_obs]

  # 2) WLS estimation ---------------------------------------------------
  # use weight column if present (added by build_link(weight = ...))
  # otherwise fall back to target_from (standard volume-weighted chain ladder)
  wt_col    <- if ("weight" %in% names(dt)) "weight" else 1
  link_factors <- .lm_link(object, weights = wt_col, alpha = alpha, ...)

  # 3) join WLS results onto descriptive statistics ---------------------
  join_cols <- c(grp_var, "ata_from", "ata_to", "ata_link")
  ds <- link_factors[
    , .SD,
    .SDcols = c(join_cols, "f", "f_se", "rse", "sigma")
  ][ds, on = join_cols]

  # 4) reorder columns --------------------------------------------------
  col_order <- c(
    join_cols,
    "mean", "median", "wt", "cv",
    "f", "f_se", "rse", "sigma",
    "n_obs", "n_valid", "n_inf", "n_nan", "valid_ratio"
  )
  data.table::setcolorder(ds, col_order)

  ds[, ata_link := factor(ata_link, levels = unique(dt$ata_link))]

  # `digits` is retained for downstream display only (see print.ATASummary).
  # Numeric columns are stored at full precision so callers get raw values.
  if (!is.null(digits)) {
    digits <- suppressWarnings(as.numeric(digits[1L]))
    if (length(digits) == 0L || is.na(digits))
      stop("Non-numeric `digits` specified.", call. = FALSE)
  }

  data.table::setattr(ds, "group_var",  grp_var)
  data.table::setattr(ds, "cohort_var", attr(object, "cohort_var"))
  data.table::setattr(ds, "dev_var",    attr(object, "dev_var"))
  data.table::setattr(ds, "target",     attr(object, "target"))
  data.table::setattr(ds, "weight",     attr(object, "weight"))
  data.table::setattr(ds, "digits",     digits)

  .prepend_class(ds, "ATASummary")
}


#' Print method for `ATASummary`
#'
#' Numeric columns are stored at full double precision; rounding is applied
#' only for display. The default `digits` is taken from the `digits`
#' attribute set by [summary.Link()] (3 unless overridden).
#'
#' @param x An object of class `"ATASummary"`.
#' @param digits Number of decimal places to display. Default uses the
#'   `digits` attribute attached at construction.
#' @param ... Further arguments passed to `print.data.table`.
#'
#' @method print ATASummary
#' @export
print.ATASummary <- function(x, digits = attr(x, "digits"), ...) {
  if (is.null(digits)) {
    NextMethod()
    return(invisible(x))
  }
  y <- data.table::copy(x)
  data.table::setattr(y, "class", setdiff(class(y), "ATASummary"))
  num_cols <- vapply(y, is.numeric, logical(1L))
  for (nm in names(y)[num_cols]) {
    data.table::set(y, j = nm, value = round(y[[nm]], digits))
  }
  print(y, ...)
  invisible(x)
}


# Age-to-age maturity is now in R/maturity.R (detect_maturity / Maturity)


# Age-to-age fitting ------------------------------------------------------

#' Fit age-to-age development factors
#'
#' @description
#' Estimate age-to-age (ata) development factors from an object of class
#' `"Link"` and return a unified `"ATAFit"` object that bundles:
#'
#' \itemize{
#'   \item Summary statistics and WLS estimates (`summary`) from
#'     [summary.Link()] with `model = "ata"`.
#'   \item Selected factors (`selected`) ready for chain ladder projection,
#'     after optional maturity filtering and LOCF fill.
#'   \item Maturity diagnostics (`maturity`) from [detect_maturity()].
#' }
#'
#' @param x An object of class `"Link"`, typically produced by
#'   [build_link()].
#' @param alpha Numeric scalar controlling the variance structure. Default
#'   is `1`.
#' @param na_method Method used to fill `NA` values in `f_selected`. One of
#'   `"locf"` (default) or `"none"`. Passed to [.filter_ata()].
#' @param sigma_method Method used to extrapolate `sigma` for links where it
#'   cannot be estimated. One of `"locf"` (default), `"min_last2"`, or
#'   `"loglinear"`. Passed to [.extrapolate_sigma_ata()].
#' @param recent Optional positive integer. When supplied, only the most
#'   recent `recent` periods in the `Link` triangle are used for factor
#'   estimation. Applied before maturity filtering. Default is `NULL`
#'   (use all periods).
#' @param regime_break Optional cohort cutoff for the regime break. Accepts:
#'   `NULL` (default, no filter), a single `Date`/character coercible to Date,
#'   a vector of dates (uses the latest), or a `Regime` object (extracts
#'   the latest from `$breakpoints`). When supplied, cohorts with
#'   `cohort < break_date` are excluded from estimation. Default is `NULL`.
#' @param maturity_args A named list of arguments forwarded to
#'   [detect_maturity()], or `NULL` (default) to skip maturity filtering.
#'   When a list is supplied, missing elements are filled with package
#'   defaults via [utils::modifyList()]:
#'   \describe{
#'     \item{`max_cv`}{Default `0.15`.}
#'     \item{`max_rse`}{Default `0.05`.}
#'     \item{`min_valid_ratio`}{Default `0.5`.}
#'     \item{`min_n_valid`}{Default `3L`.}
#'     \item{`min_run`}{Default `2L`.}
#'   }
#'   Pass `list()` to use all defaults with maturity filtering enabled.
#' @param ... Additional arguments passed to [summary.Link()].
#'
#' @return An object of class `"ATAFit"` (a named list) containing:
#'   \describe{
#'     \item{`call`}{The matched call.}
#'     \item{`link`}{The input `"Link"` object.}
#'     \item{`summary`}{`"ATASummary"` object from [summary.Link()].}
#'     \item{`selected`}{`data.table` of factors ready for projection,
#'       including `f_selected` and `sigma2`.}
#'     \item{`maturity`}{Maturity diagnostics from [detect_maturity()],
#'       or `NULL` when maturity filtering was not applied.}
#'     \item{`alpha`}{Value of `alpha` used.}
#'     \item{`na_method`}{NA fill method used.}
#'     \item{`sigma_method`}{Sigma extrapolation method used.}
#'     \item{`recent`}{Number of recent periods used, or `NULL`.}
#'     \item{`regime_break`}{Resolved regime-break cutoff (`Date`), or `NULL`.}
#'     \item{`use_maturity`}{Logical; whether maturity filtering was applied.}
#'     \item{`maturity_args`}{Resolved maturity arguments, or `NULL`.}
#'   }
#'
#' @param target Cumulative metric for the link factor. Default
#'   `"loss"`. Forwarded to [build_link()].
#' @param weight Optional WLS weight variable. Forwarded to
#'   [build_link()].
#'
#' @seealso [build_link()], [summary.Link()], [detect_maturity()],
#'   [fit_cl()]
#'
#' @export
fit_ata <- function(x,
                    target        = "loss",
                    weight        = NULL,
                    alpha         = 1,
                    na_method     = c("locf", "none"),
                    sigma_method  = c("locf", "min_last2", "loglinear"),
                    recent        = NULL,
                    regime_break  = NULL,
                    maturity_args = NULL,
                    ...) {

  .assert_triangle_input(x, "fit_ata()")

  link <- build_link(x, target = target, weight = weight)

  na_method    <- match.arg(na_method)
  sigma_method <- match.arg(sigma_method)

  # 1) regime-break filter -----------------------------------------------
  # when `regime_break` is supplied, drop cohorts strictly before the
  # break date so estimation uses only the post-break regime.
  if (!is.null(regime_break)) {
    if (inherits(regime_break, "Regime")) {
      regime_break <- max(regime_break$breakpoints)
    } else {
      regime_break <- max(as.Date(regime_break))
    }
    link <- .apply_break_filter(
      link, regime_break,
      group_var  = if (is.null(attr(link, "group_var"))) character(0) else attr(link, "group_var"),
      cohort_var = "cohort",
      dev_var    = "ata_from"
    )
  }

  # 2) recent-diagonal filter -------------------------------------------
  # when `recent` is supplied, subset to rows within the last `recent`
  # calendar diagonals before estimation.
  if (!is.null(recent)) {
    link <- .apply_recent_filter(
      link, recent,
      group_var  = if (is.null(attr(link, "group_var"))) character(0) else attr(link, "group_var"),
      cohort_var = "cohort",
      dev_var    = "ata_from"
    )
  }

  # 3) resolve maturity arguments ----------------------------------------
  # maturity_args = NULL   → skip maturity filtering
  # maturity_args = list() → use all defaults
  # maturity_args = list(max_cv = 0.15) → partial override
  maturity_args <- if (!is.null(maturity_args)) {
    utils::modifyList(
      list(
        max_cv          = 0.15,
        max_rse         = 0.05,
        min_valid_ratio = 0.5,
        min_n_valid     = 3L,
        min_run         = 2L
      ),
      maturity_args
    )
  } else {
    NULL
  }

  use_maturity <- !is.null(maturity_args)

  grp_var <- attr(link, "group_var")
  if (is.null(grp_var)) grp_var <- character(0)

  # 4) compute summary statistics and WLS estimates ---------------------
  ata_summary <- summary(link, alpha = alpha, model = "ata", ...)

  # 5) find maturity point ----------------------------------------------
  maturity <- if (use_maturity) {
    do.call(.detect_maturity, c(list(x = ata_summary), maturity_args))
  } else {
    NULL
  }

  # 6) filter links by maturity and fill NA gaps with LOCF --------------
  # maturity is NULL when maturity_args = NULL; .filter_ata() ignores it
  selected <- .filter_ata(
    ata_summary  = ata_summary,
    maturity     = maturity,
    use_maturity = use_maturity,
    grp_var      = grp_var,
    na_method    = na_method
  )

  # 7) extrapolate sigma and compute sigma2 -----------------------------
  selected <- .extrapolate_sigma_ata(selected, method = sigma_method)
  selected[, sigma2 := sigma^2]

  out <- list(
    call          = match.call(),
    data          = x,
    group_var     = grp_var,
    cohort_var    = attr(link, "cohort_var"),
    dev_var       = attr(link, "dev_var"),
    target        = attr(link, "target"),
    weight        = attr(link, "weight"),
    link          = link,
    factor        = ata_summary,
    selected      = selected,
    maturity      = maturity,
    alpha         = alpha,
    na_method     = na_method,
    sigma_method  = sigma_method,
    recent        = recent,
    regime_break  = regime_break,
    use_maturity  = use_maturity,
    maturity_args = maturity_args
  )

  class(out) <- "ATAFit"
  out
}


#' Summary method for `ATAFit`
#'
#' @description
#' Returns the link-level `ATASummary` carried by the fit, i.e. one row
#' per age-to-age link with the WLS-estimated factor `f`, standard
#' error, sigma, and diagnostic statistics. Mirrors [summary.EDFit()].
#'
#' @param object An object of class `"ATAFit"`.
#' @param ... Unused.
#'
#' @return A `data.table` of class `"ATASummary"`.
#'
#' @method summary ATAFit
#' @export
summary.ATAFit <- function(object, ...) {
  object$factor
}


#' Print an `ATAFit` object
#'
#' @param x An object of class `"ATAFit"`.
#' @param ... Unused.
#'
#' @method print ATAFit
#' @export
print.ATAFit <- function(x, ...) {

  grp_var <- attr(x$link, "group_var")
  if (is.null(grp_var)) grp_var <- character(0)

  cat("<ATAFit>\n")
  cat("alpha       :", x$alpha,  "\n")
  cat("sigma_method:", x$sigma_method, "\n")
  cat("recent      :",
      if (!is.null(x$recent)) x$recent else "all", "\n")
  cat("regime_break:",
      if (!is.null(x$regime_break)) format(x$regime_break) else "none",
      "\n")
  cat("use_maturity:", x$use_maturity, "\n")

  if (length(grp_var)) {
    cat("groups      :", paste(grp_var, collapse = ", "), "\n")
    cat("n_groups    :",
        nrow(unique(x$factor[, grp_var, with = FALSE])), "\n")
  } else {
    cat("groups      : none\n")
  }

  cat("ata links   :", nrow(x$factor), "\n")

  invisible(x)
}
# ____________________________________ ------------------------------------

# Internal helpers --------------------------------------------------------

#' Filter and fill age-to-age factors for projection
#'
#' @description
#' Internal helper that produces a `f_selected` column by applying two steps:
#'
#' 1. **Filter** — when `use_maturity = TRUE`, development links that precede
#'    the maturity point are excluded (`f_selected` set to `NA`).
#'
#' 2. **Fill** — `NA` values in `f_selected` are forward-filled using LOCF,
#'    so that every link used in projection has a finite factor.
#'
#' @param ata_summary A `data.table` of class `"ATASummary"` from
#'   [summary.Link()] with `model = "ata"`.
#' @param maturity A `data.table` from [detect_maturity()], or `NULL`
#'   when `use_maturity = FALSE`.
#' @param grp_var Character vector of grouping variable names.
#' @param use_maturity Logical; if `TRUE`, apply the maturity filter.
#'   When `FALSE`, `maturity` is ignored entirely.
#' @param na_method One of `"locf"` or `"none"`.
#'
#' @return A `data.table` with `selected` and `f_selected` columns added.
#'
#' @keywords internal
.filter_ata <- function(ata_summary,
                        maturity     = NULL,
                        use_maturity = FALSE,
                        grp_var      = character(0),
                        na_method    = c("locf", "none")) {

  na_method <- match.arg(na_method)

  z <- .ensure_dt(ata_summary)

  # initialise: all links selected, f_selected equals fitted f
  z[, `:=`(selected = TRUE, f_selected = f)]

  # --- maturity filter --------------------------------------------------
  # only applied when use_maturity = TRUE and maturity is provided
  if (use_maturity && !is.null(maturity)) {

    mat <- .ensure_dt(maturity)

    # keep only group vars and maturity_from
    keep_cols <- c(grp_var, "ata_from")
    mat_from  <- mat[, .SD, .SDcols = intersect(keep_cols, names(mat))]
    data.table::setnames(mat_from, "ata_from", "maturity_from")

    if (length(grp_var)) {
      z <- mat_from[z, on = grp_var]
    } else {
      if (nrow(mat_from) != 1L)
        stop(
          "When there is no `group_var`, `maturity` must have exactly one row.",
          call. = FALSE
        )
      z[, maturity_from := mat_from$maturity_from[1L]]
    }

    z[, selected := data.table::fifelse(
      is.na(maturity_from), TRUE, ata_from >= maturity_from
    )]
    z[selected == FALSE, f_selected := NA_real_]
    z[, maturity_from := NULL]
  }

  # --- LOCF fill --------------------------------------------------------
  if (na_method == "locf") {
    if (length(grp_var)) {
      z[, f_selected := data.table::nafill(f_selected, type = "locf"),
        by = grp_var]
    } else {
      z[, f_selected := data.table::nafill(f_selected, type = "locf")]
    }
  }

  data.table::setorderv(z, c(grp_var, "ata_from", "ata_to"))
  z
}


#' Extrapolate missing sigma values for age-to-age links
#'
#' @description
#' Internal helper that fills `NA` or non-positive `sigma` values in a
#' filtered ata factor table. Three methods are supported: `"min_last2"`,
#' `"locf"`, and `"loglinear"`. See Details.
#'
#' @param x A `data.table` with `ata_from` and `sigma` columns, typically
#'   the output of [.filter_ata()].
#' @param method One of `"locf"` (default), `"min_last2"`, or
#'   `"loglinear"`.
#'
#' @return A `data.table` with missing `sigma` values filled and a new
#'   logical column `sigma_extrapolated` flagging imputed rows.
#'
#' @keywords internal
.extrapolate_sigma_ata <- function(x,
                                   method = c("locf", "min_last2", "loglinear")) {

  method <- match.arg(method)

  if (!all(c("ata_from", "sigma") %in% names(x)))
    stop("`x` must contain `ata_from` and `sigma`.", call. = FALSE)

  z <- .ensure_dt(x)

  z[, sigma_extrapolated := !is.finite(sigma) | sigma <= 0]

  idx_valid <- which(!z$sigma_extrapolated)
  idx_pred  <- which( z$sigma_extrapolated)

  if (length(idx_pred) == 0L) return(z[])

  if (length(idx_valid) < 2L) {
    warning("Fewer than two valid `sigma` values; extrapolation skipped.",
            call. = FALSE)
    return(z[])
  }

  if (method == "min_last2") {
    # conservative: use the minimum of the last two valid sigma values
    fill_val <- min(tail(z$sigma[idx_valid], 2L))
    z[idx_pred, sigma := fill_val]

  } else if (method == "locf") {
    # carry last valid sigma forward
    z[idx_pred, sigma := z$sigma[idx_valid[length(idx_valid)]]]

  } else if (method == "loglinear") {
    # log-linear regression on valid rows; assumes monotone decrease
    fit <- stats::lm(log(sigma) ~ ata_from, data = z[idx_valid])
    z[idx_pred, sigma := exp(stats::predict(fit, newdata = z[idx_pred]))]
  }

  z[]
}
