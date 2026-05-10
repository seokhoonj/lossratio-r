# Link diagnostic and triangle plots ---------------------------------------
#
# Unified plotting layer for the merged `Link` class (replaces former
# `R/ata-vis.R` and `R/ed-vis.R`). `plot.Link()` and `plot_triangle.Link()`
# act as dispatchers on the `model` argument and delegate to internal
# helpers `.plot_link_ata()` / `.plot_link_ed()` and
# `.plot_triangle_link_ata()` / `.plot_triangle_link_ed()`.


# plot.Link dispatcher ------------------------------------------------------

#' Plot link-factor diagnostics
#'
#' @description
#' Visualise diagnostic summaries from a `"Link"` object. Dispatches to
#' the multiplicative ATA branch (`model = "ata"`) or the additive
#' exposure-driven branch (`model = "ed"`).
#'
#' The default `model` is chosen from `attr(x, "premium_var")`: `NULL`
#' (single-variable link) selects `"ata"`, a non-`NULL` exposure variable
#' (dual-variable link) selects `"ed"`.
#'
#' @param x An object of class `"Link"`.
#' @param model Either `"ata"` or `"ed"`. Default depends on
#'   `attr(x, "premium_var")`.
#' @param ... Arguments forwarded to the underlying plotting helper. See
#'   the per-model parameter list in Details.
#'
#' @details
#' For `model = "ata"`, accepted arguments include `type`
#' (`"cv" | "rse" | "summary" | "box" | "point"`), `alpha`, `show_maturity`,
#' `max_cv`, `max_rse`, `min_valid_ratio`, `min_n_valid`,
#' `min_run`, `scales`, `nrow`, `ncol`, `theme`, and `x.angle`.
#'
#' For `model = "ed"`, accepted arguments include `type`
#' (`"summary" | "box" | "point"`), `alpha`, `scales`, `nrow`, `ncol`,
#' `theme`, and `x.angle`.
#'
#' @return A `ggplot` object.
#'
#' @method plot Link
#' @export
plot.Link <- function(x, model = NULL, ...) {

  .assert_class(x, "Link")

  if (is.null(model)) {
    model <- if (!is.null(attr(x, "premium_var"))) "ed" else "ata"
  }
  model <- match.arg(model, c("ata", "ed"))

  if (identical(model, "ed") && is.null(attr(x, "premium_var")))
    stop("`model = 'ed'` requires a Link built with `premium_var`.",
         call. = FALSE)

  if (identical(model, "ata")) {
    .plot_link_ata(x, ...)
  } else {
    .plot_link_ed(x, ...)
  }
}


# plot_triangle.Link dispatcher --------------------------------------------

#' Plot a Link object as a triangle heatmap
#'
#' @description
#' Visualise a `"Link"` object as a triangle-style heatmap. Dispatches to
#' the multiplicative ATA branch (`model = "ata"`) or the additive
#' exposure-driven branch (`model = "ed"`).
#'
#' The default `model` is chosen from `attr(x, "premium_var")`: `NULL`
#' selects `"ata"`, non-`NULL` selects `"ed"`.
#'
#' @param x An object of class `"Link"`.
#' @param model Either `"ata"` or `"ed"`. Default depends on
#'   `attr(x, "premium_var")`.
#' @param ... Arguments forwarded to the underlying plotting helper.
#'
#' @return A `ggplot` object.
#'
#' @method plot_triangle Link
#' @export
plot_triangle.Link <- function(x, model = NULL, ...) {

  .assert_class(x, "Link")

  if (is.null(model)) {
    model <- if (!is.null(attr(x, "premium_var"))) "ed" else "ata"
  }
  model <- match.arg(model, c("ata", "ed"))

  if (identical(model, "ed") && is.null(attr(x, "premium_var")))
    stop("`model = 'ed'` requires a Link built with `premium_var`.",
         call. = FALSE)

  if (identical(model, "ata")) {
    .plot_triangle_link_ata(x, ...)
  } else {
    .plot_triangle_link_ed(x, ...)
  }
}


# Internal: ATA-mode diagnostic plot ---------------------------------------

