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
.period_axis_label <- function(var, prefix = "cohort", grain = NULL) {
  type <- .get_period_type(var, grain = grain)
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
.cohort_label   <- function(var, grain = NULL) .period_axis_label(var, "cohort", grain)
#' @keywords internal
.calendar_label <- function(var, grain = NULL) .period_axis_label(var, "calendar", grain)


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
#' Falls back to a `grain` hint (M/Q/H/Y) when the variable name is not
#' one of the package-standard forms. This keeps plot formatting robust
#' to user-supplied raw column names like `"uym"`, `"elap_m"`, or
#' `"underwriting_month"`.
#'
#' Returns `NA_character_` when neither path resolves a type. Callers
#' can use that to fall back to `as.character()` formatting.
#'
#' @param var A single character string naming a period variable.
#' @param grain Optional grain code from `attr(tri, "grain")` -- one of
#'   `"M"`, `"Q"`, `"H"`, `"Y"`. Used when `var` is not recognised.
#'
#' @return One of `"month"`, `"quarter"`, `"half"`, `"year"`, or
#'   `NA_character_`.
#'
#' @keywords internal
.get_period_type <- function(var, grain = NULL) {
  type <- switch(
    var,
    uy_m = , cy_m = "month",
    uy_q = , cy_q = "quarter",
    uy_h = , cy_h = "half",
    uy = , cy = "year",
    NA_character_
  )
  if (!is.na(type)) return(type)
  if (is.null(grain) || is.na(grain)) return(NA_character_)
  switch(
    grain,
    M = "month",
    Q = "quarter",
    H = "half",
    Y = "year",
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
#' @param grain Optional grain code (`"M"`/`"Q"`/`"H"`/`"Y"`). Used when
#'   `var` is not a package-standard period name (see [.get_period_type()]).
#'
#' @return A character vector of formatted labels.
#'
#' @keywords internal
.format_period_safe <- function(x, var, grain = NULL) {
  type <- .get_period_type(var, grain = grain)
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

  # Suppress R CMD check NOTEs for `data.table` temp columns referenced
  # bare inside `j` expressions later in this function.
  .coh_rank <- .cal_idx <- NULL

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
  out[, (".coh_rank") := data.table::frank(.SD[[1L]], ties.method = "dense"),
      by = grp, .SDcols = coh]
  out[, (".cal_idx") := .coh_rank + .SD[[1L]] - 1L,
      .SDcols = dev]
  out[, (".max_cal") := max(.cal_idx, na.rm = TRUE), by = grp]

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
#'   the change date dispatched on. When `NULL` (default) or empty, the
#'   function always returns a scalar (the maximum change date),
#'   preserving the historical single-value contract. When non-empty and
#'   `regime` is a multi-group `Regime` whose `$groups` intersect
#'   `by`, returns a `data.table` with `[intersect(by, regime$groups)...,
#'   change_date]` (one row per group combo, holding `max(change)`).
#'   Otherwise falls back to scalar.
#'
#' @return One of:
#'   * `NULL` when no change date is specified.
#'   * A single Date (the latest change) — the scalar path.
#'   * A `data.table` `[join_cols..., change_date]` — the per-group path.
#'
#' @keywords internal
.resolve_regime_change_date <- function(regime, by = NULL) {
  if (is.null(regime)) return(NULL)

  if (inherits(regime, "Regime")) {
    bp <- regime$changes

    # Per-group path: dispatched whenever the Regime carries group
    # columns (`regime$groups`) that intersect the caller's `by`. We
    # honour this even when `regime$multi_group = FALSE` (e.g. the
    # user wrote `regime_at(coverage = "SUR", ...)` with a single
    # unique value) -- the explicit group column reflects intent to
    # scope the regime to just that group, not apply it globally.
    if (!is.null(by) && length(by) > 0L &&
        data.table::is.data.table(bp) && nrow(bp) > 0L &&
        "change" %in% names(bp)) {

      rgrp <- regime$groups
      if (is.null(rgrp)) rgrp <- character(0)
      join_cols <- intersect(by, rgrp)

      if (length(join_cols) > 0L && all(join_cols %in% names(bp))) {
        cd <- bp[, .(change_date = max(.SD[["change"]])),
                 by = join_cols, .SDcols = "change"]
        return(cd)
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


#' Assign each cohort to a regime segment
#'
#' @description
#' Maps a cohort vector to integer segment ids (`1, 2, ..., K+1`) given
#' a `"Regime"` object whose `$changes` carries `K` change points. A
#' cohort earlier than the first change is segment 1; between the k-th
#' and (k+1)-th change is segment k+1; on or after the K-th change is
#' segment K+1.
#'
#' Returns `rep(1L, length(coh_vals))` when `regime` is `NULL` or carries
#' no changes — every cohort is in the single (sole) segment.
#'
#' Treatment-agnostic: this helper preserves all change points regardless
#' of `regime$treatment`. Callers decide whether to use the full
#' partition (`"segment_wise"`) or collapse to the latest change
#' (`"latest_only"`).
#'
#' @param coh_vals Date vector of cohort values.
#' @param regime A `"Regime"` object or `NULL`.
#' @param grp_dt Optional `data.table` (`nrow == length(coh_vals)`)
#'   carrying the group columns named in `regime$groups`. Required when
#'   `regime` is multi-group; ignored otherwise. Each row's segment is
#'   computed against the change points for that row's group.
#'
#' @return Integer vector of segment ids, same length as `coh_vals`.
#'
#' @keywords internal
.assign_segment <- function(coh_vals, regime, grp_dt = NULL) {
  n <- length(coh_vals)
  if (n == 0L) return(integer(0))

  if (is.null(regime) || !inherits(regime, "Regime"))
    return(rep(1L, n))

  changes <- regime$changes
  if (!data.table::is.data.table(changes) || !nrow(changes) ||
      !"change" %in% names(changes))
    return(rep(1L, n))

  coh_vals <- as.Date(coh_vals)
  is_multi <- isTRUE(regime$multi_group) && length(regime$groups) > 0L

  if (!is_multi) {
    cd <- sort(as.Date(changes[["change"]]))
    return(findInterval(coh_vals, cd) + 1L)
  }

  rgrp <- regime$groups
  if (is.null(grp_dt))
    stop(".assign_segment(): multi-group Regime requires `grp_dt`.",
         call. = FALSE)
  if (!data.table::is.data.table(grp_dt))
    grp_dt <- data.table::as.data.table(grp_dt)

  missing_grp <- setdiff(rgrp, names(grp_dt))
  if (length(missing_grp))
    stop(sprintf(".assign_segment(): `grp_dt` missing group cols: %s",
                 paste(missing_grp, collapse = ", ")), call. = FALSE)
  if (nrow(grp_dt) != n)
    stop(sprintf(".assign_segment(): nrow(grp_dt) = %d, expected %d.",
                 nrow(grp_dt), n), call. = FALSE)

  work <- data.table::data.table(.idx = seq_len(n), .coh = coh_vals)
  for (g in rgrp) work[[g]] <- grp_dt[[g]]

  out <- integer(n)
  grp_keys <- unique(work[, rgrp, with = FALSE])
  for (i in seq_len(nrow(grp_keys))) {
    key  <- grp_keys[i]
    ch_g <- changes[key, on = rgrp, nomatch = NULL][["change"]]
    sub  <- work[key, on = rgrp]
    seg  <- if (length(ch_g))
              findInterval(sub$.coh, sort(as.Date(ch_g))) + 1L
            else
              rep(1L, nrow(sub))
    out[sub$.idx] <- seg
  }
  out
}


#' Apply regime-change (cohort) filter to a triangle-shaped data.table
#'
#' @description
#' Drops rows where `coh < change_date`. Optionally restrict the filter
#' to rows with `dev < dev_split` (the ED region of an SA fit); rows
#' with `dev >= dev_split` (CL region) are kept regardless of cohort.
#'
#' Supports both **scalar** dispatch (single change date applied to every
#' row) and **per-group** dispatch (different change date per group,
#' broadcast via left-join). The mode is auto-selected from
#' `regime` and `grp`: a multi-group `Regime` whose `$groups`
#' intersect `grp` triggers the per-group path. Groups in `dt` that have
#' no matching change date (NA after the left-join) are kept unfiltered.
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

  # treatment = "segment_wise": each segment uses its own mini-triangle
  # anchored at the latest cal diagonal -- for segment k with cohorts in
  # [first_k, last_k] (per group), USED cells satisfy
  # `dev >= dev_min(k) = max_cal_idx - last_cohort_rank_of_seg_k + 1`.
  # Cells outside any mini-triangle are dropped so downstream factor
  # estimation never sees them. Mini-triangle filter applies only when
  # `dt` is a `Triangle` (cohort x dev grid). For `Link` input (fit_ata
  # standalone path; cohort x ata_from edges, max_cal definition
  # differs by one), we keep the older tag-only behaviour. Cells in
  # groups not covered by the regime are preserved without a
  # `segment_id` tag either way.
  if (inherits(regime, "Regime") &&
      identical(regime$treatment, "segment_wise")) {
    out    <- .ensure_dt(dt)
    grp_dt <- if (length(grp)) out[, grp, with = FALSE] else NULL
    # `[[<-` is base-R's assignment form: it invalidates data.table's
    # `.internal.selfref` and triggers a one-shot self-fix warning on
    # the next `:=`. Use `data.table::set()` which assigns by
    # reference and keeps selfref intact.
    data.table::set(out, j = "segment_id",
                    value = .assign_segment(out[[coh]], regime, grp_dt))

    bp <- regime$changes
    apply_mini_tri <- inherits(dt, "Triangle") &&
                      data.table::is.data.table(bp) && nrow(bp) &&
                      "change" %in% names(bp)

    if (apply_mini_tri) {

      rgrp <- intersect(grp,
                        if (is.null(regime$groups)) character(0)
                        else regime$groups)

      # Per-group cohort rank + cal index. Match the convention used by
      # `.compute_triangle_usage()` so the algorithm boundary matches
      # the heatmap.
      if (length(grp)) {
        out[, ".coh_rank_seg" := data.table::frank(.SD[[1L]],
                                                   ties.method = "dense"),
            by = grp, .SDcols = coh]
      } else {
        out[, ".coh_rank_seg" := data.table::frank(.SD[[1L]],
                                                   ties.method = "dense"),
            .SDcols = coh]
      }
      out[, ".cal_idx_seg" := .coh_rank_seg + .SD[[1L]] - 1L,
          .SDcols = dev]
      if (length(grp)) {
        out[, ".max_cal_seg" := max(.cal_idx_seg, na.rm = TRUE), by = grp]
      } else {
        out[, ".max_cal_seg" := max(.cal_idx_seg, na.rm = TRUE)]
      }

      keep <- rep(TRUE, nrow(out))
      affected <- if (length(rgrp) == 0L) {
        data.table::data.table(.all = TRUE)
      } else {
        unique(bp[, rgrp, with = FALSE])
      }
      for (i in seq_len(nrow(affected))) {
        key <- if (length(rgrp) == 0L) NULL else affected[i]
        grp_mask <- if (length(rgrp) == 0L) {
          rep(TRUE, nrow(out))
        } else {
          Reduce(`&`, lapply(rgrp, function(c) out[[c]] == key[[c]]))
        }
        if (!any(grp_mask)) next

        seg_ids   <- out$segment_id[grp_mask]
        coh_ranks <- out$.coh_rank_seg[grp_mask]
        max_cal   <- out$.max_cal_seg[grp_mask]
        dev_vals  <- out[grp_mask][[dev]]
        seg_last  <- tapply(coh_ranks, seg_ids, max)
        dev_min   <- max_cal - seg_last[as.character(seg_ids)] + 1L
        keep[grp_mask] <- dev_vals >= dev_min
      }
      out <- out[keep]
      out[, c(".coh_rank_seg", ".cal_idx_seg", ".max_cal_seg") := NULL]
    }

    return(out[])
  }

  cd <- .resolve_regime_change_date(regime, by = grp)

  if (is.null(cd)) {
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

  if (data.table::is.data.table(cd)) {
    # Per-group path: cd is `[join_cols..., change_date]`. Look up
    # change_date row-aligned via a right outer join driven by `out`.
    join_cols <- setdiff(names(cd), "change_date")
    cd_vals <- cd[out, on = join_cols, x.change_date]

    coh_vals <- out[[coh]]
    dev_vals <- out[[dev]]
    matched  <- !is.na(cd_vals)

    if (is.null(dev_split)) {
      keep <- !matched | (coh_vals >= cd_vals)
    } else if (dev_split_is_dt) {
      ds_join_cols <- setdiff(names(dev_split), "dev_split")
      ds_vals <- dev_split[out, on = ds_join_cols, x.dev_split]
      # Group with NA dev_split: no ED region declared → cohort cut
      # applies to all dev (full filter).
      keep <- !matched | (coh_vals >= cd_vals) |
              (!is.na(ds_vals) & dev_vals >= ds_vals)
    } else {
      keep <- !matched | (coh_vals >= cd_vals) | (dev_vals >= dev_split)
    }
  } else {
    # Scalar change-date path (backward-compat)
    coh_vals <- out[[coh]]
    dev_vals <- out[[dev]]
    if (is.null(dev_split)) {
      keep <- coh_vals >= cd
    } else if (dev_split_is_dt) {
      ds_join_cols <- setdiff(names(dev_split), "dev_split")
      ds_vals <- dev_split[out, on = ds_join_cols, x.dev_split]
      keep <- (coh_vals >= cd) |
              (!is.na(ds_vals) & dev_vals >= ds_vals)
    } else {
      keep <- (coh_vals >= cd) | (dev_vals >= dev_split)
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
