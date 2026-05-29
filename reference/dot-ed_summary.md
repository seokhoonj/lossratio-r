# Cohort-level reserve summary for an `EDFit`

Internal helper that derives the per-cohort `latest` / `loss_ult` /
`reserve` / process / parameter / total SE table from `x$full` and
stores it on `x$summary`. Mirrors
[`.cl_summary()`](https://seokhoonj.github.io/lossratio-r/reference/dot-cl_summary.md)
for cross-paradigm slot symmetry: both `CLFit$summary` and
`EDFit$summary` carry the same columns, so downstream consumers
([`summary.CLFit()`](https://seokhoonj.github.io/lossratio-r/reference/summary.CLFit.md),
future
[`summary.EDFit()`](https://seokhoonj.github.io/lossratio-r/reference/summary.EDFit.md)
reserve view,
[`fit_ratio()`](https://seokhoonj.github.io/lossratio-r/reference/fit_ratio.md)
composition, etc.) read from a uniform layout.

## Usage

``` r
.ed_summary(x)
```

## Arguments

- x:

  An object of class `"EDFit"` with a populated `$full` slot.

## Value

The input `x` with `$summary` filled.
