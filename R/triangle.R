# === Triangle validation ====================================================

#' Validate triangle structure before building a development
#'
#' @description
#' Check that each `(groups, cohort)` cohort has a consecutive
#' `dev` sequence within its observed range. Non-consecutive
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
#'     report missing `dev` values within the observed range.
#'   \item \strong{Row-level calendar consistency} — when `calendar`
#'     is supplied (or auto-detected as `"cy_m"` if present), report rows
#'     where `calendar < cohort`. Such rows are logically
#'     impossible (claims cannot precede policy issue) and downstream
#'     they show up as negative `dev_m`, polluting cohort dev sequences.
#' }
#'
#' @param df A data.frame.
#' @param groups Grouping variable(s).
#' @param cohort A single cohort variable (raw column name).
#' @param dev A single development variable (raw column name).
#' @param calendar Optional calendar period variable for row-level
#'   consistency check. When supplied, rows where `calendar <
#'   cohort` are flagged as invalid. Default `NULL` (skip this check).
#'
#' @return A `data.table` of class `"TriangleValidation"` with one row
#'   per cohort containing gaps. Columns:
#'   \describe{
#'     \item{groups, cohort}{Cohort identifier.}
#'     \item{`n_observed`}{Number of distinct observed `dev`
#'       values.}
#'     \item{`n_expected`}{`max(dev) - min(dev) + 1` for that cohort.}
#'     \item{`missing`}{List column of missing `dev` values.}
#'   }
#'   Returns a zero-row data.table when no gaps are found.
#'
#'   Row-level violations (when `calendar` is supplied and the check
#'   finds any) are attached as the `"invalid_rows"` attribute — a
#'   `data.table` with columns `[groups, cohort, calendar,
#'   dev (if present), reason]`. Use `attr(out, "invalid_rows")`
#'   or rely on `print.TriangleValidation` which displays both sections.
#'
#' @seealso [build_triangle()]
#'
#' @export
validate_triangle <- function(df,
                              groups,
                              cohort,
                              dev,
                              calendar = NULL) {
  .assert_class(df, "data.frame")

  dt <- .ensure_dt(df)

  grp <- .capture_names(dt, !!rlang::enquo(groups))
  coh <- .capture_names(dt, !!rlang::enquo(cohort))
  dev <- .capture_names(dt, !!rlang::enquo(dev))

  .assert_length(coh)
  .assert_length(dev)

  # calendar: NULL skips, otherwise auto-skip if column missing
  cal_quo <- rlang::enquo(calendar)
  cal <- if (rlang::quo_is_null(cal_quo)) NULL else .capture_names(dt, !!cal_quo)
  if (!is.null(cal) && (length(cal) != 1L || !(cal %in% names(dt)))) cal <- NULL

  # 1) row-level calendar consistency first — invalid rows pollute the
  #    dev sequence and would surface as spurious negative gaps if we
  #    ran the gap check on the raw data.
  invalid <- NULL
  dt_clean <- dt
  if (!is.null(cal)) {
    invalid <- .validate_calendar_consistency_impl(
      dt, grp = grp, coh = coh,
      dev = dev, cal = cal
    )
    if (nrow(invalid) > 0L) {
      ok <- is.na(dt[[cal]]) | is.na(dt[[coh]]) |
            (dt[[cal]] >= dt[[coh]])
      dt_clean <- dt[ok]
    }
  }

  # 2) dev-sequence gaps on the cleaned data
  out <- .validate_dev_continuity_impl(dt_clean, grp, coh, dev)

  if (!is.null(invalid) && nrow(invalid) > 0L) {
    data.table::setattr(out, "invalid_rows", invalid)
  }

  out
}

.validate_dev_continuity_impl <- function(dt, grp, coh, dev) {
  grp_coh <- c(grp, coh)

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
  }, by = grp_coh, .SDcols = dev]

  gaps <- gaps[n_observed != n_expected]

  data.table::setattr(gaps, "groups" , grp)
  data.table::setattr(gaps, "cohort", coh)
  data.table::setattr(gaps, "dev"   , dev)

  .prepend_class(gaps, "TriangleValidation")
}

