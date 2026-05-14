# Link table -------------------------------------------------------------

#' Coerce a Triangle to a Link object
#'
#' @description
#' Derive the development-link table from a `Triangle` and assign the
#' `Link` S3 class so the associated `summary.Link()`, `plot.Link()`,
#' `fit_ata()`, `fit_intensity()`, etc. methods dispatch on the result.
#'
#' Unlike [as_triangle()] / [as_calendar()] / [as_total()] (which take
#' raw experience data and validate/aggregate it), `as_link()` operates
#' *on a Triangle* (already validated upstream) and reshapes it into
#' link-pair rows. Each row corresponds to one development link
#' `(cohort, ata_from -> ata_to)`, the long-format intermediate
#' underlying both the chain ladder (CL) and exposure-driven (ED)
#' workflows.
#'
#' Two modes are produced depending on `exposure`:
#'
#' \describe{
#'   \item{Single-variable mode (`exposure = NULL`)}{The age-to-age
#'     factor is \eqn{ata = value_{to} / value_{from}}, where
#'     \eqn{value} is the column named by `target`.}
#'   \item{Dual-variable mode (`exposure` supplied)}{In addition to
#'     the loss-side ATA, the exposure-driven intensity
#'     \eqn{g = \Delta loss / prem_{from}} is computed and stored in
#'     the `intensity` column. Premium measure used as denominator for
#'     loss ratio calculations; for long-term health insurance
#'     applications, risk prem is commonly used.}
#' }
#'
#' @param x A `Triangle` object.
#' @param target A single cumulative metric used as the link
#'   numerator. Must be one of `"loss"`, `"prem"`, or `"lr"`. Default
#'   `"loss"`. Generic worker name; for loss-side ATA this is the
#'   cumulative loss column, but any cumulative metric on the Triangle
#'   may be supplied.
#' @param exposure Optional second cumulative metric, treated as the
#'   exposure anchor for the ED workflow. Must be one of `"loss"`,
#'   `"prem"`, `"lr"`, and must differ from `target`. When `NULL`
#'   (default), only the single-variable columns are produced.
#' @param weight Optional cumulative metric used as WLS weight in
#'   downstream `summary` / `fit_ata` calls. Must differ from
#'   `target`. Cannot be combined with `exposure` (the dual
#'   workflow has its own anchor).
#' @param min_denom Minimum denominator required to compute `ata`
#'   and `intensity`. If `target_from <= min_denom`, `ata` becomes `NA`;
#'   if `exposure_from <= min_denom`, `intensity` becomes `NA`. Default
#'   `0`.
#' @param drop_invalid Logical; if `TRUE`, rows with non-finite `ata`
#'   (single-var) or non-finite `intensity` (dual-var) are dropped.
#'   Default `FALSE` so the full link grid is preserved for
#'   diagnostics.
#'
#' @return A `data.table` of class `"Link"` with columns:
#'
#'   * Always: `[group]`, `cohort`, `ata_from`, `ata_to`, `ata_link`,
#'     `target_from`, `target_to`, `target_delta`, `ata`.
#'   * If `exposure` is set: also `exposure_from`, `exposure_to`,
#'     `exposure_delta`, `intensity`.
#'   * If `weight` is set: also `weight`.
#'
#'   The returned object carries attributes `groups`, `cohort`,
#'   `dev`, `target`, `exposure` (or `NULL`), `weight`
#'   (or `NULL`).
#'
#' @seealso [as_triangle()], [summary.Link()], [plot.Link()],
#'   [fit_ata()], [fit_ed()]
#'
#' @examples
#' \dontrun{
#' tri <- as_triangle(
#'   df,
#'   groups   = "coverage",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "incr_loss",
#'   prem  = "incr_prem"
#' )
#'
#' # Single-variable: cumulative-loss link factors (ATA workflow)
#' link_loss <- as_link(tri, target = "loss")
#'
#' # Dual-variable: ED-ready link table (loss + prem)
#' link_ed <- as_link(tri, target = "loss", exposure = "prem")
#' head(link_ed)
#' }
#'
#' @export
as_link <- function(x,
                       target       = "loss",
                       exposure     = NULL,
                       weight       = NULL,
                       min_denom    = 0,
                       drop_invalid = FALSE) {

  .assert_class(x, "Triangle")

  if (!is.numeric(min_denom) || length(min_denom) != 1L || is.na(min_denom))
    stop("`min_denom` must be a single non-missing numeric value.",
         call. = FALSE)

  if (!is.logical(drop_invalid) || length(drop_invalid) != 1L ||
      is.na(drop_invalid))
    stop("`drop_invalid` must be a single non-missing logical value.",
         call. = FALSE)

  dt <- .copy_dt(x)

  grp <- attr(dt, "groups")
  coh <- attr(dt, "cohort")
  dev <- attr(dt, "dev")

  if (is.null(grp)) grp <- character(0)
  if (length(coh) != 1L)
    stop("`x` must contain exactly one `cohort`.", call. = FALSE)
  if (length(dev) != 1L)
    stop("`x` must contain exactly one `dev`.", call. = FALSE)

  valid_vars <- c("loss", "prem", "lr")

  if (!is.character(target) || length(target) != 1L ||
      !(target %in% valid_vars))
    stop("`target` must be one of 'loss', 'prem', or 'lr'.",
         call. = FALSE)
  tgt <- target

  use_exposure <- !is.null(exposure)
  use_weight   <- !is.null(weight)

  if (use_exposure) {
    if (!is.character(exposure) || length(exposure) != 1L ||
        !(exposure %in% valid_vars))
      stop("`exposure` must be one of 'loss', 'prem', or 'lr'.",
           call. = FALSE)
    exp <- exposure
    if (exp == tgt)
      warning(
        "`exposure` equals `target` (\"", tgt, "\") -- self-anchored ",
        "fit. Mathematically equivalent to chain ladder on the same column ",
        "(f_k = 1 + g_k); use only when intentional.",
        call. = FALSE
      )
  } else {
    exp <- NULL
  }

  if (use_weight) {
    if (use_exposure)
      stop("`weight` cannot be combined with `exposure`. ",
           "The dual-variable mode uses `exposure_from` as its anchor.",
           call. = FALSE)
    if (!is.character(weight) || length(weight) != 1L ||
        !(weight %in% valid_vars))
      stop("`weight` must be one of 'loss', 'prem', or 'lr'.",
           call. = FALSE)
    wt <- weight
    if (wt == tgt)
      stop("`weight` must differ from `target`.", call. = FALSE)
  } else {
    wt <- NULL
  }

  grp_coh <- c(grp, "cohort")

  z <- .copy_dt(x)
  data.table::setorderv(z, c(grp_coh, "dev"))

  # 1) link metadata ----------------------------------------------------
  z[, ("ata_from") := dev]
  z[, ata_to   := data.table::shift(dev, type = "lead"),
    by = grp_coh]
  z[, ("ata_link") := sprintf("%s-%s", ata_from, ata_to)]

  # 2) target_from / target_to / target_delta / ata -----------------------
  z[, ("target_from") := .SD[[tgt]], .SDcols = tgt]
  z[, target_to   := data.table::shift(.SD[[1L]], type = "lead"),
    by      = grp_coh,
    .SDcols = tgt]
  z[, ("target_delta") := target_to - target_from]
  z[, ("ata") := data.table::fifelse(
    target_from > min_denom,
    target_to / target_from,
    NA_real_
  )]

  # 3) exposure_from / exposure_to / exposure_delta / intensity --------
  if (use_exposure) {
    z[, ("exposure_from") := .SD[[exp]], .SDcols = exp]
    z[, exposure_to   := data.table::shift(.SD[[1L]], type = "lead"),
      by      = grp_coh,
      .SDcols = exp]
    z[, ("exposure_delta") := exposure_to - exposure_from]
    z[, ("intensity") := data.table::fifelse(
      exposure_from > min_denom,
      target_delta / exposure_from,
      NA_real_
    )]
  }

  # 4) attach weight column --------------------------------------------
  if (use_weight) {
    z[, ("weight") := .SD[[wt]], .SDcols = wt]
  }

  # 5) remove last dev row per cohort (no lead available) --------------
  z <- z[!is.na(ata_to)]

  # 6) drop invalid rows if requested ----------------------------------
  if (drop_invalid) {
    z <- if (use_exposure) z[is.finite(intensity)] else z[is.finite(ata)]
  }

  # 7) keep relevant columns -------------------------------------------
  keep <- c(
    grp, "cohort",
    "ata_from", "ata_to", "ata_link",
    "target_from", "target_to", "target_delta", "ata",
    if (use_exposure)
      c("exposure_from", "exposure_to", "exposure_delta", "intensity"),
    if (use_weight) "weight"
  )

  z <- z[, .SD, .SDcols = keep]

  data.table::setattr(z, "groups" , grp)
  data.table::setattr(z, "cohort", coh)
  data.table::setattr(z, "dev"   , dev)
  data.table::setattr(z, "target"    , tgt)
  data.table::setattr(z, "exposure"  , exp)
  data.table::setattr(z, "weight"    , wt)

  # Link is *not* a Triangle (different data structure: edge-level pairs
  # vs cell-level grid). Remove Triangle inheritance to prevent silent
  # `inherits(x, "Triangle")` confusion at fit_* input gates.
  .update_class(z, remove = "Triangle", prepend = "Link")
}


