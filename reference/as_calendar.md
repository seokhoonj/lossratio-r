# Coerce experience data to a Calendar object

Validate raw experience data, aggregate it along a single
calendar-period axis, and assign the `Calendar` S3 class so the
associated
[`plot.Calendar()`](https://seokhoonj.github.io/lossratio/reference/plot.Calendar.md)
/
[`summary.Calendar()`](https://seokhoonj.github.io/lossratio/reference/summary.Calendar.md)
/ longer-form methods dispatch on the result.

Compared with
[`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md),
which builds a *two-dimensional* `cohort x dev` structure,
`as_calendar()` is *one-dimensional*: a single calendar-period time
series (per group) showing how the portfolio evolves through time,
regardless of cohort membership.

The result is a long-format `data.table` with class
`c("Calendar", "data.table", "data.frame")` containing cumulative loss /
premium, incremental and cumulative LR, margin, profit, and share
columns within each `calendar` cell.

The cumulative loss ratio is defined as: \$\$lr = loss / prem\$\$

For long-term health insurance applications, risk premium is commonly
used as the `prem` measure.

Proportion variables are computed within each `calendar` cell:

- `incr_loss_share = incr_loss / sum(incr_loss)`

- `incr_prem_share = incr_prem / sum(incr_prem)`

- `loss_share = loss / sum(loss)`

- `prem_share = prem / sum(prem)`

Therefore, for a fixed `calendar` cell, the proportions sum to 1 across
groups. These are useful for examining the composition of each calendar
period across products or other grouping variables.

Calendar derives `calendar = cohort + (dev - 1)` using the Triangle's
`grain` attribute and aggregates the incremental `loss` / `prem` columns
by `(groups, calendar)`. This works for Triangles built in either mode
(with or without an original `calendar` column in the raw experience),
since `cohort + dev` is always sufficient to reconstruct the calendar
axis at the Triangle's grain.

## Usage

``` r
as_calendar(x)
```

## Arguments

- x:

  A `Triangle` object (typically from
  [`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md)).

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

- prem, incr_prem:

  Cumulative and per-period prem

- lr, incr_lr:

  Cumulative and per-period loss ratio

- margin, incr_margin:

  Cumulative and per-period margin

- profit, incr_profit:

  Profit indicator

- loss_share, incr_loss_share, prem_share, incr_prem_share:

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
  prem     = "incr_prem"
)

cal <- as_calendar(tri)
head(cal)
attr(cal, "longer")
} # }
```
