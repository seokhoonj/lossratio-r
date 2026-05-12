# Cohort Regime Plot ------------------------------------------------------

#' Plot a cohort regime detection result
#'
#' @description
#' Visualise an object of class `"Regime"` as a PCA scatter of
#' cohort trajectories coloured by detected regime. Points are
#' underwriting cohorts, axes are the first two principal components of
#' the cohort feature matrix (development-period trajectories), and
#' ellipses indicate the 90% contour per regime. Arrows show the
#' loadings of the original development-period features on PC1/PC2.
#'
#' For a multi-group `Regime`, plots are faceted by group: each group's
#' PCA is rendered in its own panel using its own feature matrix and
#' loadings (PCA cannot be meaningfully shared across groups with
#' different `K`-period bases or scale, so per-group PCA is the
#' correct representation).
#'
#' @param x An object of class `"Regime"`.
#' @param show_arrow Logical; draw loading arrows. Default `TRUE`.
#' @param show_label Logical; label arrows with development-period index.
#'   Default `TRUE`.
#' @param show_ellipse Logical; draw 90% ellipse per regime. Default
#'   `TRUE`.
#' @param show_mean,show_median Logical; draw per-regime mean / median
#'   point. Defaults `TRUE`.
#' @param alpha Numeric; point alpha. Default `0.5`.
#' @param palette Brewer palette name for discrete regimes. Default
#'   `"Set1"`.
#' @param theme Theme string passed to [.switch_theme()].
#' @param ... Additional arguments passed to [ggshort::plot_pca()].
#'
#' @return A `ggplot` object (single-group), or a named list of `ggplot`
#'   objects (multi-group; one entry per group).
#'
#' @seealso [detect_regime()]
#'
#' @method plot Regime
#' @export
plot.Regime <- function(x,
                        show_arrow   = TRUE,
                        show_label   = TRUE,
                        show_ellipse = TRUE,
                        show_mean    = TRUE,
                        show_median  = TRUE,
                        alpha        = 0.5,
                        palette      = "Set1",
                        theme        = c("view", "save", "shiny"),
                        ...) {

  .assert_class(x, "Regime")
  theme <- match.arg(theme)

  if (isTRUE(x$multi_group)) {
    return(.plot_regime_multi(
      x            = x,
      show_arrow   = show_arrow,
      show_label   = show_label,
      show_ellipse = show_ellipse,
      show_mean    = show_mean,
      show_median  = show_median,
      alpha        = alpha,
      palette      = palette,
      theme        = theme,
      ...
    ))
  }

  mat <- x$trajectory
  df  <- as.data.frame(mat)
  df$regime <- x$labels$regime

  measure_vars <- setdiff(names(df), "regime")

  ve <- (x$pca$sdev ^ 2) / sum(x$pca$sdev ^ 2)
  subtitle <- sprintf(
    "method: %s | window: %s 1, ..., %d | %d cohorts | PC1 %.1f%% / PC2 %.1f%%",
    x$method, x$dev, x$K, nrow(df), ve[1L] * 100, ve[2L] * 100
  )

  caption <- if (nrow(x$breakpoints)) {
    sprintf("breakpoint(s): %s",
            paste(format(x$breakpoints[["breakpoint"]], "%y.%m"),
                  collapse = ", "))
  } else {
    "no breakpoint detected"
  }

  ggshort::plot_pca(
    data         = df,
    measure_vars = !!measure_vars,
    color_var    = regime,
    show_arrow   = show_arrow,
    show_label   = show_label,
    show_ellipse = show_ellipse,
    show_mean    = show_mean,
    show_median  = show_median,
    alpha        = alpha,
    palette      = palette,
    title        = "Cohort regime detection",
    subtitle     = subtitle,
    caption      = caption,
    theme        = theme,
    ...
  )
}


#' Multi-group plot helper for `Regime`
#'
#' Builds one PCA panel per group via [ggshort::plot_pca()] and returns
#' a named list of `ggplot` objects keyed by group value.
#'
#' @keywords internal
.plot_regime_multi <- function(x,
                               show_arrow, show_label, show_ellipse,
                               show_mean, show_median, alpha, palette,
                               theme, ...) {

  grp <- x$groups
  grp_names <- names(x$trajectory)

  plots <- lapply(grp_names, function(gv) {
    mat <- x$trajectory[[gv]]
    pca <- x$pca[[gv]]
    df  <- as.data.frame(mat)
    lab_sub <- x$labels[x$labels[[grp]] ==
                          .coerce_match(gv, x$labels[[grp]])]
    df$regime <- lab_sub$regime

    measure_vars <- setdiff(names(df), "regime")
    ve <- (pca$sdev ^ 2) / sum(pca$sdev ^ 2)
    subtitle <- sprintf(
      "%s | %d cohorts | PC1 %.1f%% / PC2 %.1f%%",
      x$method, nrow(df), ve[1L] * 100, ve[2L] * 100
    )

    bp_g <- x$breakpoints[x$breakpoints[[grp]] ==
                            .coerce_match(gv, x$breakpoints[[grp]])][["breakpoint"]]
    caption <- if (length(bp_g)) {
      sprintf("breakpoint(s): %s",
              paste(format(bp_g, "%y.%m"), collapse = ", "))
    } else {
      "no breakpoint detected"
    }

    ggshort::plot_pca(
      data         = df,
      measure_vars = !!measure_vars,
      color_var    = regime,
      show_arrow   = show_arrow,
      show_label   = show_label,
      show_ellipse = show_ellipse,
      show_mean    = show_mean,
      show_median  = show_median,
      alpha        = alpha,
      palette      = palette,
      title        = sprintf("[%s] cohort regime detection", gv),
      subtitle     = subtitle,
      caption      = caption,
      theme        = theme,
      ...
    )
  })
  names(plots) <- grp_names

  plots
}
