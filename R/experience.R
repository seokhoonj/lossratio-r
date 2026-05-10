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
#' [derive_grain_columns()] and are not validated here:
#' \itemize{
#'   \item `uy_a`, `uy_s`, `uy_q` : Underwriting annual, semi-annual, quarterly (and `uy_m` is monthly)
#'   \item `cy_a`, `cy_s`, `cy_q` : Calendar annual, semi-annual, quarterly (and `cy_m` is monthly)
#'   \item `dev_a`, `dev_s`, `dev_q` : Development annual, semi-annual, quarterly (and `dev_m` is monthly)
#' }
#'
#' Letter-suffix family: `_m` / `_q` / `_s` / `_a` = monthly / quarterly /
#' semi-annual / annual. The underwriting (`uy_*`) and calendar (`cy_*`)
#' columns are all `Date` (annual / semi-annual / quarterly anchored to
#' the period's first day); `dev_*` columns are integer counts.
#'
#' @return Invisibly returns the result of [.check_col_spec()].
#'
#' @seealso [as_experience()], [derive_grain_columns()],
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

#' Coerce a dataset to an `Experience` object
#'
#' @description
#' Coerce a data.frame to a minimal `Experience` object for loss ratio
#' analysis.
#'
#' This function checks that the input contains the minimum required
#' columns, attempts to coerce them to the expected classes, optionally
#' derives standard period variables via [derive_grain_columns()], and
#' prepends class `"Experience"`.
#'
#' The function intentionally performs only minimal coercion. Other
#' columns such as grouping variables or presentation variables are left
#' unchanged and should be cleaned by the user in advance.
#'
#' @param df A data.frame containing experience data.
#' @param add_period Logical; if `TRUE`, derive additional period
#'   variables using [derive_grain_columns()]. Default is `TRUE`.
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
#' @seealso [check_experience()], [derive_grain_columns()]
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
    dt <- data.table::as.data.table(derive_grain_columns(dt))
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

