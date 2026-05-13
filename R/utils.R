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


# Cohort axis label ------------------------------------------------------

#' Period axis label with grain qualifier
#'
#' Maps a raw period variable name (uy_m / uy_q / uy_h / uy or the
#' calendar siblings) to a heatmap-friendly label like
#' \code{"cohort (month)"}, \code{"calendar (quarter)"},
#' \code{"cohort (half-yearly)"}, \code{"calendar (yearly)"}. Falls
#' back to the bare \code{prefix} for unrecognised inputs.
#'
#' @keywords internal
.period_axis_label <- function(var, prefix = "cohort") {
  type <- .get_period_type(var)
  qualifier <- switch(type,
    month   = "month",
    quarter = "quarter",
    half    = "half-yearly",
    year    = "yearly",
    NA_character_
  )
  if (is.na(qualifier)) prefix else sprintf("%s (%s)", prefix, qualifier)
}

#' @keywords internal
.cohort_label   <- function(var) .period_axis_label(var, "cohort")
#' @keywords internal
.calendar_label <- function(var) .period_axis_label(var, "calendar")


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
#' Internal helper that maps a period variable name (e.g. `"uy_m"`, `"cy_q"`)
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
    uy_m = , cy_m = "month",
    uy_q = , cy_q = "quarter",
    uy_h = , cy_h = "half",
    uy = , cy = "year",
    NA_character_
  )
}


