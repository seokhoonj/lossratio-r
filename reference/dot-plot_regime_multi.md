# Multi-group plot helper for `Regime`

Builds one PCA panel per group via
[`.regime_pca_plot()`](https://seokhoonj.github.io/lossratio/reference/dot-regime_pca_plot.md)
and returns a named list of `ggplot` objects keyed by group value.

## Usage

``` r
.plot_regime_multi(
  x,
  show_arrow,
  show_label,
  show_ellipse,
  show_mean,
  show_median,
  alpha,
  palette,
  theme,
  ...
)
```
