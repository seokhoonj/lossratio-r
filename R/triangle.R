# === Triangle validation ====================================================

#' Validate triangle structure before building a development
#'
#' @description
#' Check that each `(groups, cohort)` cohort has a consecutive
#' `dev` sequence within its observed range. Non-consecutive
#' cohorts produce non-consecutive age-to-age links downstream (e.g.,
#' `14 -> 17` instead of `14 -> 15`), which breaks
#' [summary.Link()] key uniqueness and causes cartesian joins in
#' [fit_ratio()].
#'
#' This function inspects the raw data without modifying it. Use it
#' before [as_triangle()] to decide whether to fix the data source, drop
#' offending cohorts, or pass `fill_gaps = TRUE` to [as_triangle()].
#'
#' Two checks are performed:
#'
#' \enumerate{
#'   \item \strong{Cohort dev-sequence gaps} -- for each `(group, cohort)`,
#'     report missing `dev` values within the observed range.
#'   \item \strong{Row-level calendar consistency} -- when `calendar`
#'     is supplied, report rows where `calendar < cohort`. Such rows are
#'     logically impossible (claims cannot precede policy issue) and
#'     downstream they show up as negative `dev_m`, polluting cohort
#'     dev sequences.
#' }
#'
#' @param df A data.frame.
#' @param groups Grouping variable(s).
#' @param cohort A single cohort variable (raw column name).
#' @param dev A single development-period variable (raw column name).
#'   Optional when `calendar` is supplied -- `dev` is then derived from
#'   `(cohort, calendar)` at the resolved `grain` (same dispatch as
#'   [as_triangle()]).
#' @param calendar Optional calendar period variable for row-level
#'   consistency check. When supplied, rows where `calendar <
#'   cohort` are flagged as invalid. Default `NULL` (skip this check).
#' @param grain Grain string (`"M"` / `"Q"` / `"H"` / `"Y"`) or
#'   `"auto"` (default) -- used only when `dev` is derived from
#'   `(cohort, calendar)`. Ignored when `dev` is supplied.
#'
#' @return A `data.table` of class `"TriangleValidation"` with one row
#'   per cohort containing gaps. Columns:
#'   \describe{
#'     \item{groups, cohort}{Cohort identifier.}
#'     \item{`n_dev`}{Number of distinct observed `dev`
#'       values.}
#'     \item{`n_expected`}{`max(dev) - min(dev) + 1` for that cohort.}
#'     \item{`missing`}{List column of missing `dev` values.}
#'   }
#'   Returns a zero-row data.table when no gaps are found.
#'
#'   Row-level violations (when `calendar` is supplied and the check
#'   finds any) are attached as the `"invalid_rows"` attribute -- a
#'   `data.table` with columns `[groups, cohort, calendar,
#'   dev (if present), reason]`. Use `attr(out, "invalid_rows")`
#'   or rely on `print.TriangleValidation` which displays both sections.
#'
#' @seealso [as_triangle()]
#'
#' @export
validate_triangle <- function(df,
                              groups   = NULL,
                              cohort,
                              calendar = NULL,
                              dev      = NULL,
                              grain    = "auto") {
  .assert_class(df, "data.frame")
  if (missing(cohort)) stop("`cohort` is required.", call. = FALSE)
  if (is.null(calendar) && is.null(dev))
    stop("Must supply at least one of `calendar` or `dev`.",
         call. = FALSE)

  dt <- .copy_dt(df)

  if (length(groups))     .assert_column_arg(groups,   "groups",   dt)
  .assert_column_arg(cohort,          "cohort",   dt, length_one = TRUE)
  if (!is.null(calendar)) .assert_column_arg(calendar, "calendar", dt, length_one = TRUE)
  if (!is.null(dev))      .assert_column_arg(dev,      "dev",      dt, length_one = TRUE)

  grp <- groups
  coh <- cohort
  cal <- calendar

  # 1) row-level calendar consistency first -- invalid rows pollute the
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

  # 2) derive dev when only calendar is given -- mirrors as_triangle's
  #    3-mode dispatch so the same arg combo works in both functions.
  if (is.null(dev)) {
    .coerce_cols_to_date(dt_clean, c(coh, cal))
    input_grain <- .infer_grain(dt_clean[[coh]])
    g           <- .resolve_grain(input_grain, grain)
    dt_clean    <- data.table::copy(dt_clean)
    dt_clean[, (".dev_derived") := .count_periods(.SD[[1L]], .SD[[2L]], g),
             .SDcols = c(coh, cal)]
    dev_col <- ".dev_derived"
  } else {
    dev_col <- dev
  }

  # 3) dev-sequence gaps on the cleaned data
  out <- .validate_dev_continuity_impl(dt_clean, grp, coh, dev_col)

  if (!is.null(invalid) && nrow(invalid) > 0L) {
    data.table::setattr(out, "invalid_rows", invalid)
  }

  # Store input cell counts so `plot_triangle.TriangleValidation` can
  # render the full data footprint as a heatmap and optionally label
  # each cell with the row count (`show_label = TRUE`).
  # Aggregate by whatever axes the user provided: `cal` enables the
  # calendar view, `dev` enables the dev view. At least one is
  # required for plotting.
  pair_cols <- c(grp, coh,
                 if (!is.null(cal)) cal,
                 if (!is.null(dev)) dev)
  if (!is.null(cal) || !is.null(dev)) {
    obs_pairs <- dt[, .N, by = pair_cols]
    data.table::setattr(out, "observed_pairs", obs_pairs)
    if (!is.null(cal)) data.table::setattr(out, "calendar", cal)
  }

  out
}

.validate_dev_continuity_impl <- function(dt, grp, coh, dev) {
  grp_coh <- c(grp, coh)

  gaps <- dt[, {
    e <- .SD[[1L]]
    e <- e[!is.na(e)]
    if (length(e) == 0L) {
      list(dev_min = NA_integer_, dev_max = NA_integer_,
           n_dev = 0L, n_expected = 0L, missing = list(integer(0)))
    } else {
      rng  <- seq.int(min(e), max(e))
      miss <- setdiff(rng, e)
      list(
        dev_min    = as.integer(min(e)),
        dev_max    = as.integer(max(e)),
        n_dev      = length(unique(e)),
        n_expected = length(rng),
        missing    = list(miss)
      )
    }
  }, by = grp_coh, .SDcols = dev]

  gaps <- gaps[n_dev != n_expected]

  data.table::setattr(gaps, "groups" , grp)
  data.table::setattr(gaps, "cohort", coh)
  data.table::setattr(gaps, "dev"   , dev)

  .prepend_class(gaps, "TriangleValidation")
}

