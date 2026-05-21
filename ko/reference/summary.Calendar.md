# Summarise calendar-development statistics (Mean, Median, Weighted)

S3 method for [`summary()`](https://rdrr.io/r/base/summary.html) on
`Calendar` objects. Computes calendar-period summary statistics for
cumulative loss ratios (`ratio`) and per-period loss ratios
(`incr_ratio`).

Where
[`summary.Triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Triangle.md)
aggregates by `(groups, dev)` (cohort x development), this method
aggregates by `(groups, calendar)` (calendar period) so the resulting
table is indexed by calendar diagonals rather than development periods.

## Usage

``` r
# S3 method for class 'Calendar'
summary(object, ...)
```

## Arguments

- object:

  An object of class `Calendar`.

- ...:

  Unused; included for S3 compatibility.

## Value

A `data.table` of class `"CalendarSummary"` with one row per
`(groups, calendar)` combination, containing:

- n_cohorts:

  Number of observations in the cell.

- ratio_mean:

  Mean of cumulative loss ratios.

- ratio_median:

  Median of cumulative loss ratios.

- ratio_wt:

  Weighted cumulative loss ratio (`sum(loss) / sum(premium)`).

- incr_ratio_mean:

  Mean of per-period loss ratios.

- incr_ratio_median:

  Median of per-period loss ratios.

- incr_ratio_wt:

  Weighted per-period loss ratio (`sum(incr_loss) / sum(incr_premium)`).

The returned object preserves the attributes `groups`, `calendar`, and
`grain`.

## Examples

``` r
if (FALSE) { # \dontrun{
cal <- as_calendar(
  df,
  groups   = "coverage",
  calendar = "cy_m",
  loss     = "incr_loss",
  premium  = "incr_premium"
)
smr  <- summary(cal)
head(smr)
} # }
```