.plot_link_ata <- function(x,
                           type            = c("cv", "rse", "summary", "box", "point"),
                           alpha           = 1,
                           show_maturity   = TRUE,
                           max_cv          = 0.15,
                           max_rse         = 0.05,
                           min_valid_ratio = 0.5,
                           min_n_valid     = 3L,
                           min_run         = 1L,
                           scales          = c("fixed", "free", "free_x", "free_y"),
                           nrow            = NULL,
                           ncol            = NULL,
                           theme           = c("view", "save", "shiny"),
                           x.angle         = 90,
                           ...) {

  .assert_class(x, "Link")

  type   <- match.arg(type)
  scales <- match.arg(scales)
  theme  <- match.arg(theme)

  grp_var <- attr(x, "group_var")
  if (is.null(grp_var)) grp_var <- character(0)

  val_var <- attr(x, "loss_var")
  meta    <- .get_plot_meta(val_var)

  # 1) compute summary --------------------------------------------------
  smr <- summary(x, model = "ata", alpha = alpha)

  # 2) build ata_link label lookup (numeric x axis) ---------------------
  smr[, ata_link_chr := sprintf("%s-%s", ata_from, ata_to)]

  link_labels <- smr[
    , setNames(ata_link_chr, as.character(ata_from))
  ]

  .x_scale <- function() {
    ggplot2::scale_x_continuous(
      breaks = smr$ata_from,
      labels = link_labels[as.character(smr$ata_from)]
    )
  }

  # 3) maturity ---------------------------------------------------------
  mat <- NULL

  if (show_maturity) {
    mat <- .detect_maturity(
      x               = smr,
      max_cv          = max_cv,
      max_rse         = max_rse,
      min_valid_ratio = min_valid_ratio,
      min_n_valid     = min_n_valid,
      min_run         = min_run
    )
    mat <- .ensure_dt(mat)
    mat <- mat[is.finite(ata_from)]
  }

  # 4) shared layers ----------------------------------------------------
  .add_vline <- function(p) {
    if (is.null(mat) || !nrow(mat)) return(p)
    p + ggplot2::geom_vline(
      data     = mat,
      mapping  = ggplot2::aes(xintercept = ata_from),
      color    = "grey40",
      linetype = "longdash"
    )
  }

  .add_shade <- function(p, ymax = Inf) {
    if (is.null(mat) || !nrow(mat)) return(p)

    shade <- if (length(grp_var)) {
      mat[smr[, .(xmax = max(ata_from)), by = grp_var], on = grp_var]
    } else {
      data.table::data.table(
        ata_from = mat$ata_from[1L],
        xmax     = max(smr$ata_from)
      )
    }

    p + ggplot2::geom_rect(
      data    = shade,
      mapping = ggplot2::aes(
        xmin = ata_from,
        xmax =  Inf,
        ymin = -Inf,
        ymax = ymax
      ),
      fill        = "#AED6F1",
      alpha       = 0.25,
      inherit.aes = FALSE
    )
  }

  .add_label <- function(p) {
    if (is.null(mat) || !nrow(mat)) return(p)

    labels <- if (length(grp_var)) {
      mat[, c(grp_var, "ata_from", "ata_to", "cv", "rse"), with = FALSE]
    } else {
      mat[, .(ata_from, ata_to, cv, rse)]
    }

    labels[, label_text := sprintf(
      "maturity: %s-%s\ncv: %.3f\nrse: %.3f\nmin_run: %d",
      ata_from, ata_to, cv, rse, min_run
    )]

    p + ggplot2::geom_label(
      data        = labels,
      mapping     = ggplot2::aes(label = label_text),
      x           = Inf,
      y           = Inf,
      hjust       = 1.05,
      vjust       = 1.05,
      size        = 3,
      label.size  = 0.3,
      fill        = "white",
      alpha       = 0.8,
      family      = getOption("ggshort.font"),
      inherit.aes = FALSE
    )
  }

  facet_layer <- if (length(grp_var)) {
    ggplot2::facet_wrap(
      stats::reformulate(grp_var),
      scales = scales,
      nrow   = nrow,
      ncol   = ncol
    )
  } else {
    NULL
  }

  # 5) type-specific plots ----------------------------------------------

  if (type == "cv") {
    p <- ggplot2::ggplot(
      smr,
      ggplot2::aes(x = ata_from, y = cv, group = 1)
    ) +
      ggplot2::geom_line(na.rm = TRUE) +
      ggplot2::geom_point(na.rm = TRUE) +
      ggplot2::geom_hline(
        yintercept = max_cv,
        color      = "red",
        linetype   = "dashed"
      ) +
      .x_scale()

    p <- .add_shade(p, ymax = max_cv)
    p <- .add_vline(p)
    p <- .add_label(p)

    p <- p + facet_layer

    p <- p + ggplot2::labs(
      title = "Coefficient of Variation of ATA Factors",
      x     = "ata link",
      y     = "CV"
    )

    return(p + .switch_theme(theme = theme, x.angle = x.angle,
                                     legend.position = "none", ...))
  }

  if (type == "rse") {
    p <- ggplot2::ggplot(
      smr,
      ggplot2::aes(x = ata_from, y = rse, group = 1)
    ) +
      ggplot2::geom_line(na.rm = TRUE) +
      ggplot2::geom_point(na.rm = TRUE) +
      ggplot2::geom_hline(
        yintercept = max_rse,
        color      = "red",
        linetype   = "dashed"
      ) +
      .x_scale()

    p <- .add_shade(p, ymax = max_rse)
    p <- .add_vline(p)
    p <- .add_label(p)

    p <- p + facet_layer

    p <- p + ggplot2::labs(
      title = "Relative Standard Error of ATA Factors",
      x     = "ata link",
      y     = "RSE"
    )

    return(p + .switch_theme(theme = theme, x.angle = x.angle,
                                     legend.position = "none", ...))
  }

  if (type == "summary") {
    dm <- data.table::melt(
      smr,
      id.vars      = c(grp_var, "ata_from", "ata_link_chr"),
      measure.vars = c("mean", "median", "wt"),
      variable.name = "stat",
      value.name    = "value"
    )
    dm[, stat := factor(stat,
                        levels = c("mean", "median", "wt"),
                        labels = c("Mean", "Median", "Weighted")
    )]

    p <- ggplot2::ggplot(
      dm,
      ggplot2::aes(
        x     = ata_from,
        y     = value,
        color = stat,
        group = stat
      )
    ) +
      ggplot2::geom_line(na.rm = TRUE) +
      ggplot2::geom_point(na.rm = TRUE) +
      .x_scale()

    if (!is.null(meta$hline)) {
      p <- p + ggplot2::geom_hline(
        yintercept = meta$hline,
        color      = "red",
        linetype   = "dashed"
      )
    }

    p <- .add_shade(p)
    p <- .add_vline(p)
    p <- .add_label(p)

    p <- p + facet_layer

    p <- p + ggplot2::labs(
      title = "Summary of ATA Factors",
      x     = "ata link",
      y     = "Factor",
      color = NULL
    )

    return(p + .switch_theme(theme = theme, x.angle = x.angle, ...))
  }

  if (type == "box") {
    dt <- .ensure_dt(x)
    dt[, ata_link_chr := sprintf("%s-%s", ata_from, ata_to)]

    p <- ggplot2::ggplot(
      dt,
      ggplot2::aes(x = ata_from, y = ata, group = ata_from)
    ) +
      ggplot2::geom_boxplot(na.rm = TRUE) +
      .x_scale()

    if (!is.null(meta$hline)) {
      p <- p + ggplot2::geom_hline(
        yintercept = meta$hline,
        color      = "red",
        linetype   = "dashed"
      )
    }

    p <- .add_shade(p)
    p <- .add_vline(p)
    p <- .add_label(p)

    p <- p + facet_layer

    p <- p + ggplot2::labs(
      title = "Box Plot of ATA Factors",
      x     = "ata link",
      y     = "Factor"
    )

    return(p + .switch_theme(theme = theme, x.angle = x.angle,
                                     legend.position = "none", ...))
  }

  if (type == "point") {
    dt <- .ensure_dt(x)

    p <- ggplot2::ggplot(
      dt,
      ggplot2::aes(x = ata_from, y = ata)
    ) +
      ggplot2::geom_point(na.rm = TRUE) +
      ggplot2::stat_summary(
        fun     = mean,
        geom    = "line",
        mapping = ggplot2::aes(group = 1),
        na.rm   = TRUE
      ) +
      .x_scale()

    if (!is.null(meta$hline)) {
      p <- p + ggplot2::geom_hline(
        yintercept = meta$hline,
        color      = "red",
        linetype   = "dashed"
      )
    }

    p <- .add_shade(p)
    p <- .add_vline(p)
    p <- .add_label(p)

    p <- p + facet_layer

    p <- p + ggplot2::labs(
      title = "Distribution of ATA Factors",
      x     = "ata link",
      y     = "Factor"
    )

    return(p + .switch_theme(theme = theme, x.angle = x.angle,
                                     legend.position = "none", ...))
  }
}


