#' Safely convert to data.table
#'
#' @description
#' Internal helper that converts any `data.frame`-like object to a
#' `data.table`. If the input is already a `data.table`, a copy is returned
#' to prevent unintended modification by reference. Otherwise,
#' [data.table::as.data.table()] is called, which always creates a new
#' object.
#'
#' @param x A `data.frame`, `tibble`, or `data.table`.
#'
#' @return A `data.table`.
#'
#' @keywords internal
.ensure_dt <- function(x) {
  if (data.table::is.data.table(x)) {
    data.table::copy(x)
  } else {
    data.table::as.data.table(x)
  }
}


# Amount unit -------------------------------------------------------------

#' Get a human-readable label for an amount divisor
#'
#' @description
#' Internal helper that converts a numeric scaling divisor into a
#' human-readable unit label used in plot captions.
#'
#' @param divisor A single numeric scalar.
#'
#' @return A character string such as `"100 million"`, `"billion"`, or
#'   a fallback `"scaled (/1e+08)"` for unrecognised values. Returns `""`
#'   when `divisor` is `1`.
#'
#' @keywords internal
.get_amount_unit <- function(divisor) {

  if (isTRUE(all.equal(divisor, 1)))   return("")
  if (isTRUE(all.equal(divisor, 1e3))) return("thousand")
  if (isTRUE(all.equal(divisor, 1e6))) return("million")
  if (isTRUE(all.equal(divisor, 1e7))) return("10 million")
  if (isTRUE(all.equal(divisor, 1e8))) return("100 million")
  if (isTRUE(all.equal(divisor, 1e9))) return("billion")

  paste0("scaled (/", format(divisor, scientific = TRUE), ")")
}


# Period type -------------------------------------------------------------

#' Get the period type string for a period variable name
#'
#' @description
#' Internal helper that maps a period variable name (e.g. `"uym"`, `"cyq"`)
#' to the corresponding type string accepted by [.format_period()].
#'
#' Returns `NA_character_` for unrecognised variable names, which callers
#' can use to fall back to `as.character()` formatting.
#'
#' @param var A single character string naming a period variable.
#'
#' @return One of `"month"`, `"quarter"`, `"half"`, `"year"`, or
#'   `NA_character_`.
#'
#' @keywords internal
.get_period_type <- function(var) {
  switch(
    var,
    uym = , cym = "month",
    uyq = , cyq = "quarter",
    uyh = , cyh = "half",
    uy  = , cy  = "year",
    NA_character_
  )
}


#' Granularity of a cohort or development variable
#'
#' Like [.get_period_type()] but also recognises the integer elapsed-period
#' columns (`elap_m` / `elap_q` / `elap_h` / `elap_y`). Used by
#' [build_triangle()] to verify that `cohort_var` and `dev_var` share the
#' same granularity. Not used for date formatting (these elap columns
#' are integers, not Date).
#'
#' @keywords internal
.get_granularity <- function(var) {
  type <- .get_period_type(var)
  if (!is.na(type)) return(type)
  switch(
    var,
    elap_m = "month",
    elap_q = "quarter",
    elap_h = "half",
    elap_y = "year",
    NA_character_
  )
}


# Plot meta ---------------------------------------------------------------

