# === Triangle validation ====================================================

#' Validate triangle structure before building a development
#'
#' @description
#' Check that each `(group_var, cohort_var)` cohort has a consecutive
#' `dev_var` sequence within its observed range. Non-consecutive
#' cohorts produce non-consecutive age-to-age links downstream (e.g.,
#' `14 -> 17` instead of `14 -> 15`), which breaks
#' [summary.Link()] key uniqueness and causes cartesian joins in
#' [fit_lr()].
#'
#' This function inspects the raw data without modifying it. Use it
#' before [build_triangle()] to decide whether to fix the data source, drop
#' offending cohorts, or pass `fill_gaps = TRUE` to [build_triangle()].
#'
#' Two checks are performed:
#'
#' \enumerate{
#'   \item \strong{Cohort dev-sequence gaps} — for each `(group, cohort)`,
#'     report missing `dev_var` values within the observed range.
#'   \item \strong{Row-level calendar consistency} — when `calendar_var`
#'     is supplied (or auto-detected as `"cym"` if present), report rows
#'     where `calendar_var < cohort_var`. Such rows are logically
#'     impossible (claims cannot precede policy issue) and downstream
#'     they show up as negative `elap_m`, polluting cohort dev sequences.
#' }
#'
#' @param df A data.frame.
#' @param group_var Grouping variable(s).
#' @param cohort_var A single cohort variable. Default `"uym"`.
#' @param dev_var A single development variable. Default `"elap_m"`.
#' @param calendar_var Optional calendar period variable for row-level
#'   consistency check. When supplied, rows where `calendar_var <
#'   cohort_var` are flagged as invalid. Default `"cym"`; pass `NULL`
#'   to skip this check, or a column name to override.
#'
#' @return A `data.table` of class `"TriangleValidation"` with one row
#'   per cohort containing gaps. Columns:
#'   \describe{
#'     \item{group_var(s), cohort_var}{Cohort identifier.}
#'     \item{`n_observed`}{Number of distinct observed `dev_var`
#'       values.}
#'     \item{`n_expected`}{`max(elap_m) - min(elap_m) + 1` for that cohort.}
#'     \item{`missing`}{List column of missing `dev_var` values.}
#'   }
#'   Returns a zero-row data.table when no gaps are found.
#'
#'   Row-level violations (when `calendar_var` is supplied and the check
#'   finds any) are attached as the `"invalid_rows"` attribute — a
#'   `data.table` with columns `[group_var, cohort_var, calendar_var,
#'   dev_var (if present), reason]`. Use `attr(out, "invalid_rows")`
#'   or rely on `print.TriangleValidation` which displays both sections.
#'
#' @seealso [build_triangle()]
#'
#' @export
validate_triangle <- function(df,
                              group_var,
                              cohort_var   = "uym",
                              dev_var      = "elap_m",
                              calendar_var = "cym") {
  .assert_class(df, "data.frame")

  dt <- .ensure_dt(df)

  grp_var <- .capture_names(dt, !!rlang::enquo(group_var))
  coh_var <- .capture_names(dt, !!rlang::enquo(cohort_var))
  dev_var <- .capture_names(dt, !!rlang::enquo(dev_var))

  .assert_length(coh_var)
  .assert_length(dev_var)

  # calendar_var: NULL skips, otherwise auto-skip if column missing
  cal_var <- NULL
  if (!is.null(calendar_var)) {
    cal_var <- .capture_names(dt, !!rlang::enquo(calendar_var))
    if (length(cal_var) != 1L || !(cal_var %in% names(dt))) cal_var <- NULL
  }

  # 1) row-level calendar consistency first — invalid rows pollute the
  #    dev sequence and would surface as spurious negative gaps if we
  #    ran the gap check on the raw data.
  invalid <- NULL
  dt_clean <- dt
  if (!is.null(cal_var)) {
    invalid <- .validate_calendar_consistency_impl(
      dt, grp_var = grp_var, coh_var = coh_var,
      dev_var = dev_var, cal_var = cal_var
    )
    if (nrow(invalid) > 0L) {
      ok <- is.na(dt[[cal_var]]) | is.na(dt[[coh_var]]) |
            (dt[[cal_var]] >= dt[[coh_var]])
      dt_clean <- dt[ok]
    }
  }

  # 2) dev-sequence gaps on the cleaned data
  out <- .validate_dev_continuity_impl(dt_clean, grp_var, coh_var, dev_var)

  if (!is.null(invalid) && nrow(invalid) > 0L) {
    data.table::setattr(out, "invalid_rows", invalid)
  }

  out
}

.validate_dev_continuity_impl <- function(dt, grp_var, coh_var, dev_var) {
  grp_coh <- c(grp_var, coh_var)

  gaps <- dt[, {
    e <- .SD[[1L]]
    e <- e[!is.na(e)]
    if (length(e) == 0L) {
      list(n_observed = 0L, n_expected = 0L, missing = list(integer(0)))
    } else {
      rng  <- seq.int(min(e), max(e))
      miss <- setdiff(rng, e)
      list(
        n_observed = length(unique(e)),
        n_expected = length(rng),
        missing    = list(miss)
      )
    }
  }, by = grp_coh, .SDcols = dev_var]

  gaps <- gaps[n_observed != n_expected]

  data.table::setattr(gaps, "group_var"  , grp_var)
  data.table::setattr(gaps, "cohort_var" , coh_var)
  data.table::setattr(gaps, "dev_var", dev_var)

  .prepend_class(gaps, "TriangleValidation")
}

