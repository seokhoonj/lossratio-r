# Internal ggplot2 plotting helpers ---------------------------------------
#
# The theme system, the cell-grid builder (.cell_grid -- heatmap and
# table in one), and the PCA scatter (.regime_pca_plot) used across the
# package's plot methods. They depend only on ggplot2, and are marked
# internal with a leading `.`.


# Theme system ------------------------------------------------------------

#' Unified theme dispatcher (internal)
#'
#' @description
#' Produces a [ggplot2::theme()] configured for one of three usage
#' contexts:
#' - `"view"`: RStudio screen exploration; sizes inherit from ggplot2
#'   defaults.
#' - `"save"`: embedding in spreadsheet tools such as Excel; fixed axis /
#'   title sizes, plot background untouched.
#' - `"shiny"`: embedding in Shiny apps; same as `"save"` plus a
#'   configurable transparent plot background.
#'
#' Setting any `*.size` argument to `0` replaces that element with
#' [ggplot2::element_blank()].
#'
#' @param theme One of `"view"`, `"save"`, `"shiny"`.
#' @param family Font family; defaults to
#'   `getOption("lossratio.font", "")` (empty string = system default).
#' @param x.size,y.size,t.size,s.size,l.size Font sizes for x-axis,
#'   y-axis, title, strip, and legend text. `NULL` leaves the ggplot
#'   default; `0` hides the element.
#' @param x.face,y.face,t.face,s.face,l.face Font faces
#'   (`"plain"`, `"bold"`, `"italic"`, `"bold.italic"`).
#' @param x.angle,y.angle,x.hjust,x.vjust,y.hjust,y.vjust Axis text
#'   placement.
#' @param show_grid_major,show_grid_minor Whether to draw grid lines.
#' @param legend.key.height,legend.key.width,legend.position,legend.justification
#'   Legend geometry.
#' @param plot.background.fill Fill for the plot panel background; used
#'   only when `theme = "shiny"`.
#'
#' @return A [ggplot2::theme()] object.
#'
#' @keywords internal
.switch_theme <- function(theme = c("view", "save", "shiny"),
                          family               = getOption("lossratio.font", ""),
                          x.size               = NULL, y.size = NULL,
                          t.size               = NULL, s.size = NULL, l.size = NULL,
                          x.face               = "plain", y.face = "plain",
                          t.face               = "plain", s.face = "plain", l.face = "plain",
                          x.angle              = 0, y.angle = 0,
                          x.hjust              = .5, x.vjust = .5,
                          y.hjust              = NULL, y.vjust = NULL,
                          show_grid_major      = FALSE,
                          show_grid_minor      = FALSE,
                          legend.key.height    = NULL,
                          legend.key.width     = NULL,
                          legend.position      = "right",
                          legend.justification = "center",
                          plot.background.fill = "transparent") {

  theme <- match.arg(theme)

  # Mode-specific size defaults: save / shiny use concrete sizes,
  # view inherits ggplot2 defaults (via NULL).
  if (theme %in% c("save", "shiny")) {
    if (is.null(x.size)) x.size <- 12
    if (is.null(y.size)) y.size <- 12
    if (is.null(t.size)) t.size <- 14
    if (is.null(s.size)) s.size <- 14
    if (is.null(l.size)) l.size <- 12
  }

  out <- ggplot2::theme(
    text                 = ggplot2::element_text(family = family),
    title                = ggplot2::element_text(family = family, size = t.size, face = t.face),
    strip.text.x         = ggplot2::element_text(size = s.size, face = s.face),
    axis.text.x          = .element_axis_text(x.size, x.face, x.angle, x.hjust, x.vjust, family),
    axis.text.y          = .element_axis_text(y.size, y.face, y.angle, y.hjust, y.vjust, family),
    axis.ticks.x         = .element_ticks(x.size),
    axis.ticks.y         = .element_ticks(y.size),
    legend.title         = ggplot2::element_text(size = l.size, face = l.face),
    legend.text          = ggplot2::element_text(size = l.size, face = l.face),
    legend.key.height    = legend.key.height,
    legend.key.width     = legend.key.width,
    legend.position      = legend.position,
    legend.justification = legend.justification,
    panel.border         = ggplot2::element_rect(colour = "black", fill = "transparent"),
    panel.grid.major     = .element_grid(show_grid_major, "gray80", 0.5),
    panel.grid.minor     = .element_grid(show_grid_minor, "gray90", 0.3),
    panel.background     = ggplot2::element_rect(fill = "transparent"),
    strip.background     = ggplot2::element_rect(colour = "black")
  )

  # shiny-only: transparent plot background (blends with app CSS)
  if (theme == "shiny") {
    out <- out + ggplot2::theme(
      plot.background = ggplot2::element_rect(
        fill   = plot.background.fill,
        colour = plot.background.fill
      )
    )
  }

  out
}


