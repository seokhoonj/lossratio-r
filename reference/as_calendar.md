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
which builds a *two-dimensional* `cohort × dev` structure,
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

## Usage

``` r
as_calendar(
  df,
  groups = NULL,
  calendar,
  loss,
  premium,
  grain = "auto",
  period_from = NULL,
  period_to = NULL,
  fill_gaps = FALSE
)
```

## Arguments

- df:

  A data.frame containing experience data with per-period loss and
  premium columns plus a `calendar` Date column (or any input that the
  internal Date coercion accepts: Date, POSIXt, integer `yyyy` /
  `yyyymm` / `yyyymmdd`, ISO string).

- groups:

  Column(s) used for grouping (e.g., product, gender).

- calendar:

  A single column defining the calendar-like period axis (raw name,
  e.g., `"cy_m"`). May also be an underwriting axis (`"uy_m"` etc.) when
  a single underwriting-period axis is to be summarised as a time series
  rather than as a development structure.

- loss:

  Single character; per-period loss column in `df` (raw name, e.g.,
  `"loss_incr"`).

- premium:

  Single character; per-period premium column in `df` (raw name, e.g.,
  `"premium_incr"`). Premium measure used as denominator for loss ratio
  calculations. For long-term health insurance applications, risk
  premium is commonly used.

- grain:

  One of `"auto"` (default), `"M"`, `"Q"`, `"H"`, `"Y"`. `"auto"` infers
  the grain from the `calendar` value spacing. Explicit values must be
  at least as coarse as the input grain; the input is binned (floored)
  to that grain before aggregation.

- period_from:

  Optional lower bound for `calendar`. Only rows with
  `calendar >= period_from` are kept.

- period_to:

  Optional upper bound for `calendar`. Only rows with
  `calendar <= period_to` are kept.

- fill_gaps:

  Logical; if `TRUE`, zero-fill missing `(groups, calendar)` cells so
  every group has a consecutive calendar sequence at the resolved grain.
  Default `FALSE`, which raises an error when gaps are detected.

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
res1 <- as_calendar(
  df,
  groups   = "pd_cd",
  calendar = "cy_m",
  loss     = "loss_incr",
  premium  = "premium_incr"
)

res2 <- as_calendar(
  df,
  groups      = "pd_cd",
  calendar    = "cy_q",
  loss        = "loss_incr",
  premium     = "premium_incr",
  period_from = "2023-01-01"
)

head(res1)
attr(res1, "longer")
} # }
```