#' Get plot display metadata for a value variable
#'
#' @description
#' Internal helper that returns display metadata for a given value variable,
#' including the plot title, y-axis caption, reference line value, and
#' variable type classification. Used across plot functions to avoid
#' repeating `switch` and `if` blocks for each variable type.
#'
#' @param value_var A single character string naming the variable to plot.
#'   Must be one of the recognised variable names in the `lossratio` package.
#' @param amount_divisor Numeric scaling factor for amount variables.
#'   Default is `1e8`.
#'
#' @return A named list with elements:
#'   \describe{
#'     \item{`type`}{One of `"ratio"`, `"amount"`, or `"prop"`.}
#'     \item{`title`}{Plot title string.}
#'     \item{`caption`}{Y-axis caption string, or `NULL`.}
#'     \item{`hline`}{Y-intercept for a reference line, or `NULL`.}
#'   }
#'
#' @keywords internal
.get_plot_meta <- function(value_var, amount_divisor = 1e8) {

  ratio_vars  <- c("lr", "lr_incr")
  amount_vars <- c("loss", "loss_incr",
                   "premium", "premium_incr",
                   "margin", "margin_incr")
  prop_vars   <- c("loss_prop", "loss_incr_prop",
                   "premium_prop", "premium_incr_prop")

  if (value_var %in% ratio_vars) {
    list(
      type    = "ratio",
      title   = switch(value_var,
                       lr      = "Cumulative Loss Ratio",
                       lr_incr = "Per-Period Loss Ratio"
      ),
      caption = "Unit: %",
      hline   = 1
    )

  } else if (value_var %in% amount_vars) {
    unit_txt <- .get_amount_unit(amount_divisor)
    list(
      type    = "amount",
      title   = switch(value_var,
                       loss         = "Cumulative Loss",
                       loss_incr    = "Per-Period Loss",
                       premium      = "Cumulative Premium",
                       premium_incr = "Per-Period Premium",
                       margin       = "Cumulative Margin",
                       margin_incr  = "Per-Period Margin"
      ),
      caption = if (nzchar(unit_txt)) paste("Unit:", unit_txt) else NULL,
      hline   = 0
    )

  } else if (value_var %in% prop_vars) {
    list(
      type    = "prop",
      title   = switch(value_var,
                       loss_prop         = "Cumulative Loss Proportion",
                       loss_incr_prop    = "Per-Period Loss Proportion",
                       premium_prop      = "Cumulative Premium Proportion",
                       premium_incr_prop = "Per-Period Premium Proportion"
      ),
      caption = "Unit: %",
      hline   = NULL
    )

  } else {
    stop(
      sprintf("Unknown `value_var`: '%s'.", value_var),
      call. = FALSE
    )
  }
}


# Y scale -----------------------------------------------------------------

#' Resolve y-axis scale for a plot
#'
#' @description
#' Internal helper that resolves the appropriate
#' [ggplot2::scale_y_continuous()] layer from the variable type and scaling
#' divisor. Given the metadata produced by [.get_plot_meta()], it determines
#' how y-axis labels should be formatted:
#'
#' \itemize{
#'   \item Ratio and proportion variables are displayed as percentages.
#'   \item Amount variables are scaled by `amount_divisor` and formatted
#'     with commas.
#' }
#'
#' @param meta A named list produced by [.get_plot_meta()], containing at
#'   least a `type` element.
#' @param amount_divisor Numeric scaling factor for amount variables.
#'   Default is `1e8`.
#'
#' @return A [ggplot2::scale_y_continuous()] layer.
#'
#' @keywords internal
.resolve_y_scale <- function(meta, amount_divisor = 1e8) {

  if (meta$type %in% c("ratio", "prop")) {
    return(
      ggplot2::scale_y_continuous(
        labels = function(z) .as_comma(z * 100)
      )
    )
  }

  if (meta$type == "amount") {
    return(
      ggplot2::scale_y_continuous(
        labels = function(z) .as_comma(z / amount_divisor)
      )
    )
  }

  ggplot2::scale_y_continuous()
}


# Period safe format ------------------------------------------------------

#' Human-readable label for a period / development variable name
#'
#' @description
#' Internal helper that maps a package convention variable name (e.g.
#' `"uym"`, `"elap_m"`) to a human-readable axis label (e.g.
#' `"underwriting ym"`, `"development months"`). Falls back to the input
#' string when the variable is not recognised.
#'
#' @param var A single character string.
#'
#' @return A single character string.
#'
#' @keywords internal
.pretty_var_label <- function(var) {
  if (length(var) != 1L || is.na(var)) return(var)
  switch(
    var,
    uym  = "underwriting ym",
    uyq  = "underwriting yq",
    uyh  = "underwriting yh",
    uy   = "underwriting y",
    cym  = "calendar ym",
    cyq  = "calendar yq",
    cyh  = "calendar yh",
    cy   = "calendar y",
    elap_m = "development months",
    elap_q = "development quarters",
    elap_h = "development halves",
    elap_y = "development years",
    var
  )
}


