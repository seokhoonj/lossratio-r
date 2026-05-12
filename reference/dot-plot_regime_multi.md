# Multi-group plot helper for `Regime`

Builds one PCA panel per group via
[`ggshort::plot_pca()`](https://rdrr.io/pkg/ggshort/man/plot_pca.html)
and combines them with patchwork if available, otherwise returns a list
of ggplot objects.

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
