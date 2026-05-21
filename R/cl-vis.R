# Projection plot (shared by CL / SA / BF / CC / Premium fits) ----------

#' Projection plot for a projection-level fit
#'
#' @description
#' Role-agnostic projection plot: observed and projected cumulative
#' values by cohort over development periods, with an optional
#' confidence band. The plotted column family is taken from `x$loss`
#' (the fit's standardized role -- `"loss"` for CL / SA / BF / CC,
#' `"premium"` for an `PremiumFit`), so every projection-level fit
#' shares one implementation. The interval is drawn whenever the
#' `<role>_total_se` column is present and finite.
#'
#' @param x A projection-level fit (`CLFit`, `SAFit`, `BFFit`, `CCFit`,
#'   or `PremiumFit`) with a `$full` grid and `$loss` / `$groups` /
#'   `$cohort` / `$dev` slots.
#' @inheritParams plot.CLFit
#'
#' @return A `ggplot` object.
#'
#' @keywords internal
.plot_projection_fit <- function(x,
                                 conf_level     = 0.95,
                                 show_interval  = TRUE,
                                 amount_divisor = "auto",
                                 scales         = c("fixed", "free_y",
                                                    "free_x", "free"),
                                 theme          = c("view", "save", "shiny"),
                                 nrow           = NULL,
                                 ncol           = NULL,
                                 ...) {

  scales <- match.arg(scales)
  theme  <- match.arg(theme)

  if (!is.numeric(conf_level) || length(conf_level) != 1L ||
      is.na(conf_level) || conf_level <= 0 || conf_level >= 1)
    stop("`conf_level` must be a single numeric value in (0, 1).",
         call. = FALSE)
  if (!is.logical(show_interval) || length(show_interval) != 1L ||
      is.na(show_interval))
    stop("`show_interval` must be a single non-missing logical value.",
         call. = FALSE)

  grp    <- .resolve_groups(x)
  dev    <- x$dev
  metric <- x$loss

  obs_col  <- paste0(metric, "_obs")
  proj_col <- paste0(metric, "_proj")
  se_col   <- paste0(metric, "_total_se")

  full <- .copy_dt(x$full)

  # The interval needs a per-cell total SE column; drop it when absent.
  show_interval <- show_interval && se_col %in% names(full) &&
    any(is.finite(full[[se_col]]))

  if (identical(amount_divisor, "auto"))
    amount_divisor <- .auto_divisor(full[[proj_col]])
  meta         <- .get_plot_meta(metric, amount_divisor)
  z_alpha      <- stats::qnorm((1 + conf_level) / 2)
  caption_base <- meta$caption

  obs  <- full[is.finite(full[[obs_col]])  & full$is_observed == TRUE]
  proj <- full[is.finite(full[[proj_col]]) & full$is_observed == FALSE]

  latest_obs  <- obs[, .SD[.N], by = c(grp, "cohort")]
  latest_proj <- full[is.finite(full[[proj_col]]), .SD[.N],
                      by = c(grp, "cohort")]
  first_proj  <- proj[, .SD[1L], by = c(grp, "cohort")]

  bridge <- latest_obs[, .SD, .SDcols = c(grp, "cohort", "dev", obs_col)]
  data.table::setnames(bridge, c("dev", obs_col), c("x_start", "y_start"))
  first_proj2 <- first_proj[, .SD,
                            .SDcols = c(grp, "cohort", "dev", proj_col)]
  data.table::setnames(first_proj2, c("dev", proj_col),
                       c("x_end", "y_end"))
  bridge <- first_proj2[bridge, on = c(grp, "cohort")]
  bridge <- bridge[is.finite(bridge$x_start) & is.finite(bridge$y_start) &
                   is.finite(bridge$x_end)   & is.finite(bridge$y_end)]

  if (show_interval && nrow(proj)) {
    proj$lower <- pmax(0, proj[[proj_col]] - z_alpha * proj[[se_col]])
    proj$upper <- proj[[proj_col]] + z_alpha * proj[[se_col]]
  }

  p <- ggplot2::ggplot()

  if (show_interval && nrow(proj)) {
    p <- p + ggplot2::geom_ribbon(
      data    = proj,
      mapping = ggplot2::aes(x = .data[["dev"]], ymin = .data$lower,
                             ymax = .data$upper, group = 1),
      inherit.aes = FALSE, alpha = 0.15)
  }

  p <- p +
    ggplot2::geom_line(
      data    = obs,
      mapping = ggplot2::aes(x = .data[["dev"]], y = .data[[obs_col]],
                             group = .data[["cohort"]]),
      linewidth = 0.8) +
    ggplot2::geom_segment(
      data    = bridge,
      mapping = ggplot2::aes(x = .data$x_start, y = .data$y_start,
                             xend = .data$x_end, yend = .data$y_end),
      linewidth = 0.8) +
    ggplot2::geom_line(
      data    = proj,
      mapping = ggplot2::aes(x = .data[["dev"]], y = .data[[proj_col]],
                             group = .data[["cohort"]]),
      linewidth = 0.8, linetype = "dashed") +
    ggplot2::geom_point(
      data    = latest_obs,
      mapping = ggplot2::aes(x = .data[["dev"]], y = .data[[obs_col]]),
      size = 1.8) +
    ggplot2::geom_point(
      data    = latest_proj,
      mapping = ggplot2::aes(x = .data[["dev"]], y = .data[[proj_col]]),
      size = 1.8, shape = 1)

  if (!is.null(meta$hline)) {
    p <- p + ggplot2::geom_hline(yintercept = meta$hline,
                                 linetype = "dashed", color = "red")
  }

  p <- p +
    ggplot2::scale_x_continuous(
      labels = function(z) .format_period_safe(z, dev)) +
    .resolve_y_scale(meta, amount_divisor)

  p <- p + ggplot2::facet_wrap(
    c(grp, "cohort"), scales = scales, nrow = nrow, ncol = ncol,
    labeller = .combined_facet_labeller(c(grp, "cohort")))

  p <- p + ggplot2::labs(
    title   = paste0(meta$title, " Projection"),
    x       = .pretty_var_label(dev),
    y       = metric,
    caption = if (show_interval)
      paste0(caption_base, " | Interval: ", round(conf_level * 100), "%")
    else caption_base)

  p + .switch_theme(theme = theme, ...)
}