#' Internal: row-level cohort vs calendar consistency check
#'
#' Flag rows where `calendar < cohort` -- claims/events recorded
#' as occurring before the cohort start, which is logically impossible.
#'
#' @keywords internal
.validate_calendar_consistency_impl <- function(dt, grp, coh, dev, cal) {
  ok <- !is.na(dt[[cal]]) & !is.na(dt[[coh]])
  bad_idx <- ok & (dt[[cal]] < dt[[coh]])
  if (!any(bad_idx)) {
    return(data.table::data.table())
  }

  # `dev` may be NULL when validate_triangle is called without an
  # explicit dev column; skip duplicating coh in that case.
  keep <- unique(c(grp, coh, cal, if (!is.null(dev)) dev))
  keep <- keep[keep %in% names(dt)]
  z <- dt[bad_idx, .SD, .SDcols = keep]
  z[, ("reason") := sprintf("%s < %s", cal, coh)]
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
    cat(sprintf("Cohort dev-sequence gaps : %s cohort(s) with gaps\n",
                formatC(nrow(x), big.mark = ",", format = "d")))
    NextMethod("print", x, ...)
  }

  # invalid rows section
  inv <- attr(x, "invalid_rows", exact = TRUE)
  if (!is.null(inv) && nrow(inv) > 0L) {
    cat(sprintf("\nRow-level violations     : %s row(s) where %s\n",
                formatC(nrow(inv), big.mark = ",", format = "d"),
                inv$reason[1L]))
    print(inv, ...)
  }

  invisible(x)
}


#' Plot a TriangleValidation result
#'
#' @description
#' Visualise dev-sequence gaps. Each cohort with gaps is a row; observed
#' vs. expected dev counts render as side-by-side bars. When the
#' validation found no gaps (and no row-level violations), prints a
#' message and returns `invisible(NULL)` instead of erroring.
#'
#' @param x A `TriangleValidation` object.
#' @param ... Unused. Present for S3 compatibility.
#'
#' @return A `ggplot` object, or `invisible(NULL)` when there is nothing
#'   to visualise.
#'
#' @method plot TriangleValidation
#' @export
plot.TriangleValidation <- function(x, ...) {
  inv <- attr(x, "invalid_rows", exact = TRUE)
  has_gaps <- nrow(x) > 0L
  has_invalid <- !is.null(inv) && nrow(inv) > 0L

  if (!has_gaps && !has_invalid) {
    message("No gaps or row-level violations to plot.")
    return(invisible(NULL))
  }

  if (!has_gaps) {
    message("No dev-sequence gaps; row-level violations are stored in ",
            "attr(x, \"invalid_rows\").")
    return(invisible(NULL))
  }

  grp <- attr(x, "groups", exact = TRUE)
  coh <- attr(x, "cohort", exact = TRUE)
  if (is.null(grp)) grp <- character(0)

  dt   <- .copy_dt(x)
  long <- data.table::melt(
    dt,
    id.vars       = c(grp, coh),
    measure.vars  = c("n_dev", "n_expected"),
    variable.name = "kind",
    value.name    = "n"
  )

  p <- ggplot2::ggplot(
    long,
    ggplot2::aes(x    = factor(.data[[coh]]),
                 y    = .data[["n"]],
                 fill = .data[["kind"]])
  ) +
    ggplot2::geom_col(position = "dodge") +
    ggplot2::scale_fill_manual(
      values = c(n_dev = "#1f77b4", n_expected = "#bdbdbd"),
      name   = NULL
    ) +
    ggplot2::labs(
      title = "Cohort dev-sequence gaps",
      x     = "cohort", y = "dev count"
    ) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))

  if (length(grp))
    p <- p + ggplot2::facet_wrap(grp, scales = "free_x")
  p
}


