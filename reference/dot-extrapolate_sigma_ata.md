# Extrapolate missing sigma values for age-to-age links

Internal helper that fills `NA` or non-positive `sigma` values in a
filtered ata factor table. Three methods are supported: `"min_last2"`,
`"locf"`, and `"loglinear"`. See Details.

## Usage

``` r
.extrapolate_sigma_ata(x, method = c("locf", "min_last2", "loglinear"))
```

## Arguments

- x:

  A `data.table` with `ata_from` and `sigma` columns, typically the
  output of
  [`.filter_ata()`](https://seokhoonj.github.io/lossratio/reference/dot-filter_ata.md).

- method:

  One of `"locf"` (default), `"min_last2"`, or `"loglinear"`.

## Value

A `data.table` with missing `sigma` values filled and a new logical
column `sigma_extrapolated` flagging imputed rows.
