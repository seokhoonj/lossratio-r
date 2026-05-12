# Plot break-count vs window with the elbow marker

Diagnostic plot for a `detect_regime_optimal_window()` result: shows
`break_count` (and optionally `mean_magnitude`) against the trajectory
window `window`, with a vertical line at `optimal_window`.

## Usage

``` r
# S3 method for class 'RegimeOptimalWindow'
plot(x, show_magnitude = TRUE, theme = c("view", "save", "shiny"), ...)
```

## Arguments

- x:

  A `"RegimeOptimalWindow"` object.

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
