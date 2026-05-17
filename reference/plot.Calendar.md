# Plot calendar-based development statistics

Visualise an object of class `Calendar` as a time-series plot. The
selected metric is plotted over the calendar-style `calendar`, or over
the calendar development variable stored in `attr(x, "dev")`.

Ratio metrics (`lr`, `incr_lr`) and proportion metrics (`loss_share`,
`incr_loss_share`, `prem_share`, `incr_prem_share`) are plotted on the
original scale and displayed as percentages via y-axis labels. Amount
metrics (`loss`, `incr_loss`, `prem`, `incr_prem`, `margin`,
`incr_margin`) are plotted on the original scale and displayed using
y-axis labels scaled by `amount_divisor`.

If grouping variables are present, lines are drawn separately by group.

## Usage

``` r
# S3 method for class 'Calendar'
plot(
  x,
  metric = "lr",
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

  A single metric to plot. Must be one of: `"lr"`, `"incr_lr"`,
  `"loss"`, `"incr_loss"`, `"prem"`, `"incr_prem"`, `"margin"`,
  `"incr_margin"`, `"loss_share"`, `"incr_loss_share"`, `"prem_share"`,
  or `"incr_prem_share"`.

- amount_divisor:

  Numeric scaling factor used only for y-axis labels of amount
  variables. Default `"auto"` (picks the divisor that produces the
  shortest formatted label; pass an explicit numeric to fix it).

- show_label:

  Logical; if `TRUE`, overlay the metric value as a text label at each
  (calendar, group) point. Ratio metrics (`"lr"`, `"incr_lr"`, share
  variants) are formatted as percent (one decimal). Amount metrics are
  scaled by `amount_divisor` and formatted with one decimal. Default
  `FALSE`.

- label_size:

  Numeric text size passed to `geom_text` when `show_label = TRUE`.
  Default `2.8`.

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

The x-axis is the calendar variable stored in `attr(x, "calendar")` (a
Date, formatted per the triangle's `grain`).

The loss ratio is defined as: \$\$lr = loss / prem\$\$

where `prem` denotes risk premium rather than written prem.

## Examples

``` r
if (FALSE) { # \dontrun{
x <- as_calendar(
  df,
  groups   = "coverage",
  calendar = "cy_m",
  loss     = "incr_loss",
  prem     = "incr_prem"
)

plot(x)
plot(x, metric = "lr")
} # }
```
