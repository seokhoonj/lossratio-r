# Development Plot --------------------------------------------------------

#' Plot development trajectories with optional summary overlay
#'
#' @description
#' Visualise loss ratio or related metric trajectories across development time
#' from a `Triangle` object.
#'
#' The function supports two display modes:
#' \itemize{
#'   \item \strong{Raw mode (`summary = FALSE`)}: plots cohort-level trajectories
#'   coloured by the period variable stored in the `Triangle` object.
#'   \item \strong{Summary mode (`summary = TRUE`)}: plots all cohort trajectories
#'   in grey and overlays three summary statistics:
#'   \itemize{
#'     \item Mean
#'     \item Median
#'     \item Weighted mean
#'   }
#' }
#'
#' Summary statistics are computed from [summary.Triangle()].
#'
#' @param x An object of class `Triangle`.
#' @param metric A single metric to plot. Must be one of:
#'   `"ratio"`, `"incr_ratio"`,
#'   `"loss"`, `"incr_loss"`, `"exposure"`, `"incr_exposure"`,
#'   `"margin"`, `"incr_margin"`,
#'   `"loss_share"`, `"incr_loss_share"`, `"exposure_share"`, or `"incr_exposure_share"`.
#' @param summary Logical. If `FALSE` (default), shows raw cohort trajectories.
#'   If `TRUE`, shows grey cohort trajectories with overlaid summary lines
#'   (mean, median, weighted mean). Summary overlay is supported only for
#'   `"ratio"` and `"incr_ratio"`, and only when the x-axis variable is a
#'   development-period variable (for example, `dev_m`, `dev_q`, `dev_h`,
#'   `dev_y`).
#' @param summary_min_n Optional minimum number of observations required for
#'   the summary overlay to be considered reliable. When provided and
#'   `summary = TRUE`, a vertical reference line is drawn at the midpoint just
#'   before the first development period where `n_cohorts < summary_min_n` within each
#'   facet. Default is `5`.
#' @param amount_divisor Numeric scaling factor used only for y-axis labels of
#'   amount variables. Default is `1e8`.
#' @param scales Should scales be fixed (`"fixed"`), free (`"free"`),
#'   or free in one dimension (`"free_x"`, `"free_y"`)?
#' @param theme A string passed to [.switch_theme()]
#'   (`"view"`, `"save"`, `"shiny"`).
#' @param ... Additional arguments passed to [.switch_theme()].
#'
#' @details
#' The x-axis uses the development variable stored in `attr(x, "dev")`.
#' Cohort lines are grouped by the period variable stored in
#' `attr(x, "cohort")`, and facets are created from
#' `attr(x, "groups")`.
#'
#' The cumulative loss ratio is defined here as:
#' \deqn{ratio = loss / exposure}
#'
#' For long-term health insurance applications, risk premium is commonly
#' used as the `exposure` measure.
#'
#' The weighted mean is defined as:
#' \itemize{
#'   \item `ratio_wt      = sum(loss)      / sum(exposure)`
#'   \item `incr_ratio_wt = sum(incr_loss) / sum(incr_exposure)`
#' }
#'
#' Ratio and proportion metrics are plotted on the original scale and displayed
#' as percentages via y-axis labels. Amount metrics are plotted on the original
#' scale and displayed using y-axis labels scaled by `amount_divisor`.
#'
#' @return A `ggplot` object.
#'
#' @method plot Triangle
#' @export
plot.Triangle <- function(x,
                          metric         = "ratio",
                          summary        = FALSE,
                          summary_min_n  = 5L,
                          amount_divisor = "auto",
                          scales         = c("fixed", "free_y", "free_x", "free"),
                          theme          = c("view", "save", "shiny"),
                          ...) {

  .assert_class(x, "Triangle")

  scales <- match.arg(scales)
  theme  <- match.arg(theme)

  grp     <- attr(x, "groups")
  coh     <- attr(x, "cohort")
  dev <- attr(x, "dev")
  metric <- .check_metric(metric, x)

  if (identical(amount_divisor, "auto"))
    amount_divisor <- .auto_divisor(
      if (.is_ratio_metric(metric)) numeric(0) else x[[metric]]
    )

  valid_vars <- c(
    "ratio", "incr_ratio",
    "loss", "incr_loss",
    "exposure", "incr_exposure",
    "margin", "incr_margin",
    "loss_share", "incr_loss_share",
    "exposure_share", "incr_exposure_share"
  )

  if (length(metric) != 1L || !(metric %in% valid_vars)) {
    stop(
      paste0(
        "`metric` must be one of ",
        "'ratio', 'incr_ratio', 'loss', 'incr_loss', 'exposure', 'incr_exposure', ",
        "'margin', 'incr_margin', ",
        "'loss_share', 'incr_loss_share', 'exposure_share', or 'incr_exposure_share'."
      ),
      call. = FALSE
    )
  }

  meta <- .get_plot_meta(metric, amount_divisor = amount_divisor)

  if (summary && meta$type != "ratio") {
    warning(
      "Summary overlay is only supported for `ratio` and `incr_ratio`.",
      call. = FALSE
    )
    summary <- FALSE
  }

  is_dev_axis <- length(dev) == 1L && grepl("^dev_", dev)

  if (summary && !is_dev_axis) {
    warning(
      "Summary overlay is only supported when `dev` is a development-period variable such as `dev_m`, `dev_q`, `dev_h`, or `dev_y`. Raw trajectories are shown only.",
      call. = FALSE
    )
    summary <- FALSE
  }

  dt <- .copy_dt(x)

  if (!summary) {
    p <- ggplot2::ggplot(
      data = dt,
      ggplot2::aes(
        x     = .data[["dev"]],
        y     = .data[[metric]],
        color = .data[["cohort"]],
        group = .data[["cohort"]]
      )
    ) +
      ggplot2::geom_line() +
      .scale_color_by_month_gradientn()

  } else {
    p <- ggplot2::ggplot() +
      ggplot2::geom_line(
        data = dt,
        ggplot2::aes(
          x     = .data[["dev"]],
          y     = .data[[metric]],
          group = .data[["cohort"]]
        ),
        color     = "grey70",
        alpha     = 0.5,
        linewidth = 0.5
      )
  }

  if (summary) {
    smr <- summary(x)

    sm_long <- longer(smr)
    target_types <- paste0(metric, c("_mean", "_median", "_wt"))
    sm_long <- sm_long[type %in% target_types]

    sm_long[smr, on = c(grp, "dev"), ("n_cohorts") := i.n_cohorts]

    if (!is.null(summary_min_n) && is.finite(summary_min_n)) {
      summary_min_n <- as.integer(summary_min_n)
      sm_long[n_cohorts < summary_min_n, ("value") := NA_real_]
    }

    sm_long[, ("type") := factor(
      type,
      levels = paste0(metric, c("_mean", "_median", "_wt")),
      labels = c("Mean", "Median", "Weighted")
    )]

    p <- p +
      ggplot2::geom_line(
        data    = sm_long,
        mapping = ggplot2::aes(
          x     = .data[["dev"]],
          y     = .data$value,
          color = .data$type,
          group = .data$type
        ),
        inherit.aes = FALSE,
        linewidth   = 0.8,
        na.rm       = TRUE
      ) +
      ggplot2::scale_color_manual(
        values = c(
          "Mean"     = "black",
          "Median"   = "#1f77b4",
          "Weighted" = "#d62728"
        ),
        name = NULL
      )

    if (!is.null(summary_min_n) && is.finite(summary_min_n)) {
      vline <- smr[, {
        idx <- which(n_cohorts <= summary_min_n)[1L]
        sd1 <- .SD[[1L]]

        if (is.na(idx)) {
          .(xint = NA_real_)
        } else {
          .(xint = sd1[idx])
        }
      }, by = grp, .SDcols = "dev"]

      vline <- vline[!is.na(xint)]

      if (nrow(vline)) {
        p <- p + ggplot2::geom_vline(
          data     = vline,
          mapping  = ggplot2::aes(xintercept = .data$xint),
          linetype = "dotted",
          color    = "grey40"
        )
      }
    }
  }

  if (!is.null(meta$hline)) {
    p <- p + ggplot2::geom_hline(
      yintercept = meta$hline,
      linetype   = "dashed",
      color      = "red"
    )
  }

  # scales
  if (inherits(dt[["dev"]], "Date")) {
    p <- p + ggplot2::scale_x_date(labels = function(x) .format_period(x, abb = TRUE))
  }
  p <- p + .resolve_y_scale(
    meta           = meta,
    amount_divisor = amount_divisor
  )

  # facet
  p <- p + ggplot2::facet_wrap(grp, scales = scales)

  # labs
  p <- p + ggplot2::labs(
    title   = meta$title,
    x       = .pretty_var_label(dev),
    y       = metric,
    caption = meta$caption
  )

  # theme
  p + .switch_theme(theme = theme, ...)
}

