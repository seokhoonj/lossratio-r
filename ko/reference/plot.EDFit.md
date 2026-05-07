# Plot an ED fit

Visualise an object of class `"EDFit"` by delegating to
[`plot.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Link.md)
on the underlying `Link` data stored in `x$link` with `model = "ed"`.

## Usage

``` r
# S3 method for class 'EDFit'
plot(x, ...)
```

## Arguments

- x:

  An object of class `"EDFit"`.

- ...:

  Arguments passed to
  [`plot.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Link.md).

## Value

A `ggplot` object.

## See also

[`plot.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Link.md),
[`fit_ed()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ed.md)
