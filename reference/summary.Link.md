# Summarise a `Link` table

Dispatch to the appropriate diagnostic table based on `model`.

## Usage

``` r
# S3 method for class 'Link'
summary(object, model = NULL, alpha = 1, digits = NULL, ...)
```

## Arguments

- object:

  A `Link` object from
  [`build_link()`](https://seokhoonj.github.io/lossratio/reference/build_link.md).

- model:

  Either `"ata"` (multiplicative chain-ladder factors) or `"ed"`
  (additive exposure-driven intensities). When `model = "ed"`, the link
  table must have been built with `premium_var` set. The default uses
  `"ed"` if `attr(object, "premium_var")` is non-`NULL`, otherwise
  `"ata"`.

- alpha, digits, ...:

  Forwarded to the underlying summary helper.

## Value

Either an `ATASummary` (model = `"ata"`) or `EDSummary` (model = `"ed"`)
`data.table`.

## See also

[`build_link()`](https://seokhoonj.github.io/lossratio/reference/build_link.md),
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