#' Safely format a period vector for plot axis labels
#'
#' @description
#' Internal helper that formats a period vector using [.format_period()]
#' when the variable name is a recognised period variable, or falls back to
#' [base::as.character()] otherwise.
#'
#' Used in axis label functions inside plot helpers to avoid errors when
#' the development variable is a plain integer rather than a date-like period.
#'
#' @param x A vector to format.
#' @param var A single character string naming the variable (e.g. `"uym"`,
#'   `"elap_m"`).
#'
#' @return A character vector of formatted labels.
#'
#' @keywords internal
.format_period_safe <- function(x, var) {
  type <- .get_period_type(var)
  if (!is.na(type)) {
    .format_period(as.Date(x), type = type, abb = TRUE)
  } else {
    as.character(x)
  }
}


#' Format one column of facet labels
#'
#' @description
#' Internal helper that formats a single column of facet label values.
#' Period-like variables (`uym`, `cym`, `uyq`, ...) are formatted via
#' [.format_period()] in abbreviated form (e.g. `"23.01"`); all
#' other variables are coerced with [as.character()].
#'
#' @param var Single column name.
#' @param x Values in that column.
#'
#' @return Character vector.
#'
#' @keywords internal
.format_facet_col <- function(var, x) {
  type <- .get_period_type(var)
  if (!is.na(type)) {
    .format_period(as.Date(x), type = type, abb = TRUE)
  } else if (inherits(x, "Date")) {
    .format_period(x, type = "month", abb = TRUE)
  } else {
    as.character(x)
  }
}


#' Combined single-line facet labeller
#'
#' @description
#' Internal helper that returns a labeller suitable for
#' `facet_wrap(..., labeller = ...)`, producing single-line strip labels
#' that combine multiple facet variables. Period-like columns are
#' formatted via [.format_facet_col()].
#'
#' With one variable, labels are returned as-is (formatted).
#' With multiple variables, labels are combined as
#' `"first (rest1, rest2, ...)"` — e.g. `"SUR (23.01)"`.
#'
#' @param vars Character vector of facet column names.
#' @param sep Separator used to join the non-first variables. Default `", "`.
#'
#' @return A labeller callable suitable for
#'   `facet_wrap(..., labeller = ...)`.
#'
#' @keywords internal
.combined_facet_labeller <- function(vars, sep = ", ") {
  vars <- unique(vars)
  if (!length(vars)) return("label_value")

  labs <- function(labels) {
    out <- Map(.format_facet_col, names(labels), labels)

    if (length(out) <= 1L) return(list(out[[1L]]))

    first <- out[[1L]]
    rest  <- do.call(paste, c(out[-1L], sep = sep))
    list(sprintf("%s (%s)", first, rest))
  }
  class(labs) <- "labeller"
  labs
}


# Recent-diagonal weight filter --------------------------------------------

