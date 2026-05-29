# Plot a stage-adaptive fit

Projection plot for a `"SAFit"` – observed and projected cumulative loss
by cohort, delegated to
[`.plot_projection_fit()`](https://seokhoonj.github.io/lossratio-r/reference/dot-plot_projection_fit.md).

## Usage

``` r
# S3 method for class 'SAFit'
plot(x, ...)
```

## Arguments

- x:

  An object of class `"SAFit"`.

- ...:

  Forwarded to
  [`.plot_projection_fit()`](https://seokhoonj.github.io/lossratio-r/reference/dot-plot_projection_fit.md)
  – `conf_level`, `show_interval`, `amount_divisor`, `scales`, `theme`,
  `nrow`, `ncol`, plus theme options.

## Value

A `ggplot` object.
