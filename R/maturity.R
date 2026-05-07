# Age-to-age maturity -----------------------------------------------------

#' Find ata maturity by group
#'
#' @description
#' Identify the first mature age-to-age (ata) link from a `Triangle`.
#' Internally builds a single-variable [Link] table, computes the
#' per-link diagnostic via [summary.Link()] with `model = "ata"`, and
#' then locates the first link whose statistics satisfy all maturity
#' criteria.
#'
#' Maturity is determined using a combination of:
#' \itemize{
#'   \item `cv < cv_threshold`
#'   \item `rse < rse_threshold`
#'   \item `valid_ratio >= min_valid_ratio`
#'   \item `n_valid >= min_n_valid`
#'   \item optional consecutive maturity over `min_run` ata links
#' }
#'
#' Both `cv` and `rse` must be satisfied simultaneously. `cv` captures
#' the raw variability of observed ata factors across cohorts, while `rse`
#' reflects the precision of the WLS-estimated factor. Using both criteria
#' together provides a more robust maturity assessment than either alone.
#'
#' @param x A `Triangle` object.
#' @param value_var Cumulative metric for the link factor. Default
#'   `"closs"`. Forwarded to [build_link()].
#' @param weight_var Optional WLS weight variable. Forwarded to
#'   [build_link()].
#' @param alpha Numeric scalar controlling the variance structure in
#'   the underlying WLS fit. Default `1`. Forwarded to [summary.Link()].
#' @param cv_threshold Maximum allowed coefficient of variation.
#'   Default is `0.10`.
#' @param rse_threshold Maximum allowed relative standard error.
#'   Default is `0.05`.
#' @param min_valid_ratio Minimum proportion of finite ata values required.
#'   Default is `0.5`.
#' @param min_n_valid Minimum number of finite ata factors required.
#'   Default is `3L`.
#' @param min_run Minimum number of consecutive ata links satisfying the
#'   maturity criteria. Default is `1L`.
#'
#' @return A `data.table` with class `"Maturity"` containing one row
#'   per group. If no mature link is found, all values for that group are
#'   `NA`.
#'
#' @export
find_maturity <- function(x,
                          value_var       = "closs",
                          weight_var      = NULL,
                          alpha           = 1,
                          cv_threshold    = 0.10,
                          rse_threshold   = 0.05,
                          min_valid_ratio = 0.5,
                          min_n_valid     = 3L,
                          min_run         = 1L) {

  .assert_class(x, "Triangle")

  link <- build_link(x, value_var = value_var, weight_var = weight_var)
  ata_summary <- summary(link, model = "ata", alpha = alpha)

  .find_maturity(
    ata_summary,
    cv_threshold    = cv_threshold,
    rse_threshold   = rse_threshold,
    min_valid_ratio = min_valid_ratio,
    min_n_valid     = min_n_valid,
    min_run         = min_run
  )
}