#' Triangle-heatmap view of dev-sequence gaps
#'
#' @description
#' Visualise gap positions on a `cohort x dev` grid: for every cohort
#' with gaps, expanded dev cells are coloured by status (`observed` /
#' `missing`). Complements [plot.TriangleValidation()] (which shows
#' observed-vs-expected counts as bars) -- this heatmap shows *where*
#' the gaps are.
#'
#' When the validation found no gaps, prints a message and returns
#' `invisible(NULL)`.
#'
#' @param x A `TriangleValidation` object.
#' @param view Axis layout. One of `"calendar"` (cohort x calendar grid,
#'   default) or `"dev"` (cohort x dev grid). `"calendar"` requires the
#'   calendar column to have been supplied to [validate_triangle()];
#'   `"dev"` works when either calendar or dev was supplied.
#' @param show_label Logical; when `TRUE`, overlay each cell with the
#'   input row count (`.N`). Default `FALSE`.
#' @param theme String passed to [.switch_theme()].
#' @param ... Extra arguments passed to [.switch_theme()].
#'
#' @return A `ggplot` object, or `invisible(NULL)` when there is nothing
#'   to visualise.
#'
#' @method plot_triangle TriangleValidation
#' @export
plot_triangle.TriangleValidation <- function(x,
                                             view       = c("calendar", "dev"),
                                             show_label = FALSE,
                                             theme      = c("view", "save", "shiny"),
                                             ...) {
  # Suppress R CMD check NOTEs for `data.table` temp columns referenced
  # bare inside `j` expressions later in this function.
  .status <- .coh <- .axis <- .x_pos <- .y_pos <- NULL

  view <- match.arg(view)
  inv         <- attr(x, "invalid_rows", exact = TRUE)
  obs_pairs   <- attr(x, "observed_pairs", exact = TRUE)
  cal         <- attr(x, "calendar", exact = TRUE)
  has_gaps    <- nrow(x) > 0L
  has_invalid <- !is.null(inv) && nrow(inv) > 0L

  if (!has_gaps && !has_invalid) {
    message("No gaps or row-level violations to plot.")
    return(invisible(NULL))
  }

  theme <- match.arg(theme)

  grp <- attr(x, "groups", exact = TRUE)
  coh <- attr(x, "cohort", exact = TRUE)
  dev <- attr(x, "dev", exact = TRUE)
  if (is.null(grp)) grp <- character(0)

  if (is.null(obs_pairs)) {
    message("plot_triangle.TriangleValidation requires at least one of ",
            "`calendar` or `dev` to be supplied to `validate_triangle()`.")
    return(invisible(NULL))
  }

  has_cal <- !is.null(cal) && cal %in% names(obs_pairs)
  has_dev <- !is.null(dev) && dev %in% names(obs_pairs)

  if (view == "calendar" && !has_cal) {
    message("plot_triangle.TriangleValidation(view = \"calendar\") ",
            "requires a calendar column. Re-run `validate_triangle(..., ",
            "calendar = ...)` or use `view = \"dev\"`.")
    return(invisible(NULL))
  }
  if (view == "dev" && !has_cal && !has_dev) {
    message("plot_triangle.TriangleValidation(view = \"dev\") requires ",
            "either a calendar or a dev column on the input.")
    return(invisible(NULL))
  }

  # Pick the second-axis column for this view.
  axis_col <- if (view == "dev" && has_dev) dev else cal

  bg <- data.table::copy(obs_pairs)
  # When obs_pairs has both cal and dev, drop the unused axis and
  # re-aggregate so `bg` is keyed on (grp, coh, axis_col).
  keep <- c(grp, coh, axis_col)
  bg <- bg[, .(N = sum(N)), by = keep]
  data.table::setnames(bg, c(coh, axis_col), c(".coh", ".axis"))
  bg[, (".status") := "observed"]

  if (has_invalid) {
    if (axis_col %in% names(inv)) {
      inv_agg <- inv[, .N, by = c(grp, coh, axis_col)]
      data.table::setnames(inv_agg, c(coh, axis_col), c(".coh", ".axis"))
      inv_agg[, (".status") := "invalid"]
      # `obs_pairs` already aggregates ALL input rows (valid + invalid).
      # For cells in `inv_agg`, drop the corresponding row from `bg` so we
      # don't double-count -- invalid count comes from `inv_agg` alone.
      bg <- bg[!inv_agg, on = c(grp, ".coh", ".axis")]
      bg <- data.table::rbindlist(list(bg, inv_agg), fill = TRUE)
    }
  }

  grid <- bg
  grid[, (".status") := factor(.status, levels = c("observed", "invalid"))]

  # Common: grain inferred from cohort dates for robust formatting
  # (no `grain` attribute on TriangleValidation -- the input had no
  # standardised attributes yet).
  coh_levels <- sort(unique(grid$.coh), decreasing = TRUE)
  grain      <- .infer_grain(coh_levels)

  # Cohort axis (y): newest at top, abbreviated format derived from grain
  # so non-standard column names (e.g. `"uym"`) still format correctly.
  coh_type <- .get_period_type(coh, grain = grain)
  fmt_coh  <- function(d) {
    if (!is.na(coh_type)) .format_period(d, type = coh_type, abb = TRUE)
    else as.character(d)
  }
  grid[, (".y") := factor(fmt_coh(.coh), levels = fmt_coh(coh_levels))]

  if (view == "dev") {
    if (axis_col == cal) {
      grid[, (".x") := .count_periods(.coh, .axis, grain)]
    } else {
      grid[, (".x") := as.integer(.axis)]
    }
    n_cohorts <- length(coh_levels)

    title <- "TriangleValidation: cohort x dev"
    if (has_invalid)
      title <- paste0(title, sprintf(" (%s invalid row(s))",
                                     formatC(nrow(inv), big.mark = ",",
                                             format = "d")))

    p <- ggplot2::ggplot(
      grid,
      ggplot2::aes(x = .data[[".x"]], y = .data[[".y"]],
                   fill = .data[[".status"]])
    ) +
      ggplot2::geom_tile(color = "black", linewidth = 0.3) +
      # Boundary at dev = 0.5 (between invalid dev<=0 and valid dev>=1)
      ggplot2::geom_vline(xintercept = 0.5,
                          color = "black", linewidth = 0.7) +
      ggplot2::scale_fill_manual(
        values = c(observed = "#1f77b4", invalid = "#d62728"),
        name   = NULL, drop = FALSE
      ) +
      ggplot2::scale_x_continuous(expand = c(0, 0)) +
      ggplot2::scale_y_discrete(expand = c(0, 0)) +
      ggplot2::labs(
        title   = title,
        x       = "dev (1 = first observed period; <=0 = invalid)",
        y       = .cohort_label(coh, grain = grain),
        caption = "Blue = observed (dev >= 1), red = invalid (dev <= 0); blanks = gap"
      )
  } else {
    # view == "calendar"
    title <- "TriangleValidation: cohort x calendar"
    if (has_invalid)
      title <- paste0(title, sprintf(" (%s invalid row(s))",
                                     formatC(nrow(inv), big.mark = ",",
                                             format = "d")))

    # Cell-edge staircase: trace cal == coh boundary on cell corners.
    asc_coh  <- sort(unique(grid$.coh))
    n_coh    <- length(asc_coh)
    coh_pos  <- match(format(asc_coh), format(coh_levels))
    diffs    <- diff(asc_coh)
    spacing  <- if (length(diffs)) as.numeric(stats::median(diffs)) else 30
    half_off <- spacing / 2
    xs <- numeric(0)
    ys <- numeric(0)
    for (i in seq_len(n_coh)) {
      c_i <- asc_coh[i] - half_off
      p_i <- coh_pos[i]
      xs <- c(xs, c_i, c_i)
      ys <- c(ys, p_i + 0.5, p_i - 0.5)
      if (i < n_coh) {
        xs <- c(xs, asc_coh[i + 1L] - half_off)
        ys <- c(ys, p_i - 0.5)
      }
    }
    diag_path <- data.frame(.x = as.Date(xs, origin = "1970-01-01"),
                            .y_pos = ys)

    # Convert calendar to factor so tiles get uniform unit width
    # (matches `ggshort::ggheatmap`/`ggtable` behaviour). Date axis
    # would otherwise leak thin white gaps from 28/30/31-day month
    # lengths.
    cal_levels <- sort(unique(grid$.axis))
    grid[, (".cal_lab") := factor(fmt_coh(.axis), levels = fmt_coh(cal_levels))]
    cal_pos <- match(format(asc_coh), format(cal_levels))
    # Re-build staircase corners in factor-index x coordinates.
    xs2 <- numeric(0)
    ys2 <- numeric(0)
    for (i in seq_len(n_coh)) {
      p_i <- coh_pos[i]
      x_i <- cal_pos[i] - 0.5
      xs2 <- c(xs2, x_i, x_i)
      ys2 <- c(ys2, p_i + 0.5, p_i - 0.5)
      if (i < n_coh) {
        xs2 <- c(xs2, cal_pos[i + 1L] - 0.5)
        ys2 <- c(ys2, p_i - 0.5)
      }
    }
    diag_path <- data.frame(.x_pos = xs2, .y_pos = ys2)

    p <- ggplot2::ggplot(
      grid,
      ggplot2::aes(x = .data[[".cal_lab"]], y = .data[[".y"]],
                   fill = .data[[".status"]])
    ) +
      ggplot2::geom_tile(color = "black", linewidth = 0.3) +
      ggplot2::geom_path(
        data        = diag_path,
        mapping     = ggplot2::aes(x = .x_pos, y = .y_pos),
        color       = "black", linewidth = 0.7,
        inherit.aes = FALSE
      ) +
      ggplot2::scale_fill_manual(
        values = c(observed = "#1f77b4", invalid = "#d62728"),
        name   = NULL, drop = FALSE
      ) +
      ggplot2::scale_x_discrete(expand = c(0, 0)) +
      ggplot2::scale_y_discrete(expand = c(0, 0)) +
      ggplot2::labs(
        title   = title,
        x       = .calendar_label(cal, grain = grain),
        y       = .cohort_label(coh, grain = grain),
        caption = "Blue = observed (cal >= coh), red = invalid (cal < coh); blanks = gap"
      )
  }

  if (isTRUE(show_label)) {
    p <- p + ggplot2::geom_text(
      ggplot2::aes(label = formatC(N, big.mark = ",", format = "d")),
      color = "white", size = 2.8
    )
  }

  if (length(grp))
    p <- p + ggplot2::facet_wrap(grp)

  p + .switch_theme(theme = theme, ...)
}


# === Triangle ===============================================================

