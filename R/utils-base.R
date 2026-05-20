# Internal helpers: class manipulation, assertions, formatting ------------
#
# General-purpose utilities shared across the package -- S3 class
# manipulation, argument / column-spec assertions, and period / numeric
# formatting. Internal helpers carry a leading `.`; `longer()` is the
# one exported S3 generic.


# Class manipulation ------------------------------------------------------

#' Prepend class(es) without duplication
#'
#' @description
#' Ensure one or more class names appear at the front of an object's class
#' vector, without duplicating existing classes. For `data.table` input,
#' uses [data.table::setattr()] to avoid copy and preserve selfref.
#'
#' @param x An R object.
#' @param classes Character vector of class names to prepend.
#'
#' @return `x` with class attribute updated.
#'
#' @keywords internal
.prepend_class <- function(x, classes) {
  if (length(classes) == 0L) return(x)
  if (!is.character(classes) || anyNA(classes))
    stop("`classes` must be a non-empty character vector without NA.",
         call. = FALSE)

  classes   <- unique(classes)
  org_class <- setdiff(unname(class(x)), classes)

  if (inherits(x, "data.table")) {
    data.table::setattr(x, "class", c(classes, org_class))
    return(x[])
  }

  class(x) <- c(classes, org_class)
  x
}


#' Remove class(es) from an object
#'
#' @description
#' Remove one or more class names from an object's class vector. For
#' `data.table` input, uses [data.table::setattr()] to avoid copy.
#'
#' @inheritParams .prepend_class
#' @param classes Character vector of class names to remove.
#'
#' @return `x` with class attribute updated.
#'
#' @keywords internal
.remove_class <- function(x, classes) {
  if (length(classes) == 0L) return(x)
  if (!is.character(classes) || anyNA(classes))
    stop("`classes` must be a non-empty character vector without NA.",
         call. = FALSE)

  classes <- unique(classes)
  remain  <- setdiff(unname(class(x)), classes)

  if (inherits(x, "data.table")) {
    data.table::setattr(x, "class", remain)
    return(x[])
  }

  class(x) <- remain
  x
}


#' Update class attribute: remove then prepend
#'
#' @description
#' Convenience wrapper that first removes classes listed in `remove`,
#' then prepends classes listed in `prepend`.
#'
#' @param x An R object.
#' @param remove Character vector of class names to remove. `NULL` to skip.
#' @param prepend Character vector of class names to prepend. `NULL` to skip.
#'
#' @return `x` with class attribute updated.
#'
#' @keywords internal
.update_class <- function(x, remove = NULL, prepend = NULL) {
  if ((is.null(remove)  || length(remove)  == 0L) &&
      (is.null(prepend) || length(prepend) == 0L)) {
    return(x)
  }

  if (!is.null(remove)) {
    if (!is.character(remove) || anyNA(remove))
      stop("`remove` must be a character vector without NA.", call. = FALSE)
    x <- .remove_class(x, remove)
  }

  if (!is.null(prepend)) {
    if (!is.character(prepend) || anyNA(prepend))
      stop("`prepend` must be a character vector without NA.", call. = FALSE)
    x <- .prepend_class(x, prepend)
  }

  x
}


# Assertions --------------------------------------------------------------

#' Assert that `x` inherits from the given class(es)
#'
#' @param x An R object.
#' @param classes Character vector of expected class names.
#'
#' @return Invisibly returns `x` on success; otherwise aborts.
#'
#' @keywords internal
.assert_class <- function(x, classes) {
  if (!inherits(x, classes)) {
    cli::cli_abort(
      "Input must inherit from class(es) {.cls {classes}}, not {.cls {class(x)}}."
    )
  }
  invisible(x)
}


#' Assert that `x` has nonzero length
#'
#' @param x An R object.
#'
#' @return Invisibly returns `x` on success; otherwise aborts.
#'
#' @keywords internal
.assert_length <- function(x) {
  if (!length(x)) {
    cli::cli_abort("Input must have nonzero length.")
  }
  invisible(x)
}