#' Plot a chain ladder fit
#'
#' @description
#' Visualise an object of class `"CLFit"`.
#'
#' Two plot types are supported:
#' \itemize{
#'   \item `"projection"`: observed and projected cumulative values by cohort
#'     over development periods. Optional confidence bands are drawn using
#'     `loss_total_se`.
#'   \item `"reserve"`: reserve summary by cohort with optional error bars.
#' }
#'
#' @param x An object of class `"CLFit"`.
#' @param type Plot type. One of `"projection"` or `"reserve"`.
#' @param conf_level Confidence level for interval display. Default is
#'   `0.95`.
#' @param show_interval Logical; if `TRUE`, show normal-approximation
#'   confidence intervals. Default is `TRUE`.
#' @param amount_divisor Numeric scaling factor for y-axis labels of amount
#'   variables. Default is `1e8`.
#' @param scales Facet scale argument passed to [ggplot2::facet_wrap()].
#'   One of `"fixed"`, `"free"`, `"free_x"`, or `"free_y"`.
#' @param theme A string passed to [.switch_theme()].
#' @param nrow,ncol Number of rows and columns for [ggplot2::facet_wrap()].
#' @param ... Additional arguments passed to [.switch_theme()].
#'
#' @return A `ggplot` object.
#'
#' @method plot CLFit
#' @export
plot.CLFit <- function(x,
                        type           = c("projection", "reserve"),
                        conf_level     = 0.95,
                        show_interval  = TRUE,
                        amount_divisor = "auto",
                        scales         = c("fixed", "free_y", "free_x", "free"),
                        theme          = c("view", "save", "shiny"),
                        nrow           = NULL,
                        ncol           = NULL,
                        ...) {

  .assert_class(x, "CLFit")

  type   <- match.arg(type)
  scales <- match.arg(scales)
  theme  <- match.arg(theme)

  if (type == "projection")
    return(.plot_projection_fit(
      x,
      conf_level     = conf_level,
      show_interval  = show_interval,
      amount_divisor = amount_divisor,
      scales         = scales,
      theme          = theme,
      nrow           = nrow,
      ncol           = ncol,
      ...
    ))

  # `type = "reserve"` is chain-ladder specific (needs `$summary$reserve`).
  if (!identical(x$method, "mack"))
    stop("`type = \"reserve\"` requires `method = \"mack\"`.", call. = FALSE)

  if (!is.numeric(conf_level) || length(conf_level) != 1L ||
      is.na(conf_level) || conf_level <= 0 || conf_level >= 1)
    stop("`conf_level` must be a single numeric value in (0, 1).",
         call. = FALSE)

  if (!is.logical(show_interval) || length(show_interval) != 1L ||
      is.na(show_interval))
    stop("`show_interval` must be a single non-missing logical value.",
         call. = FALSE)

  grp     <- x$groups
  coh     <- x$cohort
  dev <- x$dev
  metric <- x$loss

  if (is.null(grp)) grp <- character(0)

  if (identical(amount_divisor, "auto"))
    amount_divisor <- .auto_divisor(x$full[["loss_proj"]])
  meta         <- .get_plot_meta(metric, amount_divisor)
  z_alpha      <- stats::qnorm((1 + conf_level) / 2)
  caption_base <- meta$caption

  # --- reserve (mack only) ----------------------------------------------
  smr <- .copy_dt(x$summary)

  coh_raw  <- smr[["cohort"]]
  coh_type <- .get_period_type(coh, grain = attr(x$data, "grain"))
  coh_lab  <- if (!is.na(coh_type)) {
    .format_period(coh_raw, type = coh_type, abb = TRUE)
  } else {
    as.character(coh_raw)
  }

  smr[, (".coh") := factor(coh_lab, levels = unique(coh_lab[order(coh_raw)]))]

  if (show_interval) {
    smr[, `:=`(
      lower = pmax(0, reserve - z_alpha * loss_total_se),
      upper = reserve + z_alpha * loss_total_se
    )]
  }

  # base plot
  p <- ggplot2::ggplot(
    smr,
    ggplot2::aes(x = .data$.coh, y = .data$reserve)
  ) +
    ggplot2::geom_col()

  if (!is.null(meta$hline)) {
    p <- p + ggplot2::geom_hline(
      yintercept = meta$hline,
      linetype   = "dashed",
      color      = "red"
    )
  }

  if (show_interval) {
    p <- p + ggplot2::geom_errorbar(
      ggplot2::aes(ymin = .data$lower, ymax = .data$upper),
      width = 0.2
    )
  }

  # scale and coord
  p <- p + .resolve_y_scale(meta, amount_divisor)
  p <- p + ggplot2::coord_flip()

  # facet
  if (length(grp)) {
    p <- p + ggplot2::facet_wrap(
      grp,
      scales = scales,
      nrow   = nrow,
      ncol   = ncol
    )
  }

  # labs
  p <- p + ggplot2::labs(
    title   = paste0(meta$title, " Reserve"),
    x       = "cohort",
    y       = "reserve",
    caption = if (show_interval) {
      paste0(caption_base, " | Interval: ", round(conf_level * 100), "%")
    } else {
      caption_base
    }
  )

  # theme
  p + .switch_theme(theme = theme, ...)
}


