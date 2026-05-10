#' Period utilities (internal)
#'
#' Reusable helpers for date / grain / period operations. Domain-neutral
#' (no `cohort` / `dev` / `loss` baked into helper names). Mirrors the
#' Python sibling's `_period.py` in spirit but uses R-native idioms
#' (vector-in / vector-out, `data.table::set` for in-place column update).
#'
#' Three concerns:
#'
#' 1. **Date coercion** -- accept Date / POSIXt / integer / character and
#'    produce a Date column. Wraps `instead::as_date_safe` for the
#'    string path; integer (yyyy / yyyymm / yyyymmdd) handled inline.
#' 2. **Grain** -- detect / validate granularity codes:
#'    `"M"` (month) / `"Q"` (quarter) / `"S"` (semi-annual) / `"A"` (annual).
#'    `grain = "auto"` resolves to the inferred input grain.
#' 3. **Period operations** -- floor a Date to its period start; count
#'    elapsed periods between two Dates at a given grain.
#'
#' All functions in this file are internal (`.` prefix); not exported.
#'
#' @keywords internal
#' @noRd
NULL


# Grain codes ordered finest -> coarsest.
.GRAIN_ORDER <- c(M = 0L, Q = 1L, S = 2L, A = 3L)


# ---------------------------------------------------------------------------
# Year/month -> Date (vectorised, unique-key cache)
# ---------------------------------------------------------------------------


.first_of_month <- function(year, month) {
  if (length(month) == 1L) month <- rep_len(month, length(year))
  key   <- year * 100L + month
  ukey  <- unique(key)
  cache <- as.Date(ISOdate(ukey %/% 100L, ukey %% 100L, 1L, tz = "UTC"))
  cache[match(key, ukey)]
}


# ---------------------------------------------------------------------------
# Date coercion
# ---------------------------------------------------------------------------


.int_to_date <- function(x, var_name) {
  rng <- range(x, na.rm = TRUE)
  # Format-detect once, parse only the unique values, broadcast back.
  u <- unique(x)
  if (rng[1] >= 1900 && rng[2] <= 2100) {
    parsed <- .first_of_month(as.integer(u), 1L)
  } else if (rng[1] >= 190001 && rng[2] <= 210012) {
    parsed <- .first_of_month(as.integer(u %/% 100L), as.integer(u %% 100L))
  } else if (rng[1] >= 19000101 && rng[2] <= 21001231) {
    yr <- as.integer(u %/% 10000L)
    mo <- as.integer((u %/% 100L) %% 100L)
    dy <- as.integer(u %% 100L)
    parsed <- as.Date(ISOdate(yr, mo, dy, tz = "UTC"))
  } else {
    stop(sprintf(
      "Integer column '%s' (range %s-%s) doesn't match yyyy / yyyymm / yyyymmdd patterns.",
      var_name, format(rng[1]), format(rng[2])), call. = FALSE)
  }
  parsed[match(x, u)]
}


.coerce_to_date <- function(x, var_name) {
  if (inherits(x, "Date"))   return(x)
  if (inherits(x, "POSIXt")) return(as.Date(x))
  if (is.factor(x))          x <- as.character(x)
  if (is.character(x))       return(instead::as_date_safe(x))
  if (is.integer(x) || is.numeric(x)) return(.int_to_date(x, var_name))
  stop(sprintf(
    "Cannot coerce column '%s' (class %s) to Date. Supported: Date, POSIXt, integer, character, factor.",
    var_name, paste(class(x), collapse = "/")), call. = FALSE)
}


.coerce_cols_to_date <- function(dt, col_names) {
  for (nm in col_names)
    data.table::set(dt, j = nm, value = .coerce_to_date(dt[[nm]], nm))
  dt
}


# ---------------------------------------------------------------------------
# Grain inference + validation
# ---------------------------------------------------------------------------


.infer_grain <- function(x) {
  if (!inherits(x, "Date"))
    stop(sprintf(".infer_grain expects Date, got %s",
                 paste(class(x), collapse = "/")), call. = FALSE)
  vals <- x[!is.na(x)]
  if (length(vals) < 2L) return("M")
  ym <- sort(unique(data.table::year(vals) * 12L + data.table::month(vals)))
  if (length(ym) < 2L) return("M")
  diffs <- diff(ym)
  if (all(diffs %% 12L == 0L)) return("A")
  if (all(diffs %%  6L == 0L)) return("S")
  if (all(diffs %%  3L == 0L)) return("Q")
  "M"
}


