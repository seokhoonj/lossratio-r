# Coerce experience data to a Triangle object

Validate raw experience data, aggregate it onto a `(group, cohort, dev)`
grid, and assign the `Triangle` S3 class so the downstream methods
([`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md),
[`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md),
[`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md),
[`plot()`](https://rdrr.io/r/graphics/plot.default.html),
[`plot_triangle()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.md),
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md),
[`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md),
[`detect_convergence()`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md),
...) can dispatch on the result.

Three steps happen inside this single call:

1.  **Validate** – required columns are present, dates coerce cleanly,
    the grain is consistent. Hard errors on schema issues so downstream
    code never receives malformed input.

2.  **Standardise + aggregate** – rename to package-canonical column
    names (`cohort`, `calendar`, `dev`, `loss`, `prem`, ...),
    auto-detect grain (`M` / `Q` / `H` / `Y`) from `cohort` spacing,
    derive `dev` from `(cohort, calendar)`, aggregate to
    `(group, cohort, dev)`, and enrich with cumulative / share / LR
    columns.

3.  **Tag** – set S3 class `c("Triangle", "data.table", "data.frame")`
    so every `*.Triangle` method becomes available.

lossratio's `Triangle` is a `data.table` in **long format** (one row per
`(group, cohort, dev)` cell) with the enriched columns described above.
The name `Triangle` refers to the conceptual cohort x dev triangular
region – older cohorts have more observed dev cells than newer ones –
not to a matrix layout.

The auto-grain detection (`grain = "auto"`, default) reads `cohort`
value spacing; explicit values must be at least as coarse as the input
grain. The user does not pre-bin data or supply a `dev_*` column.

The result contains:

- cumulative loss and cumulative premium,

- per-period and cumulative proportions,

- per-period and cumulative margin,

- profit indicators,

- per-period loss ratio (`incr_lr = incr_loss / incr_prem`) and
  cumulative loss ratio (`lr = loss / prem`).

The cumulative loss ratio is defined as: \$\$lr = loss / prem\$\$

For long-term health insurance applications, risk prem is commonly used
as the `prem` measure.

Proportion variables are computed within each `(cohort, dev)` cell:

- `incr_loss_share = incr_loss / sum(incr_loss)`

- `incr_prem_share = incr_prem / sum(incr_prem)`

- `loss_share = loss / sum(loss)`

- `prem_share = prem / sum(prem)`

Therefore, for a fixed `(cohort, dev)` cell, the proportions sum to 1
across groups. These are useful for examining the composition of each
development cell across products or other grouping variables.

## Usage

``` r
as_triangle(
  df,
  groups = NULL,
  cohort,
  calendar = NULL,
  development = NULL,
  loss,
  premium,
  grain = "auto",
  cell_type = c("incremental", "cumulative"),
  fill_gaps = FALSE
)
```

## Arguments

- df:

  A data.frame containing experience data with per-period loss and prem
  columns plus `cohort` and `calendar` Date columns (or any input that
  the internal Date coercion accepts: Date, POSIXt, integer `yyyy` /
  `yyyymm` / `yyyymmdd`, ISO string).

- groups:

  Column(s) used for grouping (e.g., product, gender).

- cohort:

  Single column (raw name) defining the underwriting / exposure period
  start (e.g., `"uy_m"`).

- calendar:

  Single column (raw name) defining the calendar period of the
  observation (e.g., `"cy_m"`). Optional – supply either `calendar` or
  `development` (or both). When `calendar` is given, `dev` is derived
  internally via `count_periods(cohort, calendar, grain)`.

- development:

  Single column (raw name) holding pre-computed development periods
  (e.g., `"dev_m"`). Optional – supply either `calendar` or
  `development` (or both). When only `development` is given, the
  calendar axis is omitted from the attribute (downstream
  calendar-diagonal logic uses cohort + dev). When both are given,
  `development` is cross-checked against
  `count_periods(cohort, calendar, grain)`.

- loss:

  Single character; per-period loss column in `df` (raw name, e.g.,
  `"incr_loss"`).

- premium:

  Single character; per-period prem column in `df` (raw name, e.g.,
  `"incr_prem"`). Premium measure used as denominator for loss ratio
  calculations. For long-term health insurance applications, risk prem
  is commonly used.

- grain:

  One of `"auto"` (default), `"M"`, `"Q"`, `"H"`, `"Y"`. `"auto"` infers
  the grain from the `cohort` value spacing. Explicit values must be at
  least as coarse as the input grain; the input is binned (floored) to
  that grain before aggregation.

- cell_type:

  One of `"incremental"` (default) or `"cumulative"`. Whether `loss` and
  `prem` in `df` already hold per-period (incremental) values or
  cumulative-within-cohort values. The internal triangle is always built
  on the incremental representation; `"cumulative"` inputs are
  differenced first.

- fill_gaps:

  Logical; if `TRUE`, zero-fill missing `(groups, cohort, dev)` cells so
  that every cohort has a consecutive `dev` sequence. Default `FALSE`,
  which raises an error when gaps are detected. Use
  [`validate_triangle()`](https://seokhoonj.github.io/lossratio/reference/validate_triangle.md)
  to inspect gaps before deciding.

## Value

A data.frame with class `"Triangle"`, containing the following derived
columns:

- n_cohorts:

  Number of distinct cohorts observed

- loss, incr_loss:

  Cumulative and per-period loss

- premium, incr_prem:

  Cumulative and per-period prem

- lr, incr_lr:

  Cumulative and per-period loss ratio

- margin, incr_margin:

  Cumulative and per-period margin (`prem - loss`)

- profit, incr_profit:

  Profit indicator (factor `"pos"` / `"neg"`)

- loss_share, incr_loss_share:

  Cumulative and per-period proportions of loss within each
  `(cohort, dev)` cell

- prem_share, incr_prem_share:

  Cumulative and per-period proportions of prem within each
  `(cohort, dev)` cell

Attributes set on the returned object: `groups`, `cohort`, `calendar`,
`grain`, `dev` (= `"dev_<lower(grain)>"`, e.g. `"dev_m"`), `loss`,
`prem`, `longer`.

## Examples

``` r
if (FALSE) { # \dontrun{
df <- data.frame(
  pd_cd        = rep(c("P001", "P002"), each = 6),
  pd_nm        = rep(c("cancer", "health"), each = 6),
  uy_m         = rep(as.Date(c("2023-01-01", "2023-02-01", "2023-03-01")), 4),
  cy_m         = rep(as.Date(c("2023-01-01", "2023-02-01")), 6),
  incr_loss    = runif(12, 80, 120),
  incr_prem = runif(12, 90, 110)
)

# auto-detected monthly grain
res_m <- as_triangle(
  df,
  groups   = "pd_cd",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  premium  = "incr_prem"
)

# explicit quarterly view (re-bins monthly input to quarterly)
res_q <- as_triangle(
  df,
  groups   = "pd_cd",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  premium  = "incr_prem",
  grain    = "Q"
)

head(res_m)
attr(res_m, "longer")
} # }
```