#' Plot a stage-adaptive fit
#'
#' @description
#' Projection plot for a `"SAFit"` -- observed and projected cumulative
#' loss by cohort, delegated to `.plot_projection_fit()`.
#'
#' @param x An object of class `"SAFit"`.
#' @param ... Forwarded to `.plot_projection_fit()` -- `conf_level`,
#'   `show_interval`, `amount_divisor`, `scales`, `theme`, `nrow`,
#'   `ncol`, plus theme options.
#'
#' @return A `ggplot` object.
#'
#' @method plot SAFit
#' @export
plot.SAFit <- function(x, ...) {
  .assert_class(x, "SAFit")
  .plot_projection_fit(x, ...)
}


#' Plot a Bornhuetter-Ferguson fit
#'
#' @description
#' Projection plot for a `"BFFit"` -- observed and projected cumulative
#' loss by cohort, delegated to `.plot_projection_fit()`.
#'
#' @param x An object of class `"BFFit"`.
#' @param ... Forwarded to `.plot_projection_fit()` -- see [plot.SAFit()].
#'
#' @return A `ggplot` object.
#'
#' @method plot BFFit
#' @export
plot.BFFit <- function(x, ...) {
  .assert_class(x, "BFFit")
  .plot_projection_fit(x, ...)
}


