# Plot an Intensity fit

Visualise an object of class `"IntensityFit"` by delegating to
[`plot.Link()`](https://seokhoonj.github.io/lossratio-r/reference/plot.Link.md)
on the underlying `Link` data stored in `x$link` with `model = "ed"`.
`IntensityFit` is the factor-level diagnostic for the exposure-driven
(ED) workflow and mirrors how
[`plot.ATAFit()`](https://seokhoonj.github.io/lossratio-r/reference/plot.ATAFit.md)
delegates for the multiplicative (CL) side.

## Usage

``` r
# S3 method for class 'IntensityFit'
plot(x, ...)
```

## Arguments

- x:

  An object of class `"IntensityFit"`.

- ...:

  Arguments passed to
  [`plot.Link()`](https://seokhoonj.github.io/lossratio-r/reference/plot.Link.md).

## Value

A `ggplot` object.

## See also

[`plot.Link()`](https://seokhoonj.github.io/lossratio-r/reference/plot.Link.md),
[`fit_intensity()`](https://seokhoonj.github.io/lossratio-r/reference/fit_intensity.md),
[`plot.ATAFit()`](https://seokhoonj.github.io/lossratio-r/reference/plot.ATAFit.md)