#' Granularity of a cohort or development variable
#'
#' Like [.get_period_type()] but also recognises the integer development-period
#' columns (`dev_m` / `dev_q` / `dev_h` / `dev_y`). Used by
#' [build_triangle()] to verify that `cohort` and `dev` share the
#' same granularity. Not used for date formatting (these dev columns
#' are integers, not Date).
#'
#' @keywords internal
.get_granularity <- function(var) {
  type <- .get_period_type(var)
  if (!is.na(type)) return(type)
  switch(
    var,
    dev_m = "month",
    dev_q = "quarter",
    dev_h = "half",
    dev_y = "year",
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
#' @param metric A single character string naming the variable to plot.
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
.get_plot_meta <- function(metric, amount_divisor = 1e8) {

  ratio_vars  <- c("lr", "lr_incr")
  amount_vars <- c("loss", "loss_incr",
                   "premium", "premium_incr",
                   "margin", "margin_incr")
  prop_vars   <- c("loss_share", "loss_incr_share",
                   "premium_share", "premium_incr_share")

  if (metric %in% ratio_vars) {
    list(
      type  = "ratio",
      title = switch(metric,
                       lr      = "Cumulative Loss Ratio",
                       lr_incr = "Per-Period Loss Ratio"
      ),
      caption = "Unit: %",
      hline   = 1
    )

  } else if (metric %in% amount_vars) {
    unit_txt <- .get_amount_unit(amount_divisor)
    list(
      type  = "amount",
      title = switch(metric,
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

  } else if (metric %in% prop_vars) {
    list(
      type  = "prop",
      title = switch(metric,
                       loss_share         = "Cumulative Loss Proportion",
                       loss_incr_share    = "Per-Period Loss Proportion",
                       premium_share      = "Cumulative Premium Proportion",
                       premium_incr_share = "Per-Period Premium Proportion"
      ),
      caption = "Unit: %",
      hline   = NULL
    )

  } else {
    stop(
      sprintf("Unknown `metric`: '%s'.", metric),
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
#' `"uy_m"`, `"dev_m"`) to a human-readable axis label (e.g.
#' `"underwriting months"`, `"development months"`). Falls back to the
#' input string when the variable is not recognised.
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
    uy_m  = "underwriting months",
    uy_q  = "underwriting quarters",
    uy_h  = "underwriting halves",
    uy  = "underwriting years",
    cy_m  = "calendar months",
    cy_q  = "calendar quarters",
    cy_h  = "calendar halves",
    cy  = "calendar years",
    dev_m = "development months",
    dev_q = "development quarters",
    dev_h = "development halves",
    dev_y = "development years",
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
#' @param var A single character string naming the variable (e.g. `"uy_m"`,
#'   `"dev_m"`).
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
#' Period-like variables (`uy_m`, `cy_m`, `uy_q`, ...) are formatted via
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
#' @param grp Character vector of group columns (may be empty).
#' @param coh Single column name for the cohort variable (e.g. `cohort`).
#' @param dev Single column name for the development variable (e.g. `dev`
#'   for `Triangle` objects, or `ata_from` for `ATA`/`ED` objects).
#' @param dev_split Optional SA-boundary specifier. Accepts:
#'   * `NULL` -- no SA boundary; the recent wedge applies to every row.
#'   * A single non-NA numeric scalar -- the maturity target dev
#'     (= `ata_to`, the first CL-region dev). The recent filter is
#'     applied only to rows where `dev >= dev_split` (CL region); rows
#'     with `dev < dev_split` (ED region) are kept unconditionally.
#'   * A `data.table` `[grp..., dev_split]` -- per-group SA boundary
#'     (different `k*` per group). The group columns must be a subset
#'     of `grp`. Each row of `dt` looks up its `dev_split` via
#'     left-join; rows whose group has no matching entry (NA after the
#'     join) are treated as if `dev_split = NULL` for that row (recent
#'     wedge applies to all dev for them).
#'
#' @return A filtered copy of `dt` (class preserved), keeping only rows
#'   within the recent-diagonal window.
#'
#' @keywords internal
.apply_recent_filter <- function(dt, recent,
                                 grp = character(0),
                                 coh, dev, dev_split = NULL) {

  if (!data.table::is.data.table(dt))
    stop("`dt` must be a data.table.", call. = FALSE)

  if (missing(recent) || is.null(recent)) {
    return(data.table::copy(dt))
  }

  if (!is.numeric(recent) || length(recent) != 1L ||
      is.na(recent) || recent < 1L)
    stop("`recent` must be a single positive integer.", call. = FALSE)

  recent <- as.integer(recent)

  # `dev_split` may be either a scalar (single ED/CL boundary applied
  # to every group) or a `[grp..., dev_split]` data.table for
  # per-group SA hybrid (m_k differs across groups).
  dev_split_is_dt <- data.table::is.data.table(dev_split)
  if (!is.null(dev_split) && !dev_split_is_dt) {
    if (!is.numeric(dev_split) || length(dev_split) != 1L || is.na(dev_split))
      stop("`dev_split` must be a single non-NA numeric scalar, ",
           "or a `[grp..., dev_split]` data.table for per-group SA hybrid.",
           call. = FALSE)
  }
  if (dev_split_is_dt) {
    if (!"dev_split" %in% names(dev_split))
      stop("per-group `dev_split` data.table must have a column named ",
           "`dev_split`.", call. = FALSE)
    ds_join_cols <- intersect(setdiff(names(dev_split), "dev_split"), grp)
    if (length(ds_join_cols) == 0L)
      stop("per-group `dev_split` data.table must share at least one ",
           "group column with `grp`.", call. = FALSE)
  }

  out <- data.table::copy(dt)

  # rank of cohort within group (1 = earliest), then calendar index
  out[, .coh_rank := data.table::frank(.SD[[1L]], ties.method = "dense"),
      by = grp, .SDcols = coh]
  out[, .cal_idx := .coh_rank + .SD[[1L]] - 1L,
      .SDcols = dev]
  out[, .max_cal := max(.cal_idx, na.rm = TRUE), by = grp]

  cal_idx <- out[[".cal_idx"]]
  max_cal <- out[[".max_cal"]]
  dev_vals <- out[[dev]]
  finite_mask <- is.finite(cal_idx) & is.finite(max_cal)

  if (is.null(dev_split)) {
    keep <- finite_mask & (cal_idx > max_cal - recent)
  } else if (dev_split_is_dt) {
    ds_vals <- dev_split[out, on = ds_join_cols, x.dev_split]
    # Group with NA dev_split: no SA boundary declared → recent wedge
    # applies to all dev (no ED carve-out for that row).
    keep <- finite_mask &
            (cal_idx > max_cal - recent |
             (!is.na(ds_vals) & dev_vals < ds_vals))
  } else {
    keep <- finite_mask &
            (cal_idx > max_cal - recent | dev_vals < dev_split)
  }

  out <- out[keep]
  out[, c(".coh_rank", ".cal_idx", ".max_cal") := NULL]
  out[]
}


#' Resolve a regime specifier to a single Date
#'
#' @description
#' Internal helper used by [.apply_regime_filter()] to coerce a
#' heterogeneous `regime` argument (NULL, Date scalar/vector,
#' character coercible to Date, or a `Regime` object) into either a
#' single Date scalar or a per-group `data.table` keyed by the
#' caller-supplied `by` columns.
#'
#' @param regime See [.apply_regime_filter()].
#' @param by Optional character vector of group columns the caller wants
#'   the break dispatched on. When `NULL` (default) or empty, the
#'   function always returns a scalar (the maximum break date),
#'   preserving the historical single-value contract. When non-empty and
#'   `regime` is a multi-group `Regime` whose `$groups` intersect
#'   `by`, returns a `data.table` with `[intersect(by, regime$groups)...,
#'   break_date]` (one row per group combo, holding `max(change)`).
#'   Otherwise falls back to scalar.
#'
#' @return One of:
#'   * `NULL` when no break is specified.
#'   * A single Date (the latest break) — the scalar path.
#'   * A `data.table` `[join_cols..., break_date]` — the per-group path.
#'
#' @keywords internal
.resolve_regime_date <- function(regime, by = NULL) {
  if (is.null(regime)) return(NULL)

  if (inherits(regime, "Regime")) {
    bp <- regime$changes

    # Per-group path: multi-group Regime + caller-supplied `by` that
    # intersects the Regime's own group columns.
    if (!is.null(by) && length(by) > 0L &&
        isTRUE(regime$multi_group) &&
        data.table::is.data.table(bp) && nrow(bp) > 0L &&
        "change" %in% names(bp)) {

      rgrp <- regime$groups
      if (is.null(rgrp)) rgrp <- character(0)
      join_cols <- intersect(by, rgrp)

      if (length(join_cols) > 0L && all(join_cols %in% names(bp))) {
        bd <- bp[, .(break_date = max(.SD[["change"]])),
                 by = join_cols, .SDcols = "change"]
        return(bd)
      }
    }

    # Scalar path
    if (data.table::is.data.table(bp)) {
      if (!nrow(bp) || !"change" %in% names(bp)) return(NULL)
      return(max(bp[["change"]]))
    }
    if (length(bp) == 0L) return(NULL)
    return(max(bp))
  }

  d <- as.Date(regime)
  if (length(d) == 0L) return(NULL)
  if (any(is.na(d)))
    stop("`regime` contains NA after coercion to Date.", call. = FALSE)
  max(d)
}


#' Apply regime-change (cohort) filter to a triangle-shaped data.table
#'
#' @description
#' Drops rows where `coh < break_date`. Optionally restrict the filter
#' to rows with `dev < dev_split` (the ED region of an SA fit); rows
#' with `dev >= dev_split` (CL region) are kept regardless of cohort.
#'
#' Supports both **scalar** dispatch (single break date applied to every
#' row) and **per-group** dispatch (different break date per group,
#' broadcast via left-join). The mode is auto-selected from
#' `regime` and `grp`: a multi-group `Regime` whose `$groups`
#' intersect `grp` triggers the per-group path. Groups in `dt` that have
#' no matching break date (NA after the left-join) are kept unfiltered.
#'
#' @param dt A data.table.
#' @param regime The cohort cutoff. Accepts:
#'   * `NULL` -- no filter (return copy of `dt` unchanged).
#'   * A single Date or character (coercible to Date).
#'   * A Date/character vector -- uses the latest (max) date.
#'   * A single-group `Regime` object -- extracts the latest from
#'     `$changes`.
#'   * A multi-group `Regime` object -- dispatches per group on the
#'     intersection of `Regime$groups` and `grp`.
#' @param grp Character vector of group columns (may be empty).
#' @param coh Single column name for the cohort variable.
#' @param dev Single column name for the development variable.
#' @param dev_split Optional numeric scalar — the maturity target dev
#'   (= `ata_to`, equivalently the first CL-region dev). When supplied,
#'   the cohort filter is only applied to rows where `dev < dev_split`
#'   (ED region); rows with `dev >= dev_split` (CL region) are kept
#'   regardless of cohort.
#'
#' @return A filtered copy of `dt` (class preserved).
#'
#' @keywords internal
.apply_regime_filter <- function(dt, regime,
                                 grp = character(0),
                                 coh, dev, dev_split = NULL) {

  if (!data.table::is.data.table(dt))
    stop("`dt` must be a data.table.", call. = FALSE)

  bd <- .resolve_regime_date(regime, by = grp)

  if (is.null(bd)) {
    return(data.table::copy(dt))
  }

  # `dev_split` may be either a scalar (single ED/CL boundary applied
  # to every group) or a `[grp..., dev_split]` data.table for
  # per-group SA hybrid (m_k differs across groups).
  dev_split_is_dt <- data.table::is.data.table(dev_split)
  if (!is.null(dev_split) && !dev_split_is_dt) {
    if (!is.numeric(dev_split) || length(dev_split) != 1L || is.na(dev_split))
      stop("`dev_split` must be a single non-NA numeric scalar, ",
           "or a `[grp..., dev_split]` data.table for per-group SA hybrid.",
           call. = FALSE)
  }
  if (dev_split_is_dt && !"dev_split" %in% names(dev_split))
    stop("per-group `dev_split` data.table must have a column named ",
         "`dev_split`.", call. = FALSE)

  coh_class <- class(dt[[coh]])
  if (!any(coh_class %in% c("Date", "POSIXct", "POSIXt"))) {
    stop("Column `", coh, "` must be of class Date or POSIXct/POSIXt.",
         call. = FALSE)
  }

  out <- data.table::copy(dt)

  if (data.table::is.data.table(bd)) {
    # Per-group path: bd is `[join_cols..., break_date]`. Look up
    # break_date row-aligned via a right outer join driven by `out`.
    join_cols <- setdiff(names(bd), "break_date")
    bd_vals <- bd[out, on = join_cols, x.break_date]

    coh_vals <- out[[coh]]
    dev_vals <- out[[dev]]
    matched  <- !is.na(bd_vals)

    if (is.null(dev_split)) {
      keep <- !matched | (coh_vals >= bd_vals)
    } else if (dev_split_is_dt) {
      ds_join_cols <- setdiff(names(dev_split), "dev_split")
      ds_vals <- dev_split[out, on = ds_join_cols, x.dev_split]
      # Group with NA dev_split: no ED region declared → cohort cut
      # applies to all dev (full filter).
      keep <- !matched | (coh_vals >= bd_vals) |
              (!is.na(ds_vals) & dev_vals >= ds_vals)
    } else {
      keep <- !matched | (coh_vals >= bd_vals) | (dev_vals >= dev_split)
    }
  } else {
    # Scalar break path (backward-compat)
    coh_vals <- out[[coh]]
    dev_vals <- out[[dev]]
    if (is.null(dev_split)) {
      keep <- coh_vals >= bd
    } else if (dev_split_is_dt) {
      ds_join_cols <- setdiff(names(dev_split), "dev_split")
      ds_vals <- dev_split[out, on = ds_join_cols, x.dev_split]
      keep <- (coh_vals >= bd) |
              (!is.na(ds_vals) & dev_vals >= ds_vals)
    } else {
      keep <- (coh_vals >= bd) | (dev_vals >= dev_split)
    }
  }

  out <- out[keep]
  out[]
}


#' Validate a column-name argument
#'
#' @description
#' Internal helper used by entry-point functions (`build_triangle`,
#' `build_link`, `fit_cl`, ...) that take column names as plain
#' character arguments (no NSE). Performs:
#'   * type check — must be a non-empty character vector
#'   * optional length-one check — for arguments expected to resolve to
#'     a single column (e.g., `cohort`, `loss`)
#'   * presence check — every name must exist in `df`'s columns
#'
#' Produces clear, argument-named error messages.
#'
#' @param arg The argument value (already extracted from the call).
#' @param arg_name The argument name as a string, used in error
#'   messages (e.g., `"loss"`, `"cohort"`).
#' @param df The data.frame/data.table the columns must be present in.
#' @param length_one If `TRUE`, the argument must have length exactly 1.
#'
#' @return Invisibly returns `arg` on success; aborts otherwise.
#'
#' @keywords internal
.assert_column_arg <- function(arg, arg_name, df, length_one = FALSE) {
  if (is.null(arg) || (is.character(arg) && length(arg) == 0L))
    stop(sprintf(
      "`%s` is required (pass a character vector of column names).",
      arg_name), call. = FALSE)
  if (!is.character(arg))
    stop(sprintf(
      "`%s` must be a character vector of column names, not <%s>.",
      arg_name, class(arg)[1L]), call. = FALSE)
  if (length_one && length(arg) != 1L)
    stop(sprintf("`%s` must be exactly one column name (got %d).",
                 arg_name, length(arg)), call. = FALSE)
  missing_cols <- setdiff(arg, names(df))
  if (length(missing_cols))
    stop(sprintf("`%s` column(s) not found in `df`: %s.",
                 arg_name,
                 paste(sprintf("'%s'", missing_cols), collapse = ", ")),
         call. = FALSE)
  invisible(arg)
}


#' Format a list of records as column-aligned strings
#'
#' @description
#' Internal helper for print methods. Takes a named list of equal-length
#' character vectors (one entry per column, vectors aligned row-wise)
#' and returns a character vector of formatted rows where each column
#' is padded to its widest value with a configurable justification.
#'
#' Useful for printing multi-record summaries (e.g., per-group regime
#' info) without manually computing widths in each `print.*` method.
#'
#' @param cols A named list of equal-length character vectors. Each
#'   entry is one column of the table; the entry's name is unused
#'   (kept for caller readability).
#' @param justify Either a single string (`"left"`, `"right"`,
#'   `"centre"`) applied to all columns, or a character vector of the
#'   same length as `cols` to set per-column justification.
#' @param sep Separator inserted between columns (default `" | "`).
#'
#' @return A character vector of length `length(cols[[1L]])`, one
#'   formatted row per record.
#'
#' @keywords internal
.format_record_table <- function(cols, justify = "left", sep = " | ") {
  if (!is.list(cols) || !length(cols))
    return(character(0))
  n <- length(cols[[1L]])
  if (n == 0L) return(character(0))

  if (length(justify) == 1L) justify <- rep(justify, length(cols))
  if (length(justify) != length(cols))
    stop("`justify` must be length 1 or length(cols).", call. = FALSE)

  formatted <- Map(function(col, just) {
    vals  <- as.character(col)
    width <- max(nchar(vals, type = "width"), 0L)
    format(vals, width = width, justify = just)
  }, cols, justify)

  do.call(paste, c(formatted, list(sep = sep)))
}


#' Assert that the input is a `Triangle`, with a helpful error for `Link`
#'
#' Internal helper used by `fit_*()` entry points. Wraps
#' [.assert_class()] but intercepts `Link` inputs first to print a
#' message that explains why a `Link` is not a valid input (build_link
#' is called internally) and how to pass the data correctly.
#'
#' @param x The object to check.
#' @param called_from A short string naming the caller, e.g.
#'   `"fit_ata()"`, used in the error message.
#'
#' @return Invisibly `NULL`. Throws an error if `x` is not a Triangle.
#'
#' @keywords internal
.assert_triangle_input <- function(x, called_from) {
  if (inherits(x, "Link")) {
    fn_bare <- sub("\\(\\)$", "", called_from)
    stop(sprintf(
      "`%s` expects a Triangle, not a Link.\n  Link is built internally; pass the Triangle directly:\n    %s(tri, target = \"loss\", ...)",
      called_from, fn_bare
    ), call. = FALSE)
  }
  .assert_class(x, "Triangle")
}