#' Coerce experience data to a Triangle object
#'
#' @description
#' Validate raw experience data, aggregate it onto a `(group, cohort,
#' dev)` grid, and assign the `Triangle` S3 class so the downstream
#' methods (`fit_ratio()`, `fit_loss()`, `backtest()`, `plot()`,
#' `plot_triangle()`, `detect_maturity()`, `detect_regime()`,
#' `detect_convergence()`, ...) can dispatch on the result.
#'
#' Three steps happen inside this single call:
#'
#' \enumerate{
#'   \item **Validate** -- required columns are present, dates coerce
#'     cleanly, the grain is consistent. Hard errors on schema issues
#'     so downstream code never receives malformed input.
#'   \item **Standardise + aggregate** -- rename to package-canonical
#'     column names (`cohort`, `calendar`, `dev`, `loss`, `exposure`,
#'     ...), auto-detect grain (`M` / `Q` / `H` / `Y`) from `cohort`
#'     spacing, derive `dev` from `(cohort, calendar)`, aggregate to
#'     `(group, cohort, dev)`, and enrich with cumulative / share /
#'     LR columns.
#'   \item **Tag** -- set S3 class
#'     `c("Triangle", "data.table", "data.frame")` so every
#'     `*.Triangle` method becomes available.
#' }
#'
#' lossratio's `Triangle` is a `data.table` in **long format** (one
#' row per `(group, cohort, dev)` cell) with the enriched columns
#' described above. The name `Triangle` refers to the conceptual
#' cohort x dev triangular region -- older cohorts have more observed
#' dev cells than newer ones -- not to a matrix layout.
#'
#' The auto-grain detection (`grain = "auto"`, default) reads `cohort`
#' value spacing; explicit values must be at least as coarse as the
#' input grain. The user does not pre-bin data or supply a `dev_*`
#' column.
#'
#' The result contains:
#' - cumulative loss and cumulative premium,
#' - per-period and cumulative proportions,
#' - per-period and cumulative margin,
#' - profit indicators,
#' - per-period loss ratio (`incr_ratio = incr_loss / incr_exposure`) and
#'   cumulative loss ratio (`ratio = loss / exposure`).
#'
#' The cumulative loss ratio is defined as:
#' \deqn{ratio = loss / exposure}
#'
#' For long-term health insurance applications, risk premium is commonly
#' used as the `exposure` measure.
#'
#' Proportion variables are computed within each `(cohort, dev)` cell:
#' \itemize{
#'   \item `incr_loss_share     = incr_loss     / sum(incr_loss)`
#'   \item `incr_exposure_share = incr_exposure / sum(incr_exposure)`
#'   \item `loss_share          = loss          / sum(loss)`
#'   \item `exposure_share      = exposure      / sum(exposure)`
#' }
#'
#' Therefore, for a fixed `(cohort, dev)` cell, the proportions
#' sum to 1 across groups. These are useful for examining the composition of
#' each development cell across products or other grouping variables.
#'
#' @param df A data.frame containing experience data with per-period loss and
#'   exposure columns plus `cohort` and `calendar` Date columns
#'   (or any input that the internal Date coercion accepts: Date, POSIXt,
#'   integer `yyyy` / `yyyymm` / `yyyymmdd`, ISO string).
#' @param groups Column(s) used for grouping (e.g., product, gender).
#' @param cohort Single column (raw name) defining the underwriting /
#'   exposure period start (e.g., `"uy_m"`).
#' @param calendar Single column (raw name) defining the calendar period of
#'   the observation (e.g., `"cy_m"`). Optional -- supply either `calendar`
#'   or `dev` (or both). When `calendar` is given, `dev` is derived
#'   internally via `count_periods(cohort, calendar, grain)`.
#' @param dev Single column (raw name) holding pre-computed
#'   development periods (e.g., `"dev_m"`). Optional -- supply either
#'   `calendar` or `dev` (or both). When only `dev` is
#'   given, the calendar axis is omitted from the attribute (downstream
#'   calendar-diagonal logic uses cohort + dev). When both are given,
#'   `dev` is cross-checked against
#'   `count_periods(cohort, calendar, grain)`.
#' @param loss Single character; per-period loss column in `df`
#'   (raw name, e.g., `"incr_loss"`).
#' @param exposure Single character; per-period exposure column in `df`
#'   (raw name, e.g., `"incr_exposure"`). Exposure measure used as
#'   denominator for loss ratio calculations. For long-term health
#'   insurance applications, risk premium is commonly used.
#' @param grain One of `"auto"` (default), `"M"`, `"Q"`, `"H"`, `"Y"`.
#'   `"auto"` infers the grain from the `cohort` value spacing.
#'   Explicit values must be at least as coarse as the input grain;
#'   the input is binned (floored) to that grain before aggregation.
#' @param cell_type One of `"incremental"` (default) or `"cumulative"`.
#'   Whether `loss` and `exposure` in `df` already hold per-period
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
#'     \item{n_cohorts}{Number of distinct cohorts observed}
#'     \item{loss, incr_loss}{Cumulative and per-period loss}
#'     \item{exposure, incr_exposure}{Cumulative and per-period exposure}
#'     \item{ratio, incr_ratio}{Cumulative and per-period loss ratio}
#'     \item{margin, incr_margin}{Cumulative and per-period margin
#'       (`exposure - loss`)}
#'     \item{profit, incr_profit}{Profit indicator (factor `"pos"` / `"neg"`)}
#'     \item{loss_share, incr_loss_share}{Cumulative and per-period proportions
#'       of loss within each `(cohort, dev)` cell}
#'     \item{exposure_share, incr_exposure_share}{Cumulative and per-period
#'       proportions of exposure within each `(cohort, dev)` cell}
#'   }
#'
#' Attributes set on the returned object: `groups`, `cohort`,
#' `calendar`, `grain`, `dev` (= `"dev_<lower(grain)>"`, e.g.
#' `"dev_m"`), `loss`, `exposure`, `longer`.
#'
#' @examples
#' \dontrun{
#' df <- data.frame(
#'   pd_cd         = rep(c("P001", "P002"), each = 6),
#'   pd_nm         = rep(c("cancer", "health"), each = 6),
#'   uy_m          = rep(as.Date(c("2023-01-01", "2023-02-01", "2023-03-01")), 4),
#'   cy_m          = rep(as.Date(c("2023-01-01", "2023-02-01")), 6),
#'   incr_loss     = runif(12, 80, 120),
#'   incr_exposure = runif(12, 90, 110)
#' )
#'
#' # auto-detected monthly grain
#' res_m <- as_triangle(
#'   df,
#'   groups   = "pd_cd",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "incr_loss",
#'   exposure = "incr_exposure"
#' )
#'
#' # explicit quarterly view (re-bins monthly input to quarterly)
#' res_q <- as_triangle(
#'   df,
#'   groups   = "pd_cd",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "incr_loss",
#'   exposure = "incr_exposure",
#'   grain    = "Q"
#' )
#'
#' head(res_m)
#' attr(res_m, "longer")
#' }
#'
#' @export
as_triangle <- function(df,
                        groups    = NULL,
                        cohort,
                        calendar  = NULL,
                        dev       = NULL,
                        loss,
                        exposure,
                        grain     = "auto",
                        cell_type = c("incremental", "cumulative"),
                        fill_gaps = FALSE) {
  .assert_class(df, "data.frame")
  cell_type <- match.arg(cell_type)

  if (missing(cohort))   stop("`cohort` is required.",   call. = FALSE)
  if (missing(loss))     stop("`loss` is required.",     call. = FALSE)
  if (missing(exposure))
    stop("`exposure` is required -- lossratio is a loss-ratio package ",
         "(ratio = loss / exposure).\n",
         "For loss-only triangles, add a constant column before calling ",
         "as_triangle():\n",
         "    df$exposure <- 1\n",
         "Loss ratio will equal loss in that case (interpretation: scaled loss).",
         call. = FALSE)

  if (!is.logical(fill_gaps) || length(fill_gaps) != 1L || is.na(fill_gaps))
    stop("`fill_gaps` must be a single non-missing logical value.",
         call. = FALSE)

  if (is.null(calendar) && is.null(dev))
    stop("Must supply at least one of `calendar` or `dev`.",
         call. = FALSE)

  dt <- .copy_dt(df)

  if (length(groups)) .assert_column_arg(groups, "groups", dt)
  .assert_column_arg(cohort,   "cohort",   dt, length_one = TRUE)
  .assert_column_arg(loss,     "loss",     dt, length_one = TRUE)
  .assert_column_arg(exposure, "exposure", dt, length_one = TRUE)
  if (!is.null(calendar))
    .assert_column_arg(calendar, "calendar", dt, length_one = TRUE)
  if (!is.null(dev))
    .assert_column_arg(dev,      "dev",      dt, length_one = TRUE)

  # Capture full-word args into short internal vars (CLAUDE.md naming
  # convention: input boundary is full English, internal vars are short).
  grp <- groups
  coh <- cohort
  cal <- calendar

  # coerce cohort (and calendar if present) to Date
  .coerce_cols_to_date(dt, coh)
  if (!is.null(cal)) .coerce_cols_to_date(dt, cal)
  data.table::set(dt, j = loss,     value = as.numeric(dt[[loss]]))
  data.table::set(dt, j = exposure, value = as.numeric(dt[[exposure]]))

  # If input cells are cumulative, derive incremental via per-cohort diff
  # at INPUT grain (before binning). Sort key prefers calendar when present
  # else falls back to dev (both monotone within cohort).
  if (cell_type == "cumulative") {
    sort_axis <- if (!is.null(cal)) cal else dev
    data.table::setorderv(dt, c(grp, coh, sort_axis))
    dt[, (loss)     := .SD[[1L]] - data.table::shift(.SD[[1L]], fill = 0),
       by = c(grp, coh), .SDcols = loss]
    dt[, (exposure) := .SD[[1L]] - data.table::shift(.SD[[1L]], fill = 0),
       by = c(grp, coh), .SDcols = exposure]
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
  if (!is.null(cal) && !is.null(dev)) {
    computed_dev <- .count_periods(dt[[coh]], dt[[cal]], grain)
    given_dev    <- as.integer(dt[[dev]])
    mismatch <- !is.na(computed_dev) & !is.na(given_dev) &
                computed_dev != given_dev
    if (any(mismatch))
      stop(sprintf(
        "`dev` is inconsistent with `cohort` + `calendar` (grain `%s`) in %d row(s).",
        grain, sum(mismatch)), call. = FALSE)
    dt[, ("dev") := given_dev]
    if (dev != "dev") dt[, (dev) := NULL]
  } else if (!is.null(cal)) {
    dt[, ("dev") := .count_periods(.SD[[1L]], .SD[[2L]], grain),
       .SDcols = c(coh, cal)]
  } else {
    # NSE-safe: when user passes `dev = "dev"` (column is also named
    # "dev"), reading `dt[[dev]]` inside the j-expression resolves
    # `dev` to the column's factor values instead of the local character.
    # `.SDcols = dev` captures the source column first; LHS then overwrites.
    dt[, ("dev") := as.integer(.SD[[1L]]), .SDcols = dev]
    if (dev != "dev") dt[, (dev) := NULL]
  }

  # standardize column names: user's loss / exposure -> standard
  # slot names incr_loss / incr_exposure; cohort -> cohort.
  data.table::setnames(
    dt,
    c(coh, loss, exposure),
    c("cohort", "incr_loss", "incr_exposure")
  )

  grp_coh     <- c(grp, "cohort")
  grp_dev     <- c(grp, "dev")
  grp_coh_dev <- c(grp, "cohort", "dev")
  coh_dev     <- c("cohort", "dev")

  incr_vars <- c("incr_loss", "incr_exposure")
  cum_vars  <- c("loss",      "exposure")

  # count observed cohorts per (grp, dev)
  dn <- dt[, .(n_cohorts = data.table::uniqueN(cohort)),
           by = grp_dev]

  # aggregate per-period values per (grp, cohort, dev)
  ds <- dt[, lapply(.SD, sum),
           by = grp_coh_dev, .SDcols = incr_vars]

  # validate / fill dev gaps per (grp, cohort). Downstream
  # as_link / fit_* require consecutive (k, k+1) transitions per
  # cohort; non-consecutive dev produces duplicate (grp, ata_from)
  # keys in summary tables and cartesian joins in fit_ratio.
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
          "Call `validate_triangle()` to inspect; `plot_triangle(validate_triangle(...))` to visualise; or pass `fill_gaps = TRUE` to zero-fill.",
          paste(utils::capture.output(print(head(gaps, 5L))), collapse = "\n")
        ),
        call. = FALSE
      )
    }
  }

  # join n_cohorts
  n_cohorts <- i.n_cohorts <- NULL
  ds[dn, on = grp_dev, ("n_cohorts") := i.n_cohorts]
  data.table::setcolorder(ds, "n_cohorts", before = "cohort")

  # cumulative values: cumsum of per-period within each (grp, cohort)
  ds[, (cum_vars) := lapply(.SD, cumsum),
     by = grp_coh, .SDcols = incr_vars]

  # margin (cumulative + per-period)
  data.table::set(ds, j = "margin",
                  value = ds[["exposure"]] - ds[["loss"]])
  data.table::set(ds, j = "incr_margin",
                  value = ds[["incr_exposure"]] - ds[["incr_loss"]])

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
    j     = "incr_profit",
    value = factor(
      ifelse(ds[["incr_margin"]] >= 0, "pos", "neg"),
      levels = c("pos", "neg")
    )
  )

  # loss ratios (cumulative + per-period)
  data.table::set(ds, j = "ratio",
                  value = ds[["loss"]] / ds[["exposure"]])
  data.table::set(ds, j = "incr_ratio",
                  value = ds[["incr_loss"]] / ds[["incr_exposure"]])

  # proportions within each (cohort, dev) cell
  ds[, ("loss_share")          := loss          / sum(loss),          by = coh_dev]
  ds[, ("incr_loss_share")     := incr_loss     / sum(incr_loss),     by = coh_dev]
  ds[, ("exposure_share")      := exposure      / sum(exposure),      by = coh_dev]
  ds[, ("incr_exposure_share") := incr_exposure / sum(incr_exposure), by = coh_dev]

  # final column order: cum-first paired
  out_cols <- c(
    grp, "n_cohorts", "cohort", "dev",
    "loss", "incr_loss", "exposure", "incr_exposure",
    "ratio", "incr_ratio",
    "margin", "incr_margin", "profit", "incr_profit",
    "loss_share", "incr_loss_share", "exposure_share", "incr_exposure_share"
  )
  data.table::setcolorder(ds, intersect(out_cols, names(ds)))

  # long format
  dm <- data.table::melt(
    data         = ds,
    id.vars      = grp_coh_dev,
    measure.vars = c("loss", "exposure")
  )
  dm <- .prepend_class(dm, "TriangleLonger")

  data.table::setattr(ds, "groups"  , grp)
  data.table::setattr(ds, "cohort"  , coh)
  data.table::setattr(ds, "calendar", cal)
  data.table::setattr(ds, "grain"   , grain)
  data.table::setattr(ds, "dev"     , paste0("dev_", tolower(grain)))
  data.table::setattr(ds, "loss"    , loss)
  data.table::setattr(ds, "exposure", exposure)
  data.table::setattr(ds, "longer"  , dm)

  .update_class(ds, prepend = "Triangle")
}