#' Internal: row-level cohort vs calendar consistency check
#'
#' Flag rows where `calendar_var < cohort_var` — claims/events recorded
#' as occurring before the cohort start, which is logically impossible.
#'
#' @keywords internal
.validate_calendar_consistency_impl <- function(dt, grp_var, coh_var, dev_var, cal_var) {
  ok <- !is.na(dt[[cal_var]]) & !is.na(dt[[coh_var]])
  bad_idx <- ok & (dt[[cal_var]] < dt[[coh_var]])
  if (!any(bad_idx)) {
    return(data.table::data.table())
  }

  keep <- c(grp_var, coh_var, cal_var, dev_var)
  keep <- keep[keep %in% names(dt)]
  z <- dt[bad_idx, .SD, .SDcols = keep]
  z[, reason := sprintf("%s < %s", cal_var, coh_var)]
  z
}

#' @method print TriangleValidation
#' @export
print.TriangleValidation <- function(x, ...) {
  cat("<TriangleValidation>\n")

  # gap section
  if (nrow(x) == 0L) {
    cat("Cohort dev-sequence gaps : none\n")
  } else {
    cat(sprintf("Cohort dev-sequence gaps : %d cohort(s) with gaps\n",
                nrow(x)))
    NextMethod("print", x, ...)
  }

  # invalid rows section
  inv <- attr(x, "invalid_rows", exact = TRUE)
  if (!is.null(inv) && nrow(inv) > 0L) {
    cat(sprintf("\nRow-level violations     : %d row(s) where %s\n",
                nrow(inv), inv$reason[1L]))
    print(inv, ...)
  }

  invisible(x)
}


# === Triangle ===============================================================

