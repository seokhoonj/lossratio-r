# Plot an ata fit

Visualise an object of class `"ATAFit"` by delegating to
[`plot.Link()`](https://seokhoonj.github.io/lossratio/reference/plot.Link.md)
on the underlying `Link` data stored in `x$link` with `model = "ata"`.

## Usage

``` r
# S3 method for class 'ATAFit'
plot(x, ...)
```

## Arguments

- x:

  An object of class `"ATAFit"`.

- ...:

  Arguments passed to
  [`plot.Link()`](https://seokhoonj.github.io/lossratio/reference/plot.Link.md).

## Value

A `ggplot` object.

## See also

[`plot.Link()`](https://seokhoonj.github.io/lossratio/reference/plot.Link.md),
[`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md)
