# Build a calendar-based development structure from experience data

Aggregate experience data into a development structure along a single
calendar-style period axis, including:

- cumulative loss and cumulative premium,

- per-period and cumulative proportions,

- per-period and cumulative margin,

- profit indicators,

- per-period loss ratio (`lr_incr = loss_incr / premium_incr`) and
  cumulative loss ratio (`lr = loss / premium`).

In contrast to
[`build_triangle()`](https://seokhoonj.github.io/lossratio/reference/build_triangle.md),
which builds a development structure using `cohort_var × dev_var`, this
function aggregates values over a one-dimensional calendar axis.

The cumulative loss ratio is defined as: \$\$lr = loss / premium\$\$

For long-term health insurance applications, risk premium is commonly
used as the `premium` measure.

Proportion variables are computed within each `calendar_var` cell:

- `loss_incr_prop = loss_incr / sum(loss_incr)`

- `premium_incr_prop = premium_incr / sum(premium_incr)`

- `loss_prop = loss / sum(loss)`

- `premium_prop = premium / sum(premium)`

Therefore, for a fixed `calendar_var` cell, the proportions sum to 1
across groups. These are useful for examining the composition of each
calendar period across products or other grouping variables.

## Usage

``` r
build_calendar(
  df,
  group_var,
  calendar_var = "cym",
  loss_var = "loss_incr",
  premium_var = "premium_incr",
  period_from = NULL,
  period_to = NULL,
  fill_gaps = FALSE
)
```

## Arguments

- df:

  A data.frame containing experience data with per-period loss and
  premium columns.

- group_var:

  Column(s) used for grouping (e.g., product, gender).

- calendar_var:

  A single calendar-like period variable defining the summary axis.
  Typical examples include:

  - `cym` (calendar year-month),

  - `cyq` (calendar year-quarter),

  - `cyh` (calendar year-half),

  - `cy` (calendar year),

  - `uym`, `uyq`, `uyh`, `uy` when a single underwriting-period axis is
    to be summarised as a time series rather than as a development
    structure.

- loss_var:

  Single character; per-period loss column in `df`. Default
  `"loss_incr"`.

- premium_var:

  Single character; per-period premium column in `df`. Default
  `"premium_incr"`. Premium measure used as denominator for loss ratio
  calculations. For long-term health insurance applications, risk
  premium is commonly used.

- period_from:

  Optional lower bound for `calendar_var`. Only rows with
  `calendar_var >= period_from` are kept.

- period_to:

  Optional upper bound for `calendar_var`. Only rows with
  `calendar_var <= period_to` are kept.

- fill_gaps:

  Logical; if `TRUE`, zero-fill missing `(group_var, calendar_var)`
  cells so every group has a consecutive calendar sequence (monthly,
  quarterly, etc. based on `calendar_var`). Default `FALSE`, which
  raises an error when gaps are detected.

## Value

A data.frame with class `"Calendar"`, containing the following derived
columns:

- dev:

  Calendar index within each group, defined as the sequential order of
  `calendar_var` after sorting in ascending order. This represents the
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

- loss_prop, loss_incr_prop, premium_prop, premium_incr_prop:

  Proportions within each `calendar_var` cell

The returned object also has an attribute `"longer"` containing a melted
long-format version (`class = "CalendarLonger"`).

## Examples

``` r
if (FALSE) { # \dontrun{
res1 <- build_calendar(
  df,
  group_var    = pd_cd,
  calendar_var = "cym"
)

res2 <- build_calendar(
  df,
  group_var    = pd_cd,
  calendar_var = "cyq",
  period_from  = "2023-01-01"
)

head(res1)
attr(res1, "longer")
} # }
```
