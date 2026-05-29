# Triangle heatmap for an Intensity fit

Visualise an object of class `"IntensityFit"` as a triangle-style
heatmap by delegating to
[`plot_triangle.Link()`](https://seokhoonj.github.io/lossratio-r/ko/reference/plot_triangle.Link.md)
on the underlying `Link` data stored in `x$link` with `model = "ed"`.

## Usage

``` r
# S3 method for class 'IntensityFit'
plot_triangle(x, ...)
```

## Arguments

- x:

  An object of class `"IntensityFit"`.

- ...:

  Arguments passed to
  [`plot_triangle.Link()`](https://seokhoonj.github.io/lossratio-r/ko/reference/plot_triangle.Link.md).

## Value

A `ggplot` object.

## See also

[`plot_triangle.Link()`](https://seokhoonj.github.io/lossratio-r/ko/reference/plot_triangle.Link.md),
[`fit_intensity()`](https://seokhoonj.github.io/lossratio-r/ko/reference/fit_intensity.md),
[`plot_triangle.ATAFit()`](https://seokhoonj.github.io/lossratio-r/ko/reference/plot_triangle.ATAFit.md)
