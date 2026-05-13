# Triangle heatmap of backtest A/E Error

Display the held-out cells as a `cohort x dev` heatmap coloured by A/E
Error (red = under-projected (actual \> proj), blue = over-projected
(actual \< proj), white at 0).

## Usage

``` r
# S3 method for class 'Backtest'
plot_triangle(
  x,
  view = c("value", "usage"),
  cell_type = c("cumulative", "incremental"),
  label_size = 2.5,
  theme = c("view", "save", "shiny"),
  ...
)
```

## Arguments

- x:

  An object of class `"Backtest"`.

- view:

  Plot mode:

  `"value"` (default)

  :   Held-out-cell heatmap coloured by A/E Error.

  `"usage"`

  :   Cell-status heatmap (training / held-out / dropped
      (regime-filtered) / future) driven by `x$holdout` and the fit's
      `regime`. Useful to inspect what data the masked refit actually
      saw, especially when combined with multi-group `regime`.

- cell_type:

  Which projection view to display in `view = "value"`. One of
  `"cumulative"` (default; uses `ae_err`) or `"incremental"` (uses
  `ae_err_incr`).

- label_size:

  Numeric label text size for cell labels. Default `2.5` (single-line
  A/E Error percent labels on the held-out wedge).

- theme:

  String passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-switch_theme.md).

- ...:

  Extra arguments passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-switch_theme.md).

## Value

A `ggplot` object.
