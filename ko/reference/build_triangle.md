# Build a development structure from experience data

Aggregate experience data into a development structure by grouping and
`(cohort, calendar)` Date columns. Auto-detects input grain (M / Q / S /
A) from `cohort_var` spacing and derives the development-period column
internally; the user does not pre-bin data or supply a `dev_*` column.

The result contains:

- cumulative loss and cumulative premium,

- per-period and cumulative proportions,

- per-period and cumulative margin,

- profit indicators,

- per-period loss ratio (`lr_incr = loss_incr / premium_incr`) and
  cumulative loss ratio (`lr = loss / premium`).

The cumulative loss ratio is defined as: \$\$lr = loss / premium\$\$

For long-term health insurance applications, risk premium is commonly
used as the `premium` measure.

Proportion variables are computed within each `(cohort, dev)` cell:

- `loss_incr_prop = loss_incr / sum(loss_incr)`

- `premium_incr_prop = premium_incr / sum(premium_incr)`

- `loss_prop = loss / sum(loss)`

- `premium_prop = premium / sum(premium)`

Therefore, for a fixed `(cohort, dev)` cell, the proportions sum to 1
across groups. These are useful for examining the composition of each
development cell across products or other grouping variables.

## Usage

``` r
build_triangle(
  df,
  group_var,
  cohort_var = "uy_m",
  calendar_var = "cy_m",
  grain = "auto",
  loss_var = "loss_incr",
  premium_var = "premium_incr",
  cell_type = c("incremental", "cumulative"),
  fill_gaps = FALSE
)
```

## Arguments

- df:

  A data.frame containing experience data with per-period loss and
  premium columns plus `cohort_var` and `calendar_var` Date columns (or
  any input that the internal Date coercion accepts: Date, POSIXt,
  integer `yyyy` / `yyyymm` / `yyyymmdd`, ISO string).

- group_var:

  Column(s) used for grouping (e.g., product, gender).

- cohort_var:

  Single column defining the underwriting/exposure period start (e.g.,
  `"uy_m"`). Default `"uy_m"`.

- calendar_var:

  Single column defining the calendar period of the observation (e.g.,
  `"cy_m"`). Default `"cy_m"`. Used together with `cohort_var` to derive
  the development column at the resolved grain.

- grain:

  One of `"auto"` (default), `"M"`, `"Q"`, `"S"`, `"A"`. `"auto"` infers
  the grain from the `cohort_var` value spacing. Explicit values must be
  at least as coarse as the input grain; the input is binned (floored)
  to that grain before aggregation.

- loss_var:

  Single character; per-period loss column in `df`. Default
  `"loss_incr"`.

- premium_var:

  Single character; per-period premium column in `df`. Default
  `"premium_incr"`. Premium measure used as denominator for loss ratio
  calculations. For long-term health insurance applications, risk
  premium is commonly used.

- cell_type:

  One of `"incremental"` (default) or `"cumulative"`. Whether `loss_var`
  and `premium_var` in `df` already hold per-period (incremental) values
  or cumulative-within-cohort values. The internal triangle is always
  built on the incremental representation; `"cumulative"` inputs are
  differenced first.

- fill_gaps:

  Logical; if `TRUE`, zero-fill missing `(group_var, cohort, dev)` cells
  so that every cohort has a consecutive `dev` sequence. Default
  `FALSE`, which raises an error when gaps are detected. Use
  [`validate_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/validate_triangle.md)
  to inspect gaps before deciding.

## Value

A data.frame with class `"Triangle"`, containing the following derived
columns:

- n_obs:

  Number of distinct cohorts observed

- loss, loss_incr:

  Cumulative and per-period loss

- premium, premium_incr:

  Cumulative and per-period premium

- lr, lr_incr:

  Cumulative and per-period loss ratio

- margin, margin_incr:

  Cumulative and per-period margin (`premium - loss`)

- profit, profit_incr:

  Profit indicator (factor `"pos"` / `"neg"`)

- loss_prop, loss_incr_prop:

  Cumulative and per-period proportions of loss within each
  `(cohort, dev)` cell

- premium_prop, premium_incr_prop:

  Cumulative and per-period proportions of premium within each
  `(cohort, dev)` cell

Attributes set on the returned object: `group_var`, `cohort_var`,
`calendar_var`, `grain`, `dev_var` (= `"dev_<lower(grain)>"`, e.g.
`"dev_m"`), `loss_var`, `premium_var`, `longer`.

## Examples

``` r
if (FALSE) { # \dontrun{
df <- data.frame(
  pd_cd        = rep(c("P001", "P002"), each = 6),
  pd_nm        = rep(c("cancer", "health"), each = 6),
  uy_m         = rep(as.Date(c("2023-01-01", "2023-02-01", "2023-03-01")), 4),
  cy_m         = rep(as.Date(c("2023-01-01", "2023-02-01")), 6),
  loss_incr    = runif(12, 80, 120),
  premium_incr = runif(12, 90, 110)
)

# auto-detected monthly grain
res_m <- build_triangle(df, group_var = pd_cd)

# explicit quarterly view (re-bins monthly input to quarterly)
res_q <- build_triangle(df, group_var = pd_cd, grain = "Q")

head(res_m)
attr(res_m, "longer")
} # }
```
