# Extrapolate missing sigma values for age-to-age links

Internal helper that fills `NA` or non-positive `sigma` values in a
filtered ata factor table. Five methods are supported: `"locf"`,
`"min_last2"`, `"loglinear"`, `"mack"`, and `"none"`. See Details.

## Usage

``` r
.extrapolate_sigma_ata(
  x,
  method = c("locf", "min_last2", "loglinear", "mack", "none")
)
```

## Arguments

- x:

  A `data.table` with `ata_from` and `sigma` columns, typically the
  output of
  [`.filter_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-filter_ata.md).

- method:

  One of `"locf"` (default), `"min_last2"`, `"loglinear"`, `"mack"`, or
  `"none"`. `"mack"` applies Mack (1993) Appendix B tail estimator to
  the last unestimated link only and falls back to LOCF for any earlier
  unestimated links with a warning. `"none"` performs no extrapolation
  and leaves `sigma` as `NA`; downstream variance terms then drop those
  links via finite-value guards.

## Value

A `data.table` with missing `sigma` values filled and a new logical
column `sigma_extrapolated` flagging imputed rows.