# Theme element helpers ---------------------------------------------------

#' Axis text element with size=0 sentinel for element_blank
#'
#' @keywords internal
.element_axis_text <- function(size, face, angle, hjust, vjust, family) {
  if (!is.null(size) && identical(size, 0)) {
    ggplot2::element_blank()
  } else {
    ggplot2::element_text(
      size  = size, face = face, angle = angle,
      hjust = hjust, vjust = vjust, family = family
    )
  }
}

#' Axis ticks element with size=0 sentinel for element_blank
#'
#' @keywords internal
.element_ticks <- function(size) {
  if (!is.null(size) && identical(size, 0)) {
    ggplot2::element_blank()
  } else {
    ggplot2::element_line()
  }
}

#' Grid line element with a boolean show toggle
#'
#' @keywords internal
.element_grid <- function(show, color, linewidth) {
  if (show) {
    ggplot2::element_line(color = color, linewidth = linewidth)
  } else {
    ggplot2::element_blank()
  }
}


# Scales ------------------------------------------------------------------

#' Continuous color gradient by month (for Date variables)
#'
#' @description
#' A ggplot2 continuous color scale for `Date` aesthetics. Generates
#' colorbar breaks every `by_month` months (default 6), labeled as
#' `"YYYY-MM"`. Useful for cohort-month coloring in development plots.
#'
#' @param by_month Integer. Interval between colorbar breaks, in months.
#' @param palette Either a palette function, a character name
#'   (`"viridis"`, `"spectral"`, `"ylgnbu"`, `"zissou"`, `"roma"`,
#'   `"vik"`, `"cividis"`, `"berlin"`, `"rainbow"`), or an explicit
#'   vector of colors.
#' @param n Integer. Number of color steps.
#' @param begin,end Numeric in `[0, 1]`. Trim the generated palette to
#'   the `[begin, end]` slice (defaults `0` / `1` = no trim). Useful
#'   when a palette's light end is hard to read on white backgrounds.
#' @param include_endpoints Logical; if `TRUE`, add the lower and upper
#'   limit dates as extra breaks.
#' @param ... Additional arguments passed to
#'   [ggplot2::scale_color_gradientn()].
#'
#' @return A ggplot2 continuous color scale.
#'
#' @keywords internal
.scale_color_by_month_gradientn <- function(by_month = 6,
                                            palette           = "ylgnbu",
                                            n                 = 256,
                                            begin             = 0,
                                            end               = 1,
                                            include_endpoints = FALSE,
                                            ...) {
  if (!is.numeric(begin) || !is.numeric(end) ||
      begin < 0 || end > 1 || begin >= end)
    stop("`begin` and `end` must satisfy 0 <= begin < end <= 1.",
         call. = FALSE)
  # Palette preset handler
  get_palette <- function(p, n) {
    if (is.function(p)) return(p(n))
    if (is.character(p) && length(p) == 1L) {
      pname <- tolower(p)
      if (pname == "rainbow")
        return(grDevices::rainbow(n, start = .05, end = .65))
      pals <- list(
        viridis  = "Viridis",
        spectral = "Spectral",
        ylgnbu   = "YlGnBu",
        zissou   = "Zissou 1",
        roma     = "Roma",
        vik      = "Vik",
        cividis  = "Cividis",
        berlin   = "Berlin"
      )
      key <- match(pname, names(pals))
      if (!is.na(key)) {
        return(grDevices::hcl.colors(n, pals[[key]]))
      } else {
        stop(sprintf("Unknown palette name '%s'.", p), call. = FALSE)
      }
    }
    if (is.vector(p)) return(p)
    stop("Invalid palette argument. Must be a name, vector, or function.",
         call. = FALSE)
  }

  cols <- get_palette(palette, n)
  if (begin > 0 || end < 1) {
    lo   <- max(1L, as.integer(round(begin * n)) + 1L)
    hi   <- min(length(cols), as.integer(round(end * n)))
    cols <- cols[lo:hi]
  }

  # Compute colorbar breaks from numeric limits (ggplot passes Dates as numbers)
  breaks_from_numeric_date <- function(lims) {
    if (length(lims) != 2L || any(!is.finite(lims))) return(NULL)

    lo_date <- as.Date(lims[1], origin = "1970-01-01")
    hi_date <- as.Date(lims[2], origin = "1970-01-01")

    # Anchor: start at Jan or Jul depending on the first month
    start_year   <- as.integer(format(lo_date, "%Y"))
    start_month  <- as.integer(format(lo_date, "%m"))
    anchor_month <- if (start_month <= 6) 1L else 7L
    start_date   <- as.Date(sprintf("%04d-%02d-01", start_year, anchor_month))

    break_dates <- seq(from = start_date, to = hi_date,
                       by = paste(by_month, "months"))
    break_dates <- break_dates[break_dates >= lo_date & break_dates <= hi_date]

    if (include_endpoints)
      break_dates <- unique(sort(c(lo_date, break_dates, hi_date)))

    as.numeric(break_dates)
  }

  # Label formatter: restore to Date then format as "YYYY-MM"
  labels_ym <- function(x) format(as.Date(x, origin = "1970-01-01"), "%Y-%m")

  ggplot2::scale_color_gradientn(
    colours = cols,
    breaks  = breaks_from_numeric_date,
    labels  = labels_ym,
    guide   = ggplot2::guide_colorbar(
      nbin = 256, ticks = TRUE, draw.ulim = TRUE, draw.llim = TRUE
    ),
    ...
  )
}


