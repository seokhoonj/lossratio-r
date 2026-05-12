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
                          type   = c("col", "diag", "cell"),
                          scales = c("fixed", "free_y", "free_x", "free"),
                          theme  = c("view", "save", "shiny"),
                          ...) {

  .assert_class(x, "Backtest")
  type   <- match.arg(type)
  scales <- match.arg(scales)
  theme  <- match.arg(theme)

  grp <- x$groups

  if (type == "col") {
    smr <- .ensure_dt(x$col_summary)
    long <- data.table::melt(
      smr,
      id.vars       = c(grp, "dev", "n"),
      measure.vars  = c("ae_err_mean", "ae_err_med", "ae_err_wt"),
      variable.name = "stat",
      value.name    = "ae_err"
    )
    long[, stat := factor(stat,
                          levels = c("ae_err_mean", "ae_err_med", "ae_err_wt"),
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
      ggplot2::labs(title = "Backtest A/E Error by development period",
                    x = .pretty_var_label(x$dev),
                    y = "A/E ERROR = actual / pred - 1")
    if (length(grp))
      p <- p + ggplot2::facet_wrap(grp, scales = scales)

  } else if (type == "diag") {
    smr <- .ensure_dt(x$diag_summary)
    long <- data.table::melt(
      smr,
      id.vars       = c(grp, "calendar_idx", "n"),
      measure.vars  = c("ae_err_mean", "ae_err_med", "ae_err_wt"),
      variable.name = "stat",
      value.name    = "ae_err"
    )
    long[, stat := factor(stat,
                          levels = c("ae_err_mean", "ae_err_med", "ae_err_wt"),
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
      ggplot2::labs(title = "Backtest A/E Error by calendar diagonal",
                    x = "calendar diagonal index",
                    y = "A/E ERROR = actual / pred - 1")
    if (length(grp))
      p <- p + ggplot2::facet_wrap(grp, scales = scales)

  } else { # cell
    dt <- .ensure_dt(x$ae_err)
    p <- ggplot2::ggplot(
      dt,
      ggplot2::aes(x = .data[["dev"]], y = .data[["ae_err"]],
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
      ggplot2::labs(title = "Backtest A/E Error per held-out cell",
                    x = .pretty_var_label(x$dev),
                    y = "A/E ERROR = actual / pred - 1")
    if (length(grp))
      p <- p + ggplot2::facet_wrap(grp, scales = scales)
  }

  p + .switch_theme(theme = theme, ...)
}


#' Triangle heatmap of backtest A/E Error
#'
#' @description
#' Display the held-out cells as a `cohort x dev` heatmap coloured by
#' A/E Error (red = under-projected (actual > pred), blue =
#' over-projected (actual < pred), white at 0).
#'
#' @param x An object of class `"Backtest"`.
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
                                   label_size = 2.5,
                                   theme      = c("view", "save", "shiny"),
                                   ...) {

  .assert_class(x, "Backtest")
  theme <- match.arg(theme)

  grp <- x$groups
  dt <- .ensure_dt(x$ae_err)

  dt[, .label := sprintf("%.1f", ae_err * 100)]
  lim <- max(abs(dt$ae_err), na.rm = TRUE)
  if (!is.finite(lim) || lim == 0) lim <- 1

  # Encode cohort as a factor with levels in reverse-chronological order
  # so the oldest cohort sits at the top (matches plot_triangle.<other>).
  dt[, .y_lab := format(cohort, "%y.%m")]
  cohort_levels <- sort(unique(dt$.y_lab), decreasing = TRUE)
  dt[, .y_lab := factor(.y_lab, levels = cohort_levels)]

  p <- ggplot2::ggplot(
    dt,
    ggplot2::aes(x = .data[["dev"]], y = .data[[".y_lab"]],
                 fill = .data[["ae_err"]])
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
    ggplot2::labs(title = "Backtest A/E Error (held-out cells)",
                  x       = .pretty_var_label(x$dev),
                  y       = .pretty_var_label(x$cohort),
                  caption = "Unit: %")

  if (length(grp))
    p <- p + ggplot2::facet_wrap(grp, scales = "free_y")

  p + .switch_theme(theme = theme, ...)
}