# Internal: ED-mode diagnostic plot ----------------------------------------

.plot_link_ed <- function(x,
                          type    = c("summary", "box", "point"),
                          alpha   = 1,
                          scales  = c("fixed", "free", "free_x", "free_y"),
                          nrow    = NULL,
                          ncol    = NULL,
                          theme   = c("view", "save", "shiny"),
                          x.angle = 90,
                          ...) {

  .assert_class(x, "Link")

  type   <- match.arg(type)
  scales <- match.arg(scales)
  theme  <- match.arg(theme)

  grp_var <- attr(x, "group_var")
  if (is.null(grp_var)) grp_var <- character(0)

  # 1) compute summary
  smr <- summary(x, model = "ed", alpha = alpha)

  smr[, ata_link_chr := sprintf("%s-%s", ata_from, ata_to)]

  link_labels <- smr[
    , setNames(ata_link_chr, as.character(ata_from))
  ]

  .x_scale <- function() {
    ggplot2::scale_x_continuous(
      breaks = smr$ata_from,
      labels = link_labels[as.character(smr$ata_from)]
    )
  }

  facet_layer <- if (length(grp_var)) {
    ggplot2::facet_wrap(
      stats::reformulate(grp_var),
      scales = scales,
      nrow   = nrow,
      ncol   = ncol
    )
  } else {
    NULL
  }

  # 2) type-specific plots

  if (type == "summary") {
    dm <- data.table::melt(
      smr,
      id.vars       = c(grp_var, "ata_from", "ata_link_chr"),
      measure.vars  = c("mean", "median", "wt"),
      variable.name = "stat",
      value.name    = "value"
    )
    dm[, stat := factor(stat,
                        levels = c("mean", "median", "wt"),
                        labels = c("Mean", "Median", "Weighted")
    )]

    p <- ggplot2::ggplot(
      dm,
      ggplot2::aes(
        x     = ata_from,
        y     = value,
        color = stat,
        group = stat
      )
    ) +
      ggplot2::geom_line(na.rm = TRUE) +
      ggplot2::geom_point(na.rm = TRUE) +
      ggplot2::geom_hline(
        yintercept = 0,
        color      = "red",
        linetype   = "dashed"
      ) +
      .x_scale()

    p <- p + facet_layer

    p <- p + ggplot2::labs(
      title = "Summary of Incremental Loss Intensity (g)",
      x     = "development link",
      y     = "intensity",
      color = NULL
    )

    return(p + .switch_theme(theme = theme, x.angle = x.angle, ...))
  }

  if (type == "box") {
    dt <- .ensure_dt(x)

    p <- ggplot2::ggplot(
      dt,
      ggplot2::aes(x = ata_from, y = intensity, group = ata_from)
    ) +
      ggplot2::geom_boxplot(na.rm = TRUE) +
      ggplot2::geom_hline(
        yintercept = 0,
        color      = "red",
        linetype   = "dashed"
      ) +
      .x_scale()

    p <- p + facet_layer

    p <- p + ggplot2::labs(
      title = "Box Plot of Incremental Loss Intensity (g)",
      x     = "development link",
      y     = "intensity"
    )

    return(p + .switch_theme(theme = theme, x.angle = x.angle,
                                     legend.position = "none", ...))
  }

  if (type == "point") {
    dt <- .ensure_dt(x)

    p <- ggplot2::ggplot(
      dt,
      ggplot2::aes(x = ata_from, y = intensity)
    ) +
      ggplot2::geom_point(na.rm = TRUE) +
      ggplot2::stat_summary(
        fun     = mean,
        geom    = "line",
        mapping = ggplot2::aes(group = 1),
        na.rm   = TRUE
      ) +
      ggplot2::geom_hline(
        yintercept = 0,
        color      = "red",
        linetype   = "dashed"
      ) +
      .x_scale()

    p <- p + facet_layer

    p <- p + ggplot2::labs(
      title = "Distribution of Incremental Loss Intensity (g)",
      x     = "development link",
      y     = "intensity"
    )

    return(p + .switch_theme(theme = theme, x.angle = x.angle,
                                     legend.position = "none", ...))
  }
}