# Calendar Plot -----------------------------------------------------------

#' Plot calendar-based development statistics
#'
#' @description
#' Visualise an object of class `Calendar` as a time-series plot.
#' The selected metric is plotted over the calendar-style `calendar`,
#' or over the calendar development variable stored in `attr(x, "dev")`.
#'
#' Ratio metrics (`ratio`, `incr_ratio`) and proportion metrics
#' (`loss_share`, `incr_loss_share`, `exposure_share`, `incr_exposure_share`) are
#' plotted on the original scale and displayed as percentages via y-axis labels.
#' Amount metrics (`loss`, `incr_loss`, `exposure`, `incr_exposure`, `margin`,
#' `incr_margin`) are plotted on the original scale and displayed using y-axis
#' labels scaled by `amount_divisor`.
#'
#' If grouping variables are present, lines are drawn separately by group.
#'
#' @param x An object of class `Calendar`.
#' @param metric A single metric to plot. Must be one of:
#'   `"ratio"`, `"incr_ratio"`,
#'   `"loss"`, `"incr_loss"`, `"exposure"`, `"incr_exposure"`, `"margin"`, `"incr_margin"`,
#'   `"loss_share"`, `"incr_loss_share"`, `"exposure_share"`, or `"incr_exposure_share"`.
#' @param amount_divisor Numeric scaling factor used only for y-axis labels of
#'   amount variables. Default `"auto"` (picks the divisor that produces
#'   the shortest formatted label; pass an explicit numeric to fix it).
#' @param show_label Logical; if `TRUE`, overlay the metric value as a
#'   text label at each (calendar, group) point. Ratio metrics
#'   (`"ratio"`, `"incr_ratio"`, share variants) are formatted as percent
#'   (one decimal). Amount metrics are scaled by `amount_divisor` and
#'   formatted with one decimal. Default `FALSE`.
#' @param label_size Numeric text size passed to `geom_text` when
#'   `show_label = TRUE`. Default `2.8`.
#' @param theme A string passed to [.switch_theme()]
#'   (`"view"`, `"save"`, `"shiny"`).
#' @param ... Additional arguments passed to [.switch_theme()].
#'
#' @details
#' The x-axis is the calendar variable stored in `attr(x, "calendar")`
#' (a Date, formatted per the triangle's `grain`).
#'
#' The loss ratio is defined as:
#' \deqn{ratio = loss / exposure}
#'
#' where `exposure` denotes risk premium rather than written premium.
#'
#' @return A `ggplot` object.
#'
#' @examples
#' \dontrun{
#' x <- as_calendar(
#'   df,
#'   groups   = "coverage",
#'   calendar = "cy_m",
#'   loss     = "incr_loss",
#'   exposure = "incr_exposure"
#' )
#'
#' plot(x)
#' plot(x, metric = "ratio")
#' }
#'
#' @method plot Calendar
#' @export
plot.Calendar <- function(x,
                          metric         = "ratio",
                          amount_divisor = "auto",
                          show_label     = FALSE,
                          label_size     = 2.8,
                          theme          = c("view", "save", "shiny"),
                          ...) {

  # data.table NSE NULL bindings for temp label column.
  .value_label <- NULL

  .assert_class(x, "Calendar")

  theme <- match.arg(theme)

  if (!is.logical(show_label) || length(show_label) != 1L ||
      is.na(show_label))
    stop("`show_label` must be a single non-missing logical value.",
         call. = FALSE)

  grp     <- attr(x, "groups")
  cal     <- attr(x, "calendar")
  metric <- .check_metric(metric, x)

  valid_vars <- c(
    "ratio", "incr_ratio",
    "loss", "incr_loss",
    "exposure", "incr_exposure",
    "margin", "incr_margin",
    "loss_share", "incr_loss_share",
    "exposure_share", "incr_exposure_share"
  )

  if (length(cal) != 1L) {
    stop("`x` must contain exactly one `calendar`.", call. = FALSE)
  }

  if (length(metric) != 1L || !(metric %in% valid_vars)) {
    stop("Invalid `metric`.", call. = FALSE)
  }

  dt <- .copy_dt(x)

  if (identical(amount_divisor, "auto"))
    amount_divisor <- .auto_divisor(
      if (.is_ratio_metric(metric)) numeric(0) else dt[[metric]]
    )

  meta <- .get_plot_meta(metric, amount_divisor = amount_divisor)

  x_axis     <- "calendar"
  axis_label <- cal

  title_txt <- paste0(meta$title, " (Calendar, by ", axis_label, ")")

  if (!length(grp)) {

    p <- ggplot2::ggplot(
      dt,
      ggplot2::aes(
        x = .data[[x_axis]],
        y = .data[[metric]]
      )
    ) +
      ggplot2::geom_line()

  } else if (length(grp) == 1L) {

    p <- ggplot2::ggplot(
      dt,
      ggplot2::aes(
        x      = .data[[x_axis]],
        y      = .data[[metric]],
        colour = .data[[grp]],
        group  = .data[[grp]]
      )
    ) +
      ggplot2::geom_line()

  } else {

    dt[, (".group") := interaction(.SD, drop = TRUE), .SDcols = grp]

    p <- ggplot2::ggplot(
      dt,
      ggplot2::aes(
        x      = .data[[x_axis]],
        y      = .data[[metric]],
        colour = .data$.group,
        group  = .data$.group
      )
    ) +
      ggplot2::geom_line()
  }

  # optional per-point value labels
  if (show_label) {
    is_ratio <- .is_ratio_metric(metric)
    if (is_ratio) {
      dt[, (".value_label") := sprintf("%.1f", .SD[[1L]] * 100),
         .SDcols = metric]
    } else {
      dt[, (".value_label") := sprintf("%.1f", .SD[[1L]] / amount_divisor),
         .SDcols = metric]
    }
    p <- p + ggplot2::geom_text(
      data        = dt,
      mapping     = ggplot2::aes(label = .data[[".value_label"]]),
      size        = label_size,
      vjust       = -0.6,
      show.legend = FALSE
    )
  }

  if (!is.null(meta$hline)) {
    p <- p + ggplot2::geom_hline(
      yintercept = meta$hline,
      linetype   = "dashed",
      color      = "red"
    )
  }

  # scales -- x is always the calendar date, so format with the grain.
  axis_grain <- attr(x, "grain")
  p <- p +
    ggplot2::scale_x_continuous(
      labels = function(z) .format_period_safe(z, axis_label, grain = axis_grain)
    ) +
    .resolve_y_scale(
      meta           = meta,
      amount_divisor = amount_divisor
    )

  # labs
  p <- p + ggplot2::labs(
    title   = title_txt,
    x       = axis_label,
    y       = metric,
    caption = meta$caption
  )

  # theme
  p + .switch_theme(theme = theme, ...)
}

