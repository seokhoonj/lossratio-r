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
  amount_divisor = "auto",
  show_label = FALSE,
  label_size = 2.8,
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
  variables. Default `"auto"` (picks the divisor that produces the
  shortest formatted label; pass an explicit numeric to fix it).

- show_label:

  Logical; if `TRUE`, overlay the metric value as a text label at each
  (calendar, group) point. Ratio metrics (`"lr"`, `"lr_incr"`, share
  variants) are formatted as percent (one decimal). Amount metrics are
  scaled by `amount_divisor` and formatted with one decimal. Default
  `FALSE`.

- label_size:

  Numeric text size passed to `geom_text` when `show_label = TRUE`.
  Default `2.8`.

- theme:

  A string passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-switch_theme.md)
  (`"view"`, `"save"`, `"shiny"`).

- ...:

  Additional arguments passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-switch_theme.md).

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
x <- as_calendar(
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