#' Plot a Cape Cod fit
#'
#' @description
#' Projection plot for a `"CCFit"` -- observed and projected cumulative
#' loss by cohort, delegated to `.plot_projection_fit()`.
#'
#' @param x An object of class `"CCFit"`.
#' @param ... Forwarded to `.plot_projection_fit()` -- see [plot.SAFit()].
#'
#' @return A `ggplot` object.
#'
#' @method plot CCFit
#' @export
plot.CCFit <- function(x, ...) {
  .assert_class(x, "CCFit")
  .plot_projection_fit(x, ...)
}


#' Plot an premium fit
#'
#' @description
#' Projection plot for an `"PremiumFit"` -- observed and projected
#' cumulative premium by cohort, delegated to `.plot_projection_fit()`.
#' Defined so an `PremiumFit` does not fall through to [plot.CLFit()],
#' whose `$full` schema is loss-side.
#'
#' @param x An object of class `"PremiumFit"`.
#' @param ... Forwarded to `.plot_projection_fit()` -- see [plot.SAFit()].
#'
#' @return A `ggplot` object.
#'
#' @method plot PremiumFit
#' @export
plot.PremiumFit <- function(x, ...) {
  .assert_class(x, "PremiumFit")
  .plot_projection_fit(x, ...)
}


#' Triangle-table plot for a projection-level fit
#'
#' @description
#' Role-agnostic triangle-style heatmap shared by the `plot_triangle`
#' methods for `CLFit` / `SAFit` / `BFFit` / `CCFit` / `PremiumFit`.
#' The cell metric and per-cell SE / CV columns are derived from
#' `x$loss` (`loss_*` for the loss-side fits, `premium_*` for an
#' `PremiumFit`).
#'
#' The `region` argument controls which values are shown:
#' \describe{
#'   \item{`"proj"`}{Projected cells only.}
#'   \item{`"full"`}{Observed and projected full triangle.}
#'   \item{`"data"`}{Original observed data from `x$data`.}
#' }
#'
#' The `label_style` argument controls cell labels:
#' \describe{
#'   \item{`"value"`}{Projected value only. Applied to all cells.}
#'   \item{`"cv"`}{Coefficient of variation (%) for projected cells.}
#'   \item{`"se"`}{Standard error for projected cells.}
#'   \item{`"ci"`}{Confidence interval for projected cells.}
#' }
#'
#' @param x A projection-level fit (`CLFit`, `SAFit`, `BFFit`, `CCFit`,
#'   or `PremiumFit`).
#' @param region Cell region to plot (only used when `view = "value"`).
#'   One of `"proj"` (default; projected cells only, observed cells
#'   masked), `"full"` (observed + projected), or `"data"` (observed
#'   from `x$data` -- the raw Triangle, no projection).
#' @param view Plot mode. One of:
#'   \describe{
#'     \item{"value" (default)}{Per-cell metric heatmap. `region`
#'       selects which cells to display.}
#'     \item{"usage"}{Cell-status heatmap (`fit_data` / `excluded` /
#'       `future`) driven by the fit's `x$recent`. `region` is
#'       ignored. CL has no `regime` / maturity hooks, so the
#'       hybrid overlays do not apply.}
#'   }
#' @param label_style One of `"value"` (default), `"cv"`, `"se"`, or
#'   `"ci"`.
#' @param label_size Numeric size of the in-cell text label. Defaults
#'   to `3` for `label_style = "value"`, `"cv"`, or `"se"` and `2.5`
#'   for `label_style = "ci"` (two-line labels).
#' @param conf_level Confidence level used when `label_style = "ci"`.
#'   Default is `0.95`.
#' @param amount_divisor Numeric scaling factor for amount variables.
#'   Default is `1`.
#' @param theme A string passed to [.switch_theme()].
#' @param nrow,ncol Number of rows and columns for [ggplot2::facet_wrap()].
#' @param ... Additional arguments passed to [.switch_theme()].
#'
#' @return A ggplot object.
#'
#' @keywords internal
.plot_triangle_fit <- function(x,
                                region         = c("proj", "full", "data"),
                                view           = c("value", "usage"),
                                label_style    = c("value", "cv", "se", "ci"),
                                label_size     = NULL,
                                conf_level     = 0.95,
                                amount_divisor = "auto",
                                theme          = c("view", "save", "shiny"),
                                nrow           = NULL,
                                ncol           = NULL,
                                ...) {

  # Suppress R CMD check NOTEs for `data.table` temp columns referenced
  # bare inside `j` expressions later in this function.
  .value <- .cv <- .se <- is_observed <- NULL

  region      <- match.arg(region)
  view        <- match.arg(view)
  label_style <- match.arg(label_style)
  theme       <- match.arg(theme)
  if (is.null(label_size))
    label_size <- if (label_style == "ci") 2.5 else 3

  # view = "usage": cell-status heatmap driven by the fit's `recent`
  # metadata (CL has no regime / maturity hooks).
  if (view == "usage") {
    return(.plot_triangle_usage(
      x$data,
      recent   = x$recent,
      regime   = NULL,
      holdout  = NULL,
      maturity = "auto",
      theme    = theme,
      ...
    ))
  }

  # cv / se / ci labels need per-cell standard errors on the fit.
  if (label_style != "value" &&
      !paste0(x$loss, "_total_se") %in% names(x$full))
    stop(
      "`label_style = \"", label_style,
      "\"` requires per-cell standard errors on the fit.",
      call. = FALSE
    )

  if (!is.numeric(conf_level) || length(conf_level) != 1L ||
      is.na(conf_level) || conf_level <= 0 || conf_level >= 1)
    stop("`conf_level` must be a single numeric value in (0, 1).", call. = FALSE)

  grp     <- x$groups
  coh     <- x$cohort
  dev <- x$dev
  metric <- x$loss

  if (is.null(grp)) grp <- character(0)

  if (length(coh) != 1L)
    stop("`x` must contain exactly one `cohort`.", call. = FALSE)
  if (length(dev) != 1L)
    stop("`x` must contain exactly one `dev`.", call. = FALSE)

  ratio_vars <- c("ratio", "incr_ratio")
  prop_vars  <- c("loss_share", "incr_loss_share",
                  "premium_share", "incr_premium_share")
  is_ratio   <- metric %in% c(ratio_vars, prop_vars)

  base_title <- switch(
    metric,
    ratio               = "Cumulative Loss Ratio",
    incr_ratio          = "Per-Period Loss Ratio",
    loss                = "Cumulative Loss",
    incr_loss           = "Per-Period Loss",
    premium             = "Cumulative Premium",
    incr_premium        = "Per-Period Premium",
    margin              = "Cumulative Margin",
    incr_margin         = "Per-Period Margin",
    loss_share          = "Cumulative Loss Proportion",
    incr_loss_share     = "Per-Period Loss Proportion",
    premium_share       = "Cumulative Premium Proportion",
    incr_premium_share  = "Per-Period Premium Proportion",
    metric
  )

  region_title <- switch(region,
                         proj = "Projected",
                         full = "Full",
                         data = "Observed")
  title_txt    <- paste(region_title, base_title)

  # 1) select data source -----------------------------------------------
  dt <- .copy_dt(
    switch(region, data = x$data, full = x$full, proj = x$proj)
  )

  if (region == "data") {
    dt[, (".value") := .SD[[1L]], .SDcols = metric]
  } else {
    dt[, (".value") := .SD[[1L]], .SDcols = paste0(metric, "_proj")]
  }

  if (identical(amount_divisor, "auto"))
    amount_divisor <- .auto_divisor(
      if (is_ratio) numeric(0) else dt[[".value"]]
    )

  # 2) period label -----------------------------------------------------
  grain    <- attr(x$data, "grain")
  coh_type <- .get_period_type(coh, grain = grain)
  if (!is.na(coh_type)) {
    dt[, (".y") := .format_period(
      .SD[["cohort"]], type = coh_type, abb = TRUE
    ), .SDcols = "cohort"]
  } else {
    dt[, (".y") := as.character(.SD[["cohort"]]), .SDcols = "cohort"]
  }

  # 3) build cell label -------------------------------------------------
  z_alpha  <- stats::qnorm((1 + conf_level) / 2)
  unit_txt <- .get_amount_unit(amount_divisor)

  if (label_style == "value" || region == "data") {
    if (is_ratio) {
      dt[, ("label") := data.table::fifelse(
        is.na(.value), "", sprintf("%.0f", .value * 100)
      )]
    } else {
      dt[, ("label") := data.table::fifelse(
        is.na(.value), "", sprintf("%.1f", .value / amount_divisor)
      )]
    }

  } else {
    dt[, ("label") := ""]

    # Alias the metric's per-cell SE / CV to fixed names so the label
    # expressions stay role-agnostic (loss_* for CL/SA/BF/CC,
    # premium_* for an PremiumFit).
    dt[, (".se") := .SD[[1L]], .SDcols = paste0(metric, "_total_se")]
    dt[, (".cv") := .SD[[1L]], .SDcols = paste0(metric, "_total_cv")]

    if (label_style == "cv") {
      dt[is_observed == FALSE & is.finite(.cv),
         ("label") := sprintf("%.0f", .cv * 100)]

    } else if (label_style == "se") {
      if (is_ratio) {
        dt[is_observed == FALSE & is.finite(.se),
           ("label") := sprintf("%.3f", .se)]
      } else {
        dt[is_observed == FALSE & is.finite(.se),
           ("label") := sprintf("%.1f", .se / amount_divisor)]
      }

    } else if (label_style == "ci") {
      if (is_ratio) {
        dt[is_observed == FALSE & is.finite(.se),
           ("label") := sprintf(
             "[%.0f, %.0f]",
             pmax(0, .value - z_alpha * .se) * 100,
             (.value + z_alpha * .se) * 100
           )]
      } else {
        dt[is_observed == FALSE & is.finite(.se),
           ("label") := sprintf(
             "[%.1f, %.1f]",
             pmax(0, .value - z_alpha * .se) / amount_divisor,
             (.value + z_alpha * .se) / amount_divisor
           )]
      }
    }
  }

  # 4) caption ----------------------------------------------------------
  caption_txt <- if (label_style == "value") {
    if (is_ratio) {
      "Unit: %"
    } else if (nzchar(unit_txt)) {
      paste("Unit:", unit_txt)
    } else {
      NULL
    }
  } else if (label_style == "cv") {
    if (!is_ratio && nzchar(unit_txt)) {
      paste("Label: CV (%) | Unit:", unit_txt)
    } else {
      "Label: CV (%)"
    }
  } else if (label_style == "se") {
    if (is_ratio) {
      "Label: SE"
    } else if (nzchar(unit_txt)) {
      paste("Label: SE | Unit:", unit_txt)
    } else {
      "Label: SE"
    }
  } else {
    ci_txt <- sprintf("Label: %d%% CI [lower, upper]", round(conf_level * 100))
    if (is_ratio) {
      ci_txt
    } else if (nzchar(unit_txt)) {
      paste(ci_txt, "| Unit:", unit_txt)
    } else {
      ci_txt
    }
  }

  # 5) fill args --------------------------------------------------------
  fill_args <- if (metric %in% ratio_vars) {
    list(threshold = 1)
  } else if (metric %in% prop_vars) {
    list(threshold = 0.05)
  } else {
    list(when = "<", threshold = 0)
  }

  # 6) base plot --------------------------------------------------------
  label_args <- .modify_label_args(list(size = label_size))
  p <- .cell_grid(
    data       = dt,
    x          = "dev",
    y          = ".y",
    label      = "label",
    fill       = ".value",
    fill_scale = "threshold",
    fill_args  = fill_args,
    label_args = label_args,
    border     = "panel"
  )

  # 7) facet
  if (length(grp)) {
    p <- p + ggplot2::facet_wrap(
      grp,
      nrow = nrow,
      ncol = ncol
    )
  }

  # 8) labs
  p <- p + ggplot2::labs(
    title   = title_txt,
    y       = .cohort_label(coh, grain = grain),
    caption = caption_txt
  )

  # 9) theme
  p + .switch_theme(theme = theme, ...)
}


