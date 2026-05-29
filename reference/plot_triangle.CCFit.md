# Plot a Cape Cod fit as a triangle table

Triangle-style heatmap for a `"CCFit"`. Delegates to the shared
role-agnostic
[`.plot_triangle_fit()`](https://seokhoonj.github.io/lossratio-r/reference/dot-plot_triangle_fit.md)
implementation.

## Usage

``` r
# S3 method for class 'CCFit'
plot_triangle(x, ...)
```

## Arguments

- x:

  An object of class `"CCFit"`.

- ...:

  Forwarded to the shared implementation – see
  [`plot_triangle.SAFit()`](https://seokhoonj.github.io/lossratio-r/reference/plot_triangle.SAFit.md).

## Value

A `ggplot` object.
