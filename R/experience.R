#' Check an experience dataset
#'
#' @description
#' Check that an experience dataset contains the required columns with
#' the expected classes, and validate the classes of optional columns
#' when present.
#'
#' @param df A data.frame containing experience data.
#'
#' @section Required columns:
#' These columns must be present:
#' \itemize{
#'   \item `cy_m`         : Calendar year-month (`Date`)
#'   \item `uy_m`         : Underwriting year-month (`Date`)
#'   \item `loss_incr`    : Per-period loss amount (`numeric`)
#'   \item `premium_incr` : Per-period premium (`numeric`); for long-term
#'     health insurance, risk premium is commonly used
#' }
#'
#' @section Optional columns:
#' These columns are validated only when present:
#' \itemize{
#'   \item `dev_m`     : Development month (`integer`)
#'   \item `pd_tp_cd`, `pd_tp_nm`, `pd_cd`, `pd_nm`:
#'     Product type/product codes and names (`character`)
#'   \item `cv_tp_cd`, `cv_tp_nm`, `cv_cd`, `coverage`:
#'     Coverage type/coverage codes and names (`character`)
#'   \item `rd_tp_cd`, `rd_tp_nm`, `rd_cd`, `rd_nm`:
#'     Rider type/rider codes and names (`character`)
#'   \item `age_band` : Age band (`ordered`)
#'   \item `gender`   : Gender (`factor`)
#'   \item `ch_cd`, `ch_nm` : Channel code and name (`character`)
#'   \item `n_policy` : Number of unique policies in the cell (`integer`)
#' }
#'
#' @section Derived columns:
#' The following columns may be derived later by
#' [add_experience_period()] and are not validated here:
#' \itemize{
#'   \item `uy_a`, `uy_s`, `uy_q` : Underwriting year, half-year, quarter
#'   \item `cy_a`, `cy_s`, `cy_q` : Calendar year, half-year, quarter
#'   \item `dev_a`, `dev_s`, `dev_q` : Development year, half-year, quarter
#' }
#'
#' @return Invisibly returns the result of [.check_col_spec()].
#'
#' @seealso [as_experience()], [add_experience_period()],
#'   [.check_col_spec()]
#'
#' @export
check_experience <- function(df) {
  .assert_class(df, "data.frame")

  required_spec <- list(
    cy_m         = "Date",
    uy_m         = "Date",
    loss_incr    = "numeric",
    premium_incr = "numeric"
  )

  optional_spec <- list(
    dev_m    = "integer",
    pd_tp_cd = "character",
    pd_tp_nm = "character",
    pd_cd    = "character",
    pd_nm    = "character",
    cv_tp_cd = "character",
    cv_tp_nm = "character",
    cv_cd    = "character",
    coverage = "character",
    rd_tp_cd = "character",
    rd_tp_nm = "character",
    rd_cd    = "character",
    rd_nm    = "character",
    age_band = "ordered",
    gender   = "factor",
    ch_cd    = "character",
    ch_nm    = "character",
    n_policy = "integer"
  )

  # check required columns (strict)
  .check_col_spec(df, required_spec)

  # check optional columns (only those present)
  present_optional <- optional_spec[names(optional_spec) %in% names(df)]
  if (length(present_optional)) {
    .check_col_spec(df, present_optional)
  }

  invisible(NULL)
}

