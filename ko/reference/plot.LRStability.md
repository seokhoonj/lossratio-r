# Plot the LRStability diagnostic

Two-panel diagnostic showing the dual criterion driving \\k_0\\:

- Top panel: \\R_v / \widehat{SE}^{param}\_v\\ (predictive revision
  normalised by parameter SE), with horizontal guide at the threshold
  `c`.

- Bottom panel: \\\widehat{D}\_v\\ (robust cross-cohort dispersion of
  incremental loss ratio), with horizontal guide at the threshold `tau`.

Vertical guides mark `k_star` (dashed) and `k_stable` (solid). A point
falling below both threshold lines passes the joint criterion.

## Usage

``` r
# S3 method for class 'LRStability'
plot(x, theme = c("view", "save", "shiny"), ...)
```

## Arguments

- x:

  An object of class `LRStability`.

- theme:

  String passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-switch_theme.md).

- ...:

  Additional arguments passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-switch_theme.md).

## Value

A `ggplot` object.
