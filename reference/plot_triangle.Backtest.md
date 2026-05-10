# Triangle heatmap of backtest A/E Error

Display the held-out cells as a `cohort x dev` heatmap coloured by A/E
Error (red = under-projected (actual \> pred), blue = over-projected
(actual \< pred), white at 0).

## Usage

``` r
# S3 method for class 'Backtest'
plot_triangle(x, label_size = 2.5, theme = c("view", "save", "shiny"), ...)
```

## Arguments

- x:

  An object of class `"Backtest"`.

- label_size:

  Numeric label text size for cell labels. Default `2.5` (single-line
  A/E Error percent labels on the held-out wedge).

- theme:

  String passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/reference/dot-switch_theme.md).

- ...:

  Extra arguments passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/reference/dot-switch_theme.md).

## Value

A `ggplot` object.
