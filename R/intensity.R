# Fit ED intensity factors (factor level, parallel to fit_ata) -------------

#' Fit per-link ED intensity factors
#'
#' @description
#' Estimate per-development-link incremental loss intensities
#' \eqn{g_k = \mathbb{E}[\Delta L_k / C^P_k]} from a `"Triangle"` and
#' return an `"IntensityFit"` object that bundles the link-level
#' WLS-estimated intensities along with their standard errors and
#' diagnostic statistics.
#'
#' This is the factor-level diagnostic for the exposure-driven (ED)
#' workflow, parallel to [fit_ata()] for the multiplicative (chain
#' ladder) side. Both operate at the *factor level* without
#' producing a full projection. For full ED projection (cumulative
#' loss / premium / lr), use [fit_ed()] which accepts either a
#' `Triangle` or an `IntensityFit` (skipping a rebuild of the link
#' table when factors are already computed).
#'
#' @section ED has no maturity concept:
#' Unlike ATA factors, where CV / RSE drive a `detect_maturity()`
#' threshold, ED intensities behave differently — as \eqn{g_k \to 0}
#' in late development the CV / RSE blow up by construction, not by
#' instability. `fit_intensity()` therefore deliberately omits a
#' `maturity_args` parameter, and `detect_maturity()` rejects
#' `IntensityFit` input with an informative error.
#'
#' @param x A `Triangle` object.
#' @param target A single cumulative metric used as the link
#'   numerator. Default `"loss"`.
#' @param exposure A single cumulative metric used as the
#'   exposure anchor. Default `"premium"`.
#' @param alpha WLS weight exponent. Default `1`.
#' @param na_method NA fill method for the selected intensity series
#'   used downstream by [fit_ed()]. One of `"locf"` (default —
#'   carries the last observed intensity forward, appropriate for
#'   long-term health where ageing keeps \eqn{g_k} elevated rather
#'   than decaying to 0), `"zero"` (sets late-dev NAs to 0; suits
#'   short-tail lines where claims fully settle), or `"none"`.
#' @param sigma_method Method for extrapolating missing or
#'   non-positive `sigma` values across links. One of `"min_last2"`
#'   (default), `"locf"`, `"loglinear"`.
#' @param recent Optional positive integer. When supplied, restricts
#'   estimation to rows within the last `recent` calendar diagonals
#'   (calendar-diagonal wedge filter; see [.apply_recent_filter()]).
#' @param regime_break Optional cohort cutoff. Accepts a `Date`,
#'   character date, vector of dates (uses the maximum), or a
#'   `"Regime"` object (uses `max($breakpoints)`). When supplied,
#'   cohorts strictly before the break are dropped before
#'   estimation.
#' @param ... Passed to [summary.Link()] (e.g. `digits`).
#'
#' @return A list of class `"IntensityFit"` with components:
#' \describe{
#'   \item{`call`}{The matched call.}
#'   \item{`data`}{The (possibly filtered) `Link` object used for
#'     estimation.}
#'   \item{`group_var`, `cohort_var`, `dev_var`, `target`,
#'     `exposure`}{Variable name relays from the input `Triangle`.}
#'   \item{`link`}{Alias of `data` for parallelism with
#'     [fit_ata()].}
#'   \item{`factor`}{The `EDSummary` returned by
#'     [summary.Link()] — one row per link with WLS-estimated `g`,
#'     `g_se`, `rse`, `sigma`, plus descriptive statistics.}
#'   \item{`selected`}{`data.table` of selected intensities
#'     per link (`g_selected`, `sigma`, `sigma2`,
#'     `sigma_extrapolated`). LOCF NA-fill is applied when
#'     `na_method = "locf"`; sigma extrapolation is applied per
#'     `sigma_method`.}
#'   \item{`alpha`, `na_method`, `sigma_method`, `recent`,
#'     `regime_break`}{Call metadata.}
#' }
#'
#' @seealso [fit_ata()], [fit_ed()], [build_link()],
#'   [summary.Link()]
#'
#' @examples
#' \dontrun{
#' tri <- build_triangle(df, group_var = coverage)
#' intensity_fit <- fit_intensity(tri, target = "loss", exposure = "premium")
#' summary(intensity_fit)
#' }
#'
#' @export
fit_intensity <- function(x,
                          target       = "loss",
                          exposure     = "premium",
                          alpha        = 1,
                          na_method    = c("locf", "zero", "none"),
                          sigma_method = c("locf", "min_last2", "loglinear"),
                          recent       = NULL,
                          regime_break = NULL,
                          ...) {

  .assert_triangle_input(x, "fit_intensity()")

  link <- build_link(x, target = target, exposure = exposure)

  na_method    <- match.arg(na_method)
  sigma_method <- match.arg(sigma_method)

  # 1) regime-break filter ----------------------------------------------
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
  if (!is.null(recent)) {
    link <- .apply_recent_filter(
      link, recent,
      group_var  = if (is.null(attr(link, "group_var"))) character(0) else attr(link, "group_var"),
      cohort_var = "cohort",
      dev_var    = "ata_from"
    )
  }

  grp_var <- attr(link, "group_var")
  if (is.null(grp_var)) grp_var <- character(0)

  # 3) WLS intensity per link -------------------------------------------
  ed_summary <- summary(link, alpha = alpha, model = "ed", ...)

  # 4) selected intensity series with LOCF + sigma extrapolation --------
  selected <- .select_intensity(
    ed_summary = ed_summary,
    grp_var    = grp_var,
    na_method  = na_method
  )
  selected <- .extrapolate_sigma_ata(selected, method = sigma_method)
  selected[, sigma2 := sigma^2]

  out <- list(
    call         = match.call(),
    data         = x,
    group_var    = grp_var,
    cohort_var   = attr(link, "cohort_var"),
    dev_var      = attr(link, "dev_var"),
    target       = attr(link, "target"),
    exposure     = attr(link, "exposure"),
    link         = link,
    factor       = ed_summary,
    selected     = selected,
    alpha        = alpha,
    na_method    = na_method,
    sigma_method = sigma_method,
    recent       = recent,
    regime_break = regime_break
  )

  class(out) <- "IntensityFit"
  out
}


