# Plot a cohort regime detection result

Visualise an object of class `"Regime"` as a PCA scatter of cohort
trajectories coloured by detected regime. Points are underwriting
cohorts, axes are the first two principal components of the cohort
feature matrix (development-period trajectories), and ellipses indicate
the 90% contour per regime. Arrows show the loadings of the original
development-period features on PC1/PC2.

For a multi-group `Regime`, plots are faceted by group: each group's PCA
is rendered in its own panel using its own feature matrix and loadings
(PCA cannot be meaningfully shared across groups with different
`K`-period bases or scale, so per-group PCA is the correct
representation).

## Usage

``` r
# S3 method for class 'Regime'
plot(
  x,
  show_arrow = TRUE,
  show_label = TRUE,
  show_ellipse = TRUE,
  show_mean = TRUE,
  show_median = TRUE,
  alpha = 0.5,
  palette = "Set1",
  theme = c("view", "save", "shiny"),
  ...
)
```

## Arguments

- x:

  An object of class `"Regime"`.

- show_arrow:

  Logical; draw loading arrows. Default `TRUE`.

- show_label:

  Logical; label arrows with development-period index. Default `TRUE`.

- show_ellipse:

  Logical; draw 90% ellipse per regime. Default `TRUE`.

- show_mean, show_median:

  Logical; draw per-regime mean / median point. Defaults `TRUE`.

- alpha:

  Numeric; point alpha. Default `0.5`.

- palette:

  Brewer palette name for discrete regimes. Default `"Set1"`.

- theme:

  Theme string passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/reference/dot-switch_theme.md).

- ...:

  Additional arguments passed to
  [`ggshort::plot_pca()`](https://rdrr.io/pkg/ggshort/man/plot_pca.html).

## Value

A `ggplot` object (single-group) or a `patchwork` / list-of-`ggplot`
composite (multi-group; one panel per group).

## See also

[`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
