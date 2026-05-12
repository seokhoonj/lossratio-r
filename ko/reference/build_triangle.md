# Build a development structure from experience data

Aggregate experience data into a development structure by grouping and
`(cohort, calendar)` Date columns. Auto-detects input grain (M / Q / S /
A) from `cohort` spacing and derives the development-period column
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

- `loss_incr_share = loss_incr / sum(loss_incr)`

- `premium_incr_share = premium_incr / sum(premium_incr)`

- `loss_share = loss / sum(loss)`

- `premium_share = premium / sum(premium)`

Therefore, for a fixed `(cohort, dev)` cell, the proportions sum to 1
across groups. These are useful for examining the composition of each
development cell across products or other grouping variables.

## Usage

``` r
build_triangle(
  df,
  groups,
  cohort,
  calendar = NULL,
  dev = NULL,
  loss,
  premium,
  grain = "auto",
  cell_type = c("incremental", "cumulative"),
  fill_gaps = FALSE
)
```

## Arguments

- df:

  A data.frame containing experience data with per-period loss and
  premium columns plus `cohort` and `calendar` Date columns (or any
  input that the internal Date coercion accepts: Date, POSIXt, integer
  `yyyy` / `yyyymm` / `yyyymmdd`, ISO string).

- groups:

  Column(s) used for grouping (e.g., product, gender).

- cohort:

  Single column (raw name) defining the underwriting / exposure period
  start (e.g., `"uy_m"`).

- calendar:

  Single column (raw name) defining the calendar period of the
  observation (e.g., `"cy_m"`). Optional — supply either `calendar` or
  `dev` (or both). When `calendar` is given, `dev` is derived internally
  via `count_periods(cohort, calendar, grain)`.

- dev:

  Single column (raw name) holding pre-computed development periods
  (e.g., `"dev_m"`). Optional — supply either `calendar` or `dev` (or
  both). When only `dev` is given, the calendar axis is omitted from the
  attribute (downstream calendar-diagonal logic uses cohort + dev). When
  both are given, `dev` is cross-checked against
  `count_periods(cohort, calendar, grain)`.

- loss:

  Single character; per-period loss column in `df` (raw name, e.g.,
  `"loss_incr"`).

- premium:

  Single character; per-period premium column in `df` (raw name, e.g.,
  `"premium_incr"`). Premium measure used as denominator for loss ratio
  calculations. For long-term health insurance applications, risk
  premium is commonly used.

- grain:

  One of `"auto"` (default), `"M"`, `"Q"`, `"S"`, `"A"`. `"auto"` infers
  the grain from the `cohort` value spacing. Explicit values must be at
  least as coarse as the input grain; the input is binned (floored) to
  that grain before aggregation.

- cell_type:

  One of `"incremental"` (default) or `"cumulative"`. Whether `loss` and
  `premium` in `df` already hold per-period (incremental) values or
  cumulative-within-cohort values. The internal triangle is always built
  on the incremental representation; `"cumulative"` inputs are
  differenced first.

- fill_gaps:

  Logical; if `TRUE`, zero-fill missing `(groups, cohort, dev)` cells so
  that every cohort has a consecutive `dev` sequence. Default `FALSE`,
  which raises an error when gaps are detected. Use
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

- loss_share, loss_incr_share:

  Cumulative and per-period proportions of loss within each
  `(cohort, dev)` cell

- premium_share, premium_incr_share:

  Cumulative and per-period proportions of premium within each
  `(cohort, dev)` cell

Attributes set on the returned object: `groups`, `cohort`, `calendar`,
`grain`, `dev` (= `"dev_<lower(grain)>"`, e.g. `"dev_m"`), `loss`,
`premium`, `longer`.

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
res_m <- build_triangle(
  df,
  groups   = pd_cd,
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "loss_incr",
  premium  = "premium_incr"
)

# explicit quarterly view (re-bins monthly input to quarterly)
res_q <- build_triangle(df, groups = pd_cd, grain = "Q")

head(res_m)
attr(res_m, "longer")
} # }
```
