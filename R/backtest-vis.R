# Backtest plots ----------------------------------------------------------

#' Plot a backtest object
#'
#' @description
#' Visualise the A/E Error (`ae_err`) of a `"Backtest"` object.
#'
#' Three plot types:
#' \itemize{
#'   \item `"col"`: A/E Error aggregated by development period (one line
#'     per summary statistic).
#'   \item `"diag"`: A/E Error aggregated by calendar diagonal.
#'   \item `"cell"`: per-cell A/E Error as a scatter / line, faceted by
#'     group.
#' }
#'
#' @param x An object of class `"Backtest"`.
#' @param type Plot type. One of `"col"`, `"diag"`, `"cell"`.
#' @param cell_type Which projection view to display. One of
#'   `"cumulative"` (default; uses `ae_err`) or `"incremental"` (uses
#'   `incr_ae_err`). Both are stored on every `Backtest` object -- pick
#'   the view at plot time.
#' @param scales Facet scale argument. One of `"fixed"`, `"free"`,
#'   `"free_x"`, `"free_y"`.
#' @param theme String passed to [.switch_theme()].
#' @param ... Extra arguments passed to [.switch_theme()].
#'
#' @return A `ggplot` object.
#'
#' @method plot Backtest
#' @export
plot.Backtest <- function(x,
                          type      = c("col", "diag", "cell"),
                          cell_type = c("cumulative", "incremental"),
                          scales    = c("fixed", "free_y", "free_x", "free"),
                          theme     = c("view", "save", "shiny"),
                          ...) {

  .assert_class(x, "Backtest")
  type      <- match.arg(type)
  cell_type <- match.arg(cell_type)
  scales    <- match.arg(scales)
  theme     <- match.arg(theme)

  is_incr <- cell_type == "incremental"
  # column prefix for selecting the requested view from wide summaries
  pfx <- if (is_incr) "incr_" else ""
  ae_err_col <- paste0(pfx, "ae_err")
  stat_cols  <- paste0(pfx, "ae_err",
                       c("_mean", "_med", "_wt"))
  cum_word <- if (is_incr) "incremental" else "cumulative"

  grp <- x$groups

  if (type == "col") {
    smr  <- .copy_dt(x$col_summary)
    long <- data.table::melt(
      smr,
      id.vars       = c(grp, "dev", "n"),
      measure.vars  = stat_cols,
      variable.name = "stat",
      value.name    = "ae_err"
    )
    long[, ("stat") := factor(stat,
                          levels = stat_cols,
                          labels = c("Mean", "Median", "Weighted"))]
    p <- ggplot2::ggplot(
      long,
      ggplot2::aes(x = .data[["dev"]], y = .data[["ae_err"]],
                   color = .data[["stat"]], group = .data[["stat"]])
    ) +
      ggplot2::annotate("rect",
                        xmin = -Inf, xmax = Inf,
                        ymin = -0.1, ymax = 0.1,
                        fill = "grey60", alpha = 0.12) +
      ggplot2::geom_hline(yintercept = c(-0.1, 0.1),
                          linetype  = "dotted", color = "grey50",
                          linewidth = 0.3) +
      ggplot2::geom_hline(yintercept = 0, linetype = "dashed",
                          color = "grey50") +
      ggplot2::geom_line(linewidth = 0.8) +
      ggplot2::geom_point() +
      ggplot2::scale_color_manual(
        values = c("Mean" = "black", "Median" = "#1f77b4",
                   "Weighted" = "#d62728"),
        name = NULL
      ) +
      ggplot2::scale_y_continuous(labels = function(v) paste0(round(v * 100), "%")) +
      ggplot2::labs(title = sprintf("Backtest A/E Error by development period (%s)",
                                    cum_word),
                    x = .pretty_var_label(x$dev),
                    y = "A/E Error = Actual / Projected - 1")
    if (length(grp))
      p <- p + ggplot2::facet_wrap(grp, scales = scales)

  } else if (type == "diag") {
    smr  <- .copy_dt(x$diag_summary)
    long <- data.table::melt(
      smr,
      id.vars       = c(grp, "calendar_idx", "n"),
      measure.vars  = stat_cols,
      variable.name = "stat",
      value.name    = "ae_err"
    )
    long[, ("stat") := factor(stat,
                          levels = stat_cols,
                          labels = c("Mean", "Median", "Weighted"))]
    p <- ggplot2::ggplot(
      long,
      ggplot2::aes(x = .data[["calendar_idx"]], y = .data[["ae_err"]],
                   color = .data[["stat"]], group = .data[["stat"]])
    ) +
      ggplot2::annotate("rect",
                        xmin = -Inf, xmax = Inf,
                        ymin = -0.1, ymax = 0.1,
                        fill = "grey60", alpha = 0.12) +
      ggplot2::geom_hline(yintercept = c(-0.1, 0.1),
                          linetype  = "dotted", color = "grey50",
                          linewidth = 0.3) +
      ggplot2::geom_hline(yintercept = 0, linetype = "dashed",
                          color = "grey50") +
      ggplot2::geom_line(linewidth = 0.8) +
      ggplot2::geom_point() +
      ggplot2::scale_color_manual(
        values = c("Mean" = "black", "Median" = "#1f77b4",
                   "Weighted" = "#d62728"),
        name = NULL
      ) +
      ggplot2::scale_y_continuous(labels = function(v) paste0(round(v * 100), "%")) +
      ggplot2::labs(title = sprintf("Backtest A/E Error by calendar diagonal (%s)",
                                    cum_word),
                    x = "calendar diagonal index",
                    y = "A/E Error = Actual / Projected - 1")
    if (length(grp))
      p <- p + ggplot2::facet_wrap(grp, scales = scales)

  } else { # cell
    dt <- .copy_dt(x$ae_err)
    p <- ggplot2::ggplot(
      dt,
      ggplot2::aes(x = .data[["dev"]], y = .data[[ae_err_col]],
                   color = .data[["cohort"]], group = .data[["cohort"]])
    ) +
      ggplot2::annotate("rect",
                        xmin = -Inf, xmax = Inf,
                        ymin = -0.1, ymax = 0.1,
                        fill = "grey60", alpha = 0.12) +
      ggplot2::geom_hline(yintercept = c(-0.1, 0.1),
                          linetype  = "dotted", color = "grey50",
                          linewidth = 0.3) +
      ggplot2::geom_hline(yintercept = 0, linetype = "dashed",
                          color = "grey50") +
      ggplot2::geom_line(alpha = 0.6) +
      ggplot2::geom_point(alpha = 0.6, size = 1.2) +
      .scale_color_by_month_gradientn(begin = 0.25) +
      ggplot2::scale_y_continuous(labels = function(v) paste0(round(v * 100), "%")) +
      ggplot2::labs(title = sprintf("Backtest A/E Error per held-out cell (%s)",
                                    cum_word),
                    x = .pretty_var_label(x$dev),
                    y = "A/E Error = Actual / Projected - 1")
    if (length(grp))
      p <- p + ggplot2::facet_wrap(grp, scales = scales)
  }

  p + .switch_theme(theme = theme, ...)
}