#' Internal: row-level cohort vs calendar consistency check
#'
#' Flag rows where `calendar < cohort` — claims/events recorded
#' as occurring before the cohort start, which is logically impossible.
#'
#' @keywords internal
.validate_calendar_consistency_impl <- function(dt, grp, coh, dev, cal) {
  ok <- !is.na(dt[[cal]]) & !is.na(dt[[coh]])
  bad_idx <- ok & (dt[[cal]] < dt[[coh]])
  if (!any(bad_idx)) {
    return(data.table::data.table())
  }

  keep <- c(grp, coh, cal, dev)
  keep <- keep[keep %in% names(dt)]
  z <- dt[bad_idx, .SD, .SDcols = keep]
  z[, reason := sprintf("%s < %s", cal, coh)]
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
#' Aggregate experience data into a development structure by grouping
#' and `(cohort, calendar)` Date columns. Auto-detects input grain
#' (M / Q / S / A) from `cohort` spacing and derives the
#' development-period column internally; the user does not pre-bin
#' data or supply a `dev_*` column.
#'
#' The result contains:
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
#'   \item `loss_incr_share    = loss_incr    / sum(loss_incr)`
#'   \item `premium_incr_share = premium_incr / sum(premium_incr)`
#'   \item `loss_share         = loss         / sum(loss)`
#'   \item `premium_share      = premium      / sum(premium)`
#' }
#'
#' Therefore, for a fixed `(cohort, dev)` cell, the proportions
#' sum to 1 across groups. These are useful for examining the composition of
#' each development cell across products or other grouping variables.
#'
#' @param df A data.frame containing experience data with per-period loss and
#'   premium columns plus `cohort` and `calendar` Date columns
#'   (or any input that the internal Date coercion accepts: Date, POSIXt,
#'   integer `yyyy` / `yyyymm` / `yyyymmdd`, ISO string).
#' @param groups Column(s) used for grouping (e.g., product, gender).
#' @param cohort Single column (raw name) defining the underwriting /
#'   exposure period start (e.g., `"uy_m"`).
#' @param calendar Single column (raw name) defining the calendar period of
#'   the observation (e.g., `"cy_m"`). Optional — supply either `calendar`
#'   or `dev` (or both). When `calendar` is given, `dev` is derived
#'   internally via `count_periods(cohort, calendar, grain)`.
#' @param dev Single column (raw name) holding pre-computed development
#'   periods (e.g., `"dev_m"`). Optional — supply either `calendar`
#'   or `dev` (or both). When only `dev` is given, the calendar
#'   axis is omitted from the attribute (downstream calendar-diagonal
#'   logic uses cohort + dev). When both are given, `dev` is
#'   cross-checked against `count_periods(cohort, calendar, grain)`.
#' @param loss Single character; per-period loss column in `df`
#'   (raw name, e.g., `"loss_incr"`).
#' @param premium Single character; per-period premium column in `df`
#'   (raw name, e.g., `"premium_incr"`). Premium measure used as
#'   denominator for loss ratio calculations. For long-term health
#'   insurance applications, risk premium is commonly used.
#' @param grain One of `"auto"` (default), `"M"`, `"Q"`, `"S"`, `"A"`.
#'   `"auto"` infers the grain from the `cohort` value spacing.
#'   Explicit values must be at least as coarse as the input grain;
#'   the input is binned (floored) to that grain before aggregation.
#' @param cell_type One of `"incremental"` (default) or `"cumulative"`.
#'   Whether `loss` and `premium` in `df` already hold per-period
#'   (incremental) values or cumulative-within-cohort values. The
#'   internal triangle is always built on the incremental representation;
#'   `"cumulative"` inputs are differenced first.
#' @param fill_gaps Logical; if `TRUE`, zero-fill missing
#'   `(groups, cohort, dev)` cells so that every cohort
#'   has a consecutive `dev` sequence. Default `FALSE`, which
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
#'     \item{loss_share, loss_incr_share}{Cumulative and per-period proportions
#'       of loss within each `(cohort, dev)` cell}
#'     \item{premium_share, premium_incr_share}{Cumulative and per-period
#'       proportions of premium within each `(cohort, dev)` cell}
#'   }
#'
#' Attributes set on the returned object: `groups`, `cohort`,
#' `calendar`, `grain`, `dev` (= `"dev_<lower(grain)>"`, e.g.
#' `"dev_m"`), `loss`, `premium`, `longer`.
#'
#' @examples
#' \dontrun{
#' df <- data.frame(
#'   pd_cd        = rep(c("P001", "P002"), each = 6),
#'   pd_nm        = rep(c("cancer", "health"), each = 6),
#'   uy_m         = rep(as.Date(c("2023-01-01", "2023-02-01", "2023-03-01")), 4),
#'   cy_m         = rep(as.Date(c("2023-01-01", "2023-02-01")), 6),
#'   loss_incr    = runif(12, 80, 120),
#'   premium_incr = runif(12, 90, 110)
#' )
#'
#' # auto-detected monthly grain
#' res_m <- build_triangle(
#'   df,
#'   groups   = pd_cd,
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "loss_incr",
#'   premium  = "premium_incr"
#' )
#'
#' # explicit quarterly view (re-bins monthly input to quarterly)
#' res_q <- build_triangle(df, groups = pd_cd, grain = "Q")
#'
#' head(res_m)
#' attr(res_m, "longer")
#' }
#'
#' @export
build_triangle <- function(df,
                           groups,
                           cohort,
                           calendar  = NULL,
                           dev       = NULL,
                           loss,
                           premium,
                           grain     = "auto",
                           cell_type = c("incremental", "cumulative"),
                           fill_gaps = FALSE) {
  .assert_class(df, "data.frame")
  cell_type <- match.arg(cell_type)

  if (!is.logical(fill_gaps) || length(fill_gaps) != 1L || is.na(fill_gaps))
    stop("`fill_gaps` must be a single non-missing logical value.",
         call. = FALSE)

  dt <- .ensure_dt(df)

  grp  <- .capture_names(dt, !!rlang::enquo(groups))
  coh  <- .capture_names(dt, !!rlang::enquo(cohort))
  loss <- .capture_names(dt, !!rlang::enquo(loss))
  prem <- .capture_names(dt, !!rlang::enquo(premium))

  # axis columns: at least one of `calendar` or `dev` must be supplied.
  # Use enquo to distinguish `NULL` (explicit absence) from a captured value.
  cal_quo <- rlang::enquo(calendar)
  dev_quo <- rlang::enquo(dev)
  cal <- if (rlang::quo_is_null(cal_quo)) NULL else .capture_names(dt, !!cal_quo)
  dev_col <- if (rlang::quo_is_null(dev_quo)) NULL else .capture_names(dt, !!dev_quo)

  if (is.null(cal) && is.null(dev_col))
    stop("Must supply at least one of `calendar` or `dev`.", call. = FALSE)

  .assert_length(coh)
  .assert_length(loss)
  .assert_length(prem)
  if (!is.null(cal))     .assert_length(cal)
  if (!is.null(dev_col)) .assert_length(dev_col)

  if (length(coh) != 1L)
    stop("`cohort` must resolve to exactly one column.", call. = FALSE)
  if (!is.null(cal) && length(cal) != 1L)
    stop("`calendar` must resolve to exactly one column.", call. = FALSE)
  if (!is.null(dev_col) && length(dev_col) != 1L)
    stop("`dev` must resolve to exactly one column.", call. = FALSE)

  # required columns presence check
  required <- c(grp, coh, loss, prem,
                if (!is.null(cal)) cal,
                if (!is.null(dev_col)) dev_col)
  missing_cols <- setdiff(required, names(dt))
  if (length(missing_cols))
    stop(sprintf("Missing required columns: %s.",
                 paste(sprintf("'%s'", missing_cols), collapse = ", ")),
         call. = FALSE)

  # coerce cohort (and calendar if present) to Date
  .coerce_cols_to_date(dt, coh)
  if (!is.null(cal)) .coerce_cols_to_date(dt, cal)
  data.table::set(dt, j = loss, value = as.numeric(dt[[loss]]))
  data.table::set(dt, j = prem, value = as.numeric(dt[[prem]]))

  # If input cells are cumulative, derive incremental via per-cohort diff
  # at INPUT grain (before binning). Sort key prefers calendar when present
  # else falls back to dev (both monotone within cohort).
  if (cell_type == "cumulative") {
    sort_axis <- if (!is.null(cal)) cal else dev_col
    data.table::setorderv(dt, c(grp, coh, sort_axis))
    dt[, (loss) := .SD[[1L]] - data.table::shift(.SD[[1L]], fill = 0),
       by = c(grp, coh), .SDcols = loss]
    dt[, (prem) := .SD[[1L]] - data.table::shift(.SD[[1L]], fill = 0),
       by = c(grp, coh), .SDcols = prem]
  }

  # auto-detect input grain from cohort; resolve user-supplied grain.
  input_grain <- .infer_grain(dt[[coh]])
  grain       <- .resolve_grain(input_grain, grain)

  # bin cohort (and calendar if present) to grain.
  .floor_cols_to_period(dt, coh, grain)
  if (!is.null(cal)) .floor_cols_to_period(dt, cal, grain)

  # derive / validate dev under three modes:
  #   mode 1 (calendar only): dev = count_periods(cohort, calendar, grain)
  #   mode 2 (dev only):      use given dev as-is (calendar attribute = NA)
  #   mode 3 (both):          cross-check given dev vs derived
  if (!is.null(cal) && !is.null(dev_col)) {
    computed_dev <- .count_periods(dt[[coh]], dt[[cal]], grain)
    given_dev    <- as.integer(dt[[dev_col]])
    mismatch <- !is.na(computed_dev) & !is.na(given_dev) &
                computed_dev != given_dev
    if (any(mismatch))
      stop(sprintf(
        "`dev` is inconsistent with `cohort` + `calendar` (grain `%s`) in %d row(s).",
        grain, sum(mismatch)), call. = FALSE)
    dt[, dev := given_dev]
    if (dev_col != "dev") dt[, (dev_col) := NULL]
  } else if (!is.null(cal)) {
    dt[, dev := .count_periods(.SD[[1L]], .SD[[2L]], grain),
       .SDcols = c(coh, cal)]
  } else {
    dt[, dev := as.integer(dt[[dev_col]])]
    if (dev_col != "dev") dt[, (dev_col) := NULL]
  }

  # standardize column names: user's loss / premium → standard
  # slot names loss_incr / premium_incr; cohort → cohort.
  data.table::setnames(
    dt,
    c(coh, loss, prem),
    c("cohort", "loss_incr", "premium_incr")
  )

  grp_coh     <- c(grp, "cohort")
  grp_dev     <- c(grp, "dev")
  grp_coh_dev <- c(grp, "cohort", "dev")
  coh_dev     <- c("cohort", "dev")

  incr_vars <- c("loss_incr", "premium_incr")
  cum_vars  <- c("loss", "premium")

  # count observed cohorts per (grp, dev)
  dn <- dt[, .(n_obs = data.table::uniqueN(cohort)),
           by = grp_dev]

  # aggregate per-period values per (grp, cohort, dev)
  ds <- dt[, lapply(.SD, sum),
           by = grp_coh_dev, .SDcols = incr_vars]

  # validate / fill dev gaps per (grp, cohort). Downstream
  # build_link / fit_* require consecutive (k, k+1) transitions per
  # cohort; non-consecutive dev produces duplicate (grp, ata_from)
  # keys in summary tables and cartesian joins in fit_lr.
  gaps <- .validate_dev_continuity_impl(ds, grp, "cohort", "dev")
  if (nrow(gaps)) {
    if (fill_gaps) {
      grid <- ds[, .(dev = seq.int(min(dev, na.rm = TRUE),
                                       max(dev, na.rm = TRUE))),
                 by = grp_coh]
      ds <- ds[grid, on = c(grp_coh, "dev")]
      data.table::setnafill(ds, type = "const", fill = 0, cols = incr_vars)
      data.table::setorderv(ds, c(grp_coh, "dev"))
    } else {
      stop(
        sprintf(
          "Non-consecutive `dev` (grain `%s`) detected in %d cohort(s). %s\n%s",
          grain,
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
  ds[dn, on = grp_dev, n_obs := i.n_obs]
  data.table::setcolorder(ds, "n_obs", before = "cohort")

  # cumulative values: cumsum of per-period within each (grp, cohort)
  ds[, (cum_vars) := lapply(.SD, cumsum),
     by = grp_coh, .SDcols = incr_vars]

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
  ds[, loss_share         := loss         / sum(loss),         by = coh_dev]
  ds[, loss_incr_share    := loss_incr    / sum(loss_incr),    by = coh_dev]
  ds[, premium_share      := premium      / sum(premium),      by = coh_dev]
  ds[, premium_incr_share := premium_incr / sum(premium_incr), by = coh_dev]

  # final column order: cum-first paired
  out_cols <- c(
    grp, "n_obs", "cohort", "dev",
    "loss", "loss_incr", "premium", "premium_incr",
    "lr", "lr_incr",
    "margin", "margin_incr", "profit", "profit_incr",
    "loss_share", "loss_incr_share", "premium_share", "premium_incr_share"
  )
  data.table::setcolorder(ds, intersect(out_cols, names(ds)))

  # long format
  dm <- data.table::melt(
    data         = ds,
    id.vars      = grp_coh_dev,
    measure.vars = c("loss", "premium")
  )
  dm <- .prepend_class(dm, "TriangleLonger")

  data.table::setattr(ds, "groups"  , grp)
  data.table::setattr(ds, "cohort"  , coh)
  data.table::setattr(ds, "calendar", cal)
  data.table::setattr(ds, "grain"   , grain)
  data.table::setattr(ds, "dev"     , paste0("dev_", tolower(grain)))
  data.table::setattr(ds, "loss"    , loss)
  data.table::setattr(ds, "premium" , prem)
  data.table::setattr(ds, "longer"  , dm)

  .update_class(ds, prepend = "Triangle")
}

#' Summarise development statistics (Mean, Median, Weighted)
#'
#' @description
#' S3 method for `summary()` on `Triangle` objects. Computes group-wise summary
#' statistics for cumulative loss ratios (`lr`) and per-period loss ratios
#' (`lr_incr`).
#'
#' The function aggregates data by the grouping variables stored in
#' `attr(x, "groups")` and the development variable stored in
#' `attr(x, "dev")`.
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
#' A `data.table` grouped by `groups` and `dev`, containing:
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
#' The returned object keeps the attributes `groups` and `dev`,
#' and its class is updated to `"TriangleSummary"`.
#'
#' @examples
#' \dontrun{
#' d <- build_triangle(
#'   df,
#'   groups   = "coverage",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "loss_incr",
#'   premium  = "premium_incr"
#' )
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

  grp     <- attr(dt, "groups")
  dev     <- attr(dt, "dev")
  grp_dev <- c(grp, "dev")

  ds <- dt[, .(
    n_obs          = .N,
    lr_mean        = mean(lr),
    lr_median      = median(lr),
    lr_wt          = sum(loss)      / sum(premium),
    lr_incr_mean   = mean(lr_incr),
    lr_incr_median = median(lr_incr),
    lr_incr_wt     = sum(loss_incr) / sum(premium_incr)
  ), keyby = grp_dev]

  dm <- data.table::melt(
    data         = ds,
    id.vars      = grp_dev,
    measure.vars = c(
      "lr_mean"     , "lr_median"     , "lr_wt",
      "lr_incr_mean", "lr_incr_median", "lr_incr_wt"
    ),
    variable.name = "type",
    value.name    = "value"
  )
  dm <- .prepend_class(dm, "TriangleSummaryLonger")

  data.table::setattr(ds, "groups", grp)
  data.table::setattr(ds, "dev"  , dev)
  data.table::setattr(ds, "longer"   , dm)

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
#' `cohort × dev`, this function aggregates values over
#' a one-dimensional calendar axis.
#'
#' The cumulative loss ratio is defined as:
#' \deqn{lr = loss / premium}
#'
#' For long-term health insurance applications, risk premium is commonly
#' used as the `premium` measure.
#'
#' Proportion variables are computed within each `calendar` cell:
#' \itemize{
#'   \item `loss_incr_share    = loss_incr    / sum(loss_incr)`
#'   \item `premium_incr_share = premium_incr / sum(premium_incr)`
#'   \item `loss_share         = loss         / sum(loss)`
#'   \item `premium_share      = premium      / sum(premium)`
#' }
#'
#' Therefore, for a fixed `calendar` cell, the proportions
#' sum to 1 across groups. These are useful for examining the composition of
#' each calendar period across products or other grouping variables.
#'
#' @param df A data.frame containing experience data with per-period loss
#'   and premium columns plus a `calendar` Date column (or any input
#'   that the internal Date coercion accepts: Date, POSIXt, integer
#'   `yyyy` / `yyyymm` / `yyyymmdd`, ISO string).
#' @param groups Column(s) used for grouping (e.g., product, gender).
#' @param calendar A single column defining the calendar-like period
#'   axis (raw name, e.g., `"cy_m"`). May also be an underwriting axis
#'   (`"uy_m"` etc.) when a single underwriting-period axis is to be
#'   summarised as a time series rather than as a development structure.
#' @param loss Single character; per-period loss column in `df`
#'   (raw name, e.g., `"loss_incr"`).
#' @param premium Single character; per-period premium column in `df`
#'   (raw name, e.g., `"premium_incr"`). Premium measure used as
#'   denominator for loss ratio calculations. For long-term health
#'   insurance applications, risk premium is commonly used.
#' @param grain One of `"auto"` (default), `"M"`, `"Q"`, `"S"`, `"A"`.
#'   `"auto"` infers the grain from the `calendar` value spacing.
#'   Explicit values must be at least as coarse as the input grain;
#'   the input is binned (floored) to that grain before aggregation.
#' @param period_from Optional lower bound for `calendar`. Only rows with
#'   `calendar >= period_from` are kept.
#' @param period_to Optional upper bound for `calendar`. Only rows with
#'   `calendar <= period_to` are kept.
#' @param fill_gaps Logical; if `TRUE`, zero-fill missing
#'   `(groups, calendar)` cells so every group has a consecutive
#'   calendar sequence at the resolved grain.
#'   Default `FALSE`, which raises an error when gaps are detected.
#'
#' @return A data.frame with class `"Calendar"`, containing the following
#'   derived columns:
#'   \describe{
#'     \item{dev}{Calendar index within each group, defined as the sequential
#'       order of `calendar` after sorting in ascending order. This represents
#'       the progression of calendar periods for each group (e.g., 1 = first
#'       observed period, 2 = second, ...), and can be used to align groups with
#'       different starting periods on a common index scale.}
#'     \item{loss, loss_incr}{Cumulative and per-period loss}
#'     \item{premium, premium_incr}{Cumulative and per-period premium}
#'     \item{lr, lr_incr}{Cumulative and per-period loss ratio}
#'     \item{margin, margin_incr}{Cumulative and per-period margin}
#'     \item{profit, profit_incr}{Profit indicator}
#'     \item{loss_share, loss_incr_share, premium_share, premium_incr_share}{
#'       Proportions within each `calendar` cell}
#'   }
#'
#' The returned object also has an attribute `"longer"` containing
#' a melted long-format version (`class = "CalendarLonger"`).
#'
#' @examples
#' \dontrun{
#' res1 <- build_calendar(
#'   df,
#'   groups   = pd_cd,
#'   calendar = "cy_m"
#' )
#'
#' res2 <- build_calendar(
#'   df,
#'   groups      = pd_cd,
#'   calendar    = "cy_q",
#'   period_from = "2023-01-01"
#' )
#'
#' head(res1)
#' attr(res1, "longer")
#' }
#'
#' @export
build_calendar <- function(df,
                           groups,
                           calendar,
                           loss,
                           premium,
                           grain       = "auto",
                           period_from = NULL,
                           period_to   = NULL,
                           fill_gaps   = FALSE) {
  .assert_class(df, "data.frame")

  if (!is.logical(fill_gaps) || length(fill_gaps) != 1L || is.na(fill_gaps))
    stop("`fill_gaps` must be a single non-missing logical value.",
         call. = FALSE)

  dt <- .ensure_dt(df)

  grp   <- .capture_names(dt, !!rlang::enquo(groups))
  cal   <- .capture_names(dt, !!rlang::enquo(calendar))
  loss  <- .capture_names(dt, !!rlang::enquo(loss))
  prem  <- .capture_names(dt, !!rlang::enquo(premium))

  .assert_length(cal)
  .assert_length(loss)
  .assert_length(prem)

  if (length(cal) != 1L)
    stop("`calendar` must resolve to exactly one column.", call. = FALSE)

  required <- c(grp, cal, loss, prem)
  missing_cols <- setdiff(required, names(dt))
  if (length(missing_cols))
    stop(sprintf("Missing required columns: %s.",
                 paste(sprintf("'%s'", missing_cols), collapse = ", ")),
         call. = FALSE)

  # coerce calendar column to Date and numeric loss/premium
  .coerce_cols_to_date(dt, cal)
  data.table::set(dt, j = loss, value = as.numeric(dt[[loss]]))
  data.table::set(dt, j = prem, value = as.numeric(dt[[prem]]))

  # period filtering happens before grain binning so user's bounds are
  # interpreted at the input scale.
  if (!is.null(period_from)) {
    period_from <- as.Date(period_from)
    dt <- dt[dt[[cal]] >= period_from]
  }

  if (!is.null(period_to)) {
    period_to <- as.Date(period_to)
    dt <- dt[dt[[cal]] <= period_to]
  }

  # auto-detect grain from calendar column; resolve user-supplied grain.
  input_grain <- .infer_grain(dt[[cal]])
  grain       <- .resolve_grain(input_grain, grain)

  # bin to requested grain (idempotent floor when input already at grain).
  .floor_cols_to_period(dt, cal, grain)

  # standardize column names: cal → calendar; loss/premium to standard slots
  data.table::setnames(
    dt,
    c(cal, loss, prem),
    c("calendar", "loss_incr", "premium_incr")
  )

  grp_cal   <- c(grp, "calendar")
  incr_vars <- c("loss_incr", "premium_incr")
  cum_vars  <- c("loss", "premium")

  # aggregate per-period values
  ds <- dt[, lapply(.SD, sum),
           by = grp_cal, .SDcols = incr_vars]

  # validate / fill calendar period consecutiveness per group
  gaps <- .validate_calendar_continuity_impl_grain(ds, grp, "calendar", grain)
  if (nrow(gaps)) {
    if (fill_gaps) {
      step <- switch(grain,
                     M = "month",
                     Q = "3 months",
                     S = "6 months",
                     A = "year")
      if (length(grp)) {
        grid <- ds[, .(calendar = seq(min(calendar, na.rm = TRUE),
                                      max(calendar, na.rm = TRUE),
                                      by = step)),
                   by = grp]
      } else {
        grid <- data.table::data.table(
          calendar = seq(min(ds$calendar, na.rm = TRUE),
                         max(ds$calendar, na.rm = TRUE),
                         by = step)
        )
      }
      ds <- ds[grid, on = grp_cal]
      data.table::setnafill(ds, type = "const", fill = 0, cols = incr_vars)
    } else {
      stop(
        sprintf(
          "Non-consecutive `calendar` (grain `%s`) detected in %d group(s). %s\n%s",
          grain,
          nrow(gaps),
          "Inspect gaps manually or pass `fill_gaps = TRUE` to zero-fill.",
          paste(utils::capture.output(print(head(gaps, 5L))), collapse = "\n")
        ),
        call. = FALSE
      )
    }
  }

  data.table::setorderv(ds, c(grp, "calendar"))

  # sequential dev index per group
  if (length(grp)) {
    ds[, dev := seq_len(.N), by = grp]
  } else {
    ds[, dev := seq_len(.N)]
  }

  data.table::setcolorder(ds, "dev", after = "calendar")

  # cumulative values
  if (length(grp)) {
    ds[, (cum_vars) := lapply(.SD, cumsum),
       by = grp, .SDcols = incr_vars]
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
  ds[, loss_share         := loss         / sum(loss),         by = "calendar"]
  ds[, loss_incr_share    := loss_incr    / sum(loss_incr),    by = "calendar"]
  ds[, premium_share      := premium      / sum(premium),      by = "calendar"]
  ds[, premium_incr_share := premium_incr / sum(premium_incr), by = "calendar"]

  # final column order: cum-first paired
  out_cols <- c(
    grp, "calendar", "dev",
    "loss", "loss_incr", "premium", "premium_incr",
    "lr", "lr_incr",
    "margin", "margin_incr", "profit", "profit_incr",
    "loss_share", "loss_incr_share", "premium_share", "premium_incr_share"
  )
  data.table::setcolorder(ds, intersect(out_cols, names(ds)))

  # long format
  dm <- data.table::melt(
    data         = ds,
    id.vars      = c(grp_cal, "dev"),
    measure.vars = c("loss", "premium")
  )
  dm <- .prepend_class(dm, "CalendarLonger")

  data.table::setattr(ds, "groups"   , grp)
  data.table::setattr(ds, "calendar", cal)
  data.table::setattr(ds, "grain"       , grain)
  data.table::setattr(ds, "loss"    , loss)
  data.table::setattr(ds, "premium" , prem)
  data.table::setattr(ds, "longer"      , dm)

  .prepend_class(ds, "Calendar")
}

.validate_calendar_continuity_impl_grain <- function(dt, grp, cal, grain) {
  step <- switch(grain,
                 M = "month",
                 Q = "3 months",
                 S = "6 months",
                 A = "year",
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

  if (length(grp)) {
    gaps <- dt[, .row(.SD[[1L]]), by = grp, .SDcols = cal]
  } else {
    r <- .row(dt[[cal]])
    gaps <- data.table::data.table(
      n_observed = r$n_observed,
      n_expected = r$n_expected,
      missing    = r$missing
    )
  }

  gaps <- gaps[n_observed != n_expected]

  data.table::setattr(gaps, "groups" , grp)
  data.table::setattr(gaps, "cohort", cal)

  .prepend_class(gaps, "CalendarValidation")
}

#' Summarise calendar-development statistics (Mean, Median, Weighted)
#'
#' @description
#' S3 method for `summary()` on `Calendar` objects. Computes
#' calendar-period summary statistics for cumulative loss ratios (`lr`)
#' and per-period loss ratios (`lr_incr`).
#'
#' Where [summary.Triangle()] aggregates by `(groups, dev)` (cohort
#' × development), this method aggregates by `(groups, calendar)`
#' (calendar period) so the resulting table is indexed by calendar
#' diagonals rather than development periods.
#'
#' @param object An object of class `Calendar`.
#' @param ... Unused; included for S3 compatibility.
#'
#' @return
#' A `data.table` of class `"CalendarSummary"` with one row per
#' `(groups, calendar)` combination, containing:
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
#' The returned object preserves the attributes `groups`,
#' `calendar`, and `calendar_type`.
#'
#' @examples
#' \dontrun{
#' cal <- build_calendar(
#'   df,
#'   groups   = "coverage",
#'   calendar = "cy_m",
#'   loss     = "loss_incr",
#'   premium  = "premium_incr"
#' )
#' smr  <- summary(cal)
#' head(smr)
#' }
#'
#' @method summary Calendar
#' @export
summary.Calendar <- function(object, ...) {
  .assert_class(object, "Calendar")

  dt <- .ensure_dt(object)

  grp     <- attr(dt, "groups")
  cal     <- attr(dt, "calendar")
  grp_cal <- c(grp, "calendar")

  ds <- dt[, .(
    n_obs          = .N,
    lr_mean        = mean(lr),
    lr_median      = stats::median(lr),
    lr_wt          = sum(loss)      / sum(premium),
    lr_incr_mean   = mean(lr_incr),
    lr_incr_median = stats::median(lr_incr),
    lr_incr_wt     = sum(loss_incr) / sum(premium_incr)
  ), keyby = grp_cal]

  data.table::setattr(ds, "groups"   , grp)
  data.table::setattr(ds, "calendar", cal)

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
#' @param groups Grouping variable(s).
#' @param cohort A single period variable (raw name). This may be an
#'   underwriting period (`"uy_m"`, `"uy_q"`, `"uy_s"`, `"uy_a"`) or a
#'   calendar period (`"cy_m"`, `"cy_q"`, `"cy_s"`, `"cy_a"`).
#' @param dev A single development variable (raw name) used to count
#'   observed periods.
#' @param loss Single character; per-period loss column in `df`
#'   (raw name, e.g., `"loss_incr"`).
#' @param premium Single character; per-period premium column in `df`
#'   (raw name, e.g., `"premium_incr"`). Premium measure used as
#'   denominator for loss ratio calculations. For long-term health
#'   insurance applications, risk premium is commonly used.
#' @param period_from Optional lower bound for `cohort`. Only rows with
#'   `cohort >= period_from` are kept. May be supplied as `Date`,
#'   character, or any value coercible to `Date`. Default `NULL`.
#' @param period_to Optional upper bound for `cohort`. Only rows with
#'   `cohort <= period_to` are kept. May be supplied as `Date`,
#'   character, or any value coercible to `Date`. Default `NULL`.
#' @param fill_gaps Logical; if `TRUE`, zero-fill missing
#'   `(groups, cohort, dev)` cells before aggregation so
#'   that every cohort has a consecutive `dev` sequence. Default
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
#'     \item{loss_share}{Share of total loss}
#'     \item{premium_share}{Share of total premium}
#'   }
#'
#' @examples
#' \dontrun{
#' build_total(df, coverage)
#'
#' build_total(
#'   df,
#'   coverage,
#'   period_from = "2023-01-01",
#'   period_to   = "2023-12-01"
#' )
#' }
#'
#' @export
build_total <- function(df,
                        groups,
                        cohort,
                        dev,
                        loss,
                        premium,
                        period_from = NULL,
                        period_to   = NULL,
                        fill_gaps   = FALSE) {
  .assert_class(df, "data.frame")

  if (!is.logical(fill_gaps) || length(fill_gaps) != 1L || is.na(fill_gaps))
    stop("`fill_gaps` must be a single non-missing logical value.",
         call. = FALSE)

  dt <- .ensure_dt(df)

  grp   <- .capture_names(dt, !!rlang::enquo(groups))
  coh   <- .capture_names(dt, !!rlang::enquo(cohort))
  dev   <- .capture_names(dt, !!rlang::enquo(dev))
  loss  <- .capture_names(dt, !!rlang::enquo(loss))
  prem  <- .capture_names(dt, !!rlang::enquo(premium))

  if (length(coh) != 1L)
    stop("`cohort` must resolve to exactly one column.", call. = FALSE)

  if (length(dev) != 1L)
    stop("`dev` must resolve to exactly one column.", call. = FALSE)

  .assert_length(loss)
  .assert_length(prem)

  incr_vars <- c(loss, prem)

  # filter by cohort range
  if (!is.null(period_from)) {
    period_from <- as.Date(period_from)
    if (is.na(period_from))
      stop("`period_from` must be coercible to `Date`.", call. = FALSE)
    dt <- dt[dt[[coh]] >= period_from]
  }

  if (!is.null(period_to)) {
    period_to <- as.Date(period_to)
    if (is.na(period_to))
      stop("`period_to` must be coercible to `Date`.", call. = FALSE)
    dt <- dt[dt[[coh]] <= period_to]
  }

  # validate / fill dev gaps per (grp, cohort)
  gaps <- .validate_dev_continuity_impl(dt, grp, coh, dev)
  if (nrow(gaps)) {
    if (fill_gaps) {
      grp_coh_dev <- c(grp, coh, dev)
      agg <- dt[, lapply(.SD, sum),
                by = grp_coh_dev, .SDcols = incr_vars]
      grid <- agg[, .(.e = seq.int(min(.SD[[1L]], na.rm = TRUE),
                                   max(.SD[[1L]], na.rm = TRUE))),
                  by = c(grp, coh), .SDcols = dev]
      data.table::setnames(grid, ".e", dev)
      dt <- agg[grid, on = grp_coh_dev]
      data.table::setnafill(dt, type = "const", fill = 0, cols = incr_vars)
    } else {
      stop(
        sprintf(
          "Non-consecutive `%s` detected in %d cohort(s). %s\n%s",
          dev,
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
  ), by = grp, .SDcols = c(dev, coh, loss, prem)]

  # compute total loss ratio and shares
  data.table::set(ds, j = "lr"           , value = ds[["loss"]]    / ds[["premium"]])
  data.table::set(ds, j = "loss_share"   , value = ds[["loss"]]    / sum(ds[["loss"]]))
  data.table::set(ds, j = "premium_share", value = ds[["premium"]] / sum(ds[["premium"]]))

  data.table::setattr(ds, "groups"  , grp)
  data.table::setattr(ds, "loss"   , loss)
  data.table::setattr(ds, "premium", prem)

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
#'   Preserves the `groups` attribute.
#'
#' @examples
#' \dontrun{
#' tot <- build_total(
#'   df,
#'   groups  = "coverage",
#'   cohort  = "uy_m",
#'   dev     = "dev_m",
#'   loss    = "loss_incr",
#'   premium = "premium_incr"
#' )
#' summary(tot)
#' }
#'
#' @method summary Total
#' @export
summary.Total <- function(object, digits = 4L, ...) {
  .assert_class(object, "Total")

  dt <- .ensure_dt(object)

  grp <- attr(dt, "groups")

  if ("lr" %in% names(dt)) {
    data.table::setorderv(dt, "lr", order = -1L)
  }

  if (!is.null(digits)) {
    digits <- suppressWarnings(as.integer(digits[1L]))
    if (length(digits) == 0L || is.na(digits))
      stop("`digits` must be a single integer or `NULL`.", call. = FALSE)

    skip_cols <- c(grp, "n_obs", "sales_start", "sales_end")
    num_cols  <- setdiff(names(dt), skip_cols)
    for (nm in num_cols) {
      if (is.numeric(dt[[nm]])) {
        data.table::set(dt, j = nm, value = round(dt[[nm]], digits))
      }
    }
  }

  data.table::setattr(dt, "groups", grp)

  .update_class(dt, "Total", "TotalSummary")
}