.validate_grain <- function(input_grain, requested) {
  if (!requested %in% names(.GRAIN_ORDER))
    stop(sprintf("grain must be one of %s, got '%s'.",
                 paste(names(.GRAIN_ORDER), collapse = ", "), requested),
         call. = FALSE)
  if (.GRAIN_ORDER[[requested]] < .GRAIN_ORDER[[input_grain]]) {
    possible <- names(.GRAIN_ORDER)[
      .GRAIN_ORDER >= .GRAIN_ORDER[[input_grain]]
    ]
    stop(sprintf(
      "Cannot view %s-grain input as '%s'. Requested grain must be at least as coarse. Possible: %s.",
      input_grain, requested,
      paste(sprintf("'%s'", possible), collapse = ", ")), call. = FALSE)
  }
  invisible(NULL)
}


.resolve_grain <- function(input_grain, requested) {
  if (identical(requested, "auto")) return(input_grain)
  .validate_grain(input_grain, requested)
  requested
}


# ---------------------------------------------------------------------------
# Period operations
# ---------------------------------------------------------------------------


.floor_to_period <- function(x, grain) {
  # M floor is pure numeric arithmetic (Date is days since 1970-01-01).
  if (grain == "M")
    return(x - data.table::mday(x) + 1L)

  # Q/S/A: build the floor month from (year, month) integer keys; the
  # `.first_of_month` cache deduplicates before hitting ISOdate.
  yr <- data.table::year(x)
  mo <- data.table::month(x)
  floor_mo <- switch(grain,
    "Q" = ((mo - 1L) %/% 3L) * 3L + 1L,
    "S" = data.table::fifelse(mo <= 6L, 1L, 7L),
    "A" = 1L,
    stop(sprintf("Unknown grain: '%s'.", grain), call. = FALSE)
  )
  .first_of_month(yr, floor_mo)
}


.floor_cols_to_period <- function(dt, col_names, grain) {
  for (nm in col_names)
    data.table::set(dt, j = nm, value = .floor_to_period(dt[[nm]], grain))
  dt
}


.count_periods <- function(start_x, end_x, grain) {
  yr_diff <- data.table::year(end_x) - data.table::year(start_x)
  if (grain == "M") {
    return(as.integer(yr_diff * 12L
                      + (data.table::month(end_x) - data.table::month(start_x))
                      + 1L))
  }
  if (grain == "Q") {
    sq <- (data.table::month(start_x) - 1L) %/% 3L
    eq <- (data.table::month(end_x)   - 1L) %/% 3L
    return(as.integer(yr_diff * 4L + (eq - sq) + 1L))
  }
  if (grain == "S") {
    sh <- (data.table::month(start_x) - 1L) %/% 6L
    eh <- (data.table::month(end_x)   - 1L) %/% 6L
    return(as.integer(yr_diff * 2L + (eh - sh) + 1L))
  }
  if (grain == "A") {
    return(as.integer(yr_diff + 1L))
  }
  stop(sprintf("Unknown grain: '%s'.", grain), call. = FALSE)
}


# ---------------------------------------------------------------------------
# User-facing: derive M/Q/S/A grain columns from monthly source
# ---------------------------------------------------------------------------