# Internal: ATA-mode triangle heatmap --------------------------------------

.plot_triangle_link_ata <- function(x,
                                    label_style     = c("value", "detail"),
                                    label_size      = NULL,
                                    show_maturity   = FALSE,
                                    alpha           = 1,
                                    max_cv          = 0.15,
                                    max_rse         = 0.05,
                                    min_valid_ratio = 0.5,
                                    min_n_valid     = 3L,
                                    min_run         = 1L,
                                    amount_divisor  = 1e8,
                                    theme           = c("view", "save", "shiny"),
                                    nrow            = NULL,
                                    ncol            = NULL,
                                    x.angle         = 90,
                                    ...) {

  .assert_class(x, "Link")

  label_style <- match.arg(label_style)
  theme       <- match.arg(theme)
  if (is.null(label_size))
    label_size <- if (label_style == "detail") 2.5 else 3

  dt      <- .ensure_dt(x)
  grp_var <- attr(x, "group_var")
  coh_var <- attr(x, "cohort_var")
  val_var <- attr(x, "loss_var")

  if (is.null(grp_var) || is.null(coh_var))
    stop("`x` must contain `group_var` and `cohort_var` attributes.",
         call. = FALSE)
  if (length(coh_var) != 1L)
    stop("`x` must contain exactly one `cohort_var`.", call. = FALSE)

  # 1) build ata_link factor with correct ordering ----------------------
  link_levels <- dt[order(ata_from), unique(sprintf("%s-%s", ata_from, ata_to))]
  dt[, ata_link := factor(sprintf("%s-%s", ata_from, ata_to),
                          levels = link_levels)]

  # 2) format period labels for y axis ----------------------------------
  coh_type <- .get_period_type(coh_var)
  dt[, .y := .format_period(.SD[["cohort"]], type = coh_type, abb = TRUE),
     .SDcols = "cohort"]

  # 3) build cell labels and caption ------------------------------------
  unit_txt <- .get_amount_unit(amount_divisor)

  if (label_style == "value") {
    dt[, label := data.table::fifelse(is.finite(ata), sprintf("%.2f", ata), "")]
    caption_txt <- "Unit: factor (column-wise relative fill)"
  } else {
    dt[, label := data.table::fifelse(
      is.finite(ata),
      sprintf("%.2f\n(%.1f->%.1f)", ata,
              loss_from / amount_divisor,
              loss_to   / amount_divisor),
      ""
    )]
    caption_txt <- sprintf(
      "Unit: factor (%s, column-wise relative fill)",
      unit_txt
    )
  }

  # 4) compute column-wise relative fill --------------------------------
  dt[, ata_fill := log(ata / stats::median(ata, na.rm = TRUE)),
     by = c(grp_var, "ata_link")]
  dt[!is.finite(ata_fill), ata_fill := NA_real_]

  # 5) build title ------------------------------------------------------
  title_txt <- switch(val_var,
                      loss    = "ATA Factor for Cumulative Loss",
                      premium = "ATA Factor for Cumulative Premium",
                      lr      = "ATA Factor for Cumulative Loss Ratio",
                      "ATA Factor"
  )

  # 6) compute maturity -------------------------------------------------
  mat <- NULL

  if (show_maturity) {
    smr <- summary(x, model = "ata", alpha = alpha)
    mat <- .detect_maturity(
      x               = smr,
      max_cv          = max_cv,
      max_rse         = max_rse,
      min_valid_ratio = min_valid_ratio,
      min_n_valid     = min_n_valid,
      min_run         = min_run
    )
    mat <- .ensure_dt(mat)
    mat <- mat[is.finite(ata_from)]

    if (nrow(mat)) {
      mat[, ata_link := factor(
        sprintf("%s-%s", ata_from, ata_to),
        levels = link_levels
      )]
    }
  }

  # 7) resolve label_args -----------------------------------------------
  label_args <- .modify_label_args(list(size = label_size))

  # 8) base heatmap -----------------------------------------------------
  p <- ggshort::ggheatmap(
    data      = dt,
    x         = ata_link,
    y         = .y,
    label     = label,
    label_args = label_args,
    fill      = ata_fill,
    fill_args = list(
      low       = "#D9ECFF",
      mid       = "white",
      high      = "#F8D7DA",
      midpoint  = 0,
      color     = "black",
      linewidth = 0.3,
      guide     = "none"
    )
  )

  # 9) maturity vline and label -----------------------------------------
  if (!is.null(mat) && nrow(mat)) {
    p <- p + ggplot2::geom_vline(
      data        = mat,
      mapping     = ggplot2::aes(xintercept = as.numeric(ata_link) - 0.5),
      color       = "grey40",
      linetype    = "longdash",
      inherit.aes = FALSE
    )

    labels <- if (length(grp_var)) {
      mat[, c(grp_var, "ata_from", "ata_to", "cv", "rse"), with = FALSE]
    } else {
      mat[, .(ata_from, ata_to, cv, rse)]
    }

    labels[, label_text := sprintf(
      "maturity: %s-%s\ncv: %.3f\nrse: %.3f\nmin_run: %d",
      ata_from, ata_to, cv, rse, min_run
    )]

    p <- p + ggplot2::geom_label(
      data        = labels,
      mapping     = ggplot2::aes(label = label_text),
      x           = Inf,
      y           = -Inf,
      hjust       = 1.05,
      vjust       = -0.05,
      family      = label_args$family,
      size        = label_args$size,
      color       = label_args$color,
      label.size  = 0.3,
      fill        = "white",
      alpha       = 0.8,
      inherit.aes = FALSE
    )
  }

  # 10) facet
  p <- p + ggplot2::facet_wrap(grp_var, nrow = nrow, ncol = ncol)

  # 11) labs
  p <- p + ggplot2::labs(
    title   = title_txt,
    x       = "Age-to-Age",
    y       = .pretty_var_label(coh_var),
    caption = caption_txt
  )

  # 12) theme
  p + .switch_theme(theme = theme, x.angle = x.angle, ...)
}