#' Internal: locate the first mature ata link from an `ATASummary`
#'
#' @keywords internal
.find_maturity <- function(x,
                           cv_threshold    = 0.10,
                           rse_threshold   = 0.05,
                           min_valid_ratio = 0.5,
                           min_n_valid     = 3L,
                           min_run         = 1L) {

  .assert_class(x, "ATASummary")

  if (!is.numeric(cv_threshold) || length(cv_threshold) != 1L ||
      is.na(cv_threshold))
    stop("`cv_threshold` must be a single non-missing numeric value.",
         call. = FALSE)

  if (!is.numeric(rse_threshold) || length(rse_threshold) != 1L ||
      is.na(rse_threshold))
    stop("`rse_threshold` must be a single non-missing numeric value.",
         call. = FALSE)

  if (!is.numeric(min_valid_ratio) || length(min_valid_ratio) != 1L ||
      is.na(min_valid_ratio))
    stop("`min_valid_ratio` must be a single non-missing numeric value.",
         call. = FALSE)

  if (!is.numeric(min_n_valid) || length(min_n_valid) != 1L ||
      is.na(min_n_valid))
    stop("`min_n_valid` must be a single non-missing numeric value.",
         call. = FALSE)

  if (!is.numeric(min_run) || length(min_run) != 1L ||
      is.na(min_run) || min_run < 1)
    stop("`min_run` must be a single integer >= 1.", call. = FALSE)

  min_n_valid <- as.integer(min_n_valid)
  min_run     <- as.integer(min_run)

  sm      <- .ensure_dt(x)
  grp_var <- attr(x, "group_var")
  if (is.null(grp_var)) grp_var <- character(0)

  # internal: find first mature row in a single-group summary table
  .first_mature_row <- function(d,
                                cv_threshold,
                                rse_threshold,
                                min_valid_ratio,
                                min_n_valid,
                                min_run) {

    d  <- .ensure_dt(d)
    ok <- with(d,
               is.finite(cv)          & cv          <  cv_threshold    &
                 is.finite(rse)         & rse         <  rse_threshold   &
                 is.finite(valid_ratio) & valid_ratio >= min_valid_ratio &
                 is.finite(n_valid)     & n_valid     >= min_n_valid
    )

    idx <- NA_integer_

    if (min_run == 1L) {
      idx <- which(ok)[1L]
    } else if (length(ok) >= min_run) {
      for (i in seq_len(length(ok) - min_run + 1L)) {
        if (all(ok[i:(i + min_run - 1L)])) { idx <- i; break }
      }
    }

    if (length(idx) == 0L || is.na(idx)) {
      return(data.table::data.table(
        ata_from    = NA_real_,
        ata_to      = NA_real_,
        ata_link    = NA_character_,
        mean        = NA_real_,
        median      = NA_real_,
        wt          = NA_real_,
        cv          = NA_real_,
        f           = NA_real_,
        f_se        = NA_real_,
        rse         = NA_real_,
        sigma       = NA_real_,
        n_obs       = NA_real_,
        n_valid     = NA_real_,
        n_inf       = NA_real_,
        n_nan       = NA_real_,
        valid_ratio = NA_real_
      ))
    }

    data.table::data.table(
      ata_from    = d$ata_from[idx],
      ata_to      = d$ata_to[idx],
      ata_link    = as.character(d$ata_link[idx]),
      mean        = d$mean[idx],
      median      = d$median[idx],
      wt          = d$wt[idx],
      cv          = d$cv[idx],
      f           = d$f[idx],
      f_se        = d$f_se[idx],
      rse         = d$rse[idx],
      sigma       = d$sigma[idx],
      n_obs       = d$n_obs[idx],
      n_valid     = d$n_valid[idx],
      n_inf       = d$n_inf[idx],
      n_nan       = d$n_nan[idx],
      valid_ratio = d$valid_ratio[idx]
    )
  }

  if (length(grp_var)) {
    z <- sm[, .first_mature_row(
      .SD,
      cv_threshold    = cv_threshold,
      rse_threshold   = rse_threshold,
      min_valid_ratio = min_valid_ratio,
      min_n_valid     = min_n_valid,
      min_run         = min_run
    ), by = grp_var]
  } else {
    z <- .first_mature_row(
      sm,
      cv_threshold    = cv_threshold,
      rse_threshold   = rse_threshold,
      min_valid_ratio = min_valid_ratio,
      min_n_valid     = min_n_valid,
      min_run         = min_run
    )
  }

  data.table::setattr(z, "cv_threshold",    cv_threshold)
  data.table::setattr(z, "rse_threshold",   rse_threshold)
  data.table::setattr(z, "min_valid_ratio", min_valid_ratio)
  data.table::setattr(z, "min_n_valid",     min_n_valid)
  data.table::setattr(z, "min_run",         min_run)
  data.table::setattr(z, "group_var",       grp_var)
  data.table::setattr(z, "value_var",       attr(x, "value_var"))
  data.table::setattr(z, "weight_var",      attr(x, "weight_var"))

  .prepend_class(z, "Maturity")
}