#' Merge user-supplied `label_args` with the standard label defaults
#'
#' A cell label is a `geom_text()` layer; this fills any slot the
#' caller did not supply (`family`, `size`, `angle`, `hjust`, `vjust`,
#' `color`) so callers can pass a partial list such as `list(size = 2.5)`.
#'
#' @keywords internal
.modify_label_args <- function(label_args) {
  defaults <- list(
    family = getOption("lossratio.font", ""),
    size   = 3.88,
    angle  = 0,
    hjust  = 0.5,
    vjust  = 0.5,
    color  = "black"
  )
  utils::modifyList(defaults, label_args, keep.null = TRUE)
}


# Cell grid plot ----------------------------------------------------------

#' Coerce a vector to a factor with sorted levels
#'
#' Existing factors pass through unchanged; character / numeric / Date
#' vectors become factors with ascending levels, so cells draw on a
#' regular integer grid.
#'
#' @keywords internal
.coerce_to_factor <- function(x) {
  if (is.factor(x)) return(x)
  factor(x, levels = sort(unique(x)))
}


#' Draw a cohort x development cell grid (heatmap or table)
#'
#' @description
#' A general `ggplot2` cell-grid builder: the `x` and `y` columns are
#' coerced to factors and placed on a regular integer grid of unit
#' tiles, with optional in-cell text labels. One builder covers both
#' the continuous heatmap and the threshold-coloured table -- the only
#' difference is how the fill is mapped, selected by `fill_scale`:
#'
#' \describe{
#'   \item{`"gradient"`}{`fill` is numeric and mapped continuously
#'     ([ggplot2::scale_fill_gradient2()] when `fill_args$midpoint` is
#'     set, otherwise [ggplot2::scale_fill_gradient()]).}
#'   \item{`"threshold"`}{`fill` is numeric and compared to
#'     `fill_args$threshold` with the `fill_args$when` operator; cells
#'     are coloured `high` / `low` / `na` and drawn with
#'     [ggplot2::scale_fill_identity()].}
#'   \item{`"none"`}{no fill.}
#' }
#'
#' Columns are referenced by name (plain strings) -- no non-standard
#' evaluation. The result is a `ggplot` object the caller can extend.
#'
#' @param data A `data.frame` / `data.table`.
#' @param x,y Column-name strings mapped to the grid axes.
#' @param label Optional column-name string drawn as in-cell text.
#' @param fill Optional column-name string (numeric) driving cell fill.
#' @param fill_scale One of `"gradient"`, `"threshold"`, `"none"`.
#' @param fill_args Named list of fill options. Gradient keys: `low`,
#'   `mid`, `high`, `midpoint`, `na`, `guide`. Threshold keys:
#'   `threshold`, `when` (`">"`, `">="`, `"<"`, `"<="`), `high`, `low`,
#'   `na`.
#' @param label_args Named list passed to the label `geom_text()`.
#' @param border One of `"tile"` (per-cell border), `"panel"` (grid
#'   lines on cell edges), or `"none"`.
#' @param border_color,border_width Border colour and line width.
#'
#' @return A `ggplot` object.
#'
#' @keywords internal
.cell_grid <- function(data, x, y, label = NULL, fill = NULL,
                       fill_scale   = c("none", "gradient", "threshold"),
                       fill_args    = list(),
                       label_args   = list(),
                       border       = c("tile", "panel", "none"),
                       border_color = "black",
                       border_width = 0.3) {

  fill_scale <- match.arg(fill_scale)
  border     <- match.arg(border)

  d <- .copy_dt(data)
  fx <- .coerce_to_factor(d[[x]])
  fy <- .coerce_to_factor(d[[y]])
  d[[".cg_x"]] <- as.numeric(fx)
  d[[".cg_y"]] <- as.numeric(fy)
  x_lvl <- levels(fx)
  y_lvl <- levels(fy)

  tile_color <- if (border == "tile") border_color else NA

  # Resolve fill options and materialise any derived column *before*
  # ggplot() is called -- ggplot() snapshots `d`, so a column added
  # afterwards would be missing when the layer is drawn.
  fa <- NULL
  if (fill_scale == "gradient") {
    fa <- utils::modifyList(
      list(low = "white", mid = "white", high = "mistyrose",
           midpoint = NULL, na = "white", guide = "colourbar"),
      fill_args)
  } else if (fill_scale == "threshold") {
    fa <- utils::modifyList(
      list(threshold = NULL, when = ">", high = "mistyrose",
           low = "white", na = "white"),
      fill_args)
    if (is.null(fa$threshold))
      stop("`fill_args$threshold` is required for fill_scale = ",
           "'threshold'.", call. = FALSE)
    v    <- d[[fill]]
    flag <- switch(fa$when,
      ">"  = v >  fa$threshold,  ">=" = v >= fa$threshold,
      "<"  = v <  fa$threshold,  "<=" = v <= fa$threshold,
      stop("`fill_args$when` must be one of >, >=, <, <=.",
           call. = FALSE))
    d[[".cg_fill"]] <- data.table::fifelse(
      is.na(v), fa$na, data.table::fifelse(flag, fa$high, fa$low))
  }

  p <- ggplot2::ggplot(
    d, ggplot2::aes(x = .data[[".cg_x"]], y = .data[[".cg_y"]]))

  if (fill_scale == "gradient") {
    p <- p + ggplot2::geom_tile(
      ggplot2::aes(fill = .data[[fill]]),
      width = 1, height = 1, color = tile_color, linewidth = border_width)
    p <- p + if (is.null(fa$midpoint))
      ggplot2::scale_fill_gradient(low = fa$low, high = fa$high,
                                   na.value = fa$na, guide = fa$guide)
    else
      ggplot2::scale_fill_gradient2(low = fa$low, mid = fa$mid,
                                    high = fa$high, midpoint = fa$midpoint,
                                    na.value = fa$na, guide = fa$guide)
  } else if (fill_scale == "threshold") {
    p <- p + ggplot2::geom_tile(
      ggplot2::aes(fill = .data[[".cg_fill"]]),
      width = 1, height = 1, color = tile_color, linewidth = border_width) +
      ggplot2::scale_fill_identity(na.value = NA)
  }

  if (!is.null(label)) {
    la <- .modify_label_args(label_args)
    p <- p + ggplot2::geom_text(
      ggplot2::aes(label = .data[[label]]),
      family = la$family, size = la$size, angle = la$angle,
      hjust = la$hjust, vjust = la$vjust, color = la$color)
  }

  if (border == "panel") {
    p <- p +
      ggplot2::geom_vline(
        xintercept = seq_len(length(x_lvl) + 1L) - 0.5,
        color = border_color, linewidth = border_width) +
      ggplot2::geom_hline(
        yintercept = seq_len(length(y_lvl) + 1L) - 0.5,
        color = border_color, linewidth = border_width)
  }

  p +
    ggplot2::scale_x_continuous(
      breaks = seq_along(x_lvl), labels = x_lvl,
      limits = c(0.5, length(x_lvl) + 0.5), expand = c(0, 0)) +
    ggplot2::scale_y_reverse(
      breaks = seq_along(y_lvl), labels = y_lvl,
      limits = c(length(y_lvl) + 0.5, 0.5), expand = c(0, 0))
}