#' Build a development structure from experience data
#'
#' @description
#' Aggregate experience data into a development structure by grouping,
#' period, and development-period variables. The result contains:
#' - cumulative loss and cumulative premium,
#' - per-period and cumulative proportions,
#' - per-period and cumulative margin,
#' - profit indicators,
#' - per-period loss ratio (`lr_incr = loss_incr / premium_incr`) and
#'   cumulative loss ratio (`lr = loss / premium`).
#'
#' The cumulative loss ratio is defined as:
#' \deqn{lr = loss / premium}
#'
#' For long-term health insurance applications, risk premium is commonly
#' used as the `premium` measure.
#'
#' Proportion variables are computed within each `(cohort, dev)` cell:
#' \itemize{
#'   \item `loss_incr_prop    = loss_incr    / sum(loss_incr)`
#'   \item `premium_incr_prop = premium_incr / sum(premium_incr)`
#'   \item `loss_prop         = loss         / sum(loss)`
#'   \item `premium_prop      = premium      / sum(premium)`
#' }
#'
#' Therefore, for a fixed `(cohort, dev)` cell, the proportions
#' sum to 1 across groups. These are useful for examining the composition of
#' each development cell across products or other grouping variables.
#'
#' @param df A data.frame containing experience data with per-period loss and
#'   premium columns.
#' @param group_var Column(s) used for grouping (e.g., product, gender).
#' @param cohort_var Column(s) defining the exposure period
#'   (e.g., underwriting year-month, quarter, half-year, or year such as
#'   `uym`, `uyq`, `uyh`, `uy`).
#' @param dev_var Column(s) defining development periods
#'   (e.g., months since issue such as `elap_m`).
#' @param loss_var Single character; per-period loss column in `df`.
#'   Default `"loss_incr"`.
#' @param premium_var Single character; per-period premium column in `df`.
#'   Default `"premium_incr"`. Premium measure used as denominator for
#'   loss ratio calculations. For long-term health insurance applications,
#'   risk premium is commonly used.
#' @param fill_gaps Logical; if `TRUE`, zero-fill missing
#'   `(group_var, cohort_var, dev_var)` cells so that every cohort
#'   has a consecutive `dev_var` sequence. Default `FALSE`, which
#'   raises an error when gaps are detected. Use
#'   [validate_triangle()] to inspect gaps before deciding.
#'
#' @return A data.frame with class `"Triangle"`, containing the following
#'   derived columns:
#'   \describe{
#'     \item{n_obs}{Number of distinct cohorts observed}
#'     \item{loss, loss_incr}{Cumulative and per-period loss}
#'     \item{premium, premium_incr}{Cumulative and per-period premium}
#'     \item{lr, lr_incr}{Cumulative and per-period loss ratio}
#'     \item{margin, margin_incr}{Cumulative and per-period margin
#'       (`premium - loss`)}
#'     \item{profit, profit_incr}{Profit indicator (factor `"pos"` / `"neg"`)}
#'     \item{loss_prop, loss_incr_prop}{Cumulative and per-period proportions
#'       of loss within each `(cohort, dev)` cell}
#'     \item{premium_prop, premium_incr_prop}{Cumulative and per-period
#'       proportions of premium within each `(cohort, dev)` cell}
#'   }
#'
#' The returned object also has an attribute `"longer"` containing
#' a melted long-format version (`class = "TriangleLonger"`).
#'
#' @examples
#' \dontrun{
#' df <- data.frame(
#'   pd_cd        = rep(c("P001", "P002"), each = 6),
#'   pd_nm        = rep(c("cancer", "health"), each = 6),
#'   uym          = rep(as.Date(c("2023-01-01", "2023-02-01", "2023-03-01")), 4),
#'   elap_m       = rep(1:2, 6),
#'   loss_incr    = runif(12, 80, 120),
#'   premium_incr = runif(12, 90, 110)
#' )
#'
#' res <- build_triangle(
#'   df,
#'   group_var  = pd_cd,
#'   cohort_var = "uym",
#'   dev_var    = "elap_m"
#' )
#'
#' head(res)
#' attr(res, "longer")
#' }
#'
#' @export
build_triangle <- function(df,
                           group_var,
                           cohort_var  = "uym",
                           dev_var     = "elap_m",
                           loss_var    = "loss_incr",
                           premium_var = "premium_incr",
                           fill_gaps   = FALSE) {
  .assert_class(df, "data.frame")

  if (!is.logical(fill_gaps) || length(fill_gaps) != 1L || is.na(fill_gaps))
    stop("`fill_gaps` must be a single non-missing logical value.",
         call. = FALSE)

  dt <- .ensure_dt(df)

  grp_var <- .capture_names(dt, !!rlang::enquo(group_var))
  coh_var <- .capture_names(dt, !!rlang::enquo(cohort_var))
  dev_var <- .capture_names(dt, !!rlang::enquo(dev_var))
  l_var   <- .capture_names(dt, !!rlang::enquo(loss_var))
  p_var   <- .capture_names(dt, !!rlang::enquo(premium_var))

  .assert_length(coh_var)
  .assert_length(dev_var)
  .assert_length(l_var)
  .assert_length(p_var)

  coh_gran <- .get_granularity(coh_var)
  dev_gran <- .get_granularity(dev_var)
  if (!is.na(coh_gran) && !is.na(dev_gran) && coh_gran != dev_gran)
    stop(sprintf(
      "`cohort_var` and `dev_var` must share the same granularity; got `%s` (%s) and `%s` (%s).",
      coh_var, coh_gran, dev_var, dev_gran
    ), call. = FALSE)

  # standardize column names early: user's loss_var / premium_var → standard
  # slot names loss_incr / premium_incr; cohort_var / dev_var → cohort / dev
  data.table::setnames(
    dt,
    c(coh_var, dev_var, l_var, p_var),
    c("cohort", "dev", "loss_incr", "premium_incr")
  )

  grp_coh_var     <- c(grp_var, "cohort")
  grp_dev_var     <- c(grp_var, "dev")
  grp_coh_dev_var <- c(grp_var, "cohort", "dev")
  coh_dev_var     <- c("cohort", "dev")

  incr_vars <- c("loss_incr", "premium_incr")
  cum_vars  <- c("loss", "premium")

  # count observed cohorts per (grp, dev)
  dn <- dt[, .(n_obs = data.table::uniqueN(cohort)),
           by = grp_dev_var]

  # aggregate per-period values per (grp, cohort, dev)
  ds <- dt[, lapply(.SD, sum),
           by = grp_coh_dev_var, .SDcols = incr_vars]

  # validate / fill dev gaps per (grp, cohort). Downstream
  # build_link / fit_* require consecutive (k, k+1) transitions per
  # cohort; non-consecutive dev produces duplicate (grp, ata_from)
  # keys in summary tables and cartesian joins in fit_lr.
  gaps <- .validate_dev_continuity_impl(ds, grp_var, "cohort", "dev")
  if (nrow(gaps)) {
    if (fill_gaps) {
      grid <- ds[, .(dev = seq.int(min(dev, na.rm = TRUE),
                                       max(dev, na.rm = TRUE))),
                 by = grp_coh_var]
      ds <- ds[grid, on = c(grp_coh_var, "dev")]
      data.table::setnafill(ds, type = "const", fill = 0, cols = incr_vars)
      data.table::setorderv(ds, c(grp_coh_var, "dev"))
    } else {
      stop(
        sprintf(
          "Non-consecutive `dev` (source `%s`) detected in %d cohort(s). %s\n%s",
          dev_var,
          nrow(gaps),
          "Call `validate_triangle()` to inspect, or pass `fill_gaps = TRUE` to zero-fill.",
          paste(utils::capture.output(print(head(gaps, 5L))), collapse = "\n")
        ),
        call. = FALSE
      )
    }
  }

  # join n_obs
  n_obs <- i.n_obs <- NULL
  ds[dn, on = grp_dev_var, n_obs := i.n_obs]
  data.table::setcolorder(ds, "n_obs", before = "cohort")

  # cumulative values: cumsum of per-period within each (grp, cohort)
  ds[, (cum_vars) := lapply(.SD, cumsum),
     by = grp_coh_var, .SDcols = incr_vars]

  # margin (cumulative + per-period)
  data.table::set(ds, j = "margin",
                  value = ds[["premium"]] - ds[["loss"]])
  data.table::set(ds, j = "margin_incr",
                  value = ds[["premium_incr"]] - ds[["loss_incr"]])

  # profit indicators (cumulative + per-period)
  data.table::set(
    ds,
    j     = "profit",
    value = factor(
      ifelse(ds[["margin"]] >= 0, "pos", "neg"),
      levels = c("pos", "neg")
    )
  )

  data.table::set(
    ds,
    j     = "profit_incr",
    value = factor(
      ifelse(ds[["margin_incr"]] >= 0, "pos", "neg"),
      levels = c("pos", "neg")
    )
  )

  # loss ratios (cumulative + per-period)
  data.table::set(ds, j = "lr",
                  value = ds[["loss"]] / ds[["premium"]])
  data.table::set(ds, j = "lr_incr",
                  value = ds[["loss_incr"]] / ds[["premium_incr"]])

  # proportions within each (cohort, dev) cell
  ds[, loss_prop         := loss         / sum(loss),         by = coh_dev_var]
  ds[, loss_incr_prop    := loss_incr    / sum(loss_incr),    by = coh_dev_var]
  ds[, premium_prop      := premium      / sum(premium),      by = coh_dev_var]
  ds[, premium_incr_prop := premium_incr / sum(premium_incr), by = coh_dev_var]

  # final column order: cum-first paired
  out_cols <- c(
    grp_var, "n_obs", "cohort", "dev",
    "loss", "loss_incr", "premium", "premium_incr",
    "lr", "lr_incr",
    "margin", "margin_incr", "profit", "profit_incr",
    "loss_prop", "loss_incr_prop", "premium_prop", "premium_incr_prop"
  )
  data.table::setcolorder(ds, intersect(out_cols, names(ds)))

  # long format
  dm <- data.table::melt(
    data         = ds,
    id.vars      = grp_coh_dev_var,
    measure.vars = c("loss", "premium")
  )
  dm <- .prepend_class(dm, "TriangleLonger")

  data.table::setattr(ds, "group_var"   , grp_var)
  data.table::setattr(ds, "cohort_var"  , coh_var)
  data.table::setattr(ds, "cohort_type" , .get_period_type(coh_var))
  data.table::setattr(ds, "dev_var"     , dev_var)
  data.table::setattr(ds, "dev_type"    , .get_period_type(dev_var))
  data.table::setattr(ds, "loss_var"    , l_var)
  data.table::setattr(ds, "premium_var" , p_var)
  data.table::setattr(ds, "longer"      , dm)

  .update_class(ds, "Experience", "Triangle")
}