#' Add standard period variables to an experience dataset
#'
#' @description
#' Add underwriting, calendar, and development period variables to an
#' experience dataset using standard column conventions for loss ratio
#' analysis.
#'
#' The function detects the presence of key source columns such as `uy_m`,
#' `cy_m`, and `dev_m`, and derives additional period variables when
#' possible.
#'
#' @details
#' The following variables are added when the required source columns
#' exist:
#'
#' \strong{Underwriting period (from `uy_m`):}
#' \itemize{
#'   \item `uy_a` : underwriting year
#'   \item `uy_s` : underwriting half-year
#'   \item `uy_q` : underwriting quarter
#' }
#'
#' \strong{Calendar period (from `cy_m`):}
#' \itemize{
#'   \item `cy_a` : calendar year
#'   \item `cy_s` : calendar half-year
#'   \item `cy_q` : calendar quarter
#' }
#'
#' \strong{Development period:}
#' \itemize{
#'   \item `dev_a` is derived from `dev_m` as yearly development
#'     index, where months 1 to 12 map to 1, 13 to 24 map to 2, and so on.
#'   \item `dev_s` is derived from `uy_m` and `cy_m` using calendar half-year
#'     boundaries. For example, contracts issued in January to June are
#'     aligned to the same first development half-year block, and the next
#'     calendar half-year becomes development half-year 2.
#'   \item `dev_q` is derived from `uy_m` and `cy_m` using calendar quarter
#'     boundaries. For example, contracts issued in January to March are
#'     aligned to the same first development quarter block, and the next
#'     calendar quarter becomes development quarter 2.
#' }
#'
#' Therefore, `dev_s` and `dev_q` are not simple grouped versions of
#' `dev_m`; they are aligned to calendar half-year and quarter boundaries
#' so that underwriting cohorts such as Q1, Q2, H1, and H2 are compared
#' consistently on the same cumulative development basis.
#'
#' Newly created columns are inserted before their corresponding base
#' columns.
#'
#' @param df A data.frame containing period variables such as `uy_m`,
#'   `cy_m`, and `dev_m`.
#'
#' @return A data.frame (or tibble/data.table depending on input) with
#'   additional period variables.
#'
#' @examples
#' \dontrun{
#' df <- data.frame(
#'   uy_m  = as.Date("2023-01-01") + 0:5 * 30,
#'   cy_m  = as.Date("2023-01-01") + 0:5 * 30,
#'   dev_m = 1:6
#' )
#'
#' df2 <- add_experience_period(df)
#' head(df2)
#' }
#'
#' @export
add_experience_period <- function(df) {
  .assert_class(df, "data.frame")

  dt <- .ensure_dt(df)

  has_uy_m  <- .has_cols(dt, "uy_m")
  has_cy_m  <- .has_cols(dt, "cy_m")
  has_dev_m <- .has_cols(dt, "dev_m")

  # Extract year / month once per source column (C-level via data.table).
  if (has_uy_m) {
    uy_m_year <- data.table::year(dt[["uy_m"]])
    uy_m_mon  <- data.table::month(dt[["uy_m"]])
  }
  if (has_cy_m) {
    cy_m_year <- data.table::year(dt[["cy_m"]])
    cy_m_mon  <- data.table::month(dt[["cy_m"]])
  }

  # underwriting period (uy_a, uy_s, uy_q) — calendar-anchored
  # H1: Jan-Jun, H2: Jul-Dec; Q1: Jan-Mar, ..., Q4: Oct-Dec
  if (has_uy_m) {
    uy_s_mon <- data.table::fifelse(uy_m_mon <= 6L, 1L, 7L)
    uy_q_mon <- ((uy_m_mon - 1L) %/% 3L) * 3L + 1L
    dt[, `:=`(
      uy_a = .first_of_month(uy_m_year, 1L),
      uy_s = .first_of_month(uy_m_year, uy_s_mon),
      uy_q = .first_of_month(uy_m_year, uy_q_mon)
    )]
    data.table::setcolorder(dt, c("uy_a", "uy_s", "uy_q"), before = "uy_m")
  }

  # calendar period (cy_a, cy_s, cy_q)
  if (has_cy_m) {
    cy_s_mon <- data.table::fifelse(cy_m_mon <= 6L, 1L, 7L)
    cy_q_mon <- ((cy_m_mon - 1L) %/% 3L) * 3L + 1L
    dt[, `:=`(
      cy_a = .first_of_month(cy_m_year, 1L),
      cy_s = .first_of_month(cy_m_year, cy_s_mon),
      cy_q = .first_of_month(cy_m_year, cy_q_mon)
    )]
    data.table::setcolorder(dt, c("cy_a", "cy_s", "cy_q"), before = "cy_m")
  }

  # development month (dev_m)
  if (!has_dev_m && has_uy_m && has_cy_m) {
    dt[, dev_m := (cy_m_year - uy_m_year) * 12L + (cy_m_mon - uy_m_mon) + 1L]
    data.table::setcolorder(dt, "dev_m", after = "cy_m")
    has_dev_m <- TRUE
  }

  # development period (dev_a, dev_s, dev_q) — calendar-anchored boundaries
  if (has_uy_m && has_cy_m && has_dev_m) {
    dev_m_local <- dt[["dev_m"]]
    dev_a <- (dev_m_local - 1L) %/% 12L + 1L

    uy_half <- (uy_m_mon - 1L) %/% 6L   # 0 = H1, 1 = H2
    cy_half <- (cy_m_mon - 1L) %/% 6L
    dev_s <- (cy_m_year - uy_m_year) * 2L + (cy_half - uy_half) + 1L

    uy_quart <- (uy_m_mon - 1L) %/% 3L  # 0 = Q1, ..., 3 = Q4
    cy_quart <- (cy_m_mon - 1L) %/% 3L
    dev_q <- (cy_m_year - uy_m_year) * 4L + (cy_quart - uy_quart) + 1L

    dt[, `:=`(dev_a = dev_a, dev_s = dev_s, dev_q = dev_q)]
    data.table::setcolorder(dt, c("dev_a", "dev_s", "dev_q"), before = "dev_m")
  }

  dt[]
}

