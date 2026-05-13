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
#'   `"lr"`, `"lr_incr"`,
#'   `"loss"`, `"loss_incr"`, `"premium"`, `"premium_incr"`,
#'   `"margin"`, `"margin_incr"`,
#'   `"loss_share"`, `"loss_incr_share"`, `"premium_share"`, or `"premium_incr_share"`.
#' @param summary Logical. If `FALSE` (default), shows raw cohort trajectories.
#'   If `TRUE`, shows grey cohort trajectories with overlaid summary lines
#'   (mean, median, weighted mean). Summary overlay is supported only for
#'   `"lr"` and `"lr_incr"`, and only when the x-axis variable is a development-period
#'   variable (for example, `dev_m`, `dev_q`, `dev_s`, `dev_a`).
#' @param summary_min_n Optional minimum number of observations required for
#'   the summary overlay to be considered reliable. When provided and
#'   `summary = TRUE`, a vertical reference line is drawn at the midpoint just
#'   before the first development period where `n_obs < summary_min_n` within each
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
#' \deqn{lr = loss / premium}
#'
#' For long-term health insurance applications, risk premium is commonly
#' used as the `premium` measure.
#'
#' The weighted mean is defined as:
#' \itemize{
#'   \item `lr_wt      = sum(loss)      / sum(premium)`
#'   \item `lr_incr_wt = sum(loss_incr) / sum(premium_incr)`
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
                          metric         = "lr",
                          summary        = FALSE,
                          summary_min_n  = 5L,
                          amount_divisor = 1e8,
                          scales         = c("fixed", "free_y", "free_x", "free"),
                          theme          = c("view", "save", "shiny"),
                          ...) {

  .assert_class(x, "Triangle")

  scales <- match.arg(scales)
  theme  <- match.arg(theme)

  grp     <- attr(x, "groups")
  coh     <- attr(x, "cohort")
  dev <- attr(x, "dev")
  metric <- .capture_names(x, !!rlang::enquo(metric))

  valid_vars <- c(
    "lr", "lr_incr",
    "loss", "loss_incr",
    "premium", "premium_incr",
    "margin", "margin_incr",
    "loss_share", "loss_incr_share",
    "premium_share", "premium_incr_share"
  )

  if (length(metric) != 1L || !(metric %in% valid_vars)) {
    stop(
      paste0(
        "`metric` must be one of ",
        "'lr', 'lr_incr', 'loss', 'loss_incr', 'premium', 'premium_incr', ",
        "'margin', 'margin_incr', ",
        "'loss_share', 'loss_incr_share', 'premium_share', or 'premium_incr_share'."
      ),
      call. = FALSE
    )
  }

  meta <- .get_plot_meta(metric, amount_divisor = amount_divisor)

  if (summary && meta$type != "ratio") {
    warning(
      "Summary overlay is only supported for `lr` and `lr_incr`.",
      call. = FALSE
    )
    summary <- FALSE
  }

  is_dev_axis <- length(dev) == 1L && grepl("^dev_", dev)

  if (summary && !is_dev_axis) {
    warning(
      "Summary overlay is only supported when `dev` is a development-period variable such as `dev_m`, `dev_q`, `dev_s`, or `dev_a`. Raw trajectories are shown only.",
      call. = FALSE
    )
    summary <- FALSE
  }

  dt <- .ensure_dt(x)

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

    sm_long[smr, on = c(grp, "dev"), n_obs := i.n_obs]

    if (!is.null(summary_min_n) && is.finite(summary_min_n)) {
      summary_min_n <- as.integer(summary_min_n)
      sm_long[n_obs < summary_min_n, value := NA_real_]
    }

    sm_long[, type := factor(
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
        idx <- which(n_obs <= summary_min_n)[1L]
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
#' Ratio metrics (`lr`, `lr`) and proportion metrics
#' (`loss_share`, `loss_incr_share`, `premium_share`, `premium_incr_share`) are plotted on the
#' original scale and displayed as percentages via y-axis labels.
#' Amount metrics (`loss`, `loss_incr`, `premium`, `premium_incr`, `margin`, `margin_incr`) are
#' plotted on the original scale and displayed using y-axis labels scaled by
#' `amount_divisor`.
#'
#' If grouping variables are present, lines are drawn separately by group.
#'
#' @param x An object of class `Calendar`.
#' @param metric A single metric to plot. Must be one of:
#'   `"lr"`, `"lr_incr"`,
#'   `"loss"`, `"loss_incr"`, `"premium"`, `"premium_incr"`, `"margin"`, `"margin_incr"`,
#'   `"loss_share"`, `"loss_incr_share"`, `"premium_share"`, or `"premium_incr_share"`.
#' @param x_by X-axis basis. One of:
#'   \describe{
#'     \item{"period"}{Use the calendar variable stored in `attr(x, "calendar")`.}
#'     \item{"dev"}{Use the sequential `dev` column.}
#'   }
#' @param amount_divisor Numeric scaling factor used only for y-axis labels of
#'   amount variables. Default is `1e8`.
#' @param theme A string passed to [.switch_theme()]
#'   (`"view"`, `"save"`, `"shiny"`).
#' @param ... Additional arguments passed to [.switch_theme()].
#'
#' @details
#' The x-axis uses either the calendar variable stored in `attr(x, "calendar")`
#' or the sequential `dev` column, depending on `x_by`.
#'
#' The loss ratio is defined as:
#' \deqn{lr = loss / premium}
#'
#' where `premium` denotes risk premium rather than written premium.
#'
#' @return A `ggplot` object.
#'
#' @examples
#' \dontrun{
#' x <- build_calendar(
#'   df,
#'   groups   = "coverage",
#'   calendar = "cy_m",
#'   loss     = "loss_incr",
#'   premium  = "premium_incr"
#' )
#'
#' plot(x)
#' plot(x, metric = "lr")
#' plot(x, x_by = "dev")
#' }
#'
#' @method plot Calendar
#' @export
plot.Calendar <- function(x,
                          metric         = "lr",
                          x_by           = c("period", "dev"),
                          amount_divisor = 1e8,
                          theme          = c("view", "save", "shiny"),
                          ...) {

  .assert_class(x, "Calendar")

  theme <- match.arg(theme)
  x_by <- match.arg(x_by)

  grp     <- attr(x, "groups")
  cal     <- attr(x, "calendar")
  metric <- .capture_names(x, !!rlang::enquo(metric))

  valid_vars <- c(
    "lr", "lr_incr",
    "loss", "loss_incr",
    "premium", "premium_incr",
    "margin", "margin_incr",
    "loss_share", "loss_incr_share",
    "premium_share", "premium_incr_share"
  )

  if (length(cal) != 1L) {
    stop("`x` must contain exactly one `calendar`.", call. = FALSE)
  }

  if (length(metric) != 1L || !(metric %in% valid_vars)) {
    stop("Invalid `metric`.", call. = FALSE)
  }

  dt <- .ensure_dt(x)

  meta <- .get_plot_meta(metric, amount_divisor = amount_divisor)

  x_axis <- if (x_by == "dev") "dev" else "calendar"
  axis_label <- if (x_by == "dev") "dev" else cal

  title_txt <- paste0(
    meta$title,
    " (Calendar, by ",
    axis_label,
    ")"
  )

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

    dt[, .group := interaction(.SD, drop = TRUE), .SDcols = grp]

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

  if (!is.null(meta$hline)) {
    p <- p + ggplot2::geom_hline(
      yintercept = meta$hline,
      linetype   = "dashed",
      color      = "red"
    )
  }

  # scales
  p <- p +
    ggplot2::scale_x_continuous(
      labels = function(z) .format_period_safe(z, axis_label)
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
#' For ratio metrics (`lr`, `lr`), labels can show either the ratio alone or
#' the ratio together with the associated loss / risk premium amounts.
#'
#' For amount metrics (`loss`, `loss_incr`, `premium`, `premium_incr`, `margin`, `margin_incr`),
#' labels show the selected amount only.
#'
#' For proportion metrics (`loss_share`, `loss_incr_share`, `premium_share`, `premium_incr_share`),
#' labels are displayed as percentages.
#'
#' The loss ratio is defined as:
#' \deqn{lr = loss / premium}
#'
#' where `premium` denotes risk premium rather than written premium.
#'
#' @param x An object of class `Triangle`.
#' @param type Plot type. One of:
#'   \describe{
#'     \item{"value"}{(default) Per-cell metric heatmap controlled by
#'       `metric`, `label_style`, `amount_divisor`, `nrow`, `ncol`.}
#'     \item{"usage"}{Cell-status heatmap (used / holdout / unused /
#'       future). Accepts `recent`, `regime_break`, `holdout`, `maturity_args`
#'       via `...`. See `vignette("regime-break-filter")` for details.}
#'   }
#' @param metric A single metric to plot. Must be one of:
#'   `"lr"`, `"lr_incr"`,
#'   `"loss"`, `"loss_incr"`, `"premium"`, `"premium_incr"`, `"margin"`, `"margin_incr"`,
#'   `"loss_share"`, `"loss_incr_share"`, `"premium_share"`, or `"premium_incr_share"`.
#' @param label_style Label display style. One of:
#'   \describe{
#'     \item{"value"}{Show only the selected metric.}
#'     \item{"detail"}{For `lr` / `lr`, show the ratio in percent and, on the
#'       next line, the associated loss / premium amounts. For amount and
#'       proportion metrics, this falls back to `"value"`.}
#'   }
#' @param label_size Numeric label text size forwarded to
#'   [ggshort::ggtable()]. Defaults to `3` for `label_style = "value"`
#'   and `2.5` for `label_style = "detail"` (two-line labels need a
#'   smaller size to fit). Other label appearance fields (family,
#'   color, hjust, ...) fall back to ggshort defaults.
#' @param amount_divisor Numeric scaling factor applied to amount variables
#'   (e.g., `loss`, `loss_incr`, `premium`, `premium_incr`, `margin`, `margin_incr`) before plotting.
#'   Default is `1e8`
#' @param theme A string passed to [.switch_theme()]
#'   (`"view"`, `"save"`, `"shiny"`).
#' @param nrow,ncol Number of rows and columns passed to [ggplot2::facet_wrap()].
#' @param ... Additional arguments passed to [.switch_theme()].
#'
#' @details
#' The x-axis uses the development variable stored in `attr(x, "dev")`, and
#' the y-axis uses the period variable stored in `attr(x, "cohort")`.
#' If either axis variable is a period-like variable such as `uy_m`, `cy_m`,
#' `uy_q`, `cy_q`, `uy_s`, `cy_s`, `uy_a`, or `cy_a`, it is formatted using
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
#' d <- build_triangle(
#'   df,
#'   groups   = "pd_cat_nm",
#'   cohort   = "uy_m",
#'   calendar = "cy_m",
#'   loss     = "loss_incr",
#'   premium  = "premium_incr"
#' )
#'
#' plot_triangle(d)
#' plot_triangle(d, metric = "lr")
#' plot_triangle(d, metric = "loss")
#' plot_triangle(d, metric = "premium")
#' plot_triangle(d, metric = "loss_share")
#' plot_triangle(d, metric = "premium_share")
#' plot_triangle(d, label_style = "value")
#' plot_triangle(d, label_style = "detail")
#' }
#'
#' @method plot_triangle Triangle
#' @export
plot_triangle.Triangle <- function(x,
                                   type           = c("value", "usage"),
                                   metric         = "lr",
                                   label_style    = c("value", "detail"),
                                   label_size     = NULL,
                                   amount_divisor = 1e8,
                                   nrow           = NULL, ncol = NULL,
                                   theme          = c("view", "save", "shiny"),
                                   ...) {

  .assert_class(x, "Triangle")
  type <- match.arg(type)

  if (type == "usage") {
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
  metric <- .capture_names(x, !!rlang::enquo(metric))

  valid_vars <- c(
    "lr", "lr_incr",
    "loss", "loss_incr",
    "premium", "premium_incr",
    "margin", "margin_incr",
    "loss_share", "loss_incr_share",
    "premium_share", "premium_incr_share"
  )

  if (length(coh) != 1L)
    stop("`x` must contain exactly one `calendar`.", call. = FALSE)

  if (length(dev) != 1L)
    stop("`x` must contain exactly one `dev`.", call. = FALSE)

  if (length(metric) != 1L || !(metric %in% valid_vars))
    stop(
      paste0(
        "`metric` must be one of ",
        "'lr', 'lr_incr', 'loss', 'loss_incr', 'premium', 'premium_incr', ",
        "'margin', 'margin_incr', ",
        "'loss_share', 'loss_incr_share', 'premium_share', or 'premium_incr_share'."
      ),
      call. = FALSE
    )

  dt <- .ensure_dt(x)

  coh_type <- .get_period_type(coh)
  dev_type <- .get_period_type(dev)

  if (!is.na(coh_type)) {
    dt[, .y := .format_period(dt[["cohort"]], type = coh_type)]
  } else {
    dt[, .y := as.character(dt[["cohort"]])]
  }

  if (!is.na(dev_type)) {
    dt[, .x := .format_period(dt[["dev"]], type = dev_type)]
  } else {
    dt[, .x := dt[["dev"]]]
  }

  ratio_vars  <- c("lr", "lr_incr")
  amount_vars <- c("loss", "loss_incr",
                   "premium", "premium_incr",
                   "margin", "margin_incr")
  prop_vars   <- c("loss_share", "loss_incr_share",
                   "premium_share", "premium_incr_share")

  if (metric %in% ratio_vars) {

    is_cum <- metric == "lr"
    loss_col    <- if (is_cum) "loss"    else "loss_incr"
    premium_col <- if (is_cum) "premium" else "premium_incr"

    if (label_style == "value") {
      dt[, label := sprintf("%.0f", dt[[metric]] * 100)]
    } else {
      dt[, label := sprintf(
        "%.0f\n(%.1f/%.1f)",
        dt[[metric]]    * 100,
        dt[[loss_col]]    / amount_divisor,
        dt[[premium_col]] / amount_divisor
      )]
    }

    title_txt <- if (is_cum) "Cumulative Loss Ratio" else "Per-Period Loss Ratio"
    fill_col  <- metric

    caption_txt <- if (label_style == "detail") {
      sprintf("Unit: %% (%s)", .get_amount_unit(amount_divisor))
    } else {
      "Unit: %"
    }

    p <- ggshort::ggtable(
      data       = dt,
      x          = .data[[".x"]],
      y          = .data[[".y"]],
      label      = .data[["label"]],
      label_args = label_args,
      fill       = .data[[fill_col]],
      fill_args  = list(threshold = 1)
    )

  } else if (metric %in% amount_vars) {

    dt[, label := sprintf("%.1f", dt[[metric]] / amount_divisor)]

    title_txt <- switch(
      metric,
      loss         = "Cumulative Loss",
      loss_incr    = "Per-Period Loss",
      premium      = "Cumulative Premium",
      premium_incr = "Per-Period Premium",
      margin       = "Cumulative Margin",
      margin_incr  = "Per-Period Margin"
    )

    caption_txt <- sprintf("Unit: %s", .get_amount_unit(amount_divisor))

    p <- ggshort::ggtable(
      data       = dt,
      x          = .data[[".x"]],
      y          = .data[[".y"]],
      label      = .data[["label"]],
      label_args = label_args,
      fill       = .data[[metric]],
      fill_args  = list(when = "<", threshold = 0)
    )

  } else if (metric %in% prop_vars) {

    dt[, label := sprintf("%.1f", dt[[metric]] * 100)]

    title_txt <- switch(
      metric,
      loss_share         = "Cumulative Loss Proportion",
      loss_incr_share    = "Per-Period Loss Proportion",
      premium_share      = "Cumulative Premium Proportion",
      premium_incr_share = "Per-Period Premium Proportion"
    )

    caption_txt <- "Unit: %"

    p <- ggshort::ggtable(
      data       = dt,
      x          = .data[[".x"]],
      y          = .data[[".y"]],
      label      = .data[["label"]],
      label_args = label_args,
      fill       = .data[[metric]],
      fill_args  = list(threshold = 0.05)
    )
  }

  # facet
  p <- p + ggplot2::facet_wrap(grp, nrow = nrow, ncol = ncol)

  # labs
  p <- p + ggplot2::labs(
    title   = title_txt,
    x       = .pretty_var_label(dev),
    y       = .cohort_label(coh),
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
#'   carried by a `Total`: `"lr"`, `"loss"`, `"premium"`, `"loss_share"`, or
#'   `"premium_share"`. Default `"lr"`.
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
#' tot <- build_total(
#'   df,
#'   groups  = "coverage",
#'   cohort  = "uy_m",
#'   dev     = "dev_m",
#'   loss    = "loss_incr",
#'   premium = "premium_incr"
#' )
#' plot(tot)
#' plot(tot, metric = "loss")
#' }
#'
#' @method plot Total
#' @export
#' @import ggplot2
plot.Total <- function(x,
                       metric         = "lr",
                       amount_divisor = 1e8,
                       theme          = c("view", "save", "shiny"),
                       ...) {

  .assert_class(x, "Total")

  theme <- match.arg(theme)

  grp     <- attr(x, "groups")
  metric <- .capture_names(x, !!rlang::enquo(metric))

  valid_vars <- c("lr", "loss", "premium", "loss_share", "premium_share")

  if (length(metric) != 1L || !(metric %in% valid_vars)) {
    stop(
      paste0(
        "`metric` must be one of ",
        "'lr', 'loss', 'premium', 'loss_share', or 'premium_share'."
      ),
      call. = FALSE
    )
  }

  if (!length(grp)) {
    stop("`Total` has no `groups`; nothing to plot.", call. = FALSE)
  }

  dt <- .ensure_dt(x)

  if (length(grp) == 1L) {
    dt[, .group := as.character(.SD[[1L]]), .SDcols = grp]
  } else {
    dt[, .group := as.character(interaction(.SD, drop = TRUE, sep = " | ")),
       .SDcols = grp]
  }

  # order bars by value (ascending so largest is at the top after coord_flip)
  data.table::setorderv(dt, metric)
  dt[, .group := factor(.group, levels = .group)]

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
#' @param regime_break Optional cohort cutoff. Accepts the same input
#'   forms as [fit_lr()] (`NULL`, `Date`, character, vector, or
#'   `Regime`).
#' @param holdout Optional positive integer. When supplied, the last
#'   `holdout` calendar diagonals are flagged `"holdout"`. The `recent`
#'   filter is then evaluated against the post-holdout boundary so the
#'   recent wedge sits *before* the holdout wedge (no overlap), matching
#'   `backtest()` semantics — the internal fitter operates on the masked
#'   triangle whose own max_cal is `original - holdout`.
#' @param m_k Optional integer. The maturity switch as a *target*
#'   development index (= `ata_to` of the first stable link). When
#'   both `recent` and `regime_break` are provided, the hybrid mask
#'   uses `m_k` as the boundary: cells with `dev < m_k` apply the
#'   cohort cut, cells with `dev >= m_k` apply the calendar-diagonal
#'   cut. When `NULL`, the hybrid logic falls back to applying both
#'   filters jointly (cohort cut AND recent cut).
#'
#' @return A `data.table` with one row per `(group, cohort, dev)` cell
#'   spanning the full triangle (observed plus future). Columns include
#'   group columns (if any), `cohort`, `dev`, `.coh_rank`, `.cal_idx`,
#'   `.max_cal`, `is_observed`, `is_held_out`, `is_fit_data`,
#'   `is_excluded`, and `status` (factor).
#'
#' @keywords internal
.compute_triangle_usage <- function(x,
                                recent       = NULL,
                                regime_break = NULL,
                                holdout      = NULL,
                                m_k        = NULL) {

  .assert_class(x, "Triangle")

  grp <- attr(x, "groups")
  if (is.null(grp)) grp <- character(0)

  obs <- .ensure_dt(x)

  # full grid (observed plus future) per group
  grp_coh_dev <- c(grp, "cohort", "dev")
  full <- obs[, .SD, .SDcols = grp_coh_dev]
  full[, is_observed := TRUE]

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

  expanded[full, on = grp_coh_dev, is_observed := i.is_observed]
  expanded[is.na(is_observed), is_observed := FALSE]

  # cohort rank (1 = earliest) and calendar index per group
  if (length(grp)) {
    expanded[, .coh_rank := data.table::frank(cohort, ties.method = "dense"),
             by = grp]
    expanded[, .cal_idx := .coh_rank + dev - 1L]
    expanded[, .max_cal := max(.cal_idx[is_observed], na.rm = TRUE),
             by = grp]
  } else {
    expanded[, .coh_rank := data.table::frank(cohort, ties.method = "dense")]
    expanded[, .cal_idx := .coh_rank + dev - 1L]
    expanded[, .max_cal := max(.cal_idx[is_observed], na.rm = TRUE)]
  }

  # held-out flag, plus an effective max-cal for fit-data filters that
  # excludes the held_out region — this matches `backtest()` semantics,
  # where the internal fitter operates on the masked triangle whose own
  # max_cal is `original_max_cal - holdout`.
  if (!is.null(holdout)) {
    if (!is.numeric(holdout) || length(holdout) != 1L ||
        is.na(holdout) || holdout < 1L)
      stop("`holdout` must be a single positive integer.", call. = FALSE)
    holdout <- as.integer(holdout)
    expanded[, is_held_out := is_observed & .cal_idx > .max_cal - holdout]
    expanded[, .max_cal_fit := .max_cal - holdout]
  } else {
    expanded[, is_held_out := FALSE]
    expanded[, .max_cal_fit := .max_cal]
  }

  # resolve regime break date — scalar (single group / scalar input)
  # or a per-group `[join_cols..., break_date]` data.table when a
  # multi-group `Regime` matches `grp`. Auto-dispatched inside the helper.
  bd <- if (!is.null(regime_break)) {
    .resolve_regime_break_date(regime_break, by = grp)
  } else {
    NULL
  }

  # fit-data mask
  has_recent <- !is.null(recent)
  has_break  <- !is.null(bd)

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

  # If bd is per-group, broadcast it as a row-aligned `.bd_join` column
  # so the filter expressions can reference a single column regardless
  # of dispatch mode. NA `.bd_join` (group not in bd) => no filter for
  # that group.
  per_group_bd <- has_break && data.table::is.data.table(bd)
  if (per_group_bd) {
    join_cols <- setdiff(names(bd), "break_date")
    expanded[, .bd_join := bd[expanded, on = join_cols, x.break_date]]
  }

  break_pass <- if (!has_break) {
    quote(TRUE)
  } else if (per_group_bd) {
    quote(is.na(.bd_join) | cohort >= .bd_join)
  } else {
    bquote(cohort >= .(bd))
  }

  if (has_recent && has_break) {
    # hybrid: cohort cut on dev < m_k (ED region), calendar cut on
    # dev >= m_k (CL region). when m_k is NULL, fall back to both
    # filters jointly.
    if (!is.null(m_k)) {
      expanded[, .pass_filter := eval(bquote(
        (dev <  .(m_k) & .(break_pass)) |
        (dev >= .(m_k) & .cal_idx > .max_cal_fit - .(recent))
      ))]
    } else {
      expanded[, .pass_filter := eval(bquote(
        .(break_pass) & (.cal_idx > .max_cal_fit - .(recent))
      ))]
    }
  } else if (has_recent) {
    expanded[, .pass_filter := .cal_idx > .max_cal_fit - recent]
  } else if (has_break) {
    # SA semantics: cohort cut applies only on dev < m_k (ED region);
    # CL region (dev >= m_k) keeps all cohorts. When m_k is NULL,
    # fall back to a simple cohort cut across all dev.
    if (!is.null(m_k)) {
      expanded[, .pass_filter := eval(bquote(
        (dev >= .(m_k)) | .(break_pass)
      ))]
    } else {
      expanded[, .pass_filter := eval(break_pass)]
    }
  } else {
    expanded[, .pass_filter := TRUE]
  }

  if (per_group_bd) expanded[, .bd_join := NULL]

  expanded[, is_fit_data := is_observed & !is_held_out & .pass_filter]
  expanded[, is_excluded := is_observed & !is_held_out & !is_fit_data]

  expanded[, status := data.table::fcase(
    is_held_out, "holdout",
    is_fit_data, "used",
    is_excluded, "unused",
    default     = "future"
  )]
  expanded[, status := factor(
    status,
    levels = c("unused", "used", "holdout", "future")
  )]

  expanded[, c(".pass_filter", ".max_cal_fit") := NULL]
  expanded[]
}


# Internal: usage-mask renderer dispatched from plot_triangle.Triangle
# when type = "usage".
.plot_triangle_usage <- function(x,
                                 recent        = NULL,
                                 regime_break  = NULL,
                                 holdout       = NULL,
                                 maturity_args = NULL,
                                 metric        = "loss",
                                 theme         = c("view", "save", "shiny"),
                                 ...) {

  .assert_class(x, "Triangle")
  theme <- match.arg(theme)

  grp      <- attr(x, "groups")
  coh      <- attr(x, "cohort")
  coh_type <- .get_period_type(coh)
  dev  <- attr(x, "dev")
  if (is.null(grp)) grp <- character(0)

  # 2-pass maturity detection: needed whenever regime_break is set, so the
  # SA-mode dev split (cohort cut on dev < k*; CL region unfiltered, or
  # recent wedge on dev >= k* when `recent` is also set) is reflected.
  # `bd` may be scalar Date or `[grp..., break_date]` data.table (when a
  # multi-group Regime is passed and grp is non-empty).
  m_k    <- NULL    # scalar fallback (passed to .compute_triangle_usage)
  m_k_dt <- NULL    # per-group [grp..., m_k] data.table for facet-routed vline
  bd <- if (!is.null(regime_break)) {
    .resolve_regime_break_date(regime_break, by = grp)
  } else {
    NULL
  }

  if (!is.null(bd)) {
    margs <- if (is.null(maturity_args)) list() else maturity_args
    fit_for_mat <- tryCatch(
      do.call(fit_ata,
              c(list(x = x, target = metric, maturity_args = margs))),
      error = function(e) NULL
    )
    if (!is.null(fit_for_mat) &&
        !is.null(fit_for_mat$maturity) &&
        nrow(fit_for_mat$maturity) > 0L &&
        !all(is.na(fit_for_mat$maturity$ata_to))) {
      mat <- fit_for_mat$maturity
      if (length(grp) > 0L && nrow(mat) > 1L &&
          all(grp %in% names(mat))) {
        m_k_dt <- mat[, c(grp, "ata_to"), with = FALSE]
        data.table::setnames(m_k_dt, "ata_to", "m_k")
        m_k_dt <- m_k_dt[is.finite(m_k)]
        if (!nrow(m_k_dt)) m_k_dt <- NULL
        m_k <- max(mat$ata_to, na.rm = TRUE)
      } else {
        m_k <- max(mat$ata_to, na.rm = TRUE)
      }
    }
  }

  dt <- .compute_triangle_usage(
    x,
    recent       = recent,
    regime_break = regime_break,
    holdout      = holdout,
    m_k        = m_k
  )

  # cohort labels: most recent at top
  if (!is.na(coh_type)) {
    dt[, .y := .format_period(cohort, type = coh_type)]
  } else {
    dt[, .y := as.character(cohort)]
  }
  y_levels <- sort(unique(dt$.y), decreasing = TRUE)
  dt[, .y := factor(.y, levels = y_levels)]

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
  # `m_k_dt` (when present) is a `[grp..., m_k]` data.table — each facet
  # draws its own k* boundary. Falls back to scalar `m_k` for single
  # group / pooled. Mirrors the regime-break hline dispatch below.
  if (!is.null(m_k_dt)) {
    vline_df <- data.table::copy(m_k_dt)
    vline_df[, .xint := m_k - 0.5]
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

  # horizontal regime-break line. The y axis is a discrete factor with
  # levels sorted descending; the break row is the row whose label
  # corresponds to the smallest cohort >= bd. Draw the line just above
  # that row (toward older cohorts).
  #
  # `bd` may be a scalar Date (single break applied to every facet) or a
  # per-group `[grp..., break_date]` data.table (each facet draws its
  # own break). In the per-group case the grp-keyed data.frame is
  # passed via `data = ...` so ggplot2's faceting machinery maps each
  # hline to the correct facet.
  if (!is.null(bd)) {
    .first_post_idx <- function(bd_scalar) {
      cohorts_sorted <- sort(unique(dt$cohort))
      post_break <- cohorts_sorted[cohorts_sorted >= bd_scalar]
      if (!length(post_break)) return(NA_integer_)
      first_post <- min(post_break)
      lab <- if (!is.na(coh_type)) {
        .format_period(first_post, type = coh_type)
      } else {
        as.character(first_post)
      }
      match(lab, y_levels)
    }

    if (data.table::is.data.table(bd) && length(grp)) {
      hline_df <- data.table::copy(bd)
      data.table::setnames(hline_df, "break_date", ".bd")
      hline_df[, .yint := vapply(.bd, .first_post_idx, integer(1L)) + 0.5]
      hline_df <- hline_df[is.finite(.yint)]
      if (nrow(hline_df)) {
        p <- p + ggplot2::geom_hline(
          data        = hline_df,
          mapping     = ggplot2::aes(yintercept = .yint),
          linetype    = "dashed", color = "black", linewidth = 0.4,
          inherit.aes = FALSE
        )
      }
    } else {
      bd_scalar <- if (data.table::is.data.table(bd)) max(bd$break_date) else bd
      idx <- .first_post_idx(bd_scalar)
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
  if (!is.null(bd))           parts <- c(parts, sprintf("regime_break=%s", format(bd)))
  if (!is.null(holdout))      parts <- c(parts, sprintf("holdout=%d", as.integer(holdout)))
  title_txt <- if (length(parts)) {
    sprintf("Data usage (%s)", paste(parts, collapse = ", "))
  } else {
    "Data usage (full)"
  }

  subtitle_txt <- if (!is.null(m_k_dt)) {
    sprintf("hybrid mode: maturity k* per group (range %g-%g)",
            min(m_k_dt$m_k), max(m_k_dt$m_k))
  } else if (!is.null(m_k)) {
    sprintf("hybrid mode: maturity k* = %g", m_k)
  } else {
    NULL
  }

  p <- p + ggplot2::labs(
    title    = title_txt,
    subtitle = subtitle_txt,
    x        = .pretty_var_label(dev),
    y        = .cohort_label(coh)
  )

  p + .switch_theme(theme = theme, ...)
}