#' Summarise development statistics (Mean, Median, Weighted)
#'
#' @description
#' S3 method for `summary()` on `Triangle` objects. Computes group-wise summary
#' statistics for cumulative loss ratios (`lr`) and per-period loss ratios
#' (`lr_incr`).
#'
#' The function aggregates data by the grouping variables stored in
#' `attr(x, "group_var")` and the development variable stored in
#' `attr(x, "dev_var")`.
#'
#' The following statistics are computed:
#' - arithmetic mean,
#' - median,
#' - weighted mean (portfolio-level ratio based on sums).
#'
#' @param object An object of class `Triangle`.
#' @param ... Unused; included for S3 compatibility.
#'
#' @details
#' The weighted mean is computed as:
#' \itemize{
#'   \item `lr_wt      = sum(loss)      / sum(premium)`
#'   \item `lr_incr_wt = sum(loss_incr) / sum(premium_incr)`
#' }
#'
#' These correspond to portfolio-level loss ratios based on premium and
#' are typically more stable than simple averages when exposure sizes differ
#' across cohorts.
#'
#' It is assumed that the input `Triangle` object does not contain missing values.
#'
#' @return
#' A `data.table` grouped by `group_var` and `dev_var`, containing:
#' \describe{
#'   \item{n_obs}{Number of observations in the cell}
#'   \item{lr_mean}{Mean of cumulative loss ratios}
#'   \item{lr_median}{Median of cumulative loss ratios}
#'   \item{lr_wt}{Weighted cumulative loss ratio (`sum(loss) / sum(premium)`)}
#'   \item{lr_incr_mean}{Mean of per-period loss ratios}
#'   \item{lr_incr_median}{Median of per-period loss ratios}
#'   \item{lr_incr_wt}{Weighted per-period loss ratio
#'     (`sum(loss_incr) / sum(premium_incr)`)}
#' }
#'
#' The returned object keeps the attributes `group_var` and `dev_var`,
#' and its class is updated to `"TriangleSummary"`.
#'
#' @examples
#' \dontrun{
#' d <- build_triangle(df, group_var = cv_nm)
#' smr <- summary(d)
#' head(smr)
#' attr(smr, "longer")
#' }
#'
#' @method summary Triangle
#' @export
summary.Triangle <- function(object, ...) {
  .assert_class(object, "Triangle")

  dt <- .ensure_dt(object)

  grp_var       <- attr(dt, "group_var")
  dev_var       <- attr(dt, "dev_var")
  dev_type      <- attr(dt, "dev_type")
  grp_dev_var   <- c(grp_var, "dev")

  ds <- dt[, .(
    n_obs          = .N,
    lr_mean        = mean(lr),
    lr_median      = median(lr),
    lr_wt          = sum(loss)      / sum(premium),
    lr_incr_mean   = mean(lr_incr),
    lr_incr_median = median(lr_incr),
    lr_incr_wt     = sum(loss_incr) / sum(premium_incr)
  ), keyby = grp_dev_var]

  dm <- data.table::melt(
    data          = ds,
    id.vars       = grp_dev_var,
    measure.vars  = c(
      "lr_mean"     , "lr_median"     , "lr_wt",
      "lr_incr_mean", "lr_incr_median", "lr_incr_wt"
    ),
    variable.name = "type",
    value.name    = "value"
  )
  dm <- .prepend_class(dm, "TriangleSummaryLonger")

  data.table::setattr(ds, "group_var"   , grp_var)
  data.table::setattr(ds, "dev_var" , dev_var)
  data.table::setattr(ds, "dev_type", dev_type)
  data.table::setattr(ds, "longer"      , dm)

  .update_class(ds, "Triangle", "TriangleSummary")
}

#' @method longer Triangle
#' @export
longer.Triangle <- function(x, ...) {
  .assert_class(x, "Triangle")
  attr(x, "longer")
}

#' @method longer TriangleSummary
#' @export
longer.TriangleSummary <- function(x, ...) {
  .assert_class(x, "TriangleSummary")
  attr(x, "longer")
}


# === Calendar ===============================================================

