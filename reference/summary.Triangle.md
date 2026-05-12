# Summarise development statistics (Mean, Median, Weighted)

S3 method for [`summary()`](https://rdrr.io/r/base/summary.html) on
`Triangle` objects. Computes group-wise summary statistics for
cumulative loss ratios (`lr`) and per-period loss ratios (`lr_incr`).

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

- n_obs:

  Number of observations in the cell

- lr_mean:

  Mean of cumulative loss ratios

- lr_median:

  Median of cumulative loss ratios

- lr_wt:

  Weighted cumulative loss ratio (`sum(loss) / sum(premium)`)

- lr_incr_mean:

  Mean of per-period loss ratios

- lr_incr_median:

  Median of per-period loss ratios

- lr_incr_wt:

  Weighted per-period loss ratio (`sum(loss_incr) / sum(premium_incr)`)

The returned object keeps the attributes `groups` and `dev`, and its
class is updated to `"TriangleSummary"`.

## Details

The weighted mean is computed as:

- `lr_wt = sum(loss) / sum(premium)`

- `lr_incr_wt = sum(loss_incr) / sum(premium_incr)`

These correspond to portfolio-level loss ratios based on premium and are
typically more stable than simple averages when exposure sizes differ
across cohorts.

It is assumed that the input `Triangle` object does not contain missing
values.

## Examples

``` r
if (FALSE) { # \dontrun{
d <- build_triangle(
  df,
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "loss_incr",
  premium  = "premium_incr"
)
smr <- summary(d)
head(smr)
attr(smr, "longer")
} # }
```