# Triangle Plot -----------------------------------------------------------

#' Triangle plot generic
#'
#' Generic function for triangle-style visualisations.
#'
#' @param x An object.
#' @param ... Additional arguments passed to methods.
#'
#' @return A plot object.
#'
#' @export
plot_triangle <- function(x, ...) {
  UseMethod("plot_triangle")
}

#' Plot development values as a triangle table
#'
#' @description
#' Visualise a `Triangle` object as a triangle-style table. Cells are arranged by
#' period and dev dimensions, and each cell displays the selected metric.
#'
#' For ratio metrics (`ratio`, `incr_ratio`), labels can show either the ratio alone or
#' the ratio together with the associated loss / risk premium amounts.
#'
#' For amount metrics (`loss`, `incr_loss`, `exposure`, `incr_exposure`, `margin`, `incr_margin`),
#' labels show the selected amount only.
#'
#' For proportion metrics (`loss_share`, `incr_loss_share`, `exposure_share`, `incr_exposure_share`),
#' labels are displayed as percentages.
#'
#' The loss ratio is defined as:
#' \deqn{ratio = loss / exposure}
#'
#' where `exposure` denotes risk premium rather than written premium.
#'
#' @param x An object of class `Triangle`.
#' @param view Plot view. One of:
#'   \describe{
#'     \item{"value"}{(default) Per-cell metric heatmap controlled by
#'       `metric`, `label_style`, `amount_divisor`, `nrow`, `ncol`.}
#'     \item{"usage"}{Cell-status heatmap (used / holdout / unused /
#'       future). Accepts `recent`, `regime`, `holdout`, `maturity`
#'       via `...`. See `vignette("regime-change-filter")` for details.}
#'   }
#' @param metric A single metric to plot. Must be one of:
#'   `"ratio"`, `"incr_ratio"`,
#'   `"loss"`, `"incr_loss"`, `"exposure"`, `"incr_exposure"`, `"margin"`, `"incr_margin"`,
#'   `"loss_share"`, `"incr_loss_share"`, `"exposure_share"`, or `"incr_exposure_share"`.
#' @param label_style Label display style. One of:
#'   \describe{
#'     \item{"value"}{Show only the selected metric.}
#'     \item{"detail"}{For `ratio` / `incr_ratio`, show the ratio in percent and, on the
#'       next line, the associated loss / exposure amounts. For amount and
#'       proportion metrics, this falls back to `"value"`.}
#'   }
#' @param label_size Numeric size of the in-cell text label. Defaults
#'   to `3` for `label_style = "value"` and `2.5` for
#'   `label_style = "detail"` (two-line labels need a smaller size to
#'   fit). Other label appearance fields (family, color, hjust, ...)
#'   fall back to the standard label defaults.
#' @param amount_divisor Numeric scaling factor applied to amount variables
#'   (e.g., `loss`, `incr_loss`, `exposure`, `incr_exposure`, `margin`, `incr_margin`) before plotting.
#'   Default `"auto"` picks the largest divisor in
#'   `{1, 1e3, 1e6, 1e7, 1e8, 1e9}` such that the median displayed
#'   value is still at least `1`, minimising label digit count.
#' @param theme A string passed to [.switch_theme()]
#'   (`"view"`, `"save"`, `"shiny"`).
#' @param nrow,ncol Number of rows and columns passed to [ggplot2::facet_wrap()].
#' @param ... Additional arguments passed to [.switch_theme()].
#'
#' @details
#' The x-axis uses the development variable stored in `attr(x, "dev")`, and
#' the y-axis uses the period variable stored in `attr(x, "cohort")`.
#' If either axis variable is a period-like variable such as `uy_m`, `cy_m`,
#' `uy_q`, `cy_q`, `uy_h`, `cy_h`, `uy`, or `cy`, it is formatted using
#' [.format_period()].
#'
#' Facets are created from `attr(x, "groups")`.
#'
#' Ratio and proportion values are displayed in percent. Amount values are
#' displayed in units of 100 million KRW.
#'
#' @return A ggplot object.
#'
#' @examples
#' \dontrun{
#' d <- as_triangle(
#'   df,
#'   groups   = "pd_cat_nm",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "incr_loss",
#'   exposure = "incr_exposure"
#' )
#'
#' plot_triangle(d)
#' plot_triangle(d, metric = "ratio")
#' plot_triangle(d, metric = "loss")
#' plot_triangle(d, metric = "exposure")
#' plot_triangle(d, metric = "loss_share")
#' plot_triangle(d, metric = "exposure_share")
#' plot_triangle(d, label_style = "value")
#' plot_triangle(d, label_style = "detail")
#' }
#'
#' @method plot_triangle Triangle
#' @export
plot_triangle.Triangle <- function(x,
                                   view           = c("value", "usage"),
                                   metric         = "ratio",
                                   label_style    = c("value", "detail"),
                                   label_size     = NULL,
                                   amount_divisor = "auto",
                                   nrow           = NULL, ncol = NULL,
                                   theme          = c("view", "save", "shiny"),
                                   ...) {

  .assert_class(x, "Triangle")
  view <- match.arg(view)

  if (view == "usage") {
    return(.plot_triangle_usage(x, theme = theme, ...))
  }

  label_style <- match.arg(label_style)
  theme       <- match.arg(theme)
  if (is.null(label_size))
    label_size <- if (label_style == "detail") 2.5 else 3
  label_args  <- .modify_label_args(list(size = label_size))

  grp     <- attr(x, "groups")
  coh     <- attr(x, "cohort")
  dev <- attr(x, "dev")
  metric <- .check_metric(metric, x)

  valid_vars <- c(
    "ratio", "incr_ratio",
    "loss", "incr_loss",
    "exposure", "incr_exposure",
    "margin", "incr_margin",
    "loss_share", "incr_loss_share",
    "exposure_share", "incr_exposure_share"
  )

  if (length(coh) != 1L)
    stop("`x` must contain exactly one `calendar`.", call. = FALSE)

  if (length(dev) != 1L)
    stop("`x` must contain exactly one `dev`.", call. = FALSE)

  if (length(metric) != 1L || !(metric %in% valid_vars))
    stop(
      paste0(
        "`metric` must be one of ",
        "'ratio', 'incr_ratio', 'loss', 'incr_loss', 'exposure', 'incr_exposure', ",
        "'margin', 'incr_margin', ",
        "'loss_share', 'incr_loss_share', 'exposure_share', or 'incr_exposure_share'."
      ),
      call. = FALSE
    )

  dt <- .copy_dt(x)

  grain    <- attr(x, "grain")
  coh_type <- .get_period_type(coh, grain = grain)
  # `dev` here is the raw integer dev column name (e.g. `"dev_m"`).
  # No grain fallback -- dev values are integers, not Date.
  dev_type <- .get_period_type(dev)

  if (!is.na(coh_type)) {
    dt[, (".y") := .format_period(dt[["cohort"]], type = coh_type)]
  } else {
    dt[, (".y") := as.character(dt[["cohort"]])]
  }

  if (!is.na(dev_type)) {
    dt[, (".x") := .format_period(dt[["dev"]], type = dev_type)]
  } else {
    dt[, (".x") := dt[["dev"]]]
  }

  ratio_vars  <- c("ratio", "incr_ratio")
  amount_vars <- c("loss", "incr_loss",
                   "exposure", "incr_exposure",
                   "margin", "incr_margin")
  prop_vars   <- c("loss_share", "incr_loss_share",
                   "exposure_share", "incr_exposure_share")

  # Resolve `amount_divisor = "auto"` based on the values the labels
  # will actually display. Amount metrics consult the metric column;
  # ratio metrics in `detail` mode show (loss / exposure) below the ratio,
  # so we resolve against the larger denominator (exposure). Proportion
  # metrics never use `amount_divisor`, but resolve anyway to avoid a
  # validation surprise.
  divisor_values <- if (metric %in% amount_vars) {
    dt[[metric]]
  } else if (metric %in% ratio_vars && label_style == "detail") {
    dt[[if (metric == "ratio") "exposure" else "incr_exposure"]]
  } else {
    numeric(0)
  }
  if (identical(amount_divisor, "auto"))
    amount_divisor <- .auto_divisor(divisor_values)

  if (metric %in% ratio_vars) {

    is_cum       <- metric == "ratio"
    loss_col     <- if (is_cum) "loss"     else "incr_loss"
    exposure_col <- if (is_cum) "exposure" else "incr_exposure"

    if (label_style == "value") {
      dt[, ("label") := sprintf("%.0f", dt[[metric]] * 100)]
    } else {
      dt[, ("label") := sprintf(
        "%.0f\n(%.1f/%.1f)",
        dt[[metric]]       * 100,
        dt[[loss_col]]     / amount_divisor,
        dt[[exposure_col]] / amount_divisor
      )]
    }

    title_txt <- if (is_cum) "Cumulative Loss Ratio" else "Per-Period Loss Ratio"
    fill_col  <- metric

    caption_txt <- if (label_style == "detail") {
      sprintf("Unit: %% (%s)", .get_amount_unit(amount_divisor))
    } else {
      "Unit: %"
    }

    p <- .cell_grid(
      data       = dt,
      x          = ".x",
      y          = ".y",
      label      = "label",
      fill       = fill_col,
      fill_scale = "threshold",
      fill_args  = list(threshold = 1),
      label_args = label_args,
      border     = "panel"
    )

  } else if (metric %in% amount_vars) {

    dt[, ("label") := sprintf("%.1f", dt[[metric]] / amount_divisor)]

    title_txt <- switch(
      metric,
      loss          = "Cumulative Loss",
      incr_loss     = "Per-Period Loss",
      exposure      = "Cumulative Premium",
      incr_exposure = "Per-Period Premium",
      margin        = "Cumulative Margin",
      incr_margin   = "Per-Period Margin"
    )

    caption_txt <- sprintf("Unit: %s", .get_amount_unit(amount_divisor))

    p <- .cell_grid(
      data       = dt,
      x          = ".x",
      y          = ".y",
      label      = "label",
      fill       = metric,
      fill_scale = "threshold",
      fill_args  = list(when = "<", threshold = 0),
      label_args = label_args,
      border     = "panel"
    )

  } else if (metric %in% prop_vars) {

    dt[, ("label") := sprintf("%.1f", dt[[metric]] * 100)]

    title_txt <- switch(
      metric,
      loss_share          = "Cumulative Loss Proportion",
      incr_loss_share     = "Per-Period Loss Proportion",
      exposure_share      = "Cumulative Premium Proportion",
      incr_exposure_share = "Per-Period Premium Proportion"
    )

    caption_txt <- "Unit: %"

    p <- .cell_grid(
      data       = dt,
      x          = ".x",
      y          = ".y",
      label      = "label",
      fill       = metric,
      fill_scale = "threshold",
      fill_args  = list(threshold = 0.05),
      label_args = label_args,
      border     = "panel"
    )
  }

  # facet
  p <- p + ggplot2::facet_wrap(grp, nrow = nrow, ncol = ncol)

  # labs
  p <- p + ggplot2::labs(
    title   = title_txt,
    x       = .pretty_var_label(dev),
    y       = .cohort_label(coh, grain = grain),
    caption = caption_txt
  )

  # theme
  p + .switch_theme(theme = theme, ...)
}