#' Build a calendar-based development structure from experience data
#'
#' @description
#' Aggregate experience data into a development structure along a single
#' calendar-style period axis, including:
#' - cumulative loss and cumulative premium,
#' - per-period and cumulative proportions,
#' - per-period and cumulative margin,
#' - profit indicators,
#' - per-period loss ratio (`lr_incr = loss_incr / premium_incr`) and
#'   cumulative loss ratio (`lr = loss / premium`).
#'
#' In contrast to [build_triangle()], which builds a development structure using
#' `cohort_var × dev_var`, this function aggregates values over
#' a one-dimensional calendar axis.
#'
#' The cumulative loss ratio is defined as:
#' \deqn{lr = loss / premium}
#'
#' For long-term health insurance applications, risk premium is commonly
#' used as the `premium` measure.
#'
#' Proportion variables are computed within each `calendar_var` cell:
#' \itemize{
#'   \item `loss_incr_prop    = loss_incr    / sum(loss_incr)`
#'   \item `premium_incr_prop = premium_incr / sum(premium_incr)`
#'   \item `loss_prop         = loss         / sum(loss)`
#'   \item `premium_prop      = premium      / sum(premium)`
#' }
#'
#' Therefore, for a fixed `calendar_var` cell, the proportions
#' sum to 1 across groups. These are useful for examining the composition of
#' each calendar period across products or other grouping variables.
#'
#' @param df A data.frame containing experience data with per-period loss
#'   and premium columns.
#' @param group_var Column(s) used for grouping (e.g., product, gender).
#' @param calendar_var A single calendar-like period variable defining
#'   the summary axis. Typical examples include:
#'   \itemize{
#'     \item `cym` (calendar year-month),
#'     \item `cyq` (calendar year-quarter),
#'     \item `cyh` (calendar year-half),
#'     \item `cy`  (calendar year),
#'     \item `uym`, `uyq`, `uyh`, `uy` when a single underwriting-period axis
#'       is to be summarised as a time series rather than as a development
#'       structure.
#'   }
#' @param loss_var Single character; per-period loss column in `df`.
#'   Default `"loss_incr"`.
#' @param premium_var Single character; per-period premium column in `df`.
#'   Default `"premium_incr"`. Premium measure used as denominator for
#'   loss ratio calculations. For long-term health insurance applications,
#'   risk premium is commonly used.
#' @param period_from Optional lower bound for `calendar_var`. Only rows with
#'   `calendar_var >= period_from` are kept.
#' @param period_to Optional upper bound for `calendar_var`. Only rows with
#'   `calendar_var <= period_to` are kept.
#' @param fill_gaps Logical; if `TRUE`, zero-fill missing
#'   `(group_var, calendar_var)` cells so every group has a consecutive
#'   calendar sequence (monthly, quarterly, etc. based on `calendar_var`).
#'   Default `FALSE`, which raises an error when gaps are detected.
#'
#' @return A data.frame with class `"Calendar"`, containing the following
#'   derived columns:
#'   \describe{
#'     \item{dev}{Calendar index within each group, defined as the sequential
#'       order of `calendar_var` after sorting in ascending order. This represents
#'       the progression of calendar periods for each group (e.g., 1 = first
#'       observed period, 2 = second, ...), and can be used to align groups with
#'       different starting periods on a common index scale.}
#'     \item{loss, loss_incr}{Cumulative and per-period loss}
#'     \item{premium, premium_incr}{Cumulative and per-period premium}
#'     \item{lr, lr_incr}{Cumulative and per-period loss ratio}
#'     \item{margin, margin_incr}{Cumulative and per-period margin}
#'     \item{profit, profit_incr}{Profit indicator}
#'     \item{loss_prop, loss_incr_prop, premium_prop, premium_incr_prop}{
#'       Proportions within each `calendar_var` cell}
#'   }
#'
#' The returned object also has an attribute `"longer"` containing
#' a melted long-format version (`class = "CalendarLonger"`).
#'
#' @examples
#' \dontrun{
#' res1 <- build_calendar(
#'   df,
#'   group_var    = pd_cd,
#'   calendar_var = "cym"
#' )
#'
#' res2 <- build_calendar(
#'   df,
#'   group_var    = pd_cd,
#'   calendar_var = "cyq",
#'   period_from  = "2023-01-01"
#' )
#'
#' head(res1)
#' attr(res1, "longer")
#' }
#'
#' @export
build_calendar <- function(df,
                           group_var,
                           calendar_var = "cym",
                           loss_var     = "loss_incr",
                           premium_var  = "premium_incr",
                           period_from  = NULL,
                           period_to    = NULL,
                           fill_gaps    = FALSE) {
  .assert_class(df, "data.frame")

  if (!is.logical(fill_gaps) || length(fill_gaps) != 1L || is.na(fill_gaps))
    stop("`fill_gaps` must be a single non-missing logical value.",
         call. = FALSE)

  dt <- .ensure_dt(df)

  grp_var <- .capture_names(dt, !!rlang::enquo(group_var))
  cal_var <- .capture_names(dt, !!rlang::enquo(calendar_var))
  l_var   <- .capture_names(dt, !!rlang::enquo(loss_var))
  p_var   <- .capture_names(dt, !!rlang::enquo(premium_var))

  .assert_length(cal_var)
  .assert_length(l_var)
  .assert_length(p_var)

  cal_type <- .get_period_type(cal_var)

  if (!is.null(period_from)) {
    period_from <- as.Date(period_from)
    dt <- dt[dt[[cal_var]] >= period_from]
  }

  if (!is.null(period_to)) {
    period_to <- as.Date(period_to)
    dt <- dt[dt[[cal_var]] <= period_to]
  }

  # standardize column names: cal_var → calendar; loss/premium to standard slots
  data.table::setnames(
    dt,
    c(cal_var, l_var, p_var),
    c("calendar", "loss_incr", "premium_incr")
  )

  grp_cal_var <- c(grp_var, "calendar")
  incr_vars   <- c("loss_incr", "premium_incr")
  cum_vars    <- c("loss", "premium")

  # aggregate per-period values
  ds <- dt[, lapply(.SD, sum),
           by = grp_cal_var, .SDcols = incr_vars]

  # validate / fill calendar period consecutiveness per group
  gaps <- .validate_calendar_continuity_impl(ds, grp_var, "calendar")
  if (nrow(gaps)) {
    if (fill_gaps) {
      step <- switch(cal_type,
                     month    = "month",
                     quarter  = "3 months",
                     half     = "6 months",
                     year     = "year")
      if (length(grp_var)) {
        grid <- ds[, .(calendar = seq(min(calendar, na.rm = TRUE),
                                      max(calendar, na.rm = TRUE),
                                      by = step)),
                   by = grp_var]
      } else {
        grid <- data.table::data.table(
          calendar = seq(min(ds$calendar, na.rm = TRUE),
                         max(ds$calendar, na.rm = TRUE),
                         by = step)
        )
      }
      ds <- ds[grid, on = grp_cal_var]
      data.table::setnafill(ds, type = "const", fill = 0, cols = incr_vars)
    } else {
      stop(
        sprintf(
          "Non-consecutive `calendar` (source `%s`) detected in %d group(s). %s\n%s",
          cal_var,
          nrow(gaps),
          "Inspect gaps manually or pass `fill_gaps = TRUE` to zero-fill.",
          paste(utils::capture.output(print(head(gaps, 5L))), collapse = "\n")
        ),
        call. = FALSE
      )
    }
  }

  data.table::setorderv(ds, c(grp_var, "calendar"))

  # sequential dev index per group
  if (length(grp_var)) {
    ds[, dev := seq_len(.N), by = grp_var]
  } else {
    ds[, dev := seq_len(.N)]
  }

  data.table::setcolorder(ds, "dev", after = "calendar")

  # cumulative values
  if (length(grp_var)) {
    ds[, (cum_vars) := lapply(.SD, cumsum),
       by = grp_var, .SDcols = incr_vars]
  } else {
    ds[, (cum_vars) := lapply(.SD, cumsum), .SDcols = incr_vars]
  }

  # margin
  data.table::set(ds, j = "margin",
                  value = ds[["premium"]] - ds[["loss"]])
  data.table::set(ds, j = "margin_incr",
                  value = ds[["premium_incr"]] - ds[["loss_incr"]])

  # profit indicators
  data.table::set(
    ds,
    j     = "profit",
    value = factor(
      ifelse(ds[["margin"]] >= 0, "pos", "neg"),
      levels = c("pos", "neg")
    )
  )

  data.table::set(
    ds,
    j     = "profit_incr",
    value = factor(
      ifelse(ds[["margin_incr"]] >= 0, "pos", "neg"),
      levels = c("pos", "neg")
    )
  )

  # loss ratios
  data.table::set(ds, j = "lr",
                  value = ds[["loss"]] / ds[["premium"]])
  data.table::set(ds, j = "lr_incr",
                  value = ds[["loss_incr"]] / ds[["premium_incr"]])

  # proportions within each calendar cell
  ds[, loss_prop         := loss         / sum(loss),         by = "calendar"]
  ds[, loss_incr_prop    := loss_incr    / sum(loss_incr),    by = "calendar"]
  ds[, premium_prop      := premium      / sum(premium),      by = "calendar"]
  ds[, premium_incr_prop := premium_incr / sum(premium_incr), by = "calendar"]

  # final column order: cum-first paired
  out_cols <- c(
    grp_var, "calendar", "dev",
    "loss", "loss_incr", "premium", "premium_incr",
    "lr", "lr_incr",
    "margin", "margin_incr", "profit", "profit_incr",
    "loss_prop", "loss_incr_prop", "premium_prop", "premium_incr_prop"
  )
  data.table::setcolorder(ds, intersect(out_cols, names(ds)))

  # long format
  dm <- data.table::melt(
    data         = ds,
    id.vars      = c(grp_cal_var, "dev"),
    measure.vars = c("loss", "premium")
  )
  dm <- .prepend_class(dm, "CalendarLonger")

  data.table::setattr(ds, "group_var"    , grp_var)
  data.table::setattr(ds, "calendar_var" , cal_var)
  data.table::setattr(ds, "calendar_type", cal_type)
  data.table::setattr(ds, "loss_var"     , l_var)
  data.table::setattr(ds, "premium_var"  , p_var)
  data.table::setattr(ds, "longer"       , dm)

  .prepend_class(ds, "Calendar")
}

