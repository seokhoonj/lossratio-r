# Plot an premium fit

Projection plot for an `"PremiumFit"` – observed and projected
cumulative premium by cohort, delegated to
[`.plot_projection_fit()`](https://seokhoonj.github.io/lossratio/reference/dot-plot_projection_fit.md).
Defined so an `PremiumFit` does not fall through to
[`plot.CLFit()`](https://seokhoonj.github.io/lossratio/reference/plot.CLFit.md),
whose `$full` schema is loss-side.

## Usage

``` r
# S3 method for class 'PremiumFit'
plot(x, ...)
```

## Arguments

- x:

  An object of class `"PremiumFit"`.

- ...:

  Forwarded to
  [`.plot_projection_fit()`](https://seokhoonj.github.io/lossratio/reference/dot-plot_projection_fit.md)
  – see
  [`plot.SAFit()`](https://seokhoonj.github.io/lossratio/reference/plot.SAFit.md).

## Value

A `ggplot` object.