#' Recent-diagonal weights for a development triangle
#'
#' @description
#' Returns a weight matrix that restricts a development triangle to its
#' most recent `recent` calendar diagonals. Cells on or after the last
#' `recent` diagonals retain their input values; earlier observed cells
#' are set to `0`. Cells that are `NA` in the input (not yet observed)
#' are left as `NA`.
#'
#' This is a standard construct for restricting chain-ladder estimation
#' to recent calendar periods when older experience is considered less
#' representative of current conditions (e.g. after a rate change or a
#' claim-handling reform).
#'
#' @section Handling of NA cells:
#' `NA` cells in the input (not yet observed) remain `NA` in the output.
#' They are semantically distinct from the `0` cells produced by the
#' recency filter, which represent observed values explicitly excluded
#' from the current weighting scheme. Callers who want both to behave
#' identically can post-process with `w[is.na(w)] <- 0`.
#'
#' @param weights A triangle-shaped numeric matrix, with origin periods
#'   as rows and development periods as columns. Unobserved future cells
#'   should be `NA`.
#' @param recent Optional positive integer: the number of most recent
#'   calendar diagonals to keep. When missing or `NULL`, `weights` is
#'   returned unchanged.
#'
#' @return A numeric matrix of the same shape as `weights`.
#'
#' @examples
#' \dontrun{
#' m <- ChainLadder::RAA
#' get_recent_weights(m)       # unchanged (no `recent` supplied)
#' get_recent_weights(m, 3)    # keep only the last 3 calendar diagonals
#' }
#'
#' @export
get_recent_weights <- function(weights, recent) {
  if (!missing(recent) && !is.null(recent)) {
    if (!is.numeric(recent) || length(recent) != 1L ||
        is.na(recent) || recent < 1L)
      stop("`recent` must be a single positive integer.", call. = FALSE)

    recent <- as.integer(recent)
    m <- nrow(weights)
    i <- m - recent + 1L
    weights[(row(weights) + col(weights) < i + 1L)] <- 0
  }
  weights
}


#' Filter a long-format table to recent calendar diagonals
#'
#' @description
#' Internal long-format analogue of [get_recent_weights()]. Returns a
#' subset of the input `data.table` containing only rows whose calendar
#' position falls within the last `recent` calendar diagonals of its
#' group.
#'
#' The matrix-form condition `row + col >= m - recent + 2` is translated
#' to the group-wise long-form condition
#' `rank(cohort) + dev - 1 > max(rank(cohort) + dev - 1) - recent`.
#'
#' @param dt A long-format development `data.table`.
#' @param recent Positive integer or `NULL`. When `NULL` or missing, `dt`
#'   is returned unchanged.
#' @param group_var Character vector of group columns (may be empty).
#' @param cohort_var Single column name for the cohort variable (e.g. `cohort`).
#' @param dev_var Single column name for the development variable (e.g. `dev`
#'   for `Triangle` objects, or `ata_from` for `ATA`/`ED` objects).
#' @param dev_min Optional numeric scalar. When supplied, the recent filter
#'   is applied only to rows where `dev_var > dev_min`; rows with
#'   `dev_var <= dev_min` are kept unconditionally (early-dev cells in the
#'   ED phase of stage-adaptive fits).
#'
#' @return A filtered copy of `dt` (class preserved), keeping only rows
#'   within the recent-diagonal window.
#'
#' @keywords internal
.apply_recent_filter <- function(dt, recent,
                                 group_var = character(0),
                                 cohort_var, dev_var, dev_min = NULL) {

  if (!data.table::is.data.table(dt))
    stop("`dt` must be a data.table.", call. = FALSE)

  if (missing(recent) || is.null(recent)) {
    return(data.table::copy(dt))
  }

  if (!is.numeric(recent) || length(recent) != 1L ||
      is.na(recent) || recent < 1L)
    stop("`recent` must be a single positive integer.", call. = FALSE)

  recent <- as.integer(recent)

  if (!is.null(dev_min)) {
    if (!is.numeric(dev_min) || length(dev_min) != 1L || is.na(dev_min))
      stop("`dev_min` must be a single non-NA numeric scalar.", call. = FALSE)
  }

  out <- data.table::copy(dt)

  # rank of cohort within group (1 = earliest), then calendar index
  out[, .coh_rank := data.table::frank(.SD[[1L]], ties.method = "dense"),
      by = group_var, .SDcols = cohort_var]
  out[, .cal_idx := .coh_rank + .SD[[1L]] - 1L,
      .SDcols = dev_var]
  out[, .max_cal := max(.cal_idx, na.rm = TRUE), by = group_var]

  if (is.null(dev_min)) {
    keep <- out[, is.finite(.cal_idx) & is.finite(.max_cal) &
                .cal_idx > .max_cal - recent]
  } else {
    keep <- out[, is.finite(.cal_idx) & is.finite(.max_cal) &
                (.cal_idx > .max_cal - recent | .SD[[1L]] <= dev_min),
                .SDcols = dev_var]
  }

  out <- out[keep]
  out[, c(".coh_rank", ".cal_idx", ".max_cal") := NULL]
  out[]
}


