

# Ratio Fit Plot -----------------------------------------------------------

#' Plot a loss ratio fit
#'
#' @description
#' Visualise an object of class `"RatioFit"`.
#'
#' The plotted metric is the cross-product of `metric` and `cell_type`:
#' \itemize{
#'   \item `metric = "ratio"`, `cell_type = "cumulative"`: cumulative loss
#'     ratio (default).
#'   \item `metric = "incr_ratio"` (i.e., `cell_type = "incremental"`):
#'     per-period loss ratio.
#'   \item `metric = "loss"` / `"exposure"`: same split -- cumulative or
#'     per-period amounts.
#' }
#' Confidence bands are drawn only for cumulative metrics
#' (`cell_type = "cumulative"`), since the fit output does not carry SE
#' columns for incremental projections.
#'
#' @param x An object of class `"RatioFit"`.
#' @param metric Metric to plot. One of `"ratio"` (default), `"loss"`,
#'   `"exposure"`.
#' @param cell_type Aggregation. One of `"cumulative"` (default) or
#'   `"incremental"`.
#' @param per_group Logical or `NULL`. When `TRUE` (auto for multi-group
#'   fits), produce one ggplot per group and print them sequentially
#'   with [devAskNewPage()] -- mirrors base R's `plot.lm()` pattern of
#'   stepping through related diagnostic plots. Returns the list of
#'   plots invisibly. When `FALSE` (auto for single-group fits), facets
#'   every (group, cohort) combination in a single ggplot.
#' @param ask Passed to [devAskNewPage()] when `per_group = TRUE`.
#'   Defaults to `dev.interactive()`.
#' @param conf_level Confidence level. Default is `0.95`.
#' @param show_interval Logical. Default is `TRUE`.
#' @param amount_divisor Numeric. Default is `1e8`.
#' @param scales Facet scale argument.
#' @param theme Theme string.
#' @param nrow,ncol Facet dimensions.
#' @param ... Additional arguments.
#'
#' @return A `ggplot` object.
#'
#' @method plot RatioFit
#' @export
plot.RatioFit <- function(x,
                          metric         = c("ratio", "loss", "exposure"),
                          cell_type      = c("cumulative", "incremental"),
                          per_group      = NULL,
                          ask            = grDevices::dev.interactive(),
                          conf_level     = 0.95,
                          show_interval  = TRUE,
                          amount_divisor = "auto",
                          scales         = c("fixed", "free_y",
                                             "free_x", "free"),
                          theme = c("view", "save", "shiny"),
                          nrow  = NULL,
                          ncol  = NULL,
                          ...) {

  .assert_class(x, "RatioFit")

  # Suppress R CMD check NOTEs for `data.table` temp columns referenced
  # bare inside `j` expressions later in this function.
  .y <- NULL

  metric    <- match.arg(metric)
  cell_type <- match.arg(cell_type)
  scales    <- match.arg(scales)
  theme     <- match.arg(theme)

  grp     <- x$groups
  coh     <- x$cohort
  dev <- x$dev

  if (is.null(grp)) grp <- character(0)

  z_alpha <- stats::qnorm((1 + conf_level) / 2)

  full <- .copy_dt(x$full)

  if (identical(amount_divisor, "auto"))
    amount_divisor <- .auto_divisor(
      if (metric == "ratio") numeric(0) else full[[paste0(metric, "_proj")]]
    )

  ci_type <- if (!is.null(x$ci_type)) x$ci_type else "analytical"

  is_incr  <- cell_type == "incremental"
  is_ratio <- metric == "ratio"

  # column key combines metric + cell_type -- e.g., "ratio" + "incremental" = "incr_ratio_proj"
  col_key <- if (is_incr) paste0("incr_", metric) else metric
  val_col <- paste0(col_key, "_proj")

  # Only cumulative metrics have CI columns; incremental projections
  # don't carry SE / CI columns in the fit output.
  if (!is_incr && is_ratio) {
    ci_lo_col <- "ratio_ci_lo";   ci_hi_col <- "ratio_ci_hi"
  } else if (!is_incr && metric == "loss") {
    ci_lo_col <- "loss_ci_lo"; ci_hi_col <- "loss_ci_hi"
  } else if (!is_incr && metric == "exposure") {
    ci_lo_col <- "exposure_ci_lo"; ci_hi_col <- "exposure_ci_hi"
  } else {
    ci_lo_col <- NA_character_;   ci_hi_col <- NA_character_
  }

  cum_word <- if (is_incr) "Per-Period" else "Cumulative"
  base_lab <- switch(
    metric,
    ratio    = "Loss Ratio",
    loss     = "Loss",
    exposure = "Premium"
  )
  y_lab <- if (is_ratio) col_key else attr(x$data, metric)
  title <- paste0("Projected ", cum_word, " ", base_lab,
                  " (method: ", x$method, ")")
  hline <- if (is_ratio && !is_incr) 1
           else if (!is_ratio)       0
           else                       NULL
  meta  <- list(type = if (is_ratio) "ratio" else "amount")

  obs  <- full[is_observed == TRUE  & is.finite(loss_obs)]
  proj <- full[is_observed == FALSE & is.finite(full[[val_col]])]

  # Observed-cell value:
  #   * Cumulative loss / exposure read the raw `_obs` column.
  #   * Cumulative ratio is derived as loss_obs / exposure_obs.
  #   * Incremental metrics reuse `<metric>_incr_proj` since
  #     loss/exposure_proj equals their `_obs` counterparts on observed rows.
  if (is_incr) {
    obs[, (".y") := .SD[[1L]], .SDcols = val_col]
  } else if (metric == "loss") {
    obs[, (".y") := loss_obs]
  } else if (metric == "exposure") {
    obs[, (".y") := exposure_obs]
  } else {  # cumulative ratio
    obs[, (".y") := data.table::fifelse(
      is.finite(exposure_obs) & exposure_obs != 0,
      loss_obs / exposure_obs, NA_real_
    )]
  }

  proj[, (".y") := proj[[val_col]]]

  # CI bounds read directly from $full (works for both analytical and bootstrap)
  if (show_interval && nrow(proj) &&
      ci_lo_col %in% names(proj) && ci_hi_col %in% names(proj)) {
    proj[, `:=`(
      lower = proj[[ci_lo_col]],
      upper = proj[[ci_hi_col]]
    )]
  }

  # bridge segment
  latest_obs <- obs[, .SD[.N], by = c(grp, "cohort")]
  first_proj <- proj[, .SD[1L], by = c(grp, "cohort")]

  bridge <- latest_obs[
    , .SD, .SDcols = c(grp, "cohort", "dev", ".y")
  ]
  data.table::setnames(bridge, c("dev", ".y"), c("x_start", "y_start"))

  first_proj2 <- first_proj[
    , .SD, .SDcols = c(grp, "cohort", "dev", ".y")
  ]
  data.table::setnames(first_proj2, c("dev", ".y"), c("x_end", "y_end"))
  bridge <- first_proj2[bridge, on = c(grp, "cohort")]
  bridge <- bridge[is.finite(x_start) & is.finite(y_start) &
                   is.finite(x_end)   & is.finite(y_end)]

  # Internal builder: assemble one ggplot from (obs, proj, bridge)
  # subsets and a list of facet variables. Called once for the combined
  # plot (length(grp) <= 1 OR per_group = FALSE) or once per group.
  build_plot <- function(obs_, proj_, bridge_, facet_vars, title_) {
    p <- ggplot2::ggplot()

    if (show_interval && nrow(proj_) &&
        "lower" %in% names(proj_)) {
      p <- p + ggplot2::geom_ribbon(
        data    = proj_,
        mapping = ggplot2::aes(
          x = .data[["dev"]], ymin = lower, ymax = upper, group = 1
        ),
        inherit.aes = FALSE,
        alpha       = 0.15
      )
    }

    # Skip geom_line for cohorts with <2 rows (single point would emit
    # ggplot2's "Each group consists of only one observation" warning).
    # Render them with geom_point instead so the value is still visible.
    obs_line  <- obs_[,  if (.N >= 2L) .SD, by = c(grp, "cohort")]
    obs_pt    <- obs_[,  if (.N <  2L) .SD, by = c(grp, "cohort")]
    proj_line <- proj_[, if (.N >= 2L) .SD, by = c(grp, "cohort")]
    proj_pt   <- proj_[, if (.N <  2L) .SD, by = c(grp, "cohort")]

    if (nrow(obs_line)) {
      p <- p + ggplot2::geom_line(
        data      = obs_line,
        mapping   = ggplot2::aes(x = .data[["dev"]], y = .y,
                                 group = .data[["cohort"]]),
        linewidth = 0.8
      )
    }
    if (nrow(obs_pt)) {
      p <- p + ggplot2::geom_point(
        data    = obs_pt,
        mapping = ggplot2::aes(x = .data[["dev"]], y = .y),
        size    = 1.8
      )
    }
    p <- p + ggplot2::geom_segment(
      data    = bridge_,
      mapping = ggplot2::aes(
        x = x_start, y = y_start, xend = x_end, yend = y_end
      ),
      linewidth = 0.8
    )
    if (nrow(proj_line)) {
      p <- p + ggplot2::geom_line(
        data      = proj_line,
        mapping   = ggplot2::aes(x = .data[["dev"]], y = .y,
                                 group = .data[["cohort"]]),
        linewidth = 0.8,
        linetype  = "dashed"
      )
    }
    if (nrow(proj_pt)) {
      p <- p + ggplot2::geom_point(
        data    = proj_pt,
        mapping = ggplot2::aes(x = .data[["dev"]], y = .y),
        size    = 1.8,
        shape   = 1
      )
    }

    if (!is.null(hline)) {
      p <- p + ggplot2::geom_hline(
        yintercept = hline,
        linetype   = "dashed",
        color      = "red"
      )
    }

    if (meta$type == "ratio") {
      p <- p + ggplot2::scale_y_continuous(
        labels = function(z) paste0(round(z * 100), "%")
      )
    } else {
      p <- p + .resolve_y_scale(meta, amount_divisor)
    }

    if (length(facet_vars)) {
      p <- p + ggplot2::facet_wrap(
        facet_vars,
        scales   = scales,
        nrow     = nrow,
        ncol     = ncol,
        labeller = .combined_facet_labeller(facet_vars)
      )
    }

    p <- p + ggplot2::labs(
      title   = title_,
      x       = .pretty_var_label(dev),
      y       = y_lab,
      caption = if (show_interval) {
        sprintf("Interval: %d%% (%s)",
                round(conf_level * 100), ci_type)
      } else {
        NULL
      }
    )

    p + .switch_theme(theme = theme, ...)
  }

  # Default per_group: TRUE iff the fit has >1 group value on >=1 group
  # column. Single-group fits keep the combined-facet behaviour.
  if (is.null(per_group)) {
    per_group <- length(grp) > 0L &&
                 nrow(unique(full[, grp, with = FALSE])) > 1L
  }

  if (per_group && length(grp) > 0L) {
    # split obs/proj/bridge per first group column; each group becomes a
    # standalone ggplot faceted by cohort only.
    g0       <- grp[1L]
    grp_vals <- sort(unique(full[[g0]]))
    grDevices::devAskNewPage(ask)
    on.exit(grDevices::devAskNewPage(FALSE), add = TRUE)

    plots <- lapply(grp_vals, function(gv) {
      o  <- obs[obs[[g0]] == gv]
      pr <- proj[proj[[g0]] == gv]
      br <- bridge[bridge[[g0]] == gv]
      title_g <- sprintf("%s [%s = %s]", title, g0, gv)
      p <- build_plot(o, pr, br, facet_vars = "cohort", title_ = title_g)
      print(p)
      p
    })
    names(plots) <- as.character(grp_vals)
    return(invisible(plots))
  }

  build_plot(obs, proj, bridge,
             facet_vars = c(grp, "cohort"),
             title_     = title)
}


