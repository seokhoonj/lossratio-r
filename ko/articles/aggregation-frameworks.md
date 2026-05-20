# Aggregation frameworks: Triangle, Calendar, Total

The same long-format experience data can be aggregated three ways
depending on the question being asked. `lossratio` exposes one builder
per framework. This vignette compares them.

## At a glance

| Builder | Output object | Dimension | When to use |
|----|----|----|----|
| [`as_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/as_triangle.md) | `Triangle` | cohort × dev (2D) | SA, ED, CL projection |
| [`as_calendar()`](https://seokhoonj.github.io/lossratio/ko/reference/as_calendar.md) | `Calendar` | calendar period (1D) | Calendar-year trend, diagonal effect |
| [`as_total()`](https://seokhoonj.github.io/lossratio/ko/reference/as_total.md) | `Total` | portfolio total (per group) | High-level loss-ratio comparison |

Conceptually:

- `Triangle` preserves both the cohort axis (when policies were
  underwritten) and the development axis (how loss accrues over
  development time). This is the canonical chain-ladder data structure.
- `Calendar` collapses cohorts onto the diagonal — each row is one
  calendar period across all underwriting cohorts. Equivalent to the
  diagonal sum of the triangle.
- `Total` collapses both dimensions to one value per group. Useful for
  portfolio-level comparison (which product had the worst loss ratio
  over the window?).

## Triangle (cohort × dev)

``` r

library(lossratio)
data(experience)

tri <- as_triangle(
  experience,
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  exposure = "incr_exposure"
)
head(tri)
#> shape: (6, 18)
#> ┌──────────┬───────────┬────────────┬───┬────────────────┬────────────────┐
#> │ coverage ┆ n_cohorts ┆ cohort     ┆ … ┆ exposure_share ┆ incr_exposure… │
#> │ <chr>    ┆ <int>     ┆ <date>     ┆ … ┆ <dbl>          ┆ <dbl>          │
#> ├──────────┼───────────┼────────────┼───┼────────────────┼────────────────┤
#> │ ci       ┆ 36        ┆ 2023-01-01 ┆ … ┆ 0.381171       ┆ 0.381171       │
#> │ ci       ┆ 35        ┆ 2023-01-01 ┆ … ┆ 0.380346       ┆ 0.379558       │
#> │ ci       ┆ 34        ┆ 2023-01-01 ┆ … ┆ 0.387352       ┆ 0.401744       │
#> │ ci       ┆ 33        ┆ 2023-01-01 ┆ … ┆ 0.379535       ┆ 0.356118       │
#> │ ci       ┆ 32        ┆ 2023-01-01 ┆ … ┆ 0.377646       ┆ 0.370060       │
#> │ ci       ┆ 31        ┆ 2023-01-01 ┆ … ┆ 0.377400       ┆ 0.376114       │
#> └──────────┴───────────┴────────────┴───┴────────────────┴────────────────┘
#> 13 more variables: dev <int>, loss <dbl>, incr_loss <dbl>, exposure <dbl>,
#>                    incr_exposure <dbl>, ratio <dbl>, incr_ratio <dbl>,
#>                    margin <dbl>, incr_margin <dbl>, profit <fct>,
#>                    incr_profit <fct>, loss_share <dbl>, incr_loss_share <dbl>
```

Each row is one (cohort, dev) cell with cumulative loss / risk premium.
Visualise as line plot or heatmap:

``` r

plot(tri)              # one trajectory per cohort, faceted by group
```

![](aggregation-frameworks_files/figure-html/unnamed-chunk-2-1.png)

``` r


# With multiple group panels each panel's cells get too narrow to read,
# so use quarterly cohort and dev to bring each panel down to ~10 x 10
# cells. This fits the documentation's display size; in practice you
# can keep monthly resolution by enlarging the plot.
tri_q <- as_triangle(experience, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure", grain = "Q")
plot_triangle(tri_q)   # cohort × dev heatmap of ratio
```

![](aggregation-frameworks_files/figure-html/unnamed-chunk-2-2.png)

Use `Triangle` as input to: -
[`as_link()`](https://seokhoonj.github.io/lossratio/ko/reference/as_link.md)
— development factors (ATA / ED via `loss` + optional `exposure`) -
[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md),
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md)
— projection -
[`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
— structural change detection

## Calendar (calendar period only)

``` r

tri <- as_triangle(experience, groups = "coverage",
                   cohort = "uy_m", calendar = "cy_m",
                   loss = "incr_loss", exposure = "incr_exposure")
cal <- as_calendar(tri)
head(cal)
#> shape: (6, 18)
#> ┌──────────┬────────────┬─────────┬───┬────────────────┬────────────────┐
#> │ coverage ┆ calendar   ┆ cal_idx ┆ … ┆ exposure_share ┆ incr_exposure… │
#> │ <chr>    ┆ <date>     ┆ <int>   ┆ … ┆ <dbl>          ┆ <dbl>          │
#> ├──────────┼────────────┼─────────┼───┼────────────────┼────────────────┤
#> │ cancer   ┆ 2023-01-01 ┆ 1       ┆ … ┆ 0.492583       ┆ 0.492583       │
#> │ cancer   ┆ 2023-02-01 ┆ 2       ┆ … ┆ 0.452030       ┆ 0.428106       │
#> │ cancer   ┆ 2023-03-01 ┆ 3       ┆ … ┆ 0.416257       ┆ 0.382514       │
#> │ cancer   ┆ 2023-04-01 ┆ 4       ┆ … ┆ 0.389202       ┆ 0.348604       │
#> │ cancer   ┆ 2023-05-01 ┆ 5       ┆ … ┆ 0.377872       ┆ 0.352976       │
#> │ cancer   ┆ 2023-06-01 ┆ 6       ┆ … ┆ 0.355725       ┆ 0.304826       │
#> └──────────┴────────────┴─────────┴───┴────────────────┴────────────────┘
#> 13 more variables: n_cohorts <int>, loss <dbl>, incr_loss <dbl>, exposure <dbl>,
#>                    incr_exposure <dbl>, ratio <dbl>, incr_ratio <dbl>,
#>                    margin <dbl>, incr_margin <dbl>, profit <fct>,
#>                    incr_profit <fct>, loss_share <dbl>, incr_loss_share <dbl>
```

Each row is one calendar period (per group). The `t` column is a
sequential index (1, 2, 3, …) within group — time-series convention. It
is **not** a development period (`cym - uym`); for that you want the
`Triangle` `dev` axis.

Calendar aggregation is mathematically the **diagonal sum** of the
triangle: cells with the same `cy_m` (regardless of `uy_m`/`dev_m`) are
combined.

Use cases: - Trend analysis (“loss ratio is rising over calendar
time”) - Calendar-year effect detection (e.g., regulatory shock, premium
on-leveling event) - Portfolio monitoring dashboards

``` r

plot(cal)                       # x axis: calendar (Date)
```

![](aggregation-frameworks_files/figure-html/unnamed-chunk-4-1.png)

## Total (portfolio summary)

``` r

# Filter the triangle first (or the raw experience) for a date-bounded
# summary, then collapse to portfolio totals.
tri_bounded <- as_triangle(
  experience[uy_m >= as.Date("2023-04-01") &
             uy_m <= as.Date("2024-03-01")],
  groups = "coverage", cohort = "uy_m",
  dev = "dev_m",
  loss = "incr_loss", exposure = "incr_exposure"
)
tot <- as_total(tri_bounded)
head(tot)
#> shape: (4, 9)
#> ┌───────────┬───────────┬─────────────┬───┬────────────┬────────────────┐
#> │ coverage  ┆ n_cohorts ┆ sales_start ┆ … ┆ loss_share ┆ exposure_share │
#> │ <chr>     ┆ <int>     ┆ <date>      ┆ … ┆ <dbl>      ┆ <dbl>          │
#> ├───────────┼───────────┼─────────────┼───┼────────────┼────────────────┤
#> │ ci        ┆ 12        ┆ 2023-04-01  ┆ … ┆ 0.33461100 ┆ 0.427133       │
#> │ cancer    ┆ 12        ┆ 2023-04-01  ┆ … ┆ 0.11375800 ┆ 0.162389       │
#> │ inpatient ┆ 12        ┆ 2023-04-01  ┆ … ┆ 0.00644687 ┆ 0.016502       │
#> │ surgery   ┆ 12        ┆ 2023-04-01  ┆ … ┆ 0.54518400 ┆ 0.393976       │
#> └───────────┴───────────┴─────────────┴───┴────────────┴────────────────┘
#> 4 more variables: sales_end <date>, loss <dbl>, exposure <dbl>, ratio <dbl>
```

One row per group, summarising loss / risk premium / loss ratio over the
window. The `period_from` / `period_to` arguments restrict to a fixed
window so groups are comparable.

Use cases: - Compare overall loss ratio across coverages - Rank groups
by reserve / share of portfolio - Build executive summary tables

## Aggregation as data flow

                         experience (long, with demographics)
                                  │
             ┌────────────────────┼─────────────────────┐
             │                    │                     │
       as_triangle      as_calendar         as_total
       (cohort × dev)      (calendar series)     (portfolio total)
             │                    │                     │
             ▼                    ▼                     ▼
         Triangle             Calendar               Total
       (2D, projection)     (1D, trend)         (0D, comparison)

All three start from the same `experience` and aggregate demographic
dimensions away. Choose the framework based on the analytical question.

## Attribute schema

After aggregation, each object stores its source-column metadata as
attributes (used for plot labels and granularity-aware date formatting):

``` r

attr(tri, "cohort")     # "uy_m"
#> [1] "uy_m"
attr(tri, "dev")        # "dev_m"
#> [1] "dev_m"
attr(tri, "grain")      # "M"
#> [1] "M"

attr(cal, "calendar")   # "cy_m"
#> [1] "cy_m"
attr(cal, "grain")      # "M"
#> [1] "M"
```

Granularity (`"month"` / `"quarter"` / `"half"` / `"year"`) is derived
on demand from the raw column name via `lossratio:::.get_period_type()`,
so no `_type` cache attributes are stored.

The data columns themselves are standardised to `cohort` / `dev` /
`calendar`, so downstream code is granularity-agnostic.
