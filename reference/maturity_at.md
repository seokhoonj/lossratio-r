# Construct a Maturity object from manually specified maturity points

User-facing helper for hand-specifying a maturity point (or a set of
per-group maturity points) without running
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md).
The returned `"Maturity"` object plugs into any function that consumes a
Maturity result –
[`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md),
[`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md),
[`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md),
and the maturity input dispatcher – by carrying the same row schema as
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
output (group columns plus `ata_from`, `change`, `ata_link`).

Use this when company-standard or domain-knowledge maturity points are
known a priori and you want to override the data-driven detection. Stat
columns (`mean`, `cv`, `f`, `rse`, ...) are set to `NA_real_` because
manual entry carries no estimates.

Argument syntax mirrors
[`data.frame()`](https://rdrr.io/r/base/data.frame.html) /
`data.table()`: named vectors of equal length, one of which **must** be
`change` (the maturity point, an integer dev index). Any other named
arguments are treated as group columns.

## Usage

``` r
maturity_at(...)
```

## Arguments

- ...:

  Named vectors of equal length. Must include `change` (coercible to
  integer; the maturity point, i.e. the `to`-index of the first mature
  ata link). Any other named arguments are interpreted as group column
  values (e.g. `coverage`, `channel`). With no group columns the result
  is a pooled (single-row) Maturity.

## Value

A `data.table` with class `"Maturity"` carrying the same columns as
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
output: group columns (if any), `ata_from = change - 1L`, `change`,
`ata_link = "<from>-<to>"`, and the diagnostic stat columns (`mean`,
`median`, `wt`, `cv`, `f`, `f_se`, `rse`, `sigma`, `n_obs`, `n_valid`,
`n_inf`, `n_nan`, `valid_ratio`) set to `NA_real_`. `attr(., "groups")`
holds the group column names (possibly `character(0)`).

## See also

[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md),
[`regime_at()`](https://seokhoonj.github.io/lossratio/reference/regime_at.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Single-group manual override
maturity_at(coverage = "SUR", change = 4)

# Multi-group manual override (e.g. company-standard k*)
maturity_at(coverage = c("CAN", "CI", "HOS", "SUR"),
            change   = c(   9,   10,     7,     4))

# Pooled (no group columns)
maturity_at(change = 5)
} # }
```
