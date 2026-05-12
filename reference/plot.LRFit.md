# Plot a loss ratio fit

Visualise an object of class `"LRFit"`.

The plotted metric is the cross-product of `metric` and `cell_type`:

- `metric = "lr"`, `cell_type = "cumulative"`: cumulative loss ratio
  (default).

- `metric = "lr_incr"` (i.e., `cell_type = "incremental"`): per-period
  loss ratio.

- `metric = "loss"` / `"premium"`: same split — cumulative or per-period
  amounts.

Confidence bands are drawn only for cumulative metrics
(`cell_type = "cumulative"`), since the fit output does not carry SE
columns for incremental projections.

## Usage

``` r
# S3 method for class 'LRFit'
plot(
  x,
  metric = c("lr", "loss", "premium"),
  cell_type = c("cumulative", "incremental"),
  per_group = NULL,
  ask = grDevices::dev.interactive(),
  conf_level = 0.95,
  show_interval = TRUE,
  amount_divisor = 1e+08,
  scales = c("fixed", "free_y", "free_x", "free"),
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

  Metric to plot. One of `"lr"` (default), `"loss"`, `"premium"`.

- cell_type:

  Aggregation. One of `"cumulative"` (default) or `"incremental"`.

- per_group:

  Logical or `NULL`. When `TRUE` (auto for multi-group fits), produce
  one ggplot per group and print them sequentially with
  [`devAskNewPage()`](https://rdrr.io/r/grDevices/devAskNewPage.html) —
  mirrors base R's `plot.lm()` pattern of stepping through related
  diagnostic plots. Returns the list of plots invisibly. When `FALSE`
  (auto for single-group fits), facets every (group, cohort) combination
  in a single ggplot.

- ask:

  Passed to
  [`devAskNewPage()`](https://rdrr.io/r/grDevices/devAskNewPage.html)
  when `per_group = TRUE`. Defaults to
  [`dev.interactive()`](https://rdrr.io/r/grDevices/dev.interactive.html).

- conf_level:

  Confidence level. Default is `0.95`.

- show_interval:

  Logical. Default is `TRUE`.

- amount_divisor:

  Numeric. Default is `1e8`.

- scales:

  Facet scale argument.

- theme:

  Theme string.

- nrow, ncol:

  Facet dimensions.

- ...:

  Additional arguments.

## Value

A `ggplot` object.