#' Summary method for `IntensityFit`
#'
#' @description
#' Returns the `EDSummary` carried by the fit — one row per link
#' with WLS-estimated `g`, `g_se`, `rse`, `sigma`, and descriptive
#' statistics. Mirrors [summary.ATAFit()].
#'
#' @param object An `"IntensityFit"`.
#' @param ... Unused.
#'
#' @return An `EDSummary` `data.table`.
#'
#' @method summary IntensityFit
#' @export
summary.IntensityFit <- function(object, ...) {
  object$factor
}


#' Print method for `IntensityFit`
#'
#' Mirrors [print.ATAFit()] — prints call metadata only. Use
#' [summary.IntensityFit()] (or `x$factor`) to inspect the per-link
#' summary table.
#'
#' @param x An `"IntensityFit"`.
#' @param ... Unused.
#'
#' @method print IntensityFit
#' @export
print.IntensityFit <- function(x, ...) {

  grp_var <- attr(x$link, "group_var")
  if (is.null(grp_var)) grp_var <- character(0)

  cat("<IntensityFit>\n")
  cat("alpha       :", x$alpha, "\n")
  cat("sigma_method:", x$sigma_method, "\n")
  cat("recent      :",
      if (!is.null(x$recent)) x$recent else "all", "\n")
  cat("regime_break:",
      if (!is.null(x$regime_break)) format(x$regime_break) else "none",
      "\n")

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


# Internal helpers ---------------------------------------------------------

#' Apply LOCF NA-fill to per-link selected intensities
#'
#' @description
#' Initialises `g_selected` from the WLS-fitted `g` and optionally
#' fills `NA` runs via `data.table::nafill(type = "locf")`. Mirrors
#' the fill phase of [.filter_ata()] without the maturity gate (ED
#' has no maturity concept).
#'
#' @param ed_summary An `EDSummary`.
#' @param grp_var Character vector of group columns.
#' @param na_method One of `"locf"` (default) or `"none"`.
#'
#' @return A `data.table` with `g_selected` added.
#'
#' @keywords internal
.select_intensity <- function(ed_summary,
                              grp_var   = character(0),
                              na_method = c("zero", "locf", "none")) {

  na_method <- match.arg(na_method)

  z <- .ensure_dt(ed_summary)
  z[, g_selected := g]

  if (na_method == "zero") {
    z[is.na(g_selected), g_selected := 0]
  } else if (na_method == "locf") {
    if (length(grp_var)) {
      z[, g_selected := data.table::nafill(g_selected, type = "locf"),
        by = grp_var]
    } else {
      z[, g_selected := data.table::nafill(g_selected, type = "locf")]
    }
  }

  data.table::setorderv(z, c(grp_var, "ata_from", "ata_to"))
  z
}