.validate_calendar_continuity_impl <- function(dt, grp_var, cal_var) {
  period_type <- .get_period_type(cal_var)
  step <- switch(period_type,
                 month    = "month",
                 quarter  = "3 months",
                 half     = "6 months",
                 year     = "year",
                 NA_character_)

  if (is.na(step)) {
    z <- data.table::data.table()
    return(.prepend_class(z, "CalendarValidation"))
  }

  .row <- function(p) {
    p <- sort(unique(p[!is.na(p)]))
    if (length(p) == 0L) {
      return(list(n_observed = 0L, n_expected = 0L,
                  missing = list(as.Date(integer(0)))))
    }
    exp_seq <- seq(min(p), max(p), by = step)
    miss    <- setdiff(exp_seq, p)
    list(
      n_observed = length(p),
      n_expected = length(exp_seq),
      missing    = list(as.Date(miss, origin = "1970-01-01"))
    )
  }

  if (length(grp_var)) {
    gaps <- dt[, .row(.SD[[1L]]), by = grp_var, .SDcols = cal_var]
  } else {
    r <- .row(dt[[cal_var]])
    gaps <- data.table::data.table(
      n_observed = r$n_observed,
      n_expected = r$n_expected,
      missing    = r$missing
    )
  }

  gaps <- gaps[n_observed != n_expected]

  data.table::setattr(gaps, "group_var" , grp_var)
  data.table::setattr(gaps, "cohort_var", cal_var)

  .prepend_class(gaps, "CalendarValidation")
}

