# Derive monthly / quarterly / semi-annual / annual grain columns

Given a long-format frame with monthly source columns (`uy_m`, `cy_m`,
optionally `dev_m`), derive the coarser-grain siblings (`uy_q` / `uy_h`
/ `uy`, `cy_q` / `cy_h` / `cy`, `dev_q` / `dev_h` / `dev_y`) so the same
frame can be aggregated at any of the four grains.

This is an *optional* utility —
[`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md)
and
[`build_calendar()`](https://seokhoonj.github.io/lossratio/ko/reference/build_calendar.md)
already derive the single grain they need internally. Use this when you
want a single enriched frame that can be re-aggregated at multiple
grains, or for exploratory plots.

## Usage

``` r
derive_grain_columns(df)
```

## Arguments

- df:

  A data.frame containing `uy_m`, `cy_m`, and optionally `dev_m`.
  Coarser-grain siblings are derived from these.

## Value

A `data.table` with the additional grain columns.

## Details

Letter-suffix family: `_m` / `_q` / `_h` / `_y` = monthly / quarterly /
half-yearly / yearly.

Derived columns when source columns exist:

**Underwriting (from `uy_m`):**

- `uy` : yearly start (Jan 1 of `uy_m`'s year)

- `uy_h` : half-yearly start (Jan 1 / Jul 1)

- `uy_q` : quarterly start (Jan / Apr / Jul / Oct 1)

**Calendar (from `cy_m`):**

- `cy` : yearly start

- `cy_h` : half-yearly start

- `cy_q` : quarterly start

**Development (from `uy_m` and `cy_m`, with `dev_m` derived if
absent):**

- `dev_y` is the yearly development index, where dev_m 1-12 map to 1,
  13-24 map to 2, and so on.

- `dev_h` and `dev_q` are aligned to calendar half-yearly and quarterly
  boundaries (not simple groupings of `dev_m`), so cohorts such as Q1 /
  Q2 / H1 / H2 are compared consistently on the same cumulative
  development basis.

Newly created columns are inserted before their corresponding base
columns.

## Examples

``` r
if (FALSE) { # \dontrun{
df <- data.frame(
  uy_m  = as.Date("2023-01-01") + 0:5 * 30,
  cy_m  = as.Date("2023-01-01") + 0:5 * 30,
  dev_m = 1:6
)

df2 <- derive_grain_columns(df)
head(df2)
} # }
```