# Vectorised first-day-of-(year, month) construction with deduplication.
# Experience data typically has only a few dozen unique (year, month)
# pairs, so we evaluate ISOdate() once per unique key (~30 calls) instead
# of once per row (~1M calls).
.first_of_month <- function(year, month) {
  if (length(month) == 1L) month <- rep_len(month, length(year))
  key   <- year * 100L + month
  ukey  <- unique(key)
  cache <- as.Date(ISOdate(ukey %/% 100L, ukey %% 100L, 1L, tz = "UTC"))
  cache[match(key, ukey)]
}

#' Coerce a dataset to an `Experience` object
#'
#' @description
#' Coerce a data.frame to a minimal `Experience` object for loss ratio
#' analysis.
#'
#' This function checks that the input contains the minimum required
#' columns, attempts to coerce them to the expected classes, optionally
#' derives standard period variables via [add_experience_period()], and
#' prepends class `"Experience"`.
#'
#' The function intentionally performs only minimal coercion. Other
#' columns such as grouping variables or presentation variables are left
#' unchanged and should be cleaned by the user in advance.
#'
#' @param df A data.frame containing experience data.
#' @param add_period Logical; if `TRUE`, derive additional period
#'   variables using [add_experience_period()]. Default is `TRUE`.
#'
#' @details
#' Minimum required columns are:
#' \itemize{
#'   \item `cy_m`         : Calendar year-month (`Date` or coercible to `Date`)
#'   \item `uy_m`         : Underwriting year-month (`Date` or coercible to `Date`)
#'   \item `loss_incr`    : Per-period loss amount (`numeric` or coercible)
#'   \item `premium_incr` : Per-period premium (`numeric` or coercible); for
#'     long-term health insurance, risk premium is commonly used
#' }
#'
#' If `add_period = TRUE`, additional period variables such as `uy_a`,
#' `uy_s`, `uy_q`, `cy_a`, `cy_s`, `cy_q`, `dev_a`, `dev_s`, and `dev_q` may be
#' added, depending on the available source columns.
#'
#' @return A data.frame with class `"Experience"` prepended.
#'
#' @seealso [check_experience()], [add_experience_period()]
#'
#' @examples
#' \dontrun{
#' x <- as_experience(df)
#' class(x)
#' }
#'
#' @export
as_experience <- function(df, add_period = TRUE) {
  .assert_class(df, "data.frame")

  if (!is.logical(add_period) || length(add_period) != 1L ||
      is.na(add_period)) {
    stop("`add_period` must be a single non-missing logical value.",
         call. = FALSE)
  }

  required_cols <- c("cy_m", "uy_m", "loss_incr", "premium_incr")
  missing_cols  <- setdiff(required_cols, names(df))

  if (length(missing_cols)) {
    stop(
      paste0(
        "`df` must contain the required columns: ",
        paste(sprintf("'%s'", required_cols), collapse = ", "),
        ". Missing columns: ",
        paste(sprintf("'%s'", missing_cols), collapse = ", "),
        "."
      ),
      call. = FALSE
    )
  }

  dt <- .ensure_dt(df)

  # coerce required period columns
  if (!inherits(dt[["cy_m"]], "Date")) {
    data.table::set(dt, j = "cy_m", value = as.Date(dt[["cy_m"]]))
  }

  if (!inherits(dt[["uy_m"]], "Date")) {
    data.table::set(dt, j = "uy_m", value = as.Date(dt[["uy_m"]]))
  }

  # coerce required numeric columns
  data.table::set(dt, j = "loss_incr",    value = as.numeric(dt[["loss_incr"]]))
  data.table::set(dt, j = "premium_incr", value = as.numeric(dt[["premium_incr"]]))

  # validate required columns after coercion
  if (anyNA(dt[["cy_m"]])) {
    stop("`cy_m` could not be safely coerced to `Date`.", call. = FALSE)
  }

  if (anyNA(dt[["uy_m"]])) {
    stop("`uy_m` could not be safely coerced to `Date`.", call. = FALSE)
  }

  if (anyNA(dt[["loss_incr"]])) {
    stop("`loss_incr` could not be safely coerced to `numeric`.", call. = FALSE)
  }

  if (anyNA(dt[["premium_incr"]])) {
    stop("`premium_incr` could not be safely coerced to `numeric`.", call. = FALSE)
  }

  # add derived period variables
  if (add_period) {
    dt <- data.table::as.data.table(add_experience_period(dt))
  }

  .prepend_class(dt, "Experience")
}

#' Check whether an object is an `Experience`
#'
#' @param x An object.
#'
#' @return Logical scalar.
#'
#' @export
is_experience <- function(x) {
  inherits(x, "Experience")
}