#' Summarise calendar-development statistics (Mean, Median, Weighted)
#'
#' @description
#' S3 method for `summary()` on `Calendar` objects. Computes
#' calendar-period summary statistics for cumulative loss ratios (`lr`)
#' and per-period loss ratios (`lr_incr`).
#'
#' Where [summary.Triangle()] aggregates by `(group_var, dev)` (cohort
#' × development), this method aggregates by `(group_var, calendar)`
#' (calendar period) so the resulting table is indexed by calendar
#' diagonals rather than development periods.
#'
#' @param object An object of class `Calendar`.
#' @param ... Unused; included for S3 compatibility.
#'
#' @return
#' A `data.table` of class `"CalendarSummary"` with one row per
#' `(group_var, calendar)` combination, containing:
#' \describe{
#'   \item{n_obs}{Number of observations in the cell.}
#'   \item{lr_mean}{Mean of cumulative loss ratios.}
#'   \item{lr_median}{Median of cumulative loss ratios.}
#'   \item{lr_wt}{Weighted cumulative loss ratio
#'     (`sum(loss) / sum(premium)`).}
#'   \item{lr_incr_mean}{Mean of per-period loss ratios.}
#'   \item{lr_incr_median}{Median of per-period loss ratios.}
#'   \item{lr_incr_wt}{Weighted per-period loss ratio
#'     (`sum(loss_incr) / sum(premium_incr)`).}
#' }
#'
#' The returned object preserves the attributes `group_var`,
#' `calendar_var`, and `calendar_type`.
#'
#' @examples
#' \dontrun{
#' cal <- build_calendar(df, group_var = cv_nm)
#' smr  <- summary(cal)
#' head(smr)
#' }
#'
#' @method summary Calendar
#' @export
summary.Calendar <- function(object, ...) {
  .assert_class(object, "Calendar")

  dt <- .ensure_dt(object)

  grp_var       <- attr(dt, "group_var")
  cal_var       <- attr(dt, "calendar_var")
  cal_type      <- attr(dt, "calendar_type")
  grp_cal_var   <- c(grp_var, "calendar")

  ds <- dt[, .(
    n_obs          = .N,
    lr_mean        = mean(lr),
    lr_median      = stats::median(lr),
    lr_wt          = sum(loss)      / sum(premium),
    lr_incr_mean   = mean(lr_incr),
    lr_incr_median = stats::median(lr_incr),
    lr_incr_wt     = sum(loss_incr) / sum(premium_incr)
  ), keyby = grp_cal_var]

  data.table::setattr(ds, "group_var"    , grp_var)
  data.table::setattr(ds, "calendar_var" , cal_var)
  data.table::setattr(ds, "calendar_type", cal_type)

  .update_class(ds, "Calendar", "CalendarSummary")
}


# === Total ==================================================================

