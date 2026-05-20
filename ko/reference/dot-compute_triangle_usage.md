# Compute cell-level data-usage status for a Triangle

Internal helper that classifies every `(group, cohort, dev)` cell of a
`Triangle` into one of four buckets given a fit-data filter
configuration: `"used"`, `"holdout"`, `"unused"`, or `"future"`.

Mask precedence: `holdout` \> `used` \> `unused` \> `future`.

## Usage

``` r
.compute_triangle_usage(
  x,
  recent = NULL,
  regime = NULL,
  holdout = NULL,
  m_k = NULL,
  m_k_grid = NULL
)
```

## Arguments

- x:

  A `Triangle` object.

- recent:

  Optional positive integer (calendar-diagonal cut), or `NULL`.

- regime:

  Optional cohort cutoff. Accepts the same input forms handled by
  [`.resolve_regime_change_date()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-resolve_regime_change_date.md)
  (`NULL`, `Date`, character, vector, or `Regime`).

- holdout:

  Optional positive integer. When supplied, the last `holdout` calendar
  diagonals are flagged `"holdout"`. The `recent` filter is then
  evaluated against the post-holdout boundary so the recent wedge sits
  *before* the holdout wedge (no overlap), matching
  [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  semantics – the internal fitter operates on the masked triangle whose
  own max_cal is `original - holdout`.

- m_k:

  Optional integer. The maturity switch as a *target* development index
  (= `change` of the first stable link). When both `recent` and `regime`
  are provided, the hybrid mask uses `m_k` as the boundary: cells with
  `dev < m_k` apply the cohort cut, cells with `dev >= m_k` apply the
  calendar-diagonal cut. When `NULL`, the hybrid logic falls back to
  applying both filters jointly (cohort cut AND recent cut).

## Value

A `data.table` with one row per `(group, cohort, dev)` cell spanning the
full triangle (observed plus future). Columns include group columns (if
any), `cohort`, `dev`, `.coh_rank`, `.cal_idx`, `.max_cal`,
`is_observed`, `is_held_out`, `is_fit_data`, `is_excluded`, and `status`
(factor).
