# Link table -------------------------------------------------------------

#' Build a link table from `Triangle` data
#'
#' @description
#' Construct a development-link table from an object of class `Triangle`,
#' typically produced by [build_triangle()]. The link table is the
#' long-format intermediate underlying both the chain ladder (CL) and
#' exposure-driven (ED) workflows. Each row corresponds to one
#' development link `(cohort, ata_from -> ata_to)`.
#'
#' Two modes are produced depending on `premium_var`:
#'
#' \describe{
#'   \item{Single-variable mode (`premium_var = NULL`)}{The age-to-age
#'     factor is \eqn{ata = value_{to} / value_{from}}, where
#'     \eqn{value} is the column named by `loss_var`.}
#'   \item{Dual-variable mode (`premium_var` supplied)}{In addition to
#'     the loss-side ATA, the exposure-driven intensity
#'     \eqn{g = \Delta loss / premium_{from}} is computed. Premium
#'     measure used as denominator for loss ratio calculations; for
#'     long-term health insurance applications, risk premium is
#'     commonly used.}
#' }
#'
#' @param x A `Triangle` object.
#' @param loss_var A single cumulative metric used as the link
#'   numerator. Must be one of `"loss"`, `"premium"`, or `"lr"`. Default
#'   `"loss"`. Despite the name, this argument accepts any cumulative
#'   metric on the Triangle; `"loss"` reflects the most common use.
#' @param premium_var Optional second cumulative metric, treated as the
#'   exposure anchor for the ED workflow. Must be one of `"loss"`,
#'   `"premium"`, `"lr"`, and must differ from `loss_var`. When `NULL`
#'   (default), only the single-variable columns are produced.
#' @param weight_var Optional cumulative metric used as WLS weight in
#'   downstream `summary` / `fit_ata` calls. Must differ from
#'   `loss_var`. Cannot be combined with `premium_var` (the dual
#'   workflow has its own anchor).
#' @param min_denom Minimum denominator required to compute `ata`
#'   and `g`. If `value_from <= min_denom`, `ata` becomes `NA`; if
#'   `premium_from <= min_denom`, `g` becomes `NA`. Default `0`.
#' @param drop_invalid Logical; if `TRUE`, rows with non-finite `ata`
#'   (single-var) or non-finite `g` (dual-var) are dropped. Default
#'   `FALSE` so the full link grid is preserved for diagnostics.
#'
#' @return A `data.table` of class `"Link"` with columns:
#'
#'   * Always: `[group_var]`, `cohort`, `ata_from`, `ata_to`, `ata_link`,
#'     `value_from`, `value_to`, `delta_value`, `ata`.
#'   * If `premium_var` is set: also `premium_from`, `premium_to`,
#'     `delta_premium`, `g`.
#'   * If `weight_var` is set: also `weight`.
#'
#'   The returned object carries attributes `group_var`, `cohort_var`,
#'   `cohort_type`, `dev_var`, `dev_type`, `loss_var`, `premium_var`
#'   (or `NULL`), `weight_var` (or `NULL`).
#'
#' @seealso [build_triangle()], [summary.Link()], [plot.Link()],
#'   [fit_ata()], [fit_ed()]
#'
#' @examples
#' \dontrun{
#' tri <- build_triangle(df, group_var = coverage)
#'
#' # Single-variable: cumulative-loss link factors (ATA workflow)
#' link_loss <- build_link(tri, loss_var = "loss")
#'
#' # Dual-variable: ED-ready link table (loss + premium)
#' link_ed <- build_link(tri, loss_var = "loss", premium_var = "premium")
#' head(link_ed)
#' }
#'
#' @export
build_link <- function(x,
                       loss_var     = "loss",
                       premium_var  = NULL,
                       weight_var   = NULL,
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

  dt <- .ensure_dt(x)

  grp_var <- attr(dt, "group_var")
  coh_var <- attr(dt, "cohort_var")
  coh_type <- attr(dt, "cohort_type")
  dev_var  <- attr(dt, "dev_var")
  dev_type <- attr(dt, "dev_type")

  if (is.null(grp_var)) grp_var <- character(0)
  if (length(coh_var) != 1L)
    stop("`x` must contain exactly one `cohort_var`.", call. = FALSE)
  if (length(dev_var) != 1L)
    stop("`x` must contain exactly one `dev_var`.", call. = FALSE)

  valid_vars <- c("loss", "premium", "lr")

  l_var <- .capture_names(dt, !!rlang::enquo(loss_var))
  if (length(l_var) != 1L || !(l_var %in% valid_vars))
    stop("`loss_var` must be one of 'loss', 'premium', or 'lr'.",
         call. = FALSE)

  use_premium <- !is.null(premium_var)
  use_weight  <- !is.null(weight_var)

  if (use_premium) {
    p_var <- .capture_names(dt, !!rlang::enquo(premium_var))
    if (length(p_var) != 1L || !(p_var %in% valid_vars))
      stop("`premium_var` must be one of 'loss', 'premium', or 'lr'.",
           call. = FALSE)
    if (p_var == l_var)
      stop("`premium_var` must differ from `loss_var`.", call. = FALSE)
  } else {
    p_var <- NULL
  }

  if (use_weight) {
    if (use_premium)
      stop("`weight_var` cannot be combined with `premium_var`. ",
           "The dual-variable mode uses `premium_from` as its anchor.",
           call. = FALSE)
    wt_var <- .capture_names(dt, !!rlang::enquo(weight_var))
    if (length(wt_var) != 1L || !(wt_var %in% valid_vars))
      stop("`weight_var` must be one of 'loss', 'premium', or 'lr'.",
           call. = FALSE)
    if (wt_var == l_var)
      stop("`weight_var` must differ from `loss_var`.", call. = FALSE)
  } else {
    wt_var <- NULL
  }

  grp_coh_var <- c(grp_var, "cohort")

  z <- .ensure_dt(x)
  data.table::setorderv(z, c(grp_coh_var, "dev"))

  # 1) link metadata ----------------------------------------------------
  z[, ata_from := dev]
  z[, ata_to   := data.table::shift(dev, type = "lead"),
    by = grp_coh_var]
  z[, ata_link := sprintf("%s-%s", ata_from, ata_to)]

  # 2) value_from / value_to / delta_value / ata -----------------------
  z[, value_from := .SD[[l_var]], .SDcols = l_var]
  z[, value_to   := data.table::shift(.SD[[1L]], type = "lead"),
    by      = grp_coh_var,
    .SDcols = l_var]
  z[, delta_value := value_to - value_from]
  z[, ata := data.table::fifelse(
    value_from > min_denom,
    value_to / value_from,
    NA_real_
  )]

  # 3) premium_from / premium_to / delta_premium / g -------------------
  if (use_premium) {
    z[, premium_from := .SD[[p_var]], .SDcols = p_var]
    z[, premium_to   := data.table::shift(.SD[[1L]], type = "lead"),
      by      = grp_coh_var,
      .SDcols = p_var]
    z[, delta_premium := premium_to - premium_from]
    z[, g := data.table::fifelse(
      premium_from > min_denom,
      delta_value / premium_from,
      NA_real_
    )]
  }

  # 4) attach weight column --------------------------------------------
  if (use_weight) {
    z[, weight := .SD[[wt_var]], .SDcols = wt_var]
  }

  # 5) remove last dev row per cohort (no lead available) --------------
  z <- z[!is.na(ata_to)]

  # 6) drop invalid rows if requested ----------------------------------
  if (drop_invalid) {
    z <- if (use_premium) z[is.finite(g)] else z[is.finite(ata)]
  }

  # 7) keep relevant columns -------------------------------------------
  keep <- c(
    grp_var, "cohort",
    "ata_from", "ata_to", "ata_link",
    "value_from", "value_to", "delta_value", "ata",
    if (use_premium)
      c("premium_from", "premium_to", "delta_premium", "g"),
    if (use_weight) "weight"
  )

  z <- z[, .SD, .SDcols = keep]

  data.table::setattr(z, "group_var"  , grp_var)
  data.table::setattr(z, "cohort_var" , coh_var)
  data.table::setattr(z, "cohort_type", coh_type)
  data.table::setattr(z, "dev_var"    , dev_var)
  data.table::setattr(z, "dev_type"   , dev_type)
  data.table::setattr(z, "loss_var"   , l_var)
  data.table::setattr(z, "premium_var", p_var)
  data.table::setattr(z, "weight_var" , wt_var)

  .prepend_class(z, "Link")
}


