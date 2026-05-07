# Triangle heatmap for an ata fit

Visualise an object of class `"ATAFit"` as a triangle-style heatmap by
delegating to
[`plot_triangle.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.Link.md)
on the underlying `Link` data stored in `x$link` with `model = "ata"`.

## Usage

``` r
# S3 method for class 'ATAFit'
plot_triangle(x, ...)
```

## Arguments

- x:

  An object of class `"ATAFit"`.

- ...:

  Arguments passed to
  [`plot_triangle.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.Link.md).

## Value

A `ggplot` object.

## See also

[`plot_triangle.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.Link.md),
[`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md)
