# Plot an exposure fit as a triangle table

Triangle-style heatmap for an `"ExposureFit"`. Delegates to the shared
role-agnostic
[`.plot_triangle_fit()`](https://seokhoonj.github.io/lossratio/reference/dot-plot_triangle_fit.md)
implementation; the cell metric is the exposure projection.

## Usage

``` r
# S3 method for class 'ExposureFit'
plot_triangle(x, ...)
```

## Arguments

- x:

  An object of class `"ExposureFit"`.

- ...:

  Forwarded to the shared implementation – see
  [`plot_triangle.SAFit()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.SAFit.md).

## Value

A `ggplot` object.