# Total Plot --------------------------------------------------------------

#' Plot a `Total` object as a per-group bar chart
#'
#' @description
#' Visualise an object of class `Total` as a horizontal bar chart, with
#' one bar per group. Because `Total` has no time dimension, this is a
#' simple group-level comparison of the chosen metric (loss ratio, total
#' loss, etc.) rather than a trajectory.
#'
#' @param x An object of class `Total`.
#' @param metric A single metric to plot. Must be one of the columns
#'   carried by a `Total`: `"ratio"`, `"loss"`, `"exposure"`, `"loss_share"`, or
#'   `"exposure_share"`. Default `"ratio"`.
#' @param amount_divisor Numeric scaling factor used only for y-axis
#'   labels of amount variables. Default `1e8`.
#' @param theme A string passed to [.switch_theme()]
#'   (`"view"`, `"save"`, `"shiny"`).
#' @param ... Additional arguments passed to [.switch_theme()].
#'
#' @details
#' Bars are ordered by the value of `metric` (descending). When more
#' than one grouping variable is present, an interaction is used as the
#' bar identifier.
#'
#' Ratio and proportion metrics are plotted on the original scale and
#' labelled as percentages. Amount metrics are plotted on the original
#' scale and labelled using `amount_divisor`.
#'
#' @return A `ggplot` object.
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
#' plot(tot)
#' plot(tot, metric = "loss")
#' }
#'
#' @method plot Total
#' @export
#' @import ggplot2
plot.Total <- function(x,
                       metric         = "ratio",
                       amount_divisor = "auto",
                       theme          = c("view", "save", "shiny"),
                       ...) {

  .assert_class(x, "Total")

  # Suppress R CMD check NOTEs for `data.table` temp columns referenced
  # bare inside `j` expressions later in this function.
  .group <- NULL

  theme <- match.arg(theme)

  grp     <- attr(x, "groups")
  metric <- .check_metric(metric, x)

  valid_vars <- c("ratio", "loss", "exposure", "loss_share", "exposure_share")

  if (length(metric) != 1L || !(metric %in% valid_vars)) {
    stop(
      paste0(
        "`metric` must be one of ",
        "'ratio', 'loss', 'exposure', 'loss_share', or 'exposure_share'."
      ),
      call. = FALSE
    )
  }

  if (!length(grp)) {
    stop("`Total` has no `groups`; nothing to plot.", call. = FALSE)
  }

  dt <- .copy_dt(x)

  if (length(grp) == 1L) {
    dt[, (".group") := as.character(.SD[[1L]]), .SDcols = grp]
  } else {
    dt[, (".group") := as.character(interaction(.SD, drop = TRUE, sep = " | ")),
       .SDcols = grp]
  }

  # order bars by value (ascending so largest is at the top after coord_flip)
  data.table::setorderv(dt, metric)
  dt[, (".group") := factor(.group, levels = .group)]

  if (identical(amount_divisor, "auto"))
    amount_divisor <- .auto_divisor(
      if (.is_ratio_metric(metric)) numeric(0) else dt[[metric]]
    )

  meta <- .get_plot_meta(metric, amount_divisor = amount_divisor)

  p <- ggplot2::ggplot(
    dt,
    ggplot2::aes(
      x = .data$.group,
      y = .data[[metric]]
    )
  ) +
    ggplot2::geom_col(fill = "#4C78A8")

  if (!is.null(meta$hline)) {
    p <- p + ggplot2::geom_hline(
      yintercept = meta$hline,
      linetype   = "dashed",
      color      = "red"
    )
  }

  p <- p + .resolve_y_scale(
    meta           = meta,
    amount_divisor = amount_divisor
  )

  p <- p +
    ggplot2::coord_flip() +
    ggplot2::labs(
      title   = meta$title,
      x       = paste(grp, collapse = " | "),
      y       = metric,
      caption = meta$caption
    )

  p + .switch_theme(theme = theme, ...)
}