# Internal: ED-mode triangle heatmap ---------------------------------------

.plot_triangle_link_ed <- function(x,
                                   label_style    = c("value", "detail"),
                                   label_size     = NULL,
                                   amount_divisor = 1e8,
                                   theme          = c("view", "save", "shiny"),
                                   nrow           = NULL,
                                   ncol           = NULL,
                                   x.angle        = 90,
                                   ...) {

  .assert_class(x, "Link")

  label_style <- match.arg(label_style)
  theme       <- match.arg(theme)
  if (is.null(label_size))
    label_size <- if (label_style == "detail") 2.5 else 3

  dt      <- .ensure_dt(x)
  grp_var <- attr(x, "group_var")
  coh_var <- attr(x, "cohort_var")

  if (is.null(grp_var)) grp_var <- character(0)

  # 1) build ata_link factor
  link_levels <- dt[order(ata_from), unique(sprintf("%s-%s", ata_from, ata_to))]
  dt[, ata_link := factor(sprintf("%s-%s", ata_from, ata_to),
                          levels = link_levels)]

  # 2) format period labels
  coh_type <- .get_period_type(coh_var)
  dt[, .y := .format_period(.SD[["cohort"]], type = coh_type, abb = TRUE),
     .SDcols = "cohort"]

  # 3) build cell labels
  if (label_style == "value") {
    dt[, label := data.table::fifelse(is.finite(intensity),
                                      sprintf("%.3f", intensity), "")]
    caption_txt <- "Unit: g (column-wise relative fill)"
  } else {
    dt[, label := data.table::fifelse(
      is.finite(intensity),
      sprintf("%.3f\n(%.1f/%.1f)", intensity,
              loss_delta / amount_divisor,
              premium_from / amount_divisor),
      ""
    )]
    caption_txt <- sprintf(
      "Unit: g (%s, column-wise relative fill)",
      .get_amount_unit(amount_divisor)
    )
  }

  # 4) column-wise relative fill
  dt[, intensity_fill := intensity - stats::median(intensity, na.rm = TRUE),
     by = c(grp_var, "ata_link")]
  dt[!is.finite(intensity_fill), intensity_fill := NA_real_]

  # 5) resolve label_args
  label_args <- .modify_label_args(list(size = label_size))

  # 6) base heatmap
  p <- ggshort::ggheatmap(
    data       = dt,
    x          = ata_link,
    y          = .y,
    label      = label,
    label_args = label_args,
    fill       = intensity_fill,
    fill_args  = list(
      low       = "#D9ECFF",
      mid       = "white",
      high      = "#F8D7DA",
      midpoint  = 0,
      color     = "black",
      linewidth = 0.3,
      guide     = "none"
    )
  )

  # 7) facet
  p <- p + ggplot2::facet_wrap(grp_var, nrow = nrow, ncol = ncol)

  # 8) labs
  p <- p + ggplot2::labs(
    title   = "Incremental Loss Intensity (g)",
    x       = "Development Link",
    y       = .pretty_var_label(coh_var),
    caption = caption_txt
  )

  # 9) theme
  p + .switch_theme(theme = theme, x.angle = x.angle, ...)
}


