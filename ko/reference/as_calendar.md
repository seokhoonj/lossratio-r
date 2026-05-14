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

The cumulative loss ratio is defined as: \$\$lr = loss / premium\$\$

For long-term health insurance applications, risk premium is commonly
used as the `premium` measure.

Proportion variables are computed within each `calendar` cell:

- `loss_incr_share = loss_incr / sum(loss_incr)`

- `premium_incr_share = premium_incr / sum(premium_incr)`

- `loss_share = loss / sum(loss)`

- `premium_share = premium / sum(premium)`

Therefore, for a fixed `calendar` cell, the proportions sum to 1 across
groups. These are useful for examining the composition of each calendar
period across products or other grouping variables.

Calendar derives `calendar = cohort + (dev - 1)` using the Triangle's
`grain` attribute and aggregates the incremental `loss` / `premium`
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

- dev:

  Calendar index within each group, defined as the sequential order of
  `calendar` after sorting in ascending order. This represents the
  progression of calendar periods for each group (e.g., 1 = first
  observed period, 2 = second, ...), and can be used to align groups
  with different starting periods on a common index scale.

- loss, loss_incr:

  Cumulative and per-period loss

- premium, premium_incr:

  Cumulative and per-period premium

- lr, lr_incr:

  Cumulative and per-period loss ratio

- margin, margin_incr:

  Cumulative and per-period margin

- profit, profit_incr:

  Profit indicator

- loss_share, loss_incr_share, premium_share, premium_incr_share:

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
  loss     = "loss_incr",
  premium  = "premium_incr"
)

cal <- as_calendar(tri)
head(cal)
attr(cal, "longer")
} # }
```
