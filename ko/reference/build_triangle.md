# Build a development structure from experience data

Aggregate experience data into a development structure by grouping,
period, and development-period variables. The result contains:

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
  cohort_var = "uym",
  dev_var = "dev_m",
  loss_var = "loss_incr",
  premium_var = "premium_incr",
  fill_gaps = FALSE
)
```

## Arguments

- df:

  A data.frame containing experience data with per-period loss and
  premium columns.

- group_var:

  Column(s) used for grouping (e.g., product, gender).

- cohort_var:

  Column(s) defining the exposure period (e.g., underwriting year-month,
  quarter, half-year, or year such as `uym`, `uyq`, `uyh`, `uy`).

- dev_var:

  Column(s) defining development periods (e.g., months since issue such
  as `dev_m`).

- loss_var:

  Single character; per-period loss column in `df`. Default
  `"loss_incr"`.

- premium_var:

  Single character; per-period premium column in `df`. Default
  `"premium_incr"`. Premium measure used as denominator for loss ratio
  calculations. For long-term health insurance applications, risk
  premium is commonly used.

- fill_gaps:

  Logical; if `TRUE`, zero-fill missing
  `(group_var, cohort_var, dev_var)` cells so that every cohort has a
  consecutive `dev_var` sequence. Default `FALSE`, which raises an error
  when gaps are detected. Use
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

The returned object also has an attribute `"longer"` containing a melted
long-format version (`class = "TriangleLonger"`).

## Examples

``` r
if (FALSE) { # \dontrun{
df <- data.frame(
  pd_cd        = rep(c("P001", "P002"), each = 6),
  pd_nm        = rep(c("cancer", "health"), each = 6),
  uym          = rep(as.Date(c("2023-01-01", "2023-02-01", "2023-03-01")), 4),
  dev_m        = rep(1:2, 6),
  loss_incr    = runif(12, 80, 120),
  premium_incr = runif(12, 90, 110)
)

res <- build_triangle(
  df,
  group_var  = pd_cd,
  cohort_var = "uym",
  dev_var    = "dev_m"
)

head(res)
attr(res, "longer")
} # }
```
