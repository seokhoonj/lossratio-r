# Plot a Cape Cod fit as a triangle table

Triangle-style heatmap for a `"CCFit"`. Delegates to the role-agnostic
implementation shared with
[`plot_triangle.CLFit()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.CLFit.md).

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
  [`plot_triangle.SAFit()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.SAFit.md).

## Value

A `ggplot` object.
