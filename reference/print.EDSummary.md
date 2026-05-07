# Print method for `EDSummary`

Numeric columns are stored at full double precision; rounding is applied
only for display. The default `digits` is taken from the `digits`
attribute set by
[`summary.Link()`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md)
(5 unless overridden).

## Usage

``` r
# S3 method for class 'EDSummary'
print(x, digits = attr(x, "digits"), ...)
```

## Arguments

- x:

  An object of class `"EDSummary"`.

- digits:

  Number of decimal places to display. Default uses the `digits`
  attribute attached at construction.

- ...:

  Further arguments passed to `print.data.table`.