#' Build a total development summary from experience data
#'
#' @description
#' Aggregate `loss` and `premium` by group and compute the corresponding total
#' loss ratio over a selected period window.
#'
#' This function is intended for high-level portfolio comparison across
#' groups such as products, coverages, or channels. It summarises:
#' \itemize{
#'   \item the number of observed cohorts (`n_obs`)
#'   \item the first and last observed periods (`sales_start`, `sales_end`)
#'   \item total `loss` and total `premium` (cumulative)
#'   \item total loss ratio (`lr = loss / premium`)
#'   \item each group's share of total loss and total premium
#' }
#'
#' If `period_from` and/or `period_to` are supplied, the input data are first
#' restricted to that period window before aggregation. This is useful when
#' comparing groups on a common period basis.
#'
#' @param df A data.frame containing experience data.
#' @param group_var Grouping variable(s).
#' @param cohort_var A single period variable. This may be an underwriting
#'   period (`uym`, `uyq`, `uyh`, `uy`) or a calendar period
#'   (`cym`, `cyq`, `cyh`, `cy`). Default `"uym"`.
#' @param dev_var A single development variable used to count observed periods.
#'   Default `"elap_m"`.
#' @param loss_var Single character; per-period loss column in `df`.
#'   Default `"loss_incr"`.
#' @param premium_var Single character; per-period premium column in `df`.
#'   Default `"premium_incr"`. Premium measure used as denominator for
#'   loss ratio calculations. For long-term health insurance applications,
#'   risk premium is commonly used.
#' @param period_from Optional lower bound for `cohort_var`. Only rows with
#'   `cohort_var >= period_from` are kept. May be supplied as `Date`,
#'   character, or any value coercible to `Date`. Default `NULL`.
#' @param period_to Optional upper bound for `cohort_var`. Only rows with
#'   `cohort_var <= period_to` are kept. May be supplied as `Date`,
#'   character, or any value coercible to `Date`. Default `NULL`.
#' @param fill_gaps Logical; if `TRUE`, zero-fill missing
#'   `(group_var, cohort_var, dev_var)` cells before aggregation so
#'   that every cohort has a consecutive `dev_var` sequence. Default
#'   `FALSE`. Note that filling inflates `n_obs` (counts filled rows as
#'   observed periods); use [validate_triangle()] to inspect first.
#'
#' @return A data.frame with class `"Total"` containing:
#'   \describe{
#'     \item{n_obs}{Number of observed development periods}
#'     \item{sales_start}{First observed period}
#'     \item{sales_end}{Last observed period}
#'     \item{loss}{Total loss}
#'     \item{premium}{Total premium}
#'     \item{lr}{Total loss ratio (`loss / premium`)}
#'     \item{loss_prop}{Share of total loss}
#'     \item{premium_prop}{Share of total premium}
#'   }
#'
#' @examples
#' \dontrun{
#' build_total(df, cv_nm)
#'
#' build_total(
#'   df,
#'   cv_nm,
#'   period_from = "2023-01-01",
#'   period_to   = "2023-12-01"
#' )
#' }
#'
#' @export
build_total <- function(df,
                        group_var,
                        cohort_var  = "uym",
                        dev_var     = "elap_m",
                        loss_var    = "loss_incr",
                        premium_var = "premium_incr",
                        period_from = NULL,
                        period_to   = NULL,
                        fill_gaps   = FALSE) {
  .assert_class(df, "data.frame")

  if (!is.logical(fill_gaps) || length(fill_gaps) != 1L || is.na(fill_gaps))
    stop("`fill_gaps` must be a single non-missing logical value.",
         call. = FALSE)

  dt <- .ensure_dt(df)

  grp_var <- .capture_names(dt, !!rlang::enquo(group_var))
  coh_var <- .capture_names(dt, !!rlang::enquo(cohort_var))
  dev_var <- .capture_names(dt, !!rlang::enquo(dev_var))
  l_var   <- .capture_names(dt, !!rlang::enquo(loss_var))
  p_var   <- .capture_names(dt, !!rlang::enquo(premium_var))

  if (length(coh_var) != 1L)
    stop("`cohort_var` must resolve to exactly one column.", call. = FALSE)

  if (length(dev_var) != 1L)
    stop("`dev_var` must resolve to exactly one column.", call. = FALSE)

  .assert_length(l_var)
  .assert_length(p_var)

  incr_vars <- c(l_var, p_var)

  # filter by cohort range
  if (!is.null(period_from)) {
    period_from <- as.Date(period_from)
    if (is.na(period_from))
      stop("`period_from` must be coercible to `Date`.", call. = FALSE)
    dt <- dt[dt[[coh_var]] >= period_from]
  }

  if (!is.null(period_to)) {
    period_to <- as.Date(period_to)
    if (is.na(period_to))
      stop("`period_to` must be coercible to `Date`.", call. = FALSE)
    dt <- dt[dt[[coh_var]] <= period_to]
  }

  # validate / fill dev gaps per (grp, cohort)
  gaps <- .validate_dev_continuity_impl(dt, grp_var, coh_var, dev_var)
  if (nrow(gaps)) {
    if (fill_gaps) {
      grp_coh_dev <- c(grp_var, coh_var, dev_var)
      agg <- dt[, lapply(.SD, sum),
                by = grp_coh_dev, .SDcols = incr_vars]
      grid <- agg[, .(.e = seq.int(min(.SD[[1L]], na.rm = TRUE),
                                   max(.SD[[1L]], na.rm = TRUE))),
                  by = c(grp_var, coh_var), .SDcols = dev_var]
      data.table::setnames(grid, ".e", dev_var)
      dt <- agg[grid, on = grp_coh_dev]
      data.table::setnafill(dt, type = "const", fill = 0, cols = incr_vars)
    } else {
      stop(
        sprintf(
          "Non-consecutive `%s` detected in %d cohort(s). %s\n%s",
          dev_var,
          nrow(gaps),
          "Call `validate_triangle()` to inspect, or pass `fill_gaps = TRUE` to zero-fill.",
          paste(utils::capture.output(print(head(gaps, 5L))), collapse = "\n")
        ),
        call. = FALSE
      )
    }
  }

  # aggregate values
  ds <- dt[, .(
    n_obs       = data.table::uniqueN(.SD[[1L]]),
    sales_start = min(.SD[[2L]]),
    sales_end   = max(.SD[[2L]]),
    loss        = sum(.SD[[3L]]),
    premium     = sum(.SD[[4L]])
  ), by = grp_var, .SDcols = c(dev_var, coh_var, l_var, p_var)]

  # compute total loss ratio and shares
  data.table::set(ds, j = "lr"          , value = ds[["loss"]]    / ds[["premium"]])
  data.table::set(ds, j = "loss_prop"   , value = ds[["loss"]]    / sum(ds[["loss"]]))
  data.table::set(ds, j = "premium_prop", value = ds[["premium"]] / sum(ds[["premium"]]))

  data.table::setattr(ds, "group_var"  , grp_var)
  data.table::setattr(ds, "loss_var"   , l_var)
  data.table::setattr(ds, "premium_var", p_var)

  .prepend_class(ds, "Total")
}

#' Summarise a `Total` object
#'
#' @description
#' S3 method for `summary()` on `Total` objects. `Total` already carries
#' one row per group (no time dimension), so this method produces a
#' compact view that orders rows by descending loss ratio and rounds
#' numeric columns for display.
#'
#' @param object An object of class `Total`.
#' @param digits Integer; number of digits passed to [round()] for
#'   numeric columns. Default `4L`. Pass `NULL` to skip rounding.
#' @param ... Unused; included for S3 compatibility.
#'
#' @return A `data.table` of class `"TotalSummary"` with the same rows
#'   as the input `Total` (one per group), ordered by descending `lr`.
#'   Preserves the `group_var` attribute.
#'
#' @examples
#' \dontrun{
#' tot <- build_total(df, group_var = cv_nm)
#' summary(tot)
#' }
#'
#' @method summary Total
#' @export
summary.Total <- function(object, digits = 4L, ...) {
  .assert_class(object, "Total")

  dt <- .ensure_dt(object)

  grp_var <- attr(dt, "group_var")

  if ("lr" %in% names(dt)) {
    data.table::setorderv(dt, "lr", order = -1L)
  }

  if (!is.null(digits)) {
    digits <- suppressWarnings(as.integer(digits[1L]))
    if (length(digits) == 0L || is.na(digits))
      stop("`digits` must be a single integer or `NULL`.", call. = FALSE)

    skip_cols <- c(grp_var, "n_obs", "sales_start", "sales_end")
    num_cols  <- setdiff(names(dt), skip_cols)
    for (nm in num_cols) {
      if (is.numeric(dt[[nm]])) {
        data.table::set(dt, j = nm, value = round(dt[[nm]], digits))
      }
    }
  }

  data.table::setattr(dt, "group_var", grp_var)

  .update_class(dt, "Total", "TotalSummary")
}
