# Plot a backtest object

Visualise the A/E Error (`ae_err`) of a `"Backtest"` object.

Three plot types:

- `"col"`: A/E Error aggregated by development period (one line per
  summary statistic).

- `"diag"`: A/E Error aggregated by calendar diagonal.

- `"cell"`: per-cell A/E Error as a scatter / line, faceted by group.

## Usage

``` r
# S3 method for class 'Backtest'
plot(
  x,
  type = c("col", "diag", "cell"),
  cell_type = c("cumulative", "incremental"),
  scales = c("fixed", "free_y", "free_x", "free"),
  theme = c("view", "save", "shiny"),
  ...
)
```

## Arguments

- x:

  An object of class `"Backtest"`.

- type:

  Plot type. One of `"col"`, `"diag"`, `"cell"`.

- cell_type:

  Which projection view to display. One of `"cumulative"` (default; uses
  `ae_err`) or `"incremental"` (uses `ae_err_incr`). Both are stored on
  every `Backtest` object – pick the view at plot time.

- scales:

  Facet scale argument. One of `"fixed"`, `"free"`, `"free_x"`,
  `"free_y"`.

- theme:

  String passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-switch_theme.md).

- ...:

  Extra arguments passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-switch_theme.md).

## Value

A `ggplot` object.