#' Plot a chain ladder fit as a triangle table
#'
#' @description
#' Triangle-style heatmap for a `"CLFit"`. Delegates to the shared
#' role-agnostic `.plot_triangle_fit()` implementation.
#'
#' @param x An object of class `"CLFit"`.
#' @param ... Forwarded to `.plot_triangle_fit()` -- `region`, `view`,
#'   `label_style`, `label_size`, `conf_level`, `amount_divisor`,
#'   `theme`, `nrow`, `ncol`.
#'
#' @return A `ggplot` object.
#'
#' @method plot_triangle CLFit
#' @export
plot_triangle.CLFit <- function(x, ...) {
  .assert_class(x, "CLFit")
  .plot_triangle_fit(x, ...)
}


#' Plot a stage-adaptive fit as a triangle table
#'
#' @description
#' Triangle-style heatmap for a `"SAFit"`. Delegates to the
#' shared role-agnostic `.plot_triangle_fit()` implementation.
#'
#' @param x An object of class `"SAFit"`.
#' @param ... Forwarded to the shared implementation -- `region`,
#'   `view`, `label_style`, `label_size`, `conf_level`,
#'   `amount_divisor`, `theme`, `nrow`, `ncol`.
#'
#' @return A `ggplot` object.
#'
#' @method plot_triangle SAFit
#' @export
plot_triangle.SAFit <- function(x, ...) {
  .assert_class(x, "SAFit")
  .plot_triangle_fit(x, ...)
}