# Group resolution --------------------------------------------------------

#' Resolve the grouping columns of a Triangle / Link / fit object
#'
#' Returns `attr(x, "groups")`, or `character(0)` when the attribute is
#' absent -- the canonical "no groups" sentinel used throughout the
#' package.
#'
#' @param x An object carrying (or lacking) a `"groups"` attribute.
#'
#' @return A character vector of group column names; `character(0)`
#'   when there are none.
#'
#' @keywords internal
.resolve_groups <- function(x) {
  grp <- attr(x, "groups")
  if (is.null(grp)) character(0) else grp
}


#' Group vector for a data.table `by =` argument
#'
#' `data.table`'s `by =` wants `NULL` (not `character(0)`) to mean
#' "no grouping". This converts an empty group vector accordingly.
#'
#' @param grp Character vector of group column names, possibly empty.
#'
#' @return `grp` unchanged, or `NULL` when `grp` is empty.
#'
#' @keywords internal
.by_grp <- function(grp) {
  if (length(grp) == 0L) NULL else grp
}


# Column helpers ----------------------------------------------------------

#' Whether all of `cols` are present in `names(df)`
#'
#' @param df A data.frame (or similar with `names()`).
#' @param cols Character vector of column names.
#'
#' @return Logical scalar.
#'
#' @keywords internal
.has_cols <- function(df, cols) {
  all(cols %in% names(df))
}


#' Check a data frame against a named list of expected column classes
#'
#' @description
#' Compares the actual class of each column in `df` against the expected
#' class defined in `col_spec`, prints a colored console summary grouped
#' by status (`match`, `mismatch`, `missing`, `extra`), and returns a
#' tidy data.frame invisibly.
#'
#' Integer/numeric mismatches are flagged as `compatible` in the note
#' column.
#'
#' @param df A data.frame.
#' @param col_spec A named list where names are column names and values
#'   are expected class strings (length-1 character).
#'
#' @return Invisibly returns a data.frame with columns
#'   `column`, `actual`, `expected`, `status`, `note`, `sample`.
#'
#' @keywords internal
.check_col_spec <- function(df, col_spec) {
  cols_act <- names(df)
  cols_exp <- names(col_spec)
  actual   <- vapply(df, function(x) class(x)[1L], character(1L))

  df_act <- data.frame(
    column           = names(actual), actual = actual,
    stringsAsFactors = FALSE
  )
  df_exp <- data.frame(
    column           = cols_exp, expected = unlist(col_spec, use.names = FALSE),
    stringsAsFactors = FALSE
  )

  merged <- merge(df_act, df_exp, by = "column", all = TRUE)
  cols_ord <- c(cols_exp, setdiff(cols_act, cols_exp))
  ord <- match(cols_ord, merged$column)
  ord <- ord[!is.na(ord)]
  merged <- merged[ord, ]
  rownames(merged) <- NULL

  merged$status <- ifelse(
    is.na(merged$actual), "missing",
    ifelse(is.na(merged$expected), "extra",
           ifelse(merged$actual == merged$expected, "match", "mismatch"))
  )

  merged$note <- ifelse(
    merged$status == "mismatch" & (
      (merged$actual == "integer" & merged$expected == "numeric") |
        (merged$actual == "numeric" & merged$expected == "integer")
    ),
    "compatible", NA_character_
  )

  first_row <- df[1, , drop = FALSE]
  merged$sample <- vapply(merged$column, function(col) {
    if (col %in% names(first_row)) {
      as.character(first_row[[col]])
    } else {
      NA_character_
    }
  }, character(1L))

  cat(cli::col_cyan(cli::rule("Column check summary", line = 2)), "\n")
  for (stat in c("match", "mismatch", "missing", "extra")) {
    sub <- merged[merged$status == stat, ]
    if (!nrow(sub)) next
    msg_str <- switch(
      stat,
      match    = paste(sub$column, collapse = ", "),
      mismatch = paste0(
        sub$column, " (", sub$actual, " \u2192 ", sub$expected,
        ifelse(!is.na(sub$note), paste0(": ", sub$note), ""), ")",
        collapse = ", "
      ),
      missing = paste(sub$column, collapse = ", "),
      extra   = paste(sub$column, collapse = ", ")
    )
    color_msg <- switch(
      stat,
      match    = cli::col_green(msg_str),
      mismatch = cli::col_red(msg_str),
      missing  = cli::col_yellow(msg_str),
      extra    = cli::col_cyan(msg_str)
    )
    icon <- switch(stat, match = "o", mismatch = "x", missing = "-", extra = "+")
    cli::cli_alert("{.strong {icon} {stat}:} {color_msg}")
  }
  cli::cli_text("")

  invisible(merged)
}