# Data Usage Plot ---------------------------------------------------------

#' Compute cell-level data-usage status for a Triangle
#'
#' @description
#' Internal helper that classifies every `(group, cohort, dev)` cell of a
#' `Triangle` into one of four buckets given a fit-data filter
#' configuration: `"used"`, `"holdout"`, `"unused"`, or `"future"`.
#'
#' Mask precedence: `holdout` > `used` > `unused` > `future`.
#'
#' @param x A `Triangle` object.
#' @param recent Optional positive integer (calendar-diagonal cut), or
#'   `NULL`.
#' @param regime Optional cohort cutoff. Accepts the same input
#'   forms handled by [.resolve_regime_change_date()] (`NULL`, `Date`, character,
#'   vector, or `Regime`).
#' @param holdout Optional positive integer. When supplied, the last
#'   `holdout` calendar diagonals are flagged `"holdout"`. The `recent`
#'   filter is then evaluated against the post-holdout boundary so the
#'   recent wedge sits *before* the holdout wedge (no overlap), matching
#'   `backtest()` semantics -- the internal fitter operates on the masked
#'   triangle whose own max_cal is `original - holdout`.
#' @param m_k Optional integer. The maturity switch as a *target*
#'   development index (= `change` of the first stable link). When
#'   both `recent` and `regime` are provided, the hybrid mask uses
#'   `m_k` as the boundary: cells with `dev < m_k` apply the cohort
#'   cut, cells with `dev >= m_k` apply the calendar-diagonal cut.
#'   When `NULL`, the hybrid logic falls back to applying both filters
#'   jointly (cohort cut AND recent cut).
#'
#' @return A `data.table` with one row per `(group, cohort, dev)` cell
#'   spanning the full triangle (observed plus future). Columns include
#'   group columns (if any), `cohort`, `dev`, `.coh_rank`, `.cal_idx`,
#'   `.max_cal`, `is_observed`, `is_held_out`, `is_fit_data`,
#'   `is_excluded`, and `status` (factor).
#'
#' @keywords internal
.compute_triangle_usage <- function(x,
                                recent  = NULL,
                                regime  = NULL,
                                holdout = NULL,
                                m_k     = NULL,
                                grp_m_k  = NULL) {

  .assert_class(x, "Triangle")

  # Suppress R CMD check NOTEs for `data.table` temp columns referenced
  # bare inside `j` expressions later in this function.
  .data_present <- .coh_rank <- .cal_idx <- .max_cal <- NULL
  .max_cal_fit <- .cd_join <- .m_k_join <- .pass_filter <- NULL

  grp <- attr(x, "groups")
  if (is.null(grp)) grp <- character(0)

  obs <- .copy_dt(x)

  # full grid (observed plus future) per group
  grp_coh_dev <- c(grp, "cohort", "dev")
  full <- obs[, .SD, .SDcols = grp_coh_dev]
  full[, ("is_observed") := TRUE]

  if (length(grp)) {
    grid_list <- split(full, by = grp, keep.by = TRUE)
    expanded <- data.table::rbindlist(lapply(grid_list, function(d) {
      cohorts <- sort(unique(d$cohort))
      devs    <- sort(unique(d$dev))
      g_vals  <- d[1L, .SD, .SDcols = grp]
      grid <- data.table::CJ(cohort = cohorts, dev = devs)
      cbind(g_vals[rep(1L, nrow(grid))], grid)
    }))
  } else {
    cohorts <- sort(unique(full$cohort))
    devs    <- sort(unique(full$dev))
    expanded <- data.table::CJ(cohort = cohorts, dev = devs)
  }

  expanded[full, on = grp_coh_dev, (".data_present") := i.is_observed]
  expanded[is.na(.data_present), (".data_present") := FALSE]

  # cohort rank (1 = earliest) and calendar index per group
  if (length(grp)) {
    expanded[, (".coh_rank") := data.table::frank(cohort, ties.method = "dense"),
             by = grp]
    expanded[, (".cal_idx") := .coh_rank + dev - 1L]
    expanded[, (".max_cal") := max(.cal_idx[.data_present], na.rm = TRUE),
             by = grp]
  } else {
    expanded[, (".coh_rank") := data.table::frank(cohort, ties.method = "dense")]
    expanded[, (".cal_idx") := .coh_rank + dev - 1L]
    expanded[, (".max_cal") := max(.cal_idx[.data_present], na.rm = TRUE)]
  }

  # `is_observed` reflects what a cell *would* be in the underlying
  # triangle, not whether the input data.table actually carries that
  # row. The latter (`.data_present`) may already be filtered (e.g. by
  # regime cut when the input is `fit$data`); we want to surface those
  # filtered-out cells as `unused` (gray), not `future` (white).
  expanded[, ("is_observed") := .cal_idx <= .max_cal]

  # held-out flag, plus an effective max-cal for fit-data filters that
  # excludes the held_out region -- this matches `backtest()` semantics,
  # where the internal fitter operates on the masked triangle whose own
  # max_cal is `original_max_cal - holdout`.
  if (!is.null(holdout)) {
    if (!is.numeric(holdout) || length(holdout) != 1L ||
        is.na(holdout) || holdout < 1L)
      stop("`holdout` must be a single positive integer.", call. = FALSE)
    holdout <- as.integer(holdout)
    expanded[, ("is_held_out") := is_observed & .cal_idx > .max_cal - holdout]
    expanded[, (".max_cal_fit") := .max_cal - holdout]
  } else {
    expanded[, ("is_held_out") := FALSE]
    expanded[, (".max_cal_fit") := .max_cal]
  }

  # Detect segment_wise treatment up-front: when set, the regime carries
  # multiple change points and the *intent* is to keep every cohort
  # (segments are estimated separately, not filtered). The usage plot
  # therefore skips the cohort cut and instead shows one hline per
  # change as a visual partition marker.
  is_segment_wise <- inherits(regime, "Regime") &&
                     identical(regime$treatment, "segment_wise")

  # resolve regime change date -- scalar (single group / scalar input)
  # or a per-group `[join_cols..., change_date]` data.table when a
  # multi-group `Regime` matches `grp`. Auto-dispatched inside the helper.
  # Skipped under segment_wise so the cohort filter doesn't kick in
  # (every observed cell stays "used"; hlines come from the full change
  # list, drawn by `.plot_triangle_usage`).
  cd <- if (!is.null(regime) && !is_segment_wise) {
    .resolve_regime_change_date(regime, by = grp)
  } else {
    NULL
  }

  # fit-data mask
  has_recent <- !is.null(recent)
  has_change <- !is.null(cd)

  if (has_recent) {
    if (!is.numeric(recent) || length(recent) != 1L ||
        is.na(recent) || recent < 1L)
      stop("`recent` must be a single positive integer.", call. = FALSE)
    recent <- as.integer(recent)
  }

  if (!is.null(m_k)) {
    if (!is.numeric(m_k) || length(m_k) != 1L || is.na(m_k))
      stop("`m_k` must be a single non-missing numeric value.",
           call. = FALSE)
  }

  # If cd is per-group, broadcast it as a row-aligned `.cd_join` column
  # so the filter expressions can reference a single column regardless
  # of dispatch mode. NA `.cd_join` (group not in cd) => no filter for
  # that group.
  per_group_cd <- has_change && data.table::is.data.table(cd)
  if (per_group_cd) {
    join_cols <- setdiff(names(cd), "change_date")
    expanded[, (".cd_join") := cd[expanded, on = join_cols, x.change_date]]
  }

  # Per-group maturity: when `grp_m_k` is supplied (a `[grp..., m_k]`
  # data.table from the caller), broadcast it to a row-aligned column
  # so the SA hybrid threshold is per-group. NA rows (group not in
  # grp_m_k) fall back to scalar `m_k` if provided, else NULL.
  per_group_m_k <- !is.null(grp_m_k) && data.table::is.data.table(grp_m_k) &&
                   nrow(grp_m_k) > 0L && "m_k" %in% names(grp_m_k)
  if (per_group_m_k) {
    m_k_join_cols <- setdiff(names(grp_m_k), "m_k")
    expanded[, (".m_k_join") := grp_m_k[expanded, on = m_k_join_cols, x.m_k]]
    if (!is.null(m_k)) expanded[is.na(.m_k_join), (".m_k_join") := m_k]
  }

  change_pass <- if (!has_change) {
    quote(TRUE)
  } else if (per_group_cd) {
    quote(is.na(.cd_join) | cohort >= .cd_join)
  } else {
    bquote(cohort >= .(cd))
  }

  # Build a dev-side maturity predicate that resolves to per-group
  # `.m_k_join` when available, falling back to scalar `m_k`. Returns a
  # quoted expression evaluating to a logical vector of nrow(expanded).
  m_k_geq <- function() {
    if (per_group_m_k) {
      quote(!is.na(.m_k_join) & dev >= .m_k_join)
    } else if (!is.null(m_k)) {
      bquote(dev >= .(m_k))
    } else {
      quote(rep(FALSE, .N))
    }
  }
  m_k_lt <- function() {
    if (per_group_m_k) {
      quote(!is.na(.m_k_join) & dev < .m_k_join)
    } else if (!is.null(m_k)) {
      bquote(dev < .(m_k))
    } else {
      quote(rep(TRUE, .N))
    }
  }
  has_m_k <- per_group_m_k || !is.null(m_k)

  if (has_recent && has_change) {
    # hybrid: cohort cut on dev < m_k (ED region), calendar cut on
    # dev >= m_k (CL region). when m_k is NULL, fall back to both
    # filters jointly.
    if (has_m_k) {
      expanded[, (".pass_filter") := eval(bquote(
        (.(m_k_lt())  & .(change_pass)) |
        (.(m_k_geq()) & .cal_idx > .max_cal_fit - .(recent))
      ))]
    } else {
      expanded[, (".pass_filter") := eval(bquote(
        .(change_pass) & (.cal_idx > .max_cal_fit - .(recent))
      ))]
    }
  } else if (has_recent) {
    expanded[, (".pass_filter") := .cal_idx > .max_cal_fit - recent]
  } else if (has_change) {
    # SA semantics: cohort cut applies only on dev < m_k (ED region);
    # CL region (dev >= m_k) keeps all cohorts. When m_k is NULL,
    # fall back to a simple cohort cut across all dev.
    if (has_m_k) {
      expanded[, (".pass_filter") := eval(bquote(
        .(m_k_geq()) | .(change_pass)
      ))]
    } else {
      expanded[, (".pass_filter") := eval(change_pass)]
    }
  } else {
    expanded[, (".pass_filter") := TRUE]
  }

  if (per_group_cd)  expanded[, .cd_join  := NULL]
  if (per_group_m_k) expanded[, (".m_k_join") := NULL]

  expanded[, ("is_fit_data") := is_observed & !is_held_out & .pass_filter]

  # segment_wise visualisation: each regime segment shows up as its own
  # mini-triangle anchored on the latest cal diagonal. Cells inside an
  # affected group (those listed in `regime$groups` / `regime$changes`)
  # but outside the segment's mini-triangle drop to `unused`. Algorithm
  # still uses all observed cells via `segment_id` tagging -- the
  # mini-triangle is a *display* convention requested by the user to
  # make per-segment dev coverage visible.
  #
  # dev_min(k) = max_cal_idx - last_cohort_rank_of_seg_k + 1
  #
  # When `m_k` / `grp_m_k` is supplied (SA hybrid + maturity), the
  # mini-triangle cut applies only in the ED region (dev < m_k); the
  # CL region (dev >= m_k) is pooled across cohorts and stays `used`
  # regardless of segment. Without `m_k` the cut applies to all dev
  # (pure mini-triangle).
  if (is_segment_wise) {
    bp <- regime$changes
    if (data.table::is.data.table(bp) && nrow(bp) &&
        "change" %in% names(bp)) {

      rgrp <- intersect(grp,
                        if (is.null(regime$groups)) character(0) else regime$groups)

      # Apply mini-triangle override per affected (group, segment).
      # Maturity (`m_k`) does NOT shrink the mini-triangle here -- it
      # only contributes the dashed vline for visual reference.
      # The mini-triangle staircase therefore stays visible whether
      # the user passes a maturity or not.
      apply_seg_filter <- function(mask_rows, cd_vec) {
        if (!any(mask_rows)) return(invisible())
        coh_vals <- as.Date(expanded$cohort[mask_rows])
        seg_id   <- findInterval(coh_vals, cd_vec) + 1L
        coh_rank <- expanded$.coh_rank[mask_rows]
        max_cal  <- expanded$.max_cal[mask_rows]
        dev_vals <- expanded$dev[mask_rows]
        is_obs   <- expanded$is_observed[mask_rows]
        is_held  <- expanded$is_held_out[mask_rows]
        seg_last <- tapply(coh_rank, seg_id, max)
        dev_min  <- max_cal - seg_last[as.character(seg_id)] + 1L
        expanded[mask_rows,
                 ("is_fit_data") := is_obs & !is_held & (dev_vals >= dev_min)]
      }

      if (length(rgrp) == 0L) {
        cd_vec <- sort(as.Date(bp[["change"]]))
        apply_seg_filter(rep(TRUE, nrow(expanded)), cd_vec)
      } else {
        affected <- unique(bp[, rgrp, with = FALSE])
        for (i in seq_len(nrow(affected))) {
          key    <- affected[i]
          bp_sub <- bp[key, on = rgrp, nomatch = NULL]
          cd_vec <- sort(as.Date(bp_sub[["change"]]))
          if (!length(cd_vec)) next
          grp_mask <- Reduce(`&`,
                             lapply(rgrp, function(c) expanded[[c]] == key[[c]]))
          apply_seg_filter(grp_mask, cd_vec)
        }
      }
    }
  }

  expanded[, ("is_excluded") := is_observed & !is_held_out & !is_fit_data]

  expanded[, ("status") := factor(
    data.table::fcase(
      is_held_out, "holdout",
      is_fit_data, "used",
      is_excluded, "unused",
      default     = "future"
    ),
    levels = c("unused", "used", "holdout", "future")
  )]

  expanded[, c(".pass_filter", ".max_cal_fit") := NULL]
  expanded[]
}