#' Resolve a regime-break specifier to a single Date
#'
#' @description
#' Internal helper used by [.apply_break_filter()] to coerce a heterogeneous
#' `break_date` argument (NULL, Date scalar/vector, character coercible to
#' Date, or a `Regime` object) into a single Date scalar (the latest
#' break) or `NULL`.
#'
#' @param break_date See [.apply_break_filter()].
#'
#' @return A single Date, or `NULL` when no break is specified.
#'
#' @keywords internal
.resolve_break_date <- function(break_date) {
  if (is.null(break_date)) return(NULL)
  if (inherits(break_date, "Regime")) {
    bp <- break_date$breakpoints
    if (length(bp) == 0L) return(NULL)
    return(max(bp))
  }
  d <- as.Date(break_date)
  if (length(d) == 0L) return(NULL)
  if (any(is.na(d)))
    stop("`break_date` contains NA after coercion to Date.", call. = FALSE)
  max(d)
}


#' Apply regime-break (cohort) filter to a triangle-shaped data.table
#'
#' @description
#' Drops rows where `coh_var < break_date`. Optionally restrict the filter
#' to rows with `dev_var <= dev_max` (apply only to ED-phase cells); rows
#' with `dev_var > dev_max` are kept regardless of cohort.
#'
#' @param dt A data.table.
#' @param break_date The cohort cutoff. Accepts:
#'   * `NULL` -- no filter (return copy of `dt` unchanged).
#'   * A single Date or character (coercible to Date).
#'   * A Date/character vector -- uses the latest (max) date.
#'   * A `Regime` object -- extracts the latest from `$breakpoints`.
#' @param group_var Character vector of group columns (may be empty).
#' @param cohort_var Single column name for the cohort variable.
#' @param dev_var Single column name for the development variable.
#' @param dev_max Optional numeric scalar. When supplied, the cohort filter
#'   is only applied to rows where `dev_var <= dev_max`; rows with
#'   `dev_var > dev_max` are kept regardless of cohort.
#'
#' @return A filtered copy of `dt` (class preserved).
#'
#' @keywords internal
.apply_break_filter <- function(dt, break_date,
                                group_var = character(0),
                                cohort_var, dev_var, dev_max = NULL) {

  if (!data.table::is.data.table(dt))
    stop("`dt` must be a data.table.", call. = FALSE)

  bd <- .resolve_break_date(break_date)

  if (is.null(bd)) {
    return(data.table::copy(dt))
  }

  if (!is.null(dev_max)) {
    if (!is.numeric(dev_max) || length(dev_max) != 1L || is.na(dev_max))
      stop("`dev_max` must be a single non-NA numeric scalar.", call. = FALSE)
  }

  coh_class <- class(dt[[cohort_var]])
  if (!any(coh_class %in% c("Date", "POSIXct", "POSIXt"))) {
    stop("Column `", cohort_var, "` must be of class Date or POSIXct/POSIXt.",
         call. = FALSE)
  }

  out <- data.table::copy(dt)

  if (is.null(dev_max)) {
    keep <- out[, .SD[[1L]] >= bd, .SDcols = cohort_var]
  } else {
    # Drop rows where coh < bd AND dev <= dev_max.
    # Keep if coh >= bd OR dev > dev_max.
    coh_vals <- out[[cohort_var]]
    dev_vals <- out[[dev_var]]
    keep <- (coh_vals >= bd) | (dev_vals > dev_max)
  }

  out <- out[keep]
  out[]
}