# ATAFit / EDFit S3 wrappers -----------------------------------------------

#' Plot an ata fit
#'
#' @description
#' Visualise an object of class `"ATAFit"` by delegating to [plot.Link()]
#' on the underlying `Link` data stored in `x$link` with `model = "ata"`.
#'
#' @param x An object of class `"ATAFit"`.
#' @param ... Arguments passed to [plot.Link()].
#'
#' @return A `ggplot` object.
#'
#' @seealso [plot.Link()], [fit_ata()]
#'
#' @method plot ATAFit
#' @export
plot.ATAFit <- function(x, ...) {
  .assert_class(x, "ATAFit")
  plot.Link(x$link, model = "ata", ...)
}


#' Triangle heatmap for an ata fit
#'
#' @description
#' Visualise an object of class `"ATAFit"` as a triangle-style heatmap
#' by delegating to [plot_triangle.Link()] on the underlying `Link` data
#' stored in `x$link` with `model = "ata"`.
#'
#' @param x An object of class `"ATAFit"`.
#' @param ... Arguments passed to [plot_triangle.Link()].
#'
#' @return A `ggplot` object.
#'
#' @seealso [plot_triangle.Link()], [fit_ata()]
#'
#' @method plot_triangle ATAFit
#' @export
plot_triangle.ATAFit <- function(x, ...) {
  .assert_class(x, "ATAFit")
  plot_triangle.Link(x$link, model = "ata", ...)
}


