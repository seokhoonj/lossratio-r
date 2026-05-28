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
#' loss / premium / ratio), use [fit_ed()] which accepts either a
#' `Triangle` or an `IntensityFit` (skipping a rebuild of the link
#' table when factors are already computed).
#'
#' @section ED has no maturity concept:
#' Unlike ATA factors, where CV / RSE drive a `detect_maturity()`
#' threshold, ED intensities behave differently -- as \eqn{g_k \to 0}
#' in late development the CV / RSE blow up by construction, not by
#' instability. `fit_intensity()` therefore deliberately omits a
#' `maturity` parameter, and `detect_maturity()` rejects
#' `IntensityFit` input with an informative error.
#'
#' @param x A `Triangle` object.
#' @param loss A single cumulative metric used as the link
#'   numerator. Default `"loss"`.
#' @param exposure A single cumulative metric used as the
#'   exposure base (denominator anchor). Default `"premium"`.
#' @param alpha WLS weight exponent. Default `1`.
#' @param na_method NA fill method for the selected intensity series
#'   used downstream by [fit_ed()]. One of `"locf"` (default --
#'   carries the last observed intensity forward, appropriate for
#'   long-term health where ageing keeps \eqn{g_k} elevated rather
#'   than decaying to 0), `"zero"` (sets late-dev NAs to 0; suits
#'   short-tail lines where claims fully settle), or `"none"`.
#' @inheritParams fit_ata
#' @param recent Optional positive integer. When supplied, restricts
#'   estimation to rows within the last `recent` calendar diagonals
#'   (calendar-diagonal wedge filter; see [.apply_recent_filter()]).
#' @param regime Optional regime specification for cohort cutoff. Accepts:
#'   `NULL` (default -- no filter), a `"Regime"` object (from
#'   [detect_regime()]), the string `"auto"` (internal
#'   `detect_regime(tri, loss = "ratio")` call), or a function
#'   `function(tri) -> Regime`. Resolved internally via
#'   [.resolve_regime()]. When supplied, cohorts strictly before the
#'   change are dropped before estimation.
#' @param ... Passed to [summary.Link()] (e.g. `digits`).
#'
#' @return A list of class `"IntensityFit"` with components:
#' \describe{
#'   \item{`call`}{The matched call.}
#'   \item{`data`}{The (possibly filtered) `Link` object used for
#'     estimation.}
#'   \item{`groups`, `cohort`, `dev`, `loss`,
#'     `premium`}{Variable name relays from the input `Triangle`.}
#'   \item{`link`}{Alias of `data` for parallelism with
#'     [fit_ata()].}
#'   \item{`factor`}{The `EDSummary` returned by
#'     [summary.Link()] -- one row per link with WLS-estimated `g`,
#'     `g_se`, `rse`, `sigma`, plus descriptive statistics.}
#'   \item{`selected`}{`data.table` of selected intensities
#'     per link (`g_sel`, `sigma`, `sigma2`,
#'     `sigma_extrapolated`). LOCF NA-fill is applied when
#'     `na_method = "locf"`; sigma extrapolation is applied per
#'     `sigma_method`.}
#'   \item{`alpha`, `na_method`, `sigma_method`, `recent`,
#'     `regime`}{Call metadata. `regime` is the resolved `"Regime"`
#'     object (or `NULL`) returned by [.resolve_regime()].}
#' }
#'
#' @seealso [fit_ata()], [fit_ed()], [as_link()],
#'   [summary.Link()]
#'
#' @examples
#' \dontrun{
#' tri <- as_triangle(
#'   df,
#'   groups   = "coverage",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "incr_loss",
#'   premium  = "incr_premium"
#' )
#' intensity_fit <- fit_intensity(tri, loss = "loss", exposure = "premium")
#' summary(intensity_fit)
#' }
#'
#' @export
fit_intensity <- function(x,
                          loss         = "loss",
                          exposure     = "premium",
                          alpha        = 1,
                          na_method    = c("locf", "zero", "none"),
                          sigma_method = c("locf", "min_last2", "loglinear",
                                           "mack", "none"),
                          recent       = NULL,
                          regime       = NULL,
                          ...) {

  .assert_triangle_input(x, "fit_intensity()")

  regime <- .resolve_regime(regime, x)

  # 1) regime band mask (BEFORE building the link) ----------------------
  # Segment treatments mask the Triangle's bridged development band on the
  # cohort x dev grid (all cohorts present), so the mask runs on the
  # `Triangle`, not the `Link` (which omits dev-1-only cohorts and would
  # corrupt each segment's last-cohort rank). For
  # `"segment_bridged_borrowed"` re-derive `segment_id` on the link.
  x_band <- if (!is.null(regime)) {
    .apply_regime_filter(
      x, regime = regime,
      groups = .resolve_groups(x),
      cohort = "cohort", dev = "dev"
    )
  } else x

  link <- as_link(x_band, loss = loss, exposure = exposure)

  if (!is.null(regime) && inherits(regime, "Regime") &&
      identical(regime$treatment, "segment_bridged_borrowed")) {
    lgrp      <- .resolve_groups(link)
    lgrp_cols <- if (length(lgrp)) link[, lgrp, with = FALSE] else NULL
    data.table::set(link, j = "segment_id",
                    value = .assign_segment(link$cohort, regime, lgrp_cols))
  }

  na_method    <- match.arg(na_method)
  sigma_method <- match.arg(sigma_method)

  # 2) recent-diagonal filter -------------------------------------------
  if (!is.null(recent)) {
    link <- .apply_recent_filter(
      link, recent,
      groups = .resolve_groups(link),
      cohort = "cohort",
      dev = "ata_from"
    )
  }

  grp <- .resolve_groups(link)

  # 3) WLS intensity per link -------------------------------------------
  ed_summary <- summary(link, alpha = alpha, model = "ed", ...)

  # 4) selected intensity series with LOCF + sigma extrapolation --------
  selected <- .select_intensity(
    ed_summary = ed_summary,
    groups     = grp,
    na_method  = na_method
  )
  selected <- .extrapolate_sigma_ata(selected, method = sigma_method)
  selected[, ("sigma2") := sigma^2]

  out <- list(
    call         = match.call(),
    data         = x,
    groups       = grp,
    cohort       = attr(link, "cohort"),
    dev          = attr(link, "dev"),
    loss         = attr(link, "loss"),
    premium      = attr(link, "premium"),
    link         = link,
    factor       = ed_summary,
    selected     = selected,
    alpha        = alpha,
    na_method    = na_method,
    sigma_method = sigma_method,
    recent       = recent,
    regime       = regime
  )

  class(out) <- c("IntensityFit", "list")
  out
}


