# Derive monthly / quarterly / semi-annual / annual grain columns

Given a long-format frame with monthly source columns (`uy_m`, `cy_m`,
optionally `dev_m`), derive the coarser-grain siblings (`uy_q` / `uy_s`
/ `uy_a`, `cy_q` / `cy_s` / `cy_a`, `dev_q` / `dev_s` / `dev_a`) so the
same frame can be aggregated at any of the four grains.

This is an *optional* utility —
[`build_triangle()`](https://seokhoonj.github.io/lossratio/reference/build_triangle.md)
and
[`build_calendar()`](https://seokhoonj.github.io/lossratio/reference/build_calendar.md)
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

Letter-suffix family: `_m` / `_q` / `_s` / `_a` = monthly / quarterly /
semi-annual / annual.

Derived columns when source columns exist:

**Underwriting (from `uy_m`):**

- `uy_a` : annual start (Jan 1 of `uy_m`'s year)

- `uy_s` : semi-annual start (Jan 1 / Jul 1)

- `uy_q` : quarterly start (Jan / Apr / Jul / Oct 1)

**Calendar (from `cy_m`):**

- `cy_a` : annual start

- `cy_s` : semi-annual start

- `cy_q` : quarterly start

**Development (from `uy_m` and `cy_m`, with `dev_m` derived if
absent):**

- `dev_a` is the annual development index, where dev_m 1-12 map to 1,
  13-24 map to 2, and so on.

- `dev_s` and `dev_q` are aligned to calendar semi-annual and quarterly
  boundaries (not simple groupings of `dev_m`), so cohorts such as Q1 /
  Q2 / S1 / S2 are compared consistently on the same cumulative
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
