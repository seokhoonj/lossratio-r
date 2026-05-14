# Coerce experience data to a Total object

Validate raw experience data, aggregate it to a single scalar row per
group (collapsing both the cohort and development axes), and assign the
`Total` S3 class so the associated
[`plot.Total()`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Total.md)
bar chart and other Total methods dispatch on the result.

Compared with
[`as_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/as_triangle.md)
(two-dimensional `cohort × dev`) and
[`as_calendar()`](https://seokhoonj.github.io/lossratio/ko/reference/as_calendar.md)
(one-dimensional time series), `as_total()` is *zero-dimensional* per
group — one row of portfolio aggregates. The typical use is high-level
portfolio comparison across products, coverages, or channels.

This function is intended for high-level portfolio comparison across
groups such as products, coverages, or channels. It summarises:

- the number of observed cohorts (`n_cohorts`)

- the first and last observed periods (`sales_start`, `sales_end`)

- total `loss` and total `premium` (cumulative)

- total loss ratio (`lr = loss / premium`)

- each group's share of total loss and total premium

If `period_from` and/or `period_to` are supplied, the input data are
first restricted to that period window before aggregation. This is
useful when comparing groups on a common period basis.

## Usage

``` r
as_total(
  df,
  groups = NULL,
  cohort,
  development,
  loss,
  premium,
  period_from = NULL,
  period_to = NULL,
  fill_gaps = FALSE
)
```

## Arguments

- df:

  A data.frame containing experience data.

- groups:

  Grouping variable(s).

- cohort:

  A single period variable (raw name). This may be an underwriting
  period (`"uy_m"`, `"uy_q"`, `"uy_h"`, `"uy"`) or a calendar period
  (`"cy_m"`, `"cy_q"`, `"cy_h"`, `"cy"`).

- development:

  A single development-period variable (raw name) used to count observed
  periods.

- loss:

  Single character; per-period loss column in `df` (raw name, e.g.,
  `"loss_incr"`).

- premium:

  Single character; per-period premium column in `df` (raw name, e.g.,
  `"premium_incr"`). Premium measure used as denominator for loss ratio
  calculations. For long-term health insurance applications, risk
  premium is commonly used.

- period_from:

  Optional lower bound for `cohort`. Only rows with
  `cohort >= period_from` are kept. May be supplied as `Date`,
  character, or any value coercible to `Date`. Default `NULL`.

- period_to:

  Optional upper bound for `cohort`. Only rows with
  `cohort <= period_to` are kept. May be supplied as `Date`, character,
  or any value coercible to `Date`. Default `NULL`.

- fill_gaps:

  Logical; if `TRUE`, zero-fill missing `(groups, cohort, dev)` cells
  before aggregation so that every cohort has a consecutive `dev`
  sequence. Default `FALSE`. Note that filling inflates `n_cohorts`
  (counts filled rows as observed periods); use
  [`validate_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/validate_triangle.md)
  to inspect first.

## Value

A data.frame with class `"Total"` containing:

- n_cohorts:

  Number of observed development periods

- sales_start:

  First observed period

- sales_end:

  Last observed period

- loss:

  Total loss

- premium:

  Total premium

- lr:

  Total loss ratio (`loss / premium`)

- loss_share:

  Share of total loss

- premium_share:

  Share of total premium

## Examples

``` r
if (FALSE) { # \dontrun{
as_total(
  df,
  groups  = "coverage",
  cohort  = "uy_m",
  dev     = "dev_m",
  loss    = "loss_incr",
  premium = "premium_incr"
)

as_total(
  df,
  groups      = "coverage",
  cohort      = "uy_m",
  dev         = "dev_m",
  loss        = "loss_incr",
  premium     = "premium_incr",
  period_from = "2023-01-01",
  period_to   = "2023-12-01"
)
} # }
```