#' Triangle heatmap of backtest A/E Error
#'
#' @description
#' Display the held-out cells as a `cohort x dev` heatmap coloured by
#' A/E Error (red = under-projected (actual > proj), blue =
#' over-projected (actual < proj), white at 0).
#'
#' @param x An object of class `"Backtest"`.
#' @param view Plot mode:
#'   \describe{
#'     \item{`"value"` (default)}{Held-out-cell heatmap coloured by
#'       A/E Error.}
#'     \item{`"usage"`}{Cell-status heatmap (training / held-out /
#'       dropped (regime-filtered) / future) driven by `x$holdout` and
#'       the fit's `regime`. Useful to inspect what data the
#'       masked refit actually saw, especially when combined with
#'       multi-group `regime`.}
#'   }
#' @param cell_type Which projection view to display in `view =
#'   "value"`. One of `"cumulative"` (default; uses `ae_err`) or
#'   `"incremental"` (uses `incr_ae_err`).
#' @param label_size Numeric label text size for cell labels. Default
#'   `2.5` (single-line A/E Error percent labels on the held-out
#'   wedge).
#' @param theme String passed to [.switch_theme()].
#' @param ... Extra arguments passed to [.switch_theme()].
#'
#' @return A `ggplot` object.
#'
#' @method plot_triangle Backtest
#' @export
plot_triangle.Backtest <- function(x,
                                   view       = c("value", "usage"),
                                   cell_type  = c("cumulative", "incremental"),
                                   label_size = 2.5,
                                   theme      = c("view", "save", "shiny"),
                                   ...) {

  .assert_class(x, "Backtest")
  view      <- match.arg(view)
  cell_type <- match.arg(cell_type)
  theme     <- match.arg(theme)

  # Suppress R CMD check NOTEs for `data.table` temp columns referenced
  # bare inside `j` expressions later in this function.
  .ae <- .y_lab <- NULL

  # view = "usage": cell-status heatmap (training / held-out /
  # regime-excluded / future). `x$usage` is pre-computed at
  # `backtest()` time with the full filter + holdout metadata baked
  # in; the renderer reads it directly.
  if (view == "usage") {
    return(.plot_triangle_usage(
      x$data,
      usage = x$usage,
      theme = theme,
      ...
    ))
  }

  is_incr    <- cell_type == "incremental"
  ae_err_col <- if (is_incr) "incr_ae_err" else "ae_err"
  cum_word   <- if (is_incr) "incremental" else "cumulative"

  grp <- x$groups
  dt <- .copy_dt(x$ae_err)

  dt[, (".ae") := .SD[[1L]], .SDcols = ae_err_col]
  dt[, (".label") := sprintf("%.1f", .ae * 100)]
  lim <- max(abs(dt$.ae), na.rm = TRUE)
  if (!is.finite(lim) || lim == 0) lim <- 1

  # Encode cohort as a factor with levels in reverse-chronological order
  # so the oldest cohort sits at the top (matches plot_triangle.<other>).
  # Grain-aware tick labels: M -> "23.04", Q -> "23.2Q", H -> "23.1H",
  # Y -> "23". Falls back to bare ISO date when neither column name nor
  # grain resolve a period type.
  bt_grain <- attr(x$data, "grain")
  coh_type <- .get_period_type(x$cohort, grain = bt_grain)
  if (!is.na(coh_type)) {
    dt[, (".y_lab") := .format_period(cohort, type = coh_type, abb = TRUE)]
  } else {
    dt[, (".y_lab") := as.character(cohort)]
  }
  cohort_levels <- sort(unique(dt$.y_lab), decreasing = TRUE)
  dt[, (".y_lab") := factor(.y_lab, levels = cohort_levels)]

  p <- ggplot2::ggplot(
    dt,
    ggplot2::aes(x = .data[["dev"]], y = .data[[".y_lab"]],
                 fill = .data[[".ae"]])
  ) +
    ggplot2::geom_tile(color = "white") +
    ggplot2::geom_text(ggplot2::aes(label = .data[[".label"]]),
                       size = label_size) +
    ggplot2::scale_fill_gradient2(
      low      = "#1f77b4",
      mid      = "white",
      high     = "#d62728",
      midpoint = 0,
      limits   = c(-lim, lim),
      labels   = function(v) paste0(round(v * 100), "%"),
      name     = "A/E Error"
    ) +
    ggplot2::labs(title = sprintf("Backtest A/E Error -- held-out cells (%s)",
                                  cum_word),
                  x       = .pretty_var_label(x$dev),
                  y       = .cohort_label(x$cohort, grain = bt_grain),
                  caption = "Unit: %")

  if (length(grp))
    p <- p + ggplot2::facet_wrap(grp, scales = "free_y")

  p + .switch_theme(theme = theme, ...)
}