#' Summarise a `Link` table
#'
#' Dispatch to the appropriate diagnostic table based on `model`.
#'
#' @param object A `Link` object from [as_link()].
#' @param model Either `"ata"` (multiplicative chain-ladder factors) or
#'   `"ed"` (additive exposure-driven intensities). When `model = "ed"`,
#'   the link table must have been built with `exposure` set. The
#'   default uses `"ed"` if `attr(object, "exposure")` is non-`NULL`,
#'   otherwise `"ata"`.
#' @param alpha,digits,... Forwarded to the underlying summary helper.
#'
#' @return Either an `ATASummary` (model = `"ata"`) or `EDSummary`
#'   (model = `"ed"`) `data.table`.
#'
#' @seealso [as_link()], [detect_maturity()]
#'
#' @method summary Link
#' @export
summary.Link <- function(object,
                         model  = NULL,
                         alpha  = 1,
                         digits = NULL,
                         ...) {

  .assert_class(object, "Link")

  if (is.null(model)) {
    model <- if (!is.null(attr(object, "exposure"))) "ed" else "ata"
  }
  model <- match.arg(model, c("ata", "ed"))

  if (identical(model, "ed") && is.null(attr(object, "exposure")))
    stop("`model = 'ed'` requires a Link built with `exposure`.",
         call. = FALSE)

  if (identical(model, "ata")) {
    if (is.null(digits)) digits <- 3
    .summarize_link_ata(object, alpha = alpha, digits = digits, ...)
  } else {
    if (is.null(digits)) digits <- 5
    .summarize_link_ed(object, alpha = alpha, digits = digits, ...)
  }
}


