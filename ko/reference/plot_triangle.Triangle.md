# Plot development values as a triangle table

Visualise a `Triangle` object as a triangle-style table. Cells are
arranged by period and dev dimensions, and each cell displays the
selected metric.

For ratio metrics (`lr`, `lr`), labels can show either the ratio alone
or the ratio together with the associated loss / risk premium amounts.

For amount metrics (`loss`, `loss_incr`, `premium`, `premium_incr`,
`margin`, `margin_incr`), labels show the selected amount only.

For proportion metrics (`loss_share`, `loss_incr_share`,
`premium_share`, `premium_incr_share`), labels are displayed as
percentages.

The loss ratio is defined as: \$\$lr = loss / premium\$\$

where `premium` denotes risk premium rather than written premium.

## Usage

``` r
# S3 method for class 'Triangle'
plot_triangle(
  x,
  view = c("value", "usage"),
  metric = "lr",
  label_style = c("value", "detail"),
  label_size = NULL,
  amount_divisor = "auto",
  nrow = NULL,
  ncol = NULL,
  theme = c("view", "save", "shiny"),
  ...
)
```

## Arguments

- x:

  An object of class `Triangle`.

- view:

  Plot view. One of:

  "value"

  :   (default) Per-cell metric heatmap controlled by `metric`,
      `label_style`, `amount_divisor`, `nrow`, `ncol`.

  "usage"

  :   Cell-status heatmap (used / holdout / unused / future). Accepts
      `recent`, `regime`, `holdout`, `maturity` via `...`. See
      [`vignette("regime-change-filter")`](https://seokhoonj.github.io/lossratio/ko/articles/regime-change-filter.md)
      for details.

- metric:

  A single metric to plot. Must be one of: `"lr"`, `"lr_incr"`,
  `"loss"`, `"loss_incr"`, `"premium"`, `"premium_incr"`, `"margin"`,
  `"margin_incr"`, `"loss_share"`, `"loss_incr_share"`,
  `"premium_share"`, or `"premium_incr_share"`.

- label_style:

  Label display style. One of:

  "value"

  :   Show only the selected metric.

  "detail"

  :   For `lr` / `lr`, show the ratio in percent and, on the next line,
      the associated loss / premium amounts. For amount and proportion
      metrics, this falls back to `"value"`.

- label_size:

  Numeric label text size forwarded to
  [`ggshort::ggtable()`](https://rdrr.io/pkg/ggshort/man/ggtable.html).
  Defaults to `3` for `label_style = "value"` and `2.5` for
  `label_style = "detail"` (two-line labels need a smaller size to fit).
  Other label appearance fields (family, color, hjust, ...) fall back to
  ggshort defaults.

- amount_divisor:

  Numeric scaling factor applied to amount variables (e.g., `loss`,
  `loss_incr`, `premium`, `premium_incr`, `margin`, `margin_incr`)
  before plotting. Default `"auto"` picks the largest divisor in
  `{1, 1e3, 1e6, 1e7, 1e8, 1e9}` such that the median displayed value is
  still at least `1`, minimising label digit count.

- nrow, ncol:

  Number of rows and columns passed to
  [`ggplot2::facet_wrap()`](https://ggplot2.tidyverse.org/reference/facet_wrap.html).

- theme:

  A string passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-switch_theme.md)
  (`"view"`, `"save"`, `"shiny"`).

- ...:

  Additional arguments passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-switch_theme.md).

## Value

A ggplot object.

## Details

The x-axis uses the development variable stored in `attr(x, "dev")`, and
the y-axis uses the period variable stored in `attr(x, "cohort")`. If
either axis variable is a period-like variable such as `uy_m`, `cy_m`,
`uy_q`, `cy_q`, `uy_h`, `cy_h`, `uy`, or `cy`, it is formatted using
[`.format_period()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-format_period.md).

Facets are created from `attr(x, "groups")`.

Ratio and proportion values are displayed in percent. Amount values are
displayed in units of 100 million KRW.

## Examples

``` r
if (FALSE) { # \dontrun{
d <- build_triangle(
  df,
  groups   = "pd_cat_nm",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "loss_incr",
  premium  = "premium_incr"
)

plot_triangle(d)
plot_triangle(d, metric = "lr")
plot_triangle(d, metric = "loss")
plot_triangle(d, metric = "premium")
plot_triangle(d, metric = "loss_share")
plot_triangle(d, metric = "premium_share")
plot_triangle(d, label_style = "value")
plot_triangle(d, label_style = "detail")
} # }
```
