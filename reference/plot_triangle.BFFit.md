# Plot a Bornhuetter-Ferguson fit as a triangle table

Triangle-style heatmap for a `"BFFit"`. Delegates to the role-agnostic
implementation shared with
[`plot_triangle.CLFit()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.CLFit.md).

## Usage

``` r
# S3 method for class 'BFFit'
plot_triangle(x, ...)
```

## Arguments

- x:

  An object of class `"BFFit"`.

- ...:

  Forwarded to the shared implementation – see
  [`plot_triangle.SAFit()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.SAFit.md).

## Value

A `ggplot` object.
