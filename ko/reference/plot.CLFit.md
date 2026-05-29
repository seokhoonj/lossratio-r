# Plot a chain ladder fit

Visualise an object of class `"CLFit"`.

Two plot types are supported:

- `"projection"`: observed and projected cumulative values by cohort
  over development periods. Optional confidence bands are drawn using
  `loss_total_se`.

- `"reserve"`: reserve summary by cohort with optional error bars.

## Usage

``` r
# S3 method for class 'CLFit'
plot(
  x,
  type = c("projection", "reserve"),
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

  An object of class `"CLFit"`.

- type:

  Plot type. One of `"projection"` or `"reserve"`.

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
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio-r/ko/reference/dot-switch_theme.md).

- nrow, ncol:

  Number of rows and columns for
  [`ggplot2::facet_wrap()`](https://ggplot2.tidyverse.org/reference/facet_wrap.html).

- ...:

  Additional arguments passed to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio-r/ko/reference/dot-switch_theme.md).

## Value

A `ggplot` object.
