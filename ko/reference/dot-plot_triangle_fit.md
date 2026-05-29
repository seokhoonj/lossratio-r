# Triangle-table plot for a projection-level fit

Role-agnostic triangle-style heatmap shared by the `plot_triangle`
methods for `CLFit` / `SAFit` / `BFFit` / `CCFit` / `PremiumFit`. The
cell metric and per-cell SE / CV columns are derived from `x$loss`
(`loss_*` for the loss-side fits, `premium_*` for an `PremiumFit`).

The `region` argument controls which values are shown:

- `"proj"`:

  Projected cells only.

- `"full"`:

  Observed and projected full triangle.

- `"data"`:

  Original observed data from `x$data`.

The `label_style` argument controls cell labels:

- `"value"`:

  Projected value only. Applied to all cells.

- `"cv"`:

  Coefficient of variation (%) for projected cells.

- `"se"`:

  Standard error for projected cells.

- `"ci"`:

  Confidence interval for projected cells.

## Usage

``` r
.plot_triangle_fit(
  x,
  region = c("proj", "full", "data"),
  view = c("value", "usage"),
  label_style = c("value", "cv", "se", "ci"),
  label_size = NULL,
  conf_level = 0.95,
  amount_divisor = "auto",
  theme = c("view", "save", "shiny"),
  nrow = NULL,
  ncol = NULL,
  ...
)
```

## Arguments

- x:

  A projection-level fit (`CLFit`, `SAFit`, `BFFit`, `CCFit`, or
  `PremiumFit`).

- region:

  Cell region to plot (only used when `view = "value"`). One of `"proj"`
  (default; projected cells only, observed cells masked), `"full"`
  (observed + projected), or `"data"` (observed from `x$data` – the raw
  Triangle, no projection).

- view:

  Plot mode. One of:

  "value" (default)

  :   Per-cell metric heatmap. `region` selects which cells to display.

  "usage"

  :   Cell-status heatmap (`fit_data` / `excluded` / `future`) driven by
      the fit's `x$recent`. `region` is ignored. CL has no `regime` /
      maturity hooks, so the hybrid overlays do not apply.

- label_style:

  One of `"value"` (default), `"cv"`, `"se"`, or `"ci"`.

- label_size:

  Numeric size of the in-cell text label. Defaults to `3` for
  `label_style = "value"`, `"cv"`, or `"se"` and `2.5` for
  `label_style = "ci"` (two-line labels).

- conf_level:

  Confidence level used when `label_style = "ci"`. Default is `0.95`.

- amount_divisor:

  Numeric scaling factor for amount variables. Default is `1`.

- theme:

  A string passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio-r/ko/reference/dot-switch_theme.md).

- nrow, ncol:

  Number of rows and columns for
  [`ggplot2::facet_wrap()`](https://ggplot2.tidyverse.org/reference/facet_wrap.html).

- ...:

  Additional arguments passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio-r/ko/reference/dot-switch_theme.md).

## Value

A ggplot object.