#' Summarise development statistics (Mean, Median, Weighted)
#'
#' @description
#' S3 method for `summary()` on `Triangle` objects. Computes group-wise summary
#' statistics for cumulative loss ratios (`ratio`) and per-period loss ratios
#' (`incr_ratio`).
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
#'   \item `ratio_wt      = sum(loss)      / sum(exposure)`
#'   \item `incr_ratio_wt = sum(incr_loss) / sum(incr_exposure)`
#' }
#'
#' These correspond to portfolio-level loss ratios based on exposure and
#' are typically more stable than simple averages when exposure sizes differ
#' across cohorts.
#'
#' It is assumed that the input `Triangle` object does not contain missing values.
#'
#' @return
#' A `data.table` grouped by `groups` and `dev`, containing:
#' \describe{
#'   \item{n_cohorts}{Number of observations in the cell}
#'   \item{ratio_mean}{Mean of cumulative loss ratios}
#'   \item{ratio_median}{Median of cumulative loss ratios}
#'   \item{ratio_wt}{Weighted cumulative loss ratio (`sum(loss) / sum(exposure)`)}
#'   \item{incr_ratio_mean}{Mean of per-period loss ratios}
#'   \item{incr_ratio_median}{Median of per-period loss ratios}
#'   \item{incr_ratio_wt}{Weighted per-period loss ratio
#'     (`sum(incr_loss) / sum(incr_exposure)`)}
#' }
#'
#' The returned object keeps the attributes `groups` and `dev`,
#' and its class is updated to `"TriangleSummary"`.
#'
#' @examples
#' \dontrun{
#' d <- as_triangle(
#'   df,
#'   groups   = "coverage",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "incr_loss",
#'   exposure = "incr_exposure"
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

  dt <- .copy_dt(object)

  grp     <- attr(dt, "groups")
  dev     <- attr(dt, "dev")
  grp_dev <- c(grp, "dev")

  ds <- dt[, .(
    n_cohorts         = .N,
    ratio_mean        = mean(ratio),
    ratio_median      = median(ratio),
    ratio_wt          = sum(loss)      / sum(exposure),
    incr_ratio_mean   = mean(incr_ratio),
    incr_ratio_median = median(incr_ratio),
    incr_ratio_wt     = sum(incr_loss) / sum(incr_exposure)
  ), keyby = grp_dev]

  dm <- data.table::melt(
    data         = ds,
    id.vars      = grp_dev,
    measure.vars = c(
      "ratio_mean"     , "ratio_median"     , "ratio_wt",
      "incr_ratio_mean", "incr_ratio_median", "incr_ratio_wt"
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

#' Coerce experience data to a Calendar object
#'
#' @description
#' Validate raw experience data, aggregate it along a single
#' calendar-period axis, and assign the `Calendar` S3 class so the
#' associated `plot.Calendar()` / `summary.Calendar()` / longer-form
#' methods dispatch on the result.
#'
#' Compared with [as_triangle()], which builds a *two-dimensional*
#' `cohort x dev` structure, `as_calendar()` is *one-dimensional*: a
#' single calendar-period time series (per group) showing how the
#' portfolio evolves through time, regardless of cohort membership.
#'
#' The result is a long-format `data.table` with class
#' `c("Calendar", "data.table", "data.frame")` containing cumulative
#' loss / premium, incremental and cumulative LR, margin, profit, and
#' share columns within each `calendar` cell.
#'
#' The cumulative loss ratio is defined as:
#' \deqn{ratio = loss / exposure}
#'
#' For long-term health insurance applications, risk premium is commonly
#' used as the `exposure` measure.
#'
#' Proportion variables are computed within each `calendar` cell:
#' \itemize{
#'   \item `incr_loss_share     = incr_loss     / sum(incr_loss)`
#'   \item `incr_exposure_share = incr_exposure / sum(incr_exposure)`
#'   \item `loss_share          = loss          / sum(loss)`
#'   \item `exposure_share      = exposure      / sum(exposure)`
#' }
#'
#' Therefore, for a fixed `calendar` cell, the proportions
#' sum to 1 across groups. These are useful for examining the composition of
#' each calendar period across products or other grouping variables.
#'
#' Calendar derives `calendar = cohort + (dev - 1)` using the
#' Triangle's `grain` attribute and aggregates the incremental
#' `loss` / `exposure` columns by `(groups, calendar)`. This works for
#' Triangles built in either mode (with or without an original
#' `calendar` column in the raw experience), since `cohort + dev` is
#' always sufficient to reconstruct the calendar axis at the
#' Triangle's grain.
#'
#' @param x A `Triangle` object (typically from [as_triangle()]).
#'
#' @return A data.frame with class `"Calendar"`, containing the following
#'   derived columns:
#'   \describe{
#'     \item{cal_idx}{Sequential calendar-period index within each group
#'       (`1, 2, ..., N`). Time-series convention; intentionally NOT
#'       `dev` -- in a Calendar the integer is just the rank of the date
#'       within its group, not a true development period (`cym - uym`).
#'       Useful for aligning groups with different starting periods on a
#'       common index scale.}
#'     \item{loss, incr_loss}{Cumulative and per-period loss}
#'     \item{exposure, incr_exposure}{Cumulative and per-period exposure}
#'     \item{ratio, incr_ratio}{Cumulative and per-period loss ratio}
#'     \item{margin, incr_margin}{Cumulative and per-period margin}
#'     \item{profit, incr_profit}{Profit indicator}
#'     \item{loss_share, incr_loss_share, exposure_share, incr_exposure_share}{
#'       Proportions within each `calendar` cell}
#'   }
#'
#' The returned object also has an attribute `"longer"` containing
#' a melted long-format version (`class = "CalendarLonger"`).
#'
#' @examples
#' \dontrun{
#' tri <- as_triangle(
#'   experience,
#'   groups   = "coverage",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "incr_loss",
#'   exposure = "incr_exposure"
#' )
#'
#' cal <- as_calendar(tri)
#' head(cal)
#' attr(cal, "longer")
#' }
#'
#' @export
as_calendar <- function(x) {
  # data.table NSE NULL bindings for bare column refs in `j` below.
  cohort <- dev <- loss <- incr_loss <- exposure <- incr_exposure <- NULL
  calendar <- NULL

  .assert_class(x, "Triangle")

  grp <- attr(x, "groups");   if (is.null(grp))  grp <- character(0)
  grain <- attr(x, "grain")
  if (is.null(grain) || !nzchar(grain))
    stop("Triangle missing `grain` attribute -- cannot derive calendar.",
         call. = FALSE)

  dt <- .copy_dt(x)

  # Synthesize `calendar = cohort + (dev - 1) * grain_step` (Date column).
  data.table::set(dt, j = "calendar",
                  value = .add_periods(dt[["cohort"]], dt[["dev"]], grain))

  grp_cal   <- c(grp, "calendar")
  incr_vars <- c("incr_loss", "incr_exposure")
  cum_vars  <- c("loss",      "exposure")

  # Aggregate Triangle's incrementals to (groups, calendar). Also carry
  # `n_cohorts` -- how many distinct cohorts contributed to each
  # calendar diagonal cell (lower calendars: 1 cohort; later calendars:
  # progressively more, up to the triangle's full cohort count).
  cohort <- NULL  # NSE binding for bare ref in agg expression below
  ds <- dt[, c(
            list(n_cohorts = data.table::uniqueN(cohort)),
            lapply(.SD, sum)
          ),
          by = grp_cal, .SDcols = incr_vars]

  data.table::setorderv(ds, c(grp, "calendar"))

  # Sequential calendar-period index per group. Named `t` (time-series
  # convention) rather than `dev`: in a Calendar object the integer is
  # just the rank of the date within its group, NOT a true development
  # period (`cym - uym`). The `dev` name lives only on Triangle.
  if (length(grp)) {
    ds[, ("cal_idx") := seq_len(.N), by = grp]
  } else {
    ds[, ("cal_idx") := seq_len(.N)]
  }

  data.table::setcolorder(ds, "cal_idx", after = "calendar")

  # cumulative values
  if (length(grp)) {
    ds[, (cum_vars) := lapply(.SD, cumsum),
       by = grp, .SDcols = incr_vars]
  } else {
    ds[, (cum_vars) := lapply(.SD, cumsum), .SDcols = incr_vars]
  }

  # margin
  data.table::set(ds, j = "margin",
                  value = ds[["exposure"]] - ds[["loss"]])
  data.table::set(ds, j = "incr_margin",
                  value = ds[["incr_exposure"]] - ds[["incr_loss"]])

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
    j     = "incr_profit",
    value = factor(
      ifelse(ds[["incr_margin"]] >= 0, "pos", "neg"),
      levels = c("pos", "neg")
    )
  )

  # loss ratios
  data.table::set(ds, j = "ratio",
                  value = ds[["loss"]] / ds[["exposure"]])
  data.table::set(ds, j = "incr_ratio",
                  value = ds[["incr_loss"]] / ds[["incr_exposure"]])

  # proportions within each calendar cell
  ds[, ("loss_share")          := loss          / sum(loss),          by = "calendar"]
  ds[, ("incr_loss_share")     := incr_loss     / sum(incr_loss),     by = "calendar"]
  ds[, ("exposure_share")      := exposure      / sum(exposure),      by = "calendar"]
  ds[, ("incr_exposure_share") := incr_exposure / sum(incr_exposure), by = "calendar"]

  # final column order: cum-first paired
  out_cols <- c(
    grp, "calendar", "cal_idx", "n_cohorts",
    "loss", "incr_loss", "exposure", "incr_exposure",
    "ratio", "incr_ratio",
    "margin", "incr_margin", "profit", "incr_profit",
    "loss_share", "incr_loss_share", "exposure_share", "incr_exposure_share"
  )
  data.table::setcolorder(ds, intersect(out_cols, names(ds)))

  # long format
  dm <- data.table::melt(
    data         = ds,
    id.vars      = c(grp_cal, "cal_idx"),
    measure.vars = c("loss", "exposure")
  )
  dm <- .prepend_class(dm, "CalendarLonger")

  data.table::setattr(ds, "groups",   grp)
  data.table::setattr(ds, "calendar", attr(x, "calendar"))
  data.table::setattr(ds, "grain",    grain)
  data.table::setattr(ds, "loss",     attr(x, "loss"))
  data.table::setattr(ds, "exposure", attr(x, "exposure"))
  data.table::setattr(ds, "longer",   dm)

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
      return(list(n_dev = 0L, n_expected = 0L,
                  missing = list(as.Date(integer(0)))))
    }
    exp_seq <- seq(min(p), max(p), by = step)
    miss    <- setdiff(exp_seq, p)
    list(
      n_dev      = length(p),
      n_expected = length(exp_seq),
      missing    = list(as.Date(miss, origin = "1970-01-01"))
    )
  }

  if (length(grp)) {
    gaps <- dt[, .row(.SD[[1L]]), by = grp, .SDcols = cal]
  } else {
    r <- .row(dt[[cal]])
    gaps <- data.table::data.table(
      n_dev      = r$n_dev,
      n_expected = r$n_expected,
      missing    = r$missing
    )
  }

  gaps <- gaps[n_dev != n_expected]

  data.table::setattr(gaps, "groups" , grp)
  data.table::setattr(gaps, "cohort", cal)

  .prepend_class(gaps, "CalendarValidation")
}

