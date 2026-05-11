# Age-to-age maturity -----------------------------------------------------

#' Find ata maturity by group
#'
#' @description
#' Identify the first mature age-to-age (ata) link from a `Triangle`.
#' Internally builds a single-variable `Link` table, computes the
#' per-link diagnostic via [summary.Link()] with `model = "ata"`, and
#' then locates the first link whose statistics satisfy all maturity
#' criteria.
#'
#' Maturity is determined using a combination of:
#' \itemize{
#'   \item `cv < max_cv`
#'   \item `rse < max_rse`
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
#' Default `loss_var = "loss"` (cumulative loss). Maturity in chain
#' ladder is methodologically a property of *loss* development:
#' the ATA factors of cumulative loss stabilize when chain ladder
#' becomes reliable, which in turn makes downstream LR projection
#' reliable. ATA factors of `lr` itself (a ratio of two cumulative
#' quantities) carry additional noise and tend to give less precise
#' maturity decisions. Override `loss_var` only when you specifically
#' want maturity of premium development or another cumulative metric.
#'
#' @param x A `Triangle` object.
#' @param loss_var Cumulative metric for the link factor. Default
#'   `"loss"` (chain-ladder convention; see Description). Forwarded to
#'   [build_link()].
#' @param weight_var Optional WLS weight variable. Forwarded to
#'   [build_link()].
#' @param alpha Numeric scalar controlling the variance structure in
#'   the underlying WLS fit. Default `1`. Forwarded to [summary.Link()].
#' @param max_cv Maximum allowed coefficient of variation.
#'   Default is `0.15`.
#' @param max_rse Maximum allowed relative standard error.
#'   Default is `0.05`.
#' @param min_valid_ratio Minimum proportion of finite ata values required.
#'   Default is `0.5`.
#' @param min_n_valid Minimum number of finite ata factors required.
#'   Default is `3L`.
#' @param min_run Minimum number of consecutive ata links satisfying the
#'   maturity criteria. Default is `2L`.
#'
#' @return A `data.table` with class `"Maturity"` containing one row
#'   per group. If no mature link is found, all values for that group are
#'   `NA`.
#'
#' @export
detect_maturity <- function(x,
                            loss_var        = "loss",
                            weight_var      = NULL,
                            alpha           = 1,
                            max_cv          = 0.15,
                            max_rse         = 0.05,
                            min_valid_ratio = 0.5,
                            min_n_valid     = 3L,
                            min_run         = 2L) {

  .assert_triangle_input(x, "detect_maturity()")

  link <- build_link(x, target = loss_var, weight = weight_var)
  ata_summary <- summary(link, model = "ata", alpha = alpha)

  .detect_maturity(
    ata_summary,
    max_cv          = max_cv,
    max_rse         = max_rse,
    min_valid_ratio = min_valid_ratio,
    min_n_valid     = min_n_valid,
    min_run         = min_run
  )
}


#' Internal: locate the first mature ata link from an `ATASummary`
#'
#' @keywords internal
.detect_maturity <- function(x,
                             max_cv          = 0.15,
                             max_rse         = 0.05,
                             min_valid_ratio = 0.5,
                             min_n_valid     = 3L,
                             min_run         = 2L) {

  .assert_class(x, "ATASummary")

  if (!is.numeric(max_cv) || length(max_cv) != 1L ||
      is.na(max_cv))
    stop("`max_cv` must be a single non-missing numeric value.",
         call. = FALSE)

  if (!is.numeric(max_rse) || length(max_rse) != 1L ||
      is.na(max_rse))
    stop("`max_rse` must be a single non-missing numeric value.",
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

  smr     <- .ensure_dt(x)
  grp_var <- attr(x, "group_var")
  if (is.null(grp_var)) grp_var <- character(0)

  # internal: find first mature row in a single-group summary table
  .first_mature_row <- function(d,
                                max_cv,
                                max_rse,
                                min_valid_ratio,
                                min_n_valid,
                                min_run) {

    d  <- .ensure_dt(d)
    ok <- with(d,
               is.finite(cv)          & cv          <  max_cv    &
                 is.finite(rse)         & rse         <  max_rse   &
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
    z <- smr[, .first_mature_row(
      .SD,
      max_cv          = max_cv,
      max_rse         = max_rse,
      min_valid_ratio = min_valid_ratio,
      min_n_valid     = min_n_valid,
      min_run         = min_run
    ), by = grp_var]
  } else {
    z <- .first_mature_row(
      smr,
      max_cv          = max_cv,
      max_rse         = max_rse,
      min_valid_ratio = min_valid_ratio,
      min_n_valid     = min_n_valid,
      min_run         = min_run
    )
  }

  data.table::setattr(z, "max_cv",    max_cv)
  data.table::setattr(z, "max_rse",   max_rse)
  data.table::setattr(z, "min_valid_ratio", min_valid_ratio)
  data.table::setattr(z, "min_n_valid",     min_n_valid)
  data.table::setattr(z, "min_run",         min_run)
  data.table::setattr(z, "group_var",       grp_var)
  data.table::setattr(z, "loss_var",       attr(x, "target"))
  data.table::setattr(z, "weight_var",      attr(x, "weight"))

  .prepend_class(z, "Maturity")
}
