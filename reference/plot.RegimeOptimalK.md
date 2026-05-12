# Plot break-count vs K with the elbow marker

Diagnostic plot for a `detect_regime_optimal_k()` result: shows
`break_count` (and optionally `mean_magnitude`) against the trajectory
window `K`, with a vertical line at `optimal_k`.

## Usage

``` r
# S3 method for class 'RegimeOptimalK'
plot(x, show_magnitude = TRUE, theme = c("view", "save", "shiny"), ...)
```

## Arguments

- x:

  A `"RegimeOptimalK"` object.

- show_magnitude:

  Logical; if `TRUE` (default), overlay `mean_magnitude` on a secondary
  y axis (right). Set `FALSE` for a cleaner break-count-only plot.

- theme:

  A string passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/reference/dot-switch_theme.md).

- ...:

  Additional arguments passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/reference/dot-switch_theme.md).

## Value

A `ggplot` object.