#' Summarise calendar-development statistics (Mean, Median, Weighted)
#'
#' @description
#' S3 method for `summary()` on `Calendar` objects. Computes
#' calendar-period summary statistics for cumulative loss ratios (`ratio`)
#' and per-period loss ratios (`incr_ratio`).
#'
#' Where [summary.Triangle()] aggregates by `(groups, dev)` (cohort
#' x development), this method aggregates by `(groups, calendar)`
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
#'   \item{n_cohorts}{Number of observations in the cell.}
#'   \item{ratio_mean}{Mean of cumulative loss ratios.}
#'   \item{ratio_median}{Median of cumulative loss ratios.}
#'   \item{ratio_wt}{Weighted cumulative loss ratio
#'     (`sum(loss) / sum(exposure)`).}
#'   \item{incr_ratio_mean}{Mean of per-period loss ratios.}
#'   \item{incr_ratio_median}{Median of per-period loss ratios.}
#'   \item{incr_ratio_wt}{Weighted per-period loss ratio
#'     (`sum(incr_loss) / sum(incr_exposure)`).}
#' }
#'
#' The returned object preserves the attributes `groups`,
#' `calendar`, and `grain`.
#'
#' @examples
#' \dontrun{
#' cal <- as_calendar(
#'   df,
#'   groups   = "coverage",
#'   calendar = "cy_m",
#'   loss     = "incr_loss",
#'   exposure = "incr_exposure"
#' )
#' smr  <- summary(cal)
#' head(smr)
#' }
#'
#' @method summary Calendar
#' @export
summary.Calendar <- function(object, ...) {
  .assert_class(object, "Calendar")

  dt <- .copy_dt(object)

  grp     <- attr(dt, "groups")
  cal     <- attr(dt, "calendar")
  grp_cal <- c(grp, "calendar")

  ds <- dt[, .(
    n_cohorts         = .N,
    ratio_mean        = mean(ratio),
    ratio_median      = stats::median(ratio),
    ratio_wt          = sum(loss)      / sum(exposure),
    incr_ratio_mean   = mean(incr_ratio),
    incr_ratio_median = stats::median(incr_ratio),
    incr_ratio_wt     = sum(incr_loss) / sum(incr_exposure)
  ), keyby = grp_cal]

  data.table::setattr(ds, "groups"   , grp)
  data.table::setattr(ds, "calendar", cal)

  .update_class(ds, "Calendar", "CalendarSummary")
}


