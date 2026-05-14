# Plot the Convergence diagnostic

Four-panel diagnostic showing the LR backtest path and each stability
metric vs. its threshold:

- Top: `lr` (the portfolio LR projection at each valuation).

- Then for each of `drift_window`, `drift_tail`, `|slope|`,
  `dispersion`: the metric over `v` with a dashed horizontal line at the
  threshold (`max_drift`, `max_slope`, or `max_dispersion`).

Vertical guides mark `mat_k` (dashed) and the detected `conv_k` for the
chosen `method` (solid). The chosen-method panel title is annotated.

## Usage

``` r
# S3 method for class 'Convergence'
plot(x, theme = c("view", "save", "shiny"), ...)
```

## Arguments

- x:

  An object of class `Convergence`.

- theme:

  String passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-switch_theme.md).

- ...:

  Additional arguments passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-switch_theme.md).

## Value

A `ggplot` object.
