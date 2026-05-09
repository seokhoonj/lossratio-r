# Plot development values as a triangle table

Visualise a `Triangle` object as a triangle-style table. Cells are
arranged by period and dev dimensions, and each cell displays the
selected metric.

For ratio metrics (`lr`, `lr`), labels can show either the ratio alone
or the ratio together with the associated loss / risk premium amounts.

For amount metrics (`loss`, `loss_incr`, `premium`, `premium_incr`,
`margin`, `margin_incr`), labels show the selected amount only.

For proportion metrics (`loss_prop`, `loss_incr_prop`, `premium_prop`,
`premium_incr_prop`), labels are displayed as percentages.

The loss ratio is defined as: \$\$lr = loss / premium\$\$

where `premium` denotes risk premium rather than written premium.

## Usage

``` r
# S3 method for class 'Triangle'
plot_triangle(
  x,
  type = c("value", "usage"),
  value_var = "lr",
  label_style = c("value", "detail"),
  amount_divisor = 1e+08,
  nrow = NULL,
  ncol = NULL,
  theme = c("view", "save", "shiny"),
  ...
)
```

## Arguments

- x:

  An object of class `Triangle`.

- type:

  Plot type. One of:

  "value"

  :   (default) Per-cell metric heatmap controlled by `value_var`,
      `label_style`, `amount_divisor`, `nrow`, `ncol`.

  "usage"

  :   Cell-status heatmap (fit_data / held_out / excluded / future).
      Accepts `recent`, `regime_break`, `holdout`, `maturity_args` via
      `...`. See
      [`vignette("regime-break-filter")`](https://seokhoonj.github.io/lossratio/articles/regime-break-filter.md)
      for details.

- value_var:

  A single metric to plot. Must be one of: `"lr"`, `"lr_incr"`,
  `"loss"`, `"loss_incr"`, `"premium"`, `"premium_incr"`, `"margin"`,
  `"margin_incr"`, `"loss_prop"`, `"loss_incr_prop"`, `"premium_prop"`,
  or `"premium_incr_prop"`.

- label_style:

  Label display style. One of:

  "value"

  :   Show only the selected metric.

  "detail"

  :   For `lr` / `lr`, show the ratio in percent and, on the next line,
      the associated loss / premium amounts. For amount and proportion
      metrics, this falls back to `"value"`.

- amount_divisor:

  Numeric scaling factor applied to amount variables (e.g., `loss`,
  `loss_incr`, `premium`, `premium_incr`, `margin`, `margin_incr`)
  before plotting. Default is `1e8`

- nrow, ncol:

  Number of rows and columns passed to
  [`ggplot2::facet_wrap()`](https://ggplot2.tidyverse.org/reference/facet_wrap.html).

- theme:

  A string passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/reference/dot-switch_theme.md)
  (`"view"`, `"save"`, `"shiny"`).

- ...:

  Additional arguments passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/reference/dot-switch_theme.md).

## Value

A ggplot object.

## Details

The x-axis uses the development variable stored in `attr(x, "dev_var")`,
and the y-axis uses the period variable stored in
`attr(x, "cohort_var")`. If either axis variable is a period-like
variable such as `uym`, `cym`, `uyq`, `cyq`, `uyh`, `cyh`, `uy`, or
`cy`, it is formatted using
[`.format_period()`](https://seokhoonj.github.io/lossratio/reference/dot-format_period.md).

Facets are created from `attr(x, "group_var")`.

Ratio and proportion values are displayed in percent. Amount values are
displayed in units of 100 million KRW.

## Examples

``` r
if (FALSE) { # \dontrun{
d <- build_triangle(df, group_var = pd_cat_nm)

plot_triangle(d)
plot_triangle(d, value_var = "lr")
plot_triangle(d, value_var = "loss")
plot_triangle(d, value_var = "premium")
plot_triangle(d, value_var = "loss_prop")
plot_triangle(d, value_var = "premium_prop")
plot_triangle(d, label_style = "value")
plot_triangle(d, label_style = "detail")
} # }
```
