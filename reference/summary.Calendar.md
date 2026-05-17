# Summarise calendar-development statistics (Mean, Median, Weighted)

S3 method for [`summary()`](https://rdrr.io/r/base/summary.html) on
`Calendar` objects. Computes calendar-period summary statistics for
cumulative loss ratios (`lr`) and per-period loss ratios (`incr_lr`).

Where
[`summary.Triangle()`](https://seokhoonj.github.io/lossratio/reference/summary.Triangle.md)
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

- lr_mean:

  Mean of cumulative loss ratios.

- lr_median:

  Median of cumulative loss ratios.

- lr_wt:

  Weighted cumulative loss ratio (`sum(loss) / sum(prem)`).

- incr_lr_mean:

  Mean of per-period loss ratios.

- incr_lr_median:

  Median of per-period loss ratios.

- incr_lr_wt:

  Weighted per-period loss ratio (`sum(incr_loss) / sum(incr_prem)`).

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
  prem     = "incr_prem"
)
smr  <- summary(cal)
head(smr)
} # }
```