# === Total ==================================================================

#' Coerce experience data to a Total object
#'
#' @description
#' Validate raw experience data, aggregate it to a single scalar row
#' per group (collapsing both the cohort and development axes), and
#' assign the `Total` S3 class so the associated `plot.Total()` bar
#' chart and other Total methods dispatch on the result.
#'
#' Compared with [as_triangle()] (two-dimensional `cohort x dev`) and
#' [as_calendar()] (one-dimensional time series), `as_total()` is
#' *zero-dimensional* per group -- one row of portfolio aggregates. The
#' typical use is high-level portfolio comparison across products,
#' coverages, or channels.
#'
#' Total summarises:
#' \itemize{
#'   \item the number of observed cohorts (`n_cohorts`)
#'   \item the first and last observed cohort periods
#'     (`sales_start`, `sales_end`)
#'   \item total `loss` and total `exposure` (sum over all cells)
#'   \item total loss ratio (`ratio = loss / exposure`)
#'   \item each group's share of total loss and total exposure
#' }
#'
#' Pre-filter the Triangle (e.g. by cohort range or coverage) before
#' calling `as_total()` if a subset summary is needed.
#'
#' @param x A `Triangle` object (typically from [as_triangle()]).
#'
#' @return A data.frame with class `"Total"` containing:
#'   \describe{
#'     \item{n_cohorts}{Number of observed development periods}
#'     \item{sales_start}{First observed period}
#'     \item{sales_end}{Last observed period}
#'     \item{loss}{Total loss}
#'     \item{exposure}{Total exposure}
#'     \item{ratio}{Total loss ratio (`loss / exposure`)}
#'     \item{loss_share}{Share of total loss}
#'     \item{exposure_share}{Share of total exposure}
#'   }
#'
#' @examples
#' \dontrun{
#' tri <- as_triangle(
#'   experience,
#'   groups   = "coverage",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "incr_loss",
#'   exposure = "incr_exposure"
#' )
#' as_total(tri)
#' }
#'
#' @export
as_total <- function(x) {
  # data.table NSE NULL bindings for bare column refs in `j` below.
  cohort <- incr_loss <- incr_exposure <- NULL

  .assert_class(x, "Triangle")

  grp <- attr(x, "groups");  if (is.null(grp)) grp <- character(0)

  dt <- .copy_dt(x)

  # Aggregate per group: n_cohorts, sales_start, sales_end, totals.
  agg_expr <- quote(.(
    n_cohorts   = data.table::uniqueN(cohort),
    sales_start = min(cohort, na.rm = TRUE),
    sales_end   = max(cohort, na.rm = TRUE),
    loss        = sum(incr_loss,     na.rm = TRUE),
    exposure    = sum(incr_exposure, na.rm = TRUE)
  ))
  ds <- if (length(grp)) dt[, eval(agg_expr), by = grp]
        else             dt[, eval(agg_expr)]

  # compute total loss ratio and shares
  data.table::set(ds, j = "ratio",
                  value = ds[["loss"]] / ds[["exposure"]])
  data.table::set(ds, j = "loss_share",
                  value = ds[["loss"]]     / sum(ds[["loss"]]))
  data.table::set(ds, j = "exposure_share",
                  value = ds[["exposure"]] / sum(ds[["exposure"]]))

  data.table::setattr(ds, "groups",   grp)
  data.table::setattr(ds, "loss",     attr(x, "loss"))
  data.table::setattr(ds, "exposure", attr(x, "exposure"))

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
#'   as the input `Total` (one per group), ordered by descending `ratio`.
#'   Preserves the `groups` attribute.
#'
#' @examples
#' \dontrun{
#' tot <- as_total(
#'   df,
#'   groups   = "coverage",
#'   cohort   = "uy_m",
#'   dev      = "dev_m",
#'   loss     = "incr_loss",
#'   exposure = "incr_exposure"
#' )
#' summary(tot)
#' }
#'
#' @method summary Total
#' @export
summary.Total <- function(object, digits = 4L, ...) {
  .assert_class(object, "Total")

  dt <- .copy_dt(object)

  grp <- attr(dt, "groups")

  if ("ratio" %in% names(dt)) {
    data.table::setorderv(dt, "ratio", order = -1L)
  }

  if (!is.null(digits)) {
    digits <- suppressWarnings(as.integer(digits[1L]))
    if (length(digits) == 0L || is.na(digits))
      stop("`digits` must be a single integer or `NULL`.", call. = FALSE)

    skip_cols <- c(grp, "n_cohorts", "sales_start", "sales_end")
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


# === mask_triangle ==========================================================

#' Mask the last N calendar diagonals from a Triangle
#'
#' @description
#' Drops the most recent `holdout` calendar diagonals (per group) from
#' a `Triangle`, returning a new `Triangle` of the same class with all
#' attributes preserved. Useful for simulating a historical analyst's
#' view -- the same masking [backtest()] and `detect_regime(holdout=)`
#' apply internally.
#'
#' The calendar diagonal index is built as `rank(cohort) + dev - 1`,
#' with `rank()` computed within group. The `holdout` most recent
#' calendar indices are dropped.
#'
#' @param x A `Triangle` object.
#' @param holdout Non-negative integer. Number of latest calendar
#'   diagonals to mask. `0L` (default) returns a copy of `x`
#'   unchanged.
#'
#' @return A `Triangle` with the held-out cells removed.
#'
#' @examples
#' \dontrun{
#' data(experience)
#' tri <- as_triangle(experience, groups = "coverage",
#'                       cohort = "uy_m", calendar = "cy_m",
#'                       loss = "incr_loss", exposure = "incr_exposure")
#'
#' # Inspect what the analyst at a 6-month historical cutoff would see
#' tri_masked <- mask_triangle(tri, holdout = 6L)
#' plot_triangle(tri_masked)
#'
#' # Use same masked tri to detect regime + fit
#' r   <- detect_regime(tri_masked)
#' fit <- fit_ratio(tri_masked, loss_regime = r)
#' }
#'
#' @export
mask_triangle <- function(x, holdout = 0L) {
  .assert_class(x, "Triangle")

  # Suppress R CMD check NOTEs for `data.table` temp columns referenced
  # bare inside `j` expressions later in this function.
  .coh_rank <- .cal_idx <- .max_cal <- NULL

  if (!is.numeric(holdout) || length(holdout) != 1L ||
      is.na(holdout) || holdout < 0L)
    stop("`holdout` must be a single non-negative integer.",
         call. = FALSE)
  holdout <- as.integer(holdout)

  if (holdout == 0L) return(data.table::copy(x))

  grp <- attr(x, "groups")
  if (is.null(grp)) grp <- character(0)

  dt <- .copy_dt(x)
  dt[, (".coh_rank") := data.table::frank(cohort, ties.method = "dense"),
     by = grp]
  dt[, (".cal_idx") := .coh_rank + dev - 1L]
  dt[, (".max_cal") := max(.cal_idx, na.rm = TRUE), by = grp]
  dt <- dt[.cal_idx <= .max_cal - holdout]
  dt[, c(".coh_rank", ".cal_idx", ".max_cal") := NULL]

  if (!nrow(dt))
    stop(sprintf(
      "After masking with `holdout = %d`, no observations remain. ",
      holdout
    ), "Reduce `holdout`.", call. = FALSE)

  # restore class + attrs from the original Triangle
  data.table::setattr(dt, "class", class(x))
  attr_names <- setdiff(names(attributes(x)),
                        c("names", "row.names", ".internal.selfref"))
  for (a in attr_names) {
    av <- attr(x, a, exact = TRUE)
    if (!is.null(av)) data.table::setattr(dt, a, av)
  }
  dt
}
