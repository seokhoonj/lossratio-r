# Summarise development statistics (Mean, Median, Weighted)

S3 method for [`summary()`](https://rdrr.io/r/base/summary.html) on
`Triangle` objects. Computes group-wise summary statistics for
cumulative loss ratios (`ratio`) and per-period loss ratios
(`incr_ratio`).

The function aggregates data by the grouping variables stored in
`attr(x, "groups")` and the development variable stored in
`attr(x, "dev")`.

The following statistics are computed:

- arithmetic mean,

- median,

- weighted mean (portfolio-level ratio based on sums).

## Usage

``` r
# S3 method for class 'Triangle'
summary(object, ...)
```

## Arguments

- object:

  An object of class `Triangle`.

- ...:

  Unused; included for S3 compatibility.

## Value

A `data.table` grouped by `groups` and `dev`, containing:

- n_cohorts:

  Number of observations in the cell

- ratio_mean:

  Mean of cumulative loss ratios

- ratio_median:

  Median of cumulative loss ratios

- ratio_wt:

  Weighted cumulative loss ratio (`sum(loss) / sum(premium)`)

- incr_ratio_mean:

  Mean of per-period loss ratios

- incr_ratio_median:

  Median of per-period loss ratios

- incr_ratio_wt:

  Weighted per-period loss ratio (`sum(incr_loss) / sum(incr_premium)`)

The returned object keeps the attributes `groups` and `dev`, and its
class is updated to `"TriangleSummary"`.

## Details

The weighted mean is computed as:

- `ratio_wt = sum(loss) / sum(premium)`

- `incr_ratio_wt = sum(incr_loss) / sum(incr_premium)`

These correspond to portfolio-level loss ratios based on premium and are
typically more stable than simple averages when premium sizes differ
across cohorts.

It is assumed that the input `Triangle` object does not contain missing
values.

## Examples

``` r
if (FALSE) { # \dontrun{
d <- as_triangle(
  df,
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  premium  = "incr_premium"
)
smr <- summary(d)
head(smr)
attr(smr, "longer")
} # }
```
