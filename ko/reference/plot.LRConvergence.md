# Plot the LRConvergence diagnostic

Two-panel diagnostic showing the dual criterion driving \\k^{\*\*}\\:

- Top panel: \\R_v / \hat{SE}^{param}\_v\\ (predictive revision
  normalised by parameter SE), with horizontal guide at the threshold
  `c`.

- Bottom panel: \\\hat{D}\_v\\ (robust cross-cohort dispersion of
  incremental loss ratio), with horizontal guide at the threshold `tau`.

Vertical guides mark `k_star` (dashed) and `k_conv` (solid). A point
falling below both threshold lines passes the joint criterion.

## Usage

``` r
# S3 method for class 'LRConvergence'
plot(x, theme = c("view", "save", "shiny"), ...)
```

## Arguments

- x:

  An object of class `LRConvergence`.

- theme:

  String passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-switch_theme.md).

- ...:

  Additional arguments passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-switch_theme.md).

## Value

A `ggplot` object.