# Internal: build the cell-usage data.table that drives the
# `view = "usage"` heatmap. Combines (1) 2-pass maturity detection
# when `regime` is set, (2) `.compute_triangle_usage()` to assign each
# cell one of `used` / `unused` / `holdout` / `future`.
#
# Called once at *fit time* (by `fit_loss`, `fit_exposure`, `fit_ratio`,
# `backtest`) so the resulting `data.table` can be attached as
# `fit$usage`; downstream `plot_triangle(fit, view = "usage")` then
# renders without re-deriving anything. Also reused directly by
# `plot_triangle.Triangle(view = "usage")` for ad-hoc triangle plots.
#
# @param triangle A `Triangle`.
# @param regime,recent,holdout,maturity Filter / mask inputs (same
#   semantics as on `fit_loss()` / `fit_ratio()` / `backtest()`).
# @param metric Target metric for the 2-pass maturity detection (only
#   used when `regime` is set). Default `"loss"`.
#
# @return A `data.table` keyed on `(group..., cohort, dev)` with the
#   `status` factor column (`unused`/`used`/`holdout`/`future`).
#
# @keywords internal
.build_usage <- function(triangle,
                         regime   = NULL,
                         recent   = NULL,
                         holdout  = NULL,
                         maturity = "auto",
                         metric   = "loss") {

  .assert_class(triangle, "Triangle")
  grp <- attr(triangle, "groups")
  if (is.null(grp)) grp <- character(0)

  # 2-pass maturity detection: run when `regime` is set AND the caller
  # actually wants maturity ("auto", a `Maturity` object, or a
  # lazy-detect spec / function). When `maturity` is `NULL` the user
  # explicitly opted out, so we skip detection and the segment_wise
  # mini-triangle stays pure (no CL pooling, no k* vline).
  m_k    <- NULL
  grp_m_k <- NULL
  if (!is.null(regime) && !is.null(maturity)) {
    fit_for_mat <- tryCatch(
      fit_ata(x = triangle, loss = metric, maturity = maturity),
      error = function(e) NULL
    )
    if (!is.null(fit_for_mat) &&
        !is.null(fit_for_mat$maturity) &&
        nrow(fit_for_mat$maturity) > 0L &&
        !all(is.na(fit_for_mat$maturity$change))) {
      mat <- fit_for_mat$maturity
      # Per-group dispatch whenever the maturity dt carries group
      # columns -- honour scope even for single-group input (e.g.
      # `maturity_at(cv_nm = "surgery", change = 4)` returns a 1-row dt
      # that should still mark *only* surgery, not every facet).
      if (length(grp) > 0L && all(grp %in% names(mat))) {
        grp_m_k <- mat[, c(grp, "change"), with = FALSE]
        data.table::setnames(grp_m_k, "change", "m_k")
        grp_m_k <- grp_m_k[is.finite(m_k)]
        if (!nrow(grp_m_k)) grp_m_k <- NULL
        m_k <- max(mat$change, na.rm = TRUE)
      } else {
        m_k <- max(mat$change, na.rm = TRUE)
      }
    }
  }

  out <- .compute_triangle_usage(
    triangle,
    recent  = recent,
    regime  = regime,
    holdout = holdout,
    m_k     = m_k,
    grp_m_k  = grp_m_k
  )

  # Carry plot-rendering metadata on attributes so
  # `.plot_triangle_usage()` (and other consumers of `fit$usage`) can
  # draw hlines / vlines / titles without re-passing the filter args.
  data.table::setattr(out, "regime",  regime)
  data.table::setattr(out, "recent",  recent)
  data.table::setattr(out, "holdout", holdout)
  data.table::setattr(out, "m_k",     m_k)
  data.table::setattr(out, "m_k",  grp_m_k)
  out
}