# Internal: WLS link-factor estimation -----------

#' Estimate age-to-age factors via weighted least squares
#'
#' @description
#' Internal helper that fits one no-intercept weighted linear model per
#' age-to-age link:
#'
#' \deqn{C_{i,k+1} = f_k \cdot C_{i,k} + \varepsilon_{i,k}}
#'
#' Weights are proportional to \eqn{w_{i,k} / C_{i,k}^{2 - \alpha}}, where
#' \eqn{w_{i,k}} is either a constant or a column supplied via `weights`.
#' This corresponds to Mack's variance assumption
#' \eqn{\mathrm{Var}(C_{i,k+1} \mid C_{i,k}) \propto C_{i,k}^{\alpha}}.
#'
#' When only one observation is available for a link, the factor is computed
#' directly as `target_to / target_from` and standard errors are set to `NA`.
#'
#' Near-zero values of `f_se` and `sigma` (below `tol`) are set to zero to
#' avoid numerical noise from essentially perfect fits.
#'
#' @param x An object of class `"Link"`.
#' @param weights Either a length-one numeric scalar (default `1`) or a
#'   single column name present in the `Link` data that provides per-row
#'   weights.
#' @param alpha Numeric scalar controlling the variance structure. Default
#'   is `1`.
#' @param na_rm Logical; if `TRUE` (default), rows with non-finite or
#'   non-positive `target_from` are dropped before fitting. Note that
#'   `target_to = 0` is permitted, as zero cumulative values are valid
#'   observations (e.g. no claims yet developed in early development periods).
#' @param tol Non-negative numeric scalar. Values below `tol` are set to
#'   zero. Default is `1e-12`.
#'
#' @return A `data.table` with one row per ata link containing `f`,
#'   `f_se`, `sigma`, `rse`, and `n_cohorts`. `rse` is defined as
#'   \eqn{f\_se / f} and represents the relative standard error of the
#'   WLS-estimated factor. `rse` is `NA` when `f_se` is `NA` (single
#'   observation links) or when `f` is zero.
#'
#' @keywords internal
.lm_link <- function(x,
                     weights = 1,
                     alpha   = 1,
                     na_rm   = TRUE,
                     tol     = 1e-12) {

  .assert_class(x, "Link")

  # Suppress R CMD check NOTEs for `data.table` temp columns referenced
  # bare inside `j` expressions later in this function.
  .reg_w <- NULL

  if (!is.numeric(alpha) || length(alpha) != 1L || is.na(alpha))
    stop("`alpha` must be a single non-missing numeric value.", call. = FALSE)

  if (!is.logical(na_rm) || length(na_rm) != 1L || is.na(na_rm))
    stop("`na_rm` must be a single non-missing logical value.", call. = FALSE)

  if (!is.numeric(tol) || length(tol) != 1L || is.na(tol) || tol < 0)
    stop("`tol` must be a single non-negative numeric value.", call. = FALSE)

  grp <- attr(x, "groups")
  if (is.null(grp)) grp <- character(0)

  dt <- .copy_dt(x)

  # 1) drop invalid rows ------------------------------------------------
  if (na_rm) {
    dt <- dt[is.finite(target_from) & is.finite(target_to) & target_from > 0]
  }

  # 2) attach weight column ---------------------------------------------
  if (is.character(weights)) {
    if (length(weights) != 1L || !weights %in% names(dt))
      stop("`weights` must be a single existing column name.", call. = FALSE)
    dt[, ("w") := .SD, .SDcols = weights]
  } else {
    if (!is.numeric(weights) || length(weights) != 1L || is.na(weights))
      stop(
        "`weights` must be a single non-missing numeric scalar or a column name.",
        call. = FALSE
      )
    dt[, ("w") := weights]
  }

  # regression weight: w / target_from^(2 - alpha)
  # this corresponds to Mack's variance assumption:
  # Var(C_{i,k+1} | C_{i,k}) proportional to C_{i,k}^alpha / w_{i,k}
  delta <- 2 - alpha
  dt[, (".reg_w") := w / target_from^delta]
  dt[, ("ata_link") := sprintf("%s-%s", ata_from, ata_to)]

  # segment_wise treatment annotates rows with segment_id upstream; when
  # present, fit one model per (link, segment) so each regime gets its
  # own factor estimate.
  has_seg <- "segment_id" %in% names(dt)
  by_cols <- c(grp, "ata_from", "ata_to", "ata_link",
               if (has_seg) "segment_id")

  # 3) fit one model per link -------------------------------------------
  res <- dt[, {
    if (.N == 1L) {
      data.table::data.table(
        f     = target_to[1L] / target_from[1L],
        f_se  = NA_real_,
        sigma = NA_real_,
        n_cohorts = 1L
      )
    } else {
      fit <- tryCatch(
        stats::lm(target_to ~ target_from + 0, weights = .reg_w),
        error = function(e) NULL
      )

      if (is.null(fit)) {
        data.table::data.table(
          f = NA_real_, f_se = NA_real_, sigma = NA_real_, n_cohorts = .N
        )
      } else {
        smr <- suppressWarnings(summary(fit))

        f_val     <- unname(stats::coef(fit)[1L])
        f_se_val  <- unname(smr$coef[1L, "Std. Error"])
        sigma_val <- unname(smr$sigma)

        if (is.finite(f_se_val)  && abs(f_se_val)  < tol) f_se_val  <- 0
        if (is.finite(sigma_val) && abs(sigma_val) < tol) sigma_val <- 0

        data.table::data.table(
          f     = f_val,
          f_se  = f_se_val,
          sigma = sigma_val,
          n_cohorts = .N
        )
      }
    }
  }, keyby = by_cols]

  # 4) compute rse = f_se / f -------------------------------------------
  data.table::set(
    res,
    j     = "rse",
    value = data.table::fifelse(
      is.finite(res$f_se) & is.finite(res$f) & res$f != 0,
      res$f_se / res$f,
      NA_real_
    )
  )

  data.table::setcolorder(res, "rse", before = "sigma")

  res
}
