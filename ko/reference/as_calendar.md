# Coerce experience data to a Calendar object

Validate raw experience data, aggregate it along a single
calendar-period axis, and assign the `Calendar` S3 class so the
associated
[`plot.Calendar()`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Calendar.md)
/
[`summary.Calendar()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Calendar.md)
/ longer-form methods dispatch on the result.

Compared with
[`as_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/as_triangle.md),
which builds a *two-dimensional* `cohort x dev` structure,
`as_calendar()` is *one-dimensional*: a single calendar-period time
series (per group) showing how the portfolio evolves through time,
regardless of cohort membership.

The result is a long-format `data.table` with class
`c("Calendar", "data.table", "data.frame")` containing cumulative loss /
premium, incremental and cumulative LR, margin, profit, and share
columns within each `calendar` cell.

The cumulative loss ratio is defined as: \$\$ratio = loss / exposure\$\$

For long-term health insurance applications, risk premium is commonly
used as the `exposure` measure.

Proportion variables are computed within each `calendar` cell:

- `incr_loss_share = incr_loss / sum(incr_loss)`

- `incr_exposure_share = incr_exposure / sum(incr_exposure)`

- `loss_share = loss / sum(loss)`

- `exposure_share = exposure / sum(exposure)`

Therefore, for a fixed `calendar` cell, the proportions sum to 1 across
groups. These are useful for examining the composition of each calendar
period across products or other grouping variables.

Calendar derives `calendar = cohort + (dev - 1)` using the Triangle's
`grain` attribute and aggregates the incremental `loss` / `exposure`
columns by `(groups, calendar)`. This works for Triangles built in
either mode (with or without an original `calendar` column in the raw
experience), since `cohort + dev` is always sufficient to reconstruct
the calendar axis at the Triangle's grain.

## Usage

``` r
as_calendar(x)
```

## Arguments

- x:

  A `Triangle` object (typically from
  [`as_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/as_triangle.md)).

## Value

A data.frame with class `"Calendar"`, containing the following derived
columns:

- cal_idx:

  Sequential calendar-period index within each group (`1, 2, ..., N`).
  Time-series convention; intentionally NOT `dev` – in a Calendar the
  integer is just the rank of the date within its group, not a true
  development period (`cym - uym`). Useful for aligning groups with
  different starting periods on a common index scale.

- loss, incr_loss:

  Cumulative and per-period loss

- exposure, incr_exposure:

  Cumulative and per-period exposure

- ratio, incr_ratio:

  Cumulative and per-period loss ratio

- margin, incr_margin:

  Cumulative and per-period margin

- profit, incr_profit:

  Profit indicator

- loss_share, incr_loss_share, exposure_share, incr_exposure_share:

  Proportions within each `calendar` cell

The returned object also has an attribute `"longer"` containing a melted
long-format version (`class = "CalendarLonger"`).

## Examples

``` r
if (FALSE) { # \dontrun{
tri <- as_triangle(
  experience,
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  exposure = "incr_exposure"
)

cal <- as_calendar(tri)
head(cal)
attr(cal, "longer")
} # }
```