# Internal: usage-mask renderer dispatched from plot_triangle.Triangle
# when type = "usage".
.plot_triangle_usage <- function(x,
                                 recent   = NULL,
                                 regime   = NULL,
                                 holdout  = NULL,
                                 maturity = "auto",
                                 metric   = "loss",
                                 theme    = c("view", "save", "shiny"),
                                 usage    = NULL,
                                 ...) {

  .assert_class(x, "Triangle")
  theme <- match.arg(theme)

  # Suppress R CMD check NOTEs for `data.table` temp columns referenced
  # bare inside `j` expressions later in this function.
  .y <- .xint <- .cd <- .yint <- NULL

  grp      <- attr(x, "groups")
  coh      <- attr(x, "cohort")
  coh_type <- .get_period_type(coh, grain = attr(x, "grain"))
  dev  <- attr(x, "dev")
  if (is.null(grp)) grp <- character(0)

  # If a pre-computed usage data.table was attached to a fit object
  # (`fit$usage`), use it directly. Otherwise build it inline from the
  # filter inputs (`regime` / `recent` / `holdout` / `maturity`), which
  # is the path taken by `plot_triangle.Triangle(view = "usage")`.
  if (is.null(usage)) {
    usage <- .build_usage(
      x,
      regime   = regime,
      recent   = recent,
      holdout  = holdout,
      maturity = maturity,
      metric   = metric
    )
  }

  # Pull plot-rendering metadata off the usage object's attributes.
  regime <- attr(usage, "regime",  exact = TRUE)
  m_k    <- attr(usage, "m_k",     exact = TRUE)
  grp_m_k <- attr(usage, "m_k",  exact = TRUE)

  is_segment_wise <- inherits(regime, "Regime") &&
                     identical(regime$treatment, "segment_wise")

  cd <- if (!is.null(regime) && !is_segment_wise) {
    .resolve_regime_change_date(regime, by = grp)
  } else {
    NULL
  }

  dt <- usage

  # cohort labels: most recent at top
  if (!is.na(coh_type)) {
    dt[, (".y") := .format_period(cohort, type = coh_type)]
  } else {
    dt[, (".y") := as.character(cohort)]
  }
  y_levels <- sort(unique(dt$.y), decreasing = TRUE)
  dt[, (".y") := factor(.y, levels = y_levels)]

  status_cols <- c(
    unused  = "#dcdcdc",
    used    = "#1f77b4",
    holdout = "#d62728",
    future  = "#ffffff"
  )

  p <- ggplot2::ggplot(
    dt,
    ggplot2::aes(x = .data[["dev"]], y = .data[[".y"]],
                 fill = .data[["status"]])
  ) +
    ggplot2::geom_tile(color = "white", linewidth = 0.2) +
    ggplot2::scale_fill_manual(values = status_cols, name = NULL,
                               drop = FALSE) +
    ggplot2::scale_x_continuous(expand = c(0, 0))

  # vertical maturity line in hybrid mode: drawn just before dev = m_k
  # so the boundary visually separates ED region (dev < m_k) on the
  # left from CL region (dev >= m_k) on the right.
  #
  # `grp_m_k` (when present) is a `[grp..., m_k]` data.table -- each facet
  # draws its own k* boundary. Falls back to scalar `m_k` for single
  # group / pooled. Mirrors the regime-change hline dispatch below.
  if (!is.null(grp_m_k)) {
    vline_df <- data.table::copy(grp_m_k)
    vline_df[, (".xint") := m_k - 0.5]
    p <- p + ggplot2::geom_vline(
      data       = vline_df,
      mapping    = ggplot2::aes(xintercept = .xint),
      linetype   = "dashed", color = "black", linewidth = 0.4
    )
  } else if (!is.null(m_k)) {
    p <- p + ggplot2::geom_vline(
      xintercept = m_k - 0.5,
      linetype   = "dashed", color = "black", linewidth = 0.4
    )
  }

  # horizontal regime-change line(s). The y axis is a discrete factor
  # with levels sorted descending; each change row is the row whose
  # label corresponds to the smallest cohort >= the change date. The
  # line is drawn just above that row (toward older cohorts).
  #
  # Three dispatch paths:
  #   - segment_wise: one hline per change in `regime$changes` (so the
  #     plot shows the full segment partition). Per-group when the
  #     Regime is multi-group and `grp` matches; scalar otherwise.
  #   - latest_only (default) + per-group `cd`: one hline per group via
  #     `data = hline_df`, faceted automatically.
  #   - latest_only + scalar `cd`: one global hline.
  .first_post_idx <- function(cd_scalar) {
    cohorts_sorted <- sort(unique(dt$cohort))
    post_change <- cohorts_sorted[cohorts_sorted >= cd_scalar]
    if (!length(post_change)) return(NA_integer_)
    first_post <- min(post_change)
    lab <- if (!is.na(coh_type)) {
      .format_period(first_post, type = coh_type)
    } else {
      as.character(first_post)
    }
    match(lab, y_levels)
  }

  if (is_segment_wise) {
    bp <- regime$changes
    if (data.table::is.data.table(bp) && nrow(bp) &&
        "change" %in% names(bp)) {

      # Per-group segment_wise: route hlines to specific facets whenever
      # `regime$changes` carries group columns (`regime$groups`) that
      # match the plot's facet groups (`grp`). We honour this even when
      # `regime$multi_group = FALSE` (e.g. user wrote
      # `regime_at(coverage = c("surgery", "surgery"), change = ...)` with only
      # one unique value) -- the explicit group column reflects intent
      # to scope the regime to just that group.
      rgrp <- intersect(grp,
                        if (is.null(regime$groups)) character(0) else regime$groups)
      per_group <- length(rgrp) > 0L && all(rgrp %in% names(bp))

      if (per_group) {
        hline_df <- bp[, c(rgrp, "change"), with = FALSE]
        data.table::setnames(hline_df, "change", ".cd")
        hline_df[, (".yint") := vapply(.cd, .first_post_idx, integer(1L)) + 0.5]
        hline_df <- hline_df[is.finite(.yint)]
        if (nrow(hline_df)) {
          p <- p + ggplot2::geom_hline(
            data        = hline_df,
            mapping     = ggplot2::aes(yintercept = .yint),
            linetype    = "dashed", color = "black", linewidth = 0.4
          )
        }
      } else {
        # Scalar segment_wise: one hline per (deduplicated) change. The
        # change list is shared across every facet (no per-group split).
        for (cd_one in sort(unique(bp[["change"]]))) {
          idx <- .first_post_idx(cd_one)
          if (!is.na(idx)) {
            p <- p + ggplot2::geom_hline(
              yintercept = idx + 0.5,
              linetype   = "dashed", color = "black", linewidth = 0.4
            )
          }
        }
      }
    }
  } else if (!is.null(cd)) {
    if (data.table::is.data.table(cd) && length(grp)) {
      hline_df <- data.table::copy(cd)
      data.table::setnames(hline_df, "change_date", ".cd")
      hline_df[, (".yint") := vapply(.cd, .first_post_idx, integer(1L)) + 0.5]
      hline_df <- hline_df[is.finite(.yint)]
      if (nrow(hline_df)) {
        p <- p + ggplot2::geom_hline(
          data        = hline_df,
          mapping     = ggplot2::aes(yintercept = .yint),
          linetype    = "dashed", color = "black", linewidth = 0.4
        )
      }
    } else {
      cd_scalar <- if (data.table::is.data.table(cd)) max(cd$change_date) else cd
      idx <- .first_post_idx(cd_scalar)
      if (!is.na(idx)) {
        p <- p + ggplot2::geom_hline(
          yintercept = idx + 0.5,
          linetype   = "dashed", color = "black", linewidth = 0.4
        )
      }
    }
  }

  # facet for multi-group triangles
  if (length(grp)) {
    p <- p + ggplot2::facet_wrap(grp)
  }

  # title summarising active filters
  parts <- character(0)
  if (!is.null(recent))       parts <- c(parts, sprintf("recent=%d", as.integer(recent)))
  if (is_segment_wise) {
    bp <- regime$changes
    if (data.table::is.data.table(bp) && nrow(bp) && "change" %in% names(bp)) {
      parts <- c(parts, sprintf("regime=%s",
                                paste(format(sort(unique(bp[["change"]]))),
                                      collapse = ",")))
    }
  } else if (!is.null(cd)) {
    cd_txt <- if (data.table::is.data.table(cd)) {
      paste(format(sort(unique(cd$change_date))), collapse = ",")
    } else {
      format(cd)
    }
    parts <- c(parts, sprintf("regime=%s", cd_txt))
  }
  if (!is.null(holdout))      parts <- c(parts, sprintf("holdout=%d", as.integer(holdout)))
  title_txt <- if (length(parts)) {
    sprintf("Data usage (%s)", paste(parts, collapse = ", "))
  } else {
    "Data usage (full)"
  }

  subtitle_txt <- if (!is.null(grp_m_k)) {
    sprintf("hybrid mode: maturity k* per group (range %g-%g)",
            min(grp_m_k$m_k), max(grp_m_k$m_k))
  } else if (!is.null(m_k)) {
    sprintf("hybrid mode: maturity k* = %g", m_k)
  } else {
    NULL
  }

  p <- p + ggplot2::labs(
    title    = title_txt,
    subtitle = subtitle_txt,
    x        = .pretty_var_label(dev),
    y        = .cohort_label(coh, grain = attr(x, "grain"))
  )

  p + .switch_theme(theme = theme, ...)
}
