# Build a total development summary from experience data

Aggregate `loss` and `premium` by group and compute the corresponding
total loss ratio over a selected period window.

This function is intended for high-level portfolio comparison across
groups such as products, coverages, or channels. It summarises:

- the number of observed cohorts (`n_obs`)

- the first and last observed periods (`sales_start`, `sales_end`)

- total `loss` and total `premium` (cumulative)

- total loss ratio (`lr = loss / premium`)

- each group's share of total loss and total premium

If `period_from` and/or `period_to` are supplied, the input data are
first restricted to that period window before aggregation. This is
useful when comparing groups on a common period basis.

## Usage

``` r
build_total(
  df,
  group_var,
  cohort_var = "uy_m",
  dev_var = "dev_m",
  loss_var = "loss_incr",
  premium_var = "premium_incr",
  period_from = NULL,
  period_to = NULL,
  fill_gaps = FALSE
)
```

## Arguments

- df:

  A data.frame containing experience data.

- group_var:

  Grouping variable(s).

- cohort_var:

  A single period variable. This may be an underwriting period (`uy_m`,
  `uy_q`, `uy_s`, `uy_a`) or a calendar period (`cy_m`, `cy_q`, `cy_s`,
  `cy_a`). Default `"uy_m"`.

- dev_var:

  A single development variable used to count observed periods. Default
  `"dev_m"`.

- loss_var:

  Single character; per-period loss column in `df`. Default
  `"loss_incr"`.

- premium_var:

  Single character; per-period premium column in `df`. Default
  `"premium_incr"`. Premium measure used as denominator for loss ratio
  calculations. For long-term health insurance applications, risk
  premium is commonly used.

- period_from:

  Optional lower bound for `cohort_var`. Only rows with
  `cohort_var >= period_from` are kept. May be supplied as `Date`,
  character, or any value coercible to `Date`. Default `NULL`.

- period_to:

  Optional upper bound for `cohort_var`. Only rows with
  `cohort_var <= period_to` are kept. May be supplied as `Date`,
  character, or any value coercible to `Date`. Default `NULL`.

- fill_gaps:

  Logical; if `TRUE`, zero-fill missing
  `(group_var, cohort_var, dev_var)` cells before aggregation so that
  every cohort has a consecutive `dev_var` sequence. Default `FALSE`.
  Note that filling inflates `n_obs` (counts filled rows as observed
  periods); use
  [`validate_triangle()`](https://seokhoonj.github.io/lossratio/reference/validate_triangle.md)
  to inspect first.

## Value

A data.frame with class `"Total"` containing:

- n_obs:

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
build_total(df, coverage)

build_total(
  df,
  coverage,
  period_from = "2023-01-01",
  period_to   = "2023-12-01"
)
} # }
```
