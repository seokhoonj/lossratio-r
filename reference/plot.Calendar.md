# Plot calendar-based development statistics

Visualise an object of class `Calendar` as a time-series plot. The
selected metric is plotted over the calendar-style `calendar`, or over
the calendar development variable stored in `attr(x, "dev")`.

Ratio metrics (`lr`, `lr`) and proportion metrics (`loss_share`,
`loss_incr_share`, `premium_share`, `premium_incr_share`) are plotted on
the original scale and displayed as percentages via y-axis labels.
Amount metrics (`loss`, `loss_incr`, `premium`, `premium_incr`,
`margin`, `margin_incr`) are plotted on the original scale and displayed
using y-axis labels scaled by `amount_divisor`.

If grouping variables are present, lines are drawn separately by group.

## Usage

``` r
# S3 method for class 'Calendar'
plot(
  x,
  metric = "lr",
  x_by = c("period", "dev"),
  amount_divisor = 1e+08,
  theme = c("view", "save", "shiny"),
  ...
)
```

## Arguments

- x:

  An object of class `Calendar`.

- metric:

  A single metric to plot. Must be one of: `"lr"`, `"lr_incr"`,
  `"loss"`, `"loss_incr"`, `"premium"`, `"premium_incr"`, `"margin"`,
  `"margin_incr"`, `"loss_share"`, `"loss_incr_share"`,
  `"premium_share"`, or `"premium_incr_share"`.

- x_by:

  X-axis basis. One of:

  "period"

  :   Use the calendar variable stored in `attr(x, "calendar")`.

  "dev"

  :   Use the sequential `dev` column.

- amount_divisor:

  Numeric scaling factor used only for y-axis labels of amount
  variables. Default is `1e8`.

- theme:

  A string passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/reference/dot-switch_theme.md)
  (`"view"`, `"save"`, `"shiny"`).

- ...:

  Additional arguments passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/reference/dot-switch_theme.md).

## Value

A `ggplot` object.

## Details

The x-axis uses either the calendar variable stored in
`attr(x, "calendar")` or the sequential `dev` column, depending on
`x_by`.

The loss ratio is defined as: \$\$lr = loss / premium\$\$

where `premium` denotes risk premium rather than written premium.

## Examples

``` r
if (FALSE) { # \dontrun{
x <- build_calendar(
  df,
  groups   = "coverage",
  calendar = "cy_m",
  loss     = "loss_incr",
  premium  = "premium_incr"
)

plot(x)
plot(x, metric = "lr")
plot(x, x_by = "dev")
} # }
```
