# Summary method for `BFFit`

Returns the cohort-level reserve summary
`[group..., cohort, latest, loss_ult, reserve, elr, q]`. Mirrors
[`summary.CLFit()`](https://seokhoonj.github.io/lossratio-r/reference/summary.CLFit.md)
for slot symmetry; the `prior`/`q` columns are BF-specific.

## Usage

``` r
# S3 method for class 'BFFit'
summary(object, ...)
```

## Arguments

- object:

  A `BFFit` object.

- ...:

  Unused.
