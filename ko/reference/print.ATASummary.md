# Print method for `ATASummary`

Numeric columns are stored at full double precision; rounding is applied
only for display. The default `digits` is taken from the `digits`
attribute set by
[`summary.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md)
(3 unless overridden).

## Usage

``` r
# S3 method for class 'ATASummary'
print(x, digits = attr(x, "digits"), ...)
```

## Arguments

- x:

  An object of class `"ATASummary"`.

- digits:

  Number of decimal places to display. Default uses the `digits`
  attribute attached at construction.

- ...:

  Further arguments passed to `print.data.table`.