#' Summary method for `IntensityFit`
#'
#' @description
#' Returns the `EDSummary` carried by the fit -- one row per link
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
#' Mirrors [print.ATAFit()] -- prints call metadata only. Use
#' [summary.IntensityFit()] (or `x$factor`) to inspect the per-link
#' summary table.
#'
#' @param x An `"IntensityFit"`.
#' @param ... Unused.
#'
#' @method print IntensityFit
#' @export
print.IntensityFit <- function(x, ...) {

  grp <- .resolve_groups(x$link)

  cat("<IntensityFit>\n")
  cat("alpha       :", x$alpha, "\n")
  cat("sigma_method:", x$sigma_method, "\n")
  cat("recent      :",
      if (!is.null(x$recent)) x$recent else "all", "\n")
  cat("regime      :")
  if (is.null(x$regime)) {
    cat(" none\n")
  } else if (inherits(x$regime, "Regime")) {
    cat("\n"); print(x$regime)
  } else {
    cat(" ", format(x$regime), "\n", sep = "")
  }

  if (length(grp)) {
    cat("groups      :", paste(grp, collapse = ", "), "\n")
    cat("n_groups    :",
        nrow(unique(x$factor[, grp, with = FALSE])), "\n")
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
#' Initialises `g_sel` from the WLS-fitted `g` and optionally
#' fills `NA` runs via `data.table::nafill(type = "locf")`. Mirrors
#' the fill phase of [.filter_ata()] without the maturity gate (ED
#' has no maturity concept).
#'
#' @param ed_summary An `EDSummary`.
#' @param groups Character vector of group columns.
#' @param na_method One of `"locf"` (default) or `"none"`.
#'
#' @return A `data.table` with `g_sel` added.
#'
#' @keywords internal
.select_intensity <- function(ed_summary,
                              groups    = character(0),
                              na_method = c("zero", "locf", "none")) {

  na_method <- match.arg(na_method)

  z <- .copy_dt(ed_summary)
  z[, ("g_sel") := g]

  # When segment_id is present (segment_bridged_borrowed), LOCF fills must
  # happen per segment so factors from one regime never leak into another.
  has_seg <- "segment_id" %in% names(z)
  fill_by <- c(groups, if (has_seg) "segment_id")

  if (na_method == "zero") {
    z[is.na(g_sel), ("g_sel") := 0]
  } else if (na_method == "locf") {
    if (length(fill_by)) {
      data.table::setorderv(z, c(fill_by, "ata_from", "ata_to"))
      z[, ("g_sel") := data.table::nafill(g_sel, type = "locf"),
        by = fill_by]
    } else {
      z[, ("g_sel") := data.table::nafill(g_sel, type = "locf")]
    }
  }

  data.table::setorderv(z, c(fill_by, "ata_from", "ata_to"))
  z
}