# Date / period formatting ------------------------------------------------

#' Format Date values as period labels
#'
#' @description
#' Convert a `Date` vector into formatted labels by month, quarter,
#' half-year, year, or day.
#'
#' Output formats:
#' - `"month"`: `"2024.02"` or `"24.02"`
#' - `"quarter"`: `"2024.Q1"` or `"24.Q1"`
#' - `"half"`: `"2024.H1"` or `"24.H1"`
#' - `"year"`: `"2024"` or `"24"`
#' - `"day"`: `"2024.02.01"` or `"24.02.01"`
#'
#' @param x A `Date` vector (or an object coercible to `Date`).
#' @param type Period unit. One of `"month"`, `"quarter"`, `"half"`,
#'   `"year"`, `"day"`.
#' @param sep Separator placed between year and period components.
#'   Default `"."`.
#' @param abb Logical; if `TRUE`, use 2-digit year. Default `TRUE`.
#'
#' @return Character vector of the same length as `x`.
#'
#' @keywords internal
.format_period <- function(x,
                           type = c("month", "quarter", "half", "year", "day"),
                           sep  = ".",
                           abb  = TRUE) {

  x <- as.Date(x)
  type <- match.arg(type)

  yi <- data.table::year(x)
  yr <- if (abb) sprintf("%02d", yi %% 100L) else as.character(yi)

  if (type == "year") return(yr)

  m <- data.table::month(x)

  if (type == "month") {
    return(paste0(yr, sep, sprintf("%02d", m)))
  }

  if (type == "quarter") {
    q <- (m - 1L) %/% 3L + 1L
    return(paste0(yr, sep, q, "Q"))
  }

  if (type == "half") {
    h <- (m > 6L) + 1L
    return(paste0(yr, sep, h, "H"))
  }

  if (type == "day") {
    d <- data.table::mday(x)
    return(paste0(
      yr, sep,
      sprintf("%02d", m), sep,
      sprintf("%02d", d)
    ))
  }

  stop("Invalid `type`.", call. = FALSE)
}


# Numeric formatting ------------------------------------------------------

#' Format numbers with comma as thousands separator
#'
#' @param x Integer or numeric vector.
#' @param digits Number of digits after the decimal point. Default `0`.
#'
#' @return Character vector of the same length as `x`.
#'
#' @keywords internal
.as_comma <- function(x, digits = 0L) {
  formatC(x, format = "f", digits = digits, big.mark = ",")
}


# S3 generic for long-form reshaping --------------------------------------

#' Reshape an object to long form (S3 generic)
#'
#' Mirrors the S3 generic originally provided by the `instead` package.
#' Concrete methods (`longer.Triangle`, `longer.TriangleSummary`) dispatch on
#' domain-specific classes and typically return the pre-computed long-form
#' data stored in `attr(x, "longer")`.
#'
#' @param x An object to reshape.
#' @param ... Passed to methods.
#'
#' @return A long-form object as defined by the dispatched method.
#'
#' @export
longer <- function(x, ...) {
  UseMethod("longer")
}
