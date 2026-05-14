# Plot development trajectories with optional summary overlay

Visualise loss ratio or related metric trajectories across development
time from a `Triangle` object.

The function supports two display modes:

- **Raw mode (`summary = FALSE`)**: plots cohort-level trajectories
  coloured by the period variable stored in the `Triangle` object.

- **Summary mode (`summary = TRUE`)**: plots all cohort trajectories in
  grey and overlays three summary statistics:

  - Mean

  - Median

  - Weighted mean

Summary statistics are computed from
[`summary.Triangle()`](https://seokhoonj.github.io/lossratio/reference/summary.Triangle.md).

## Usage

``` r
# S3 method for class 'Triangle'
plot(
  x,
  metric = "lr",
  summary = FALSE,
  summary_min_n = 5L,
  amount_divisor = "auto",
  scales = c("fixed", "free_y", "free_x", "free"),
  theme = c("view", "save", "shiny"),
  ...
)
```

## Arguments

- x:

  An object of class `Triangle`.

- metric:

  A single metric to plot. Must be one of: `"lr"`, `"lr_incr"`,
  `"loss"`, `"loss_incr"`, `"premium"`, `"premium_incr"`, `"margin"`,
  `"margin_incr"`, `"loss_share"`, `"loss_incr_share"`,
  `"premium_share"`, or `"premium_incr_share"`.

- summary:

  Logical. If `FALSE` (default), shows raw cohort trajectories. If
  `TRUE`, shows grey cohort trajectories with overlaid summary lines
  (mean, median, weighted mean). Summary overlay is supported only for
  `"lr"` and `"lr_incr"`, and only when the x-axis variable is a
  development-period variable (for example, `dev_m`, `dev_q`, `dev_h`,
  `dev_y`).

- summary_min_n:

  Optional minimum number of observations required for the summary
  overlay to be considered reliable. When provided and `summary = TRUE`,
  a vertical reference line is drawn at the midpoint just before the
  first development period where `n_cohorts < summary_min_n` within each
  facet. Default is `5`.

- amount_divisor:

  Numeric scaling factor used only for y-axis labels of amount
  variables. Default is `1e8`.

- scales:

  Should scales be fixed (`"fixed"`), free (`"free"`), or free in one
  dimension (`"free_x"`, `"free_y"`)?

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

The x-axis uses the development variable stored in `attr(x, "dev")`.
Cohort lines are grouped by the period variable stored in
`attr(x, "cohort")`, and facets are created from `attr(x, "groups")`.

The cumulative loss ratio is defined here as: \$\$lr = loss /
premium\$\$

For long-term health insurance applications, risk premium is commonly
used as the `premium` measure.

The weighted mean is defined as:

- `lr_wt = sum(loss) / sum(premium)`

- `lr_incr_wt = sum(loss_incr) / sum(premium_incr)`

Ratio and proportion metrics are plotted on the original scale and
displayed as percentages via y-axis labels. Amount metrics are plotted
on the original scale and displayed using y-axis labels scaled by
`amount_divisor`.