#' Plot a Bornhuetter-Ferguson fit as a triangle table
#'
#' @description
#' Triangle-style heatmap for a `"BFFit"`. Delegates to the
#' shared role-agnostic `.plot_triangle_fit()` implementation.
#'
#' @param x An object of class `"BFFit"`.
#' @param ... Forwarded to the shared implementation -- see
#'   [plot_triangle.SAFit()].
#'
#' @return A `ggplot` object.
#'
#' @method plot_triangle BFFit
#' @export
plot_triangle.BFFit <- function(x, ...) {
  .assert_class(x, "BFFit")
  .plot_triangle_fit(x, ...)
}


#' Plot a Cape Cod fit as a triangle table
#'
#' @description
#' Triangle-style heatmap for a `"CCFit"`. Delegates to the
#' shared role-agnostic `.plot_triangle_fit()` implementation.
#'
#' @param x An object of class `"CCFit"`.
#' @param ... Forwarded to the shared implementation -- see
#'   [plot_triangle.SAFit()].
#'
#' @return A `ggplot` object.
#'
#' @method plot_triangle CCFit
#' @export
plot_triangle.CCFit <- function(x, ...) {
  .assert_class(x, "CCFit")
  .plot_triangle_fit(x, ...)
}


#' Plot an premium fit as a triangle table
#'
#' @description
#' Triangle-style heatmap for an `"PremiumFit"`. Delegates to the
#' shared role-agnostic `.plot_triangle_fit()` implementation;
#' the cell metric is the premium projection.
#'
#' @param x An object of class `"PremiumFit"`.
#' @param ... Forwarded to the shared implementation -- see
#'   [plot_triangle.SAFit()].
#'
#' @return A `ggplot` object.
#'
#' @method plot_triangle PremiumFit
#' @export
plot_triangle.PremiumFit <- function(x, ...) {
  .assert_class(x, "PremiumFit")
  .plot_triangle_fit(x, ...)
}