# Ratio Fit Triangle Plot --------------------------------------------------

#' Plot loss ratio projection as a triangle heatmap
#'
#' @description
#' Visualise an `"RatioFit"` object as a triangle-style heatmap of
#' cumulative loss ratios. Observed and projected cells are
#' distinguished by border style.
#'
#' @param x An object of class `"RatioFit"`.
#' @param metric Metric shown in the heatmap cells. One of `"ratio"`
#'   (default), `"loss"`, `"exposure"`.
#' @param cell_type Aggregation. One of `"cumulative"` (default) or
#'   `"incremental"`. Combined with `metric` to select the column
#'   (e.g., `metric = "ratio"`, `cell_type = "incremental"` -> `incr_ratio`).
#' @param region Cell region to plot (only used when `view = "value"`).
#'   One of `"proj"` (projected cells only, observed cells masked),
#'   `"full"` (observed + projected), or `"data"` (observed cumulative
#'   loss / exposure / ratio from `x$data` -- the raw Triangle, no
#'   projection). Default is `"proj"`.
#' @param view Plot mode. One of:
#'   \describe{
#'     \item{"value" (default)}{Per-cell `ratio` heatmap with column-wise
#'       relative fill. `region` selects which cells to display.}
#'     \item{"usage"}{Cell-status heatmap (`used` / `holdout` /
#'       `unused` / `future`) driven by the fit's own metadata
#'       (`x$recent`, `x$loss_regime`, `x$maturity`). `region` is
#'       ignored.}
#'   }
#' @param label_style One of `"value"` (ratio only) or `"detail"`
#'   (ratio with loss/exposure amounts). Default is `"value"`.
#' @param label_size Numeric label text size forwarded to
#'   [ggshort::ggtable()]. Defaults to `3` for `label_style = "value"`
#'   and `2.5` for `label_style = "detail"` (two-line labels).
#' @param show_maturity Logical; if `TRUE`, show maturity line.
#'   Default is `TRUE`.
#' @param digits Number of decimal places for ratio display.
#'   Default is `0`.
#' @param amount_divisor Numeric divisor for amount display in
#'   `"detail"` mode. Default is `1e8`.
#' @param theme Theme string.
#' @param nrow,ncol Facet dimensions.
#' @param ... Additional arguments passed to [.switch_theme()].
#'
#' @return A `ggplot` object.
#'
#' @method plot_triangle RatioFit
#' @export
plot_triangle.RatioFit <- function(x,
                                   metric         = c("ratio", "loss", "exposure"),
                                   cell_type      = c("cumulative", "incremental"),
                                   region         = c("proj", "full", "data"),
                                   view           = c("value", "usage"),
                                   label_style    = c("value", "detail"),
                                   label_size     = NULL,
                                   show_maturity  = TRUE,
                                   digits         = 0,
                                   amount_divisor = "auto",
                                   theme          = c("view", "save", "shiny"),
                                   nrow           = NULL,
                                   ncol           = NULL,
                                   ...) {

  .assert_class(x, "RatioFit")

  # Suppress R CMD check NOTEs for `data.table` temp columns referenced
  # bare inside `j` expressions later in this function.
  .value <- .fill <- .y <- .px <- .py <- .px_max <- .x_pt <- .y_pt <- NULL

  metric      <- match.arg(metric)
  cell_type   <- match.arg(cell_type)
  region      <- match.arg(region)
  view        <- match.arg(view)
  label_style <- match.arg(label_style)
  theme       <- match.arg(theme)

  is_incr  <- cell_type == "incremental"
  is_ratio <- metric == "ratio"
  col_key  <- if (is_incr) paste0("incr_", metric) else metric

  # view = "usage": cell-status heatmap (used / holdout / unused /
  # future). `x$usage` is pre-computed at fit time and carries all the
  # plot-rendering metadata (regime / recent / m_k) on attributes;
  # the renderer reads it directly without re-deriving from filter
  # args. Region is irrelevant in usage view.
  if (view == "usage") {
    return(.plot_triangle_usage(
      x$data,
      usage = x$usage,
      theme = theme,
      ...
    ))
  }
  if (is.null(label_size))
    label_size <- if (label_style == "detail") 2.5 else 3

  grp     <- x$groups
  coh     <- x$cohort
  dev <- x$dev

  if (is.null(grp)) grp <- character(0)

  # 1) select data source (value view)
  dt <- .copy_dt(
    switch(region, proj = x$proj, full = x$full, data = x$data)
  )

  # `data` region uses raw Triangle which has no `is_observed` flag;
  # synthesise it so the projected-cell overlay below sees an empty
  # selection (data region has no projected cells by definition).
  if (region == "data" && !"is_observed" %in% names(dt))
    dt[, ("is_observed") := TRUE]

  # 2) compute .value for (metric, cell_type). The `data` region (raw
  # Triangle) has bare column names (ratio, incr_loss, exposure, ...).
  # The `proj` / `full` regions have the `_proj` suffix on the same base.
  if (region == "data") {
    if (!(col_key %in% names(dt)))
      stop(sprintf("column '%s' not found in `x$data`.", col_key),
           call. = FALSE)
    dt[, (".value") := .SD[[col_key]], .SDcols = col_key]
  } else {
    val_col <- paste0(col_key, "_proj")
    if (!(val_col %in% names(dt)))
      stop(sprintf("column '%s' not found in region '%s'.",
                   val_col, region), call. = FALSE)
    dt[, (".value") := .SD[[val_col]], .SDcols = val_col]
  }

  if (identical(amount_divisor, "auto"))
    amount_divisor <- .auto_divisor(
      if (is_ratio) numeric(0) else dt[[".value"]]
    )

  # 3) build dev link labels
  link_levels <- sort(unique(dt[["dev"]]))
  dt[, ("ata_link") := factor(sprintf("%s", .SD[[1L]]),
                          levels = as.character(link_levels)),
     .SDcols = "dev"]

  # 4) format period labels
  grain    <- attr(x$data, "grain")
  coh_type <- .get_period_type(coh, grain = grain)
  if (!is.na(coh_type)) {
    dt[, (".y") := .format_period(.SD[["cohort"]], type = coh_type, abb = TRUE),
       .SDcols = "cohort"]
  } else {
    dt[, (".y") := as.character(.SD[["cohort"]]), .SDcols = "cohort"]
  }

  # 5) build cell labels
  fmt <- paste0("%.", digits, "f")

  # Ratio metrics (ratio / incr_ratio) render as %. Amount metrics
  # (loss / incr_loss / exposure / incr_exposure) render scaled by
  # `amount_divisor`. `detail` label_style adds the loss/exposure
  # breakdown only for ratio metrics -- meaningless for amounts.
  if (label_style == "value" || !is_ratio) {
    if (is_ratio) {
      dt[, ("label") := data.table::fifelse(
        is.finite(.value), sprintf(fmt, .value * 100), ""
      )]
    } else {
      dt[, ("label") := data.table::fifelse(
        is.finite(.value),
        sprintf("%.1f", .value / amount_divisor), ""
      )]
    }
    caption_txt <- if (is_ratio) {
      sprintf("Unit: %s %% (column-wise relative fill)", col_key)
    } else {
      sprintf("Unit: %s (%s, column-wise relative fill)",
              col_key, .get_amount_unit(amount_divisor))
    }
  } else {
    # ratio + detail: show loss/exposure breakdown beneath the ratio value
    loss_base     <- if (is_incr) "incr_loss"     else "loss"
    exposure_base <- if (is_incr) "incr_exposure" else "exposure"
    loss_col      <- if (region == "data") loss_base     else paste0(loss_base, "_proj")
    exposure_col  <- if (region == "data") exposure_base else paste0(exposure_base, "_proj")
    dt[, ("label") := data.table::fifelse(
      is.finite(.value),
      sprintf(
        paste0(fmt, "\n(%.1f/%.1f)"),
        .value * 100,
        .SD[[1L]] / amount_divisor,
        .SD[[2L]] / amount_divisor
      ),
      ""
    ), .SDcols = c(loss_col, exposure_col)]
    caption_txt <- sprintf(
      "Unit: %s %% (%s, column-wise relative fill)",
      col_key, .get_amount_unit(amount_divisor)
    )
  }

  # 6) column-wise relative fill (centered on per-dev median)
  dt[, (".fill") := .value - stats::median(.value, na.rm = TRUE),
     by = c(grp, "dev")]
  dt[!is.finite(.fill), (".fill") := NA_real_]

  # 7) resolve label_args
  label_args <- .modify_label_args(list(size = label_size))

  plot_data <- dt[is.finite(.value)]

  # ensure .y is a factor with stable levels matching ggheatmap's internal
  # coercion (factor with levels = sort(unique(.y))), so overlays can map
  # to the same integer positions used internally by ggheatmap.
  y_levels <- sort(unique(plot_data$.y))
  plot_data[, (".y") := factor(.y, levels = y_levels)]

  # 8) base heatmap
  p <- ggshort::ggheatmap(
    data       = plot_data,
    x          = ata_link,
    y          = .y,
    label      = label,
    label_args = label_args,
    fill       = .fill,
    fill_args  = list(
      low       = "#D9ECFF",
      mid       = "white",
      high      = "#F8D7DA",
      midpoint  = 0,
      color     = "black",
      linewidth = 0.3,
      guide     = "none",
      na.value  = "grey95"
    )
  )

  # 9) projected cell overlay (dashed border)
  # ggheatmap maps factor x/y to integer positions internally; replicate
  # the same mapping for the overlay so it lands on the continuous scale.
  proj <- plot_data[is_observed == FALSE]
  if (nrow(proj)) {
    proj[, `:=`(
      .px = as.integer(ata_link),
      .py = as.integer(.y)
    )]
    p <- p + ggplot2::geom_tile(
      data        = proj,
      mapping     = ggplot2::aes(x = .px, y = .py),
      fill        = NA,
      color       = "grey50",
      linewidth   = 0.6,
      linetype    = "dashed",
      inherit.aes = FALSE
    )
  }

  # 9b) data / proj boundary (solid black staircase). Only meaningful
  # when both regions are visible (region = "full") and at least one
  # projected cell exists. The path connects (last_obs_px + 0.5,
  # cohort_py +/- 0.5) corners; consecutive cohorts with different
  # last_obs_px naturally fall on a horizontal connector since the
  # y-values share an edge (.py + 0.5 == next .py - 0.5).
  if (region == "full" && nrow(proj)) {
    plot_data[, `:=`(
      .px = as.integer(ata_link),
      .py = as.integer(.y)
    )]
    bdy_path <- plot_data[is_observed == TRUE,
                          .(.px_max = max(.px)),
                          by = c(grp, ".py")]
    data.table::setorderv(bdy_path, c(grp, ".py"))
    bdy_path <- bdy_path[, data.table::data.table(
      .x_pt = as.numeric(rbind(.px_max + 0.5, .px_max + 0.5)),
      .y_pt = as.numeric(rbind(.py - 0.5,     .py + 0.5))
    ), by = grp]

    p <- p + ggplot2::geom_path(
      data        = bdy_path,
      mapping     = ggplot2::aes(x = .x_pt, y = .y_pt),
      color       = "black",
      linewidth   = 0.7,
      inherit.aes = FALSE
    )
  }

  # 10) maturity vline. k* = change (target dev). vline drawn at
  # mat_x - 0.5 = midpoint between (change - 1) and change, i.e.
  # the ED/CL boundary.
  if (show_maturity && !is.null(x$maturity)) {
    mat <- .copy_dt(x$maturity)
    mat <- mat[is.finite(change)]

    if (nrow(mat)) {
      mat[, ("mat_x") := match(change, link_levels)]

      if (length(grp)) {
        p <- p + ggplot2::geom_vline(
          data     = mat,
          mapping  = ggplot2::aes(xintercept = mat_x - 0.5),
          color    = "grey40",
          linetype = "longdash"
        )
      } else if (nrow(mat) == 1L) {
        p <- p + ggplot2::geom_vline(
          xintercept = mat$mat_x[1L] - 0.5,
          color      = "grey40",
          linetype   = "longdash"
        )
      }
    }
  }

  # 11) facet
  if (length(grp)) {
    p <- p + ggplot2::facet_wrap(
      stats::reformulate(grp),
      nrow = nrow,
      ncol = ncol
    )
  }

  # 12) labs
  cum_word   <- if (is_incr) "Per-Period" else "Cumulative"
  base_word  <- switch(metric,
                       ratio    = "Loss Ratio",
                       loss     = "Loss",
                       exposure = "Premium")
  p <- p + ggplot2::labs(
    title   = paste0(cum_word, " ", base_word, " Triangle",
                     " (method: ", x$method, ")"),
    x       = .pretty_var_label(dev),
    y       = .cohort_label(coh, grain = grain),
    caption = caption_txt
  )

  # 13) theme
  p + .switch_theme(theme = theme, ...)
}