# PCA scatter -------------------------------------------------------------

#' Draw a PCA scatter of cohort development trajectories
#'
#' @description
#' A lean PCA biplot specialised for [detect_regime()] output: every
#' numeric column of `data` is treated as a trajectory feature, the
#' `regime` column colours the score cloud, and loading arrows show
#' how each development period contributes to the first two principal
#' components.
#'
#' Scores on `PC1` / `PC2` are divided by `sdev * sqrt(n)` raised to
#' `scale` (biplot-style scaling); loading vectors are rescaled to fit
#' inside the score range.
#'
#' @param data A `data.frame` of numeric trajectory columns plus one
#'   categorical `regime` column.
#' @param show_arrow,show_label Draw loading arrows / variable names.
#' @param show_ellipse Draw per-regime normal-theory 90% ellipses.
#' @param show_mean,show_median Draw per-regime mean (open circle) and
#'   median (cross) score points.
#' @param alpha Point transparency.
#' @param palette Discrete Brewer palette for the `regime` colour.
#' @param scale Biplot scaling exponent; `0` disables score scaling.
#' @param title,subtitle,caption Passed to [ggplot2::labs()].
#' @param theme Theme key forwarded to [.switch_theme()].
#' @param ... Forwarded to [.switch_theme()].
#'
#' @return A `ggplot` object.
#'
#' @keywords internal
.regime_pca_plot <- function(data,
                             show_arrow   = TRUE,
                             show_label   = TRUE,
                             show_ellipse = TRUE,
                             show_mean    = TRUE,
                             show_median  = TRUE,
                             alpha        = 0.3,
                             palette      = "Set1",
                             scale        = 1,
                             title        = NULL,
                             subtitle     = NULL,
                             caption      = NULL,
                             theme        = "view", ...) {

  data         <- as.data.frame(data)
  measure_vars <- setdiff(names(data), "regime")
  col_x        <- "PC1"
  col_y        <- "PC2"

  pc     <- stats::prcomp(data[, measure_vars, drop = FALSE])
  scaled <- as.data.frame(pc$x)
  scaled[["regime"]] <- data[["regime"]]

  sdev <- pc$sdev
  ve   <- sdev ^ 2 / sum(sdev ^ 2)
  xlab <- sprintf("PC1 (%.2f%%)", ve[1L] * 100)
  ylab <- sprintf("PC2 (%.2f%%)", ve[2L] * 100)

  lam <- sdev[c(1L, 2L)] * sqrt(nrow(data))
  if (scale != 0) {
    lam <- lam ^ scale
    scaled[, c(col_x, col_y)] <- t(t(scaled[, c(col_x, col_y)]) / lam)
  }

  rotation <- as.data.frame(pc$rotation[, c(col_x, col_y), drop = FALSE])
  rotation[["variable"]] <- rownames(rotation)
  scaler <- min(
    max(abs(scaled[[col_x]])) / max(abs(rotation[[col_x]])),
    max(abs(scaled[[col_y]])) / max(abs(rotation[[col_y]])))
  rotation[[col_x]] <- rotation[[col_x]] * scaler * 0.8
  rotation[[col_y]] <- rotation[[col_y]] * scaler * 0.8

  p <- ggplot2::ggplot(
    scaled, ggplot2::aes(x = .data[[col_x]], y = .data[[col_y]])) +
    ggplot2::geom_point(
      ggplot2::aes(color = .data[["regime"]]), alpha = alpha) +
    ggplot2::scale_color_brewer(palette = palette)

  if (show_arrow) {
    p <- p + ggplot2::geom_segment(
      data = rotation,
      ggplot2::aes(x = 0, y = 0,
                   xend = .data[[col_x]], yend = .data[[col_y]]),
      arrow = ggplot2::arrow(length = ggplot2::unit(7, "points")),
      color = "grey50")
  }

  if (show_arrow && show_label) {
    la <- .modify_label_args(list())
    p <- p + ggplot2::geom_text(
      data = rotation, ggplot2::aes(label = .data[["variable"]]),
      family = la$family, size = la$size, color = la$color)
  }

  if (show_ellipse) {
    p <- p + ggplot2::stat_ellipse(
      ggplot2::aes(group = .data[["regime"]], color = .data[["regime"]]),
      type = "norm", level = 0.9, alpha = 0.9)
  }

  if (show_mean || show_median) {
    pt_size <- .modify_label_args(list())$size
  }
  if (show_mean) {
    mu <- stats::aggregate(scaled[, c(col_x, col_y)],
                           by = list(regime = scaled[["regime"]]), FUN = mean)
    p <- p + ggplot2::geom_point(
      data = mu, inherit.aes = FALSE,
      ggplot2::aes(x = .data[[col_x]], y = .data[[col_y]],
                   color = .data[["regime"]]),
      shape = 1, size = pt_size)
  }
  if (show_median) {
    md <- stats::aggregate(scaled[, c(col_x, col_y)],
                           by = list(regime = scaled[["regime"]]),
                           FUN = stats::median)
    p <- p + ggplot2::geom_point(
      data = md, inherit.aes = FALSE,
      ggplot2::aes(x = .data[[col_x]], y = .data[[col_y]],
                   color = .data[["regime"]]),
      shape = 4, size = pt_size)
  }

  p +
    ggplot2::xlab(xlab) +
    ggplot2::ylab(ylab) +
    ggplot2::labs(title = title, subtitle = subtitle, caption = caption) +
    .switch_theme(theme = theme, ...)
}
