# Plot an exposure fit

Projection plot for an `"ExposureFit"` – observed and projected
cumulative exposure by cohort, delegated to
[`.plot_projection_fit()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-plot_projection_fit.md).
Defined so an `ExposureFit` does not fall through to
[`plot.CLFit()`](https://seokhoonj.github.io/lossratio/ko/reference/plot.CLFit.md),
whose `$full` schema is loss-side.

## Usage

``` r
# S3 method for class 'ExposureFit'
plot(x, ...)
```

## Arguments

- x:

  An object of class `"ExposureFit"`.

- ...:

  Forwarded to
  [`.plot_projection_fit()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-plot_projection_fit.md)
  – see
  [`plot.SAFit()`](https://seokhoonj.github.io/lossratio/ko/reference/plot.SAFit.md).

## Value

A `ggplot` object.
