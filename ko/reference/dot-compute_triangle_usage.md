# Compute cell-level data-usage status for a Triangle

Internal helper that classifies every `(group, cohort, dev)` cell of a
`Triangle` into one of four buckets given a fit-data filter
configuration: `"fit_data"`, `"held_out"`, `"excluded"`, or `"future"`.

Mask precedence: `held_out` \> `fit_data` \> `excluded` \> `future`.

## Usage

``` r
.compute_triangle_usage(
  x,
  recent = NULL,
  regime_break = NULL,
  holdout = NULL,
  mat_k = NULL
)
```

## Arguments

- x:

  A `Triangle` object.

- recent:

  Optional positive integer (calendar-diagonal cut), or `NULL`.

- regime_break:

  Optional cohort cutoff. Accepts the same input forms as
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
  (`NULL`, `Date`, character, vector, or `CohortRegime`).

- holdout:

  Optional positive integer. When supplied, the last `holdout` calendar
  diagonals are flagged `"held_out"`.

- mat_k:

  Optional integer. When both `recent` and `regime_break` are provided,
  the hybrid mask uses `mat_k` as the maturity switch: cells with
  `dev <= mat_k` apply the cohort cut, cells with `dev > mat_k` apply
  the calendar-diagonal cut. When `NULL`, the hybrid logic falls back to
  applying both filters jointly (cohort cut AND recent cut).

## Value

A `data.table` with one row per `(group, cohort, dev)` cell spanning the
full triangle (observed plus future). Columns include group columns (if
any), `cohort`, `dev`, `.coh_rank`, `.cal_idx`, `.max_cal`,
`is_observed`, `is_held_out`, `is_fit_data`, `is_excluded`, and `status`
(factor).