#' Derive monthly / quarterly / semi-annual / annual grain columns
#'
#' @description
#' Given a long-format frame with monthly source columns
#' (`uy_m`, `cy_m`, optionally `dev_m`), derive the coarser-grain
#' siblings (`uy_q` / `uy_s` / `uy_a`, `cy_q` / `cy_s` / `cy_a`,
#' `dev_q` / `dev_s` / `dev_a`) so the same frame can be aggregated
#' at any of the four grains.
#'
#' This is an *optional* utility — [build_triangle()] and
#' [build_calendar()] already derive the single grain they need
#' internally. Use this when you want a single enriched frame that
#' can be re-aggregated at multiple grains, or for exploratory plots.
#'
#' @details
#' Letter-suffix family: `_m` / `_q` / `_s` / `_a` = monthly /
#' quarterly / semi-annual / annual.
#'
#' Derived columns when source columns exist:
#'
#' \strong{Underwriting (from `uy_m`):}
#' \itemize{
#'   \item `uy_a` : annual start (Jan 1 of `uy_m`'s year)
#'   \item `uy_s` : semi-annual start (Jan 1 / Jul 1)
#'   \item `uy_q` : quarterly start (Jan / Apr / Jul / Oct 1)
#' }
#'
#' \strong{Calendar (from `cy_m`):}
#' \itemize{
#'   \item `cy_a` : annual start
#'   \item `cy_s` : semi-annual start
#'   \item `cy_q` : quarterly start
#' }
#'
#' \strong{Development (from `uy_m` and `cy_m`, with `dev_m` derived
#' if absent):}
#' \itemize{
#'   \item `dev_a` is the annual development index, where dev_m 1-12
#'     map to 1, 13-24 map to 2, and so on.
#'   \item `dev_s` and `dev_q` are aligned to calendar semi-annual
#'     and quarterly boundaries (not simple groupings of `dev_m`),
#'     so cohorts such as Q1 / Q2 / S1 / S2 are compared consistently
#'     on the same cumulative development basis.
#' }
#'
#' Newly created columns are inserted before their corresponding
#' base columns.
#'
#' @param df A data.frame containing `uy_m`, `cy_m`, and optionally
#'   `dev_m`. Coarser-grain siblings are derived from these.
#'
#' @return A `data.table` with the additional grain columns.
#'
#' @examples
#' \dontrun{
#' df <- data.frame(
#'   uy_m  = as.Date("2023-01-01") + 0:5 * 30,
#'   cy_m  = as.Date("2023-01-01") + 0:5 * 30,
#'   dev_m = 1:6
#' )
#'
#' df2 <- derive_grain_columns(df)
#' head(df2)
#' }
#'
#' @export
derive_grain_columns <- function(df) {
  .assert_class(df, "data.frame")

  dt <- .ensure_dt(df)

  has_uy_m  <- .has_cols(dt, "uy_m")
  has_cy_m  <- .has_cols(dt, "cy_m")
  has_dev_m <- .has_cols(dt, "dev_m")

  # Year / month components (C-level via data.table).
  if (has_uy_m) {
    uy_yr <- data.table::year(dt[["uy_m"]])
    uy_mo <- data.table::month(dt[["uy_m"]])
  }
  if (has_cy_m) {
    cy_yr <- data.table::year(dt[["cy_m"]])
    cy_mo <- data.table::month(dt[["cy_m"]])
  }

  # uy_a / uy_s / uy_q — first-day-of-grain Date for each row.
  # Grain start months: A = 1; S = 1 (S1) / 7 (S2);
  # Q = 1 (Q1) / 4 (Q2) / 7 (Q3) / 10 (Q4).
  if (has_uy_m) {
    uy_s_mo <- data.table::fifelse(uy_mo <= 6L, 1L, 7L)
    uy_q_mo <- ((uy_mo - 1L) %/% 3L) * 3L + 1L
    dt[, `:=`(
      uy_a = .first_of_month(uy_yr, 1L),
      uy_s = .first_of_month(uy_yr, uy_s_mo),
      uy_q = .first_of_month(uy_yr, uy_q_mo)
    )]
    data.table::setcolorder(dt, c("uy_a", "uy_s", "uy_q"), before = "uy_m")
  }

  if (has_cy_m) {
    cy_s_mo <- data.table::fifelse(cy_mo <= 6L, 1L, 7L)
    cy_q_mo <- ((cy_mo - 1L) %/% 3L) * 3L + 1L
    dt[, `:=`(
      cy_a = .first_of_month(cy_yr, 1L),
      cy_s = .first_of_month(cy_yr, cy_s_mo),
      cy_q = .first_of_month(cy_yr, cy_q_mo)
    )]
    data.table::setcolorder(dt, c("cy_a", "cy_s", "cy_q"), before = "cy_m")
  }

  # dev_m derived if absent (months between uy_m and cy_m, inclusive).
  if (!has_dev_m && has_uy_m && has_cy_m) {
    dt[, dev_m := (cy_yr - uy_yr) * 12L + (cy_mo - uy_mo) + 1L]
    data.table::setcolorder(dt, "dev_m", after = "cy_m")
    has_dev_m <- TRUE
  }

  # dev_a / dev_s / dev_q — calendar-anchored development indices.
  # dev_s / dev_q align to S / Q boundaries (so Q1, Q2, S1, S2 cohorts
  # are compared on the same cumulative basis), not simple groupings
  # of dev_m.
  if (has_uy_m && has_cy_m && has_dev_m) {
    dev_mo <- dt[["dev_m"]]
    dev_a  <- (dev_mo - 1L) %/% 12L + 1L

    uy_s_idx <- (uy_mo - 1L) %/% 6L   # 0 = S1, 1 = S2
    cy_s_idx <- (cy_mo - 1L) %/% 6L
    dev_s    <- (cy_yr - uy_yr) * 2L + (cy_s_idx - uy_s_idx) + 1L

    uy_q_idx <- (uy_mo - 1L) %/% 3L   # 0 = Q1, ..., 3 = Q4
    cy_q_idx <- (cy_mo - 1L) %/% 3L
    dev_q    <- (cy_yr - uy_yr) * 4L + (cy_q_idx - uy_q_idx) + 1L

    dt[, `:=`(dev_a = dev_a, dev_s = dev_s, dev_q = dev_q)]
    data.table::setcolorder(dt, c("dev_a", "dev_s", "dev_q"), before = "dev_m")
  }

  dt[]
}