#' Summarise a `Link` table
#'
#' Dispatch to the appropriate diagnostic table based on `model`.
#'
#' @param object A `Link` object from [build_link()].
#' @param model Either `"ata"` (multiplicative chain-ladder factors) or
#'   `"ed"` (additive exposure-driven intensities). When `model = "ed"`,
#'   the link table must have been built with `premium_var` set. The
#'   default uses `"ed"` if `attr(object, "premium_var")` is non-`NULL`,
#'   otherwise `"ata"`.
#' @param alpha,digits,... Forwarded to the underlying summary helper.
#'
#' @return Either an `ATASummary` (model = `"ata"`) or `EDSummary`
#'   (model = `"ed"`) `data.table`.
#'
#' @seealso [build_link()], [detect_maturity()]
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
    model <- if (!is.null(attr(object, "premium_var"))) "ed" else "ata"
  }
  model <- match.arg(model, c("ata", "ed"))

  if (identical(model, "ed") && is.null(attr(object, "premium_var")))
    stop("`model = 'ed'` requires a Link built with `premium_var`.",
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
#' directly as `value_to / value_from` and standard errors are set to `NA`.
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
#'   non-positive `value_from` are dropped before fitting. Note that
#'   `value_to = 0` is permitted, as zero cumulative values are valid
#'   observations (e.g. no claims yet developed in early development periods).
#' @param tol Non-negative numeric scalar. Values below `tol` are set to
#'   zero. Default is `1e-12`.
#'
#' @return A `data.table` with one row per ata link containing `f`,
#'   `f_se`, `sigma`, `rse`, and `n_obs`. `rse` is defined as
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

  if (!is.numeric(alpha) || length(alpha) != 1L || is.na(alpha))
    stop("`alpha` must be a single non-missing numeric value.", call. = FALSE)

  if (!is.logical(na_rm) || length(na_rm) != 1L || is.na(na_rm))
    stop("`na_rm` must be a single non-missing logical value.", call. = FALSE)

  if (!is.numeric(tol) || length(tol) != 1L || is.na(tol) || tol < 0)
    stop("`tol` must be a single non-negative numeric value.", call. = FALSE)

  grp_var <- attr(x, "group_var")
  if (is.null(grp_var)) grp_var <- character(0)

  dt <- .ensure_dt(x)

  # 1) drop invalid rows ------------------------------------------------
  if (na_rm) {
    dt <- dt[is.finite(value_from) & is.finite(value_to) & value_from > 0]
  }

  # 2) attach weight column ---------------------------------------------
  if (is.character(weights)) {
    if (length(weights) != 1L || !weights %in% names(dt))
      stop("`weights` must be a single existing column name.", call. = FALSE)
    dt[, w := .SD, .SDcols = weights]
  } else {
    if (!is.numeric(weights) || length(weights) != 1L || is.na(weights))
      stop(
        "`weights` must be a single non-missing numeric scalar or a column name.",
        call. = FALSE
      )
    dt[, w := weights]
  }

  # regression weight: w / value_from^(2 - alpha)
  # this corresponds to Mack's variance assumption:
  # Var(C_{i,k+1} | C_{i,k}) proportional to C_{i,k}^alpha / w_{i,k}
  delta <- 2 - alpha
  dt[, reg_w := w / value_from^delta]
  dt[, ata_link := sprintf("%s-%s", ata_from, ata_to)]

  # 3) fit one model per link -------------------------------------------
  res <- dt[, {
    if (.N == 1L) {
      data.table::data.table(
        f     = value_to[1L] / value_from[1L],
        f_se  = NA_real_,
        sigma = NA_real_,
        n_obs = 1L
      )
    } else {
      fit <- tryCatch(
        stats::lm(value_to ~ value_from + 0, weights = reg_w),
        error = function(e) NULL
      )

      if (is.null(fit)) {
        data.table::data.table(
          f = NA_real_, f_se = NA_real_, sigma = NA_real_, n_obs = .N
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
          n_obs = .N
        )
      }
    }
  }, keyby = c(grp_var, "ata_from", "ata_to", "ata_link")]

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
