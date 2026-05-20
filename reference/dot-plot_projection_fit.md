# Projection plot for a projection-level fit

Role-agnostic projection plot: observed and projected cumulative values
by cohort over development periods, with an optional confidence band.
The plotted column family is taken from `x$loss` (the fit's standardized
role – `"loss"` for CL / SA / BF / CC, `"exposure"` for an
`ExposureFit`), so every projection-level fit shares one implementation.
The interval is drawn whenever the `<role>_total_se` column is present
and finite.

## Usage

``` r
.plot_projection_fit(
  x,
  conf_level = 0.95,
  show_interval = TRUE,
  amount_divisor = "auto",
  scales = c("fixed", "free_y", "free_x", "free"),
  theme = c("view", "save", "shiny"),
  nrow = NULL,
  ncol = NULL,
  ...
)
```

## Arguments

- x:

  A projection-level fit (`CLFit`, `SAFit`, `BFFit`, `CCFit`, or
  `ExposureFit`) with a `$full` grid and `$loss` / `$groups` / `$cohort`
  / `$dev` slots.

- conf_level:

  Confidence level for interval display. Default is `0.95`.

- show_interval:

  Logical; if `TRUE`, show normal-approximation confidence intervals.
  Default is `TRUE`.

- amount_divisor:

  Numeric scaling factor for y-axis labels of amount variables. Default
  is `1e8`.

- scales:

  Facet scale argument passed to
  [`ggplot2::facet_wrap()`](https://ggplot2.tidyverse.org/reference/facet_wrap.html).
  One of `"fixed"`, `"free"`, `"free_x"`, or `"free_y"`.

- theme:

  A string passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/reference/dot-switch_theme.md).

- nrow, ncol:

  Number of rows and columns for
  [`ggplot2::facet_wrap()`](https://ggplot2.tidyverse.org/reference/facet_wrap.html).

- ...:

  Additional arguments passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio/reference/dot-switch_theme.md).

## Value

A `ggplot` object.
