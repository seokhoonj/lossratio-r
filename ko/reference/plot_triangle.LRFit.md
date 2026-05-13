# Plot loss ratio projection as a triangle heatmap

Visualise an `"LRFit"` object as a triangle-style heatmap of cumulative
loss ratios. Observed and projected cells are distinguished by border
style.

## Usage

``` r
# S3 method for class 'LRFit'
plot_triangle(
  x,
  metric = c("lr", "loss", "premium"),
  cell_type = c("cumulative", "incremental"),
  region = c("proj", "full", "data"),
  view = c("value", "usage"),
  label_style = c("value", "detail"),
  label_size = NULL,
  show_maturity = TRUE,
  digits = 0,
  amount_divisor = 1e+08,
  theme = c("view", "save", "shiny"),
  nrow = NULL,
  ncol = NULL,
  ...
)
```

## Arguments

- x:

  An object of class `"LRFit"`.

- metric:

  Metric shown in the heatmap cells. One of `"lr"` (default), `"loss"`,
  `"premium"`.

- cell_type:

  Aggregation. One of `"cumulative"` (default) or `"incremental"`.
  Combined with `metric` to select the column (e.g., `metric = "lr"`,
  `cell_type = "incremental"` → `lr_incr`).

- region:

  Cell region to plot (only used when `view = "value"`). One of `"proj"`
  (projected cells only, observed cells masked), `"full"` (observed +
  projected), or `"data"` (observed cumulative loss / premium / lr from
  `x$data` — the raw Triangle, no projection). Default is `"proj"`.

- view:

  Plot mode. One of:

  "value" (default)

  :   Per-cell `lr` heatmap with column-wise relative fill. `region`
      selects which cells to display.

  "usage"

  :   Cell-status heatmap (`used` / `holdout` / `unused` / `future`)
      driven by the fit's own metadata (`x$recent`, `x$loss_regime`,
      `x$maturity`). `region` is ignored.

- label_style:

  One of `"value"` (lr only) or `"detail"` (lr with loss/exposure
  amounts). Default is `"value"`.

- label_size:

  Numeric label text size forwarded to
  [`ggshort::ggtable()`](https://rdrr.io/pkg/ggshort/man/ggtable.html).
  Defaults to `3` for `label_style = "value"` and `2.5` for
  `label_style = "detail"` (two-line labels).

- show_maturity:

  Logical; if `TRUE`, show maturity line. Default is `TRUE`.

- digits:

  Number of decimal places for lr display. Default is `0`.

- amount_divisor:

  Numeric divisor for amount display in `"detail"` mode. Default is
  `1e8`.

- theme:

  Theme string.

- nrow, ncol:

  Facet dimensions.

- ...:

  Additional arguments passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-switch_theme.md).

## Value

A `ggplot` object.
