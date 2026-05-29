# Triangle heatmap for an ED fit

Visualise an object of class `"EDFit"` as a triangle-style heatmap by
delegating to
[`plot_triangle.Link()`](https://seokhoonj.github.io/lossratio-r/reference/plot_triangle.Link.md)
on the underlying `Link` data stored in `x$link` with `model = "ed"`.

## Usage

``` r
# S3 method for class 'EDFit'
plot_triangle(x, ...)
```

## Arguments

- x:

  An object of class `"EDFit"`.

- ...:

  Arguments passed to
  [`plot_triangle.Link()`](https://seokhoonj.github.io/lossratio-r/reference/plot_triangle.Link.md).

## Value

A `ggplot` object.

## See also

[`plot_triangle.Link()`](https://seokhoonj.github.io/lossratio-r/reference/plot_triangle.Link.md),
[`fit_ed()`](https://seokhoonj.github.io/lossratio-r/reference/fit_ed.md)