#' Plot an ED fit
#'
#' @description
#' Visualise an object of class `"EDFit"` by delegating to [plot.Link()]
#' on the underlying `Link` data stored in `x$link` with `model = "ed"`.
#'
#' @param x An object of class `"EDFit"`.
#' @param ... Arguments passed to [plot.Link()].
#'
#' @return A `ggplot` object.
#'
#' @seealso [plot.Link()], [fit_ed()]
#'
#' @method plot EDFit
#' @export
plot.EDFit <- function(x, ...) {
  .assert_class(x, "EDFit")
  plot.Link(x$link, model = "ed", ...)
}


#' Triangle heatmap for an ED fit
#'
#' @description
#' Visualise an object of class `"EDFit"` as a triangle-style heatmap
#' by delegating to [plot_triangle.Link()] on the underlying `Link` data
#' stored in `x$link` with `model = "ed"`.
#'
#' @param x An object of class `"EDFit"`.
#' @param ... Arguments passed to [plot_triangle.Link()].
#'
#' @return A `ggplot` object.
#'
#' @seealso [plot_triangle.Link()], [fit_ed()]
#'
#' @method plot_triangle EDFit
#' @export
plot_triangle.EDFit <- function(x, ...) {
  .assert_class(x, "EDFit")
  plot_triangle.Link(x$link, model = "ed", ...)
}
