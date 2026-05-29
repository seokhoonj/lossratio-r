# Resolve a regime specifier to a single Date

Internal helper used by
[`.apply_regime_filter()`](https://seokhoonj.github.io/lossratio-r/ko/reference/dot-apply_regime_filter.md)
to coerce a heterogeneous `regime` argument (NULL, Date scalar/vector,
character coercible to Date, or a `Regime` object) into either a single
Date scalar or a per-group `data.table` keyed by the caller-supplied
`by` columns.

## Usage

``` r
.resolve_regime_change_date(regime, by = NULL)
```

## Arguments

- regime:

  See
  [`.apply_regime_filter()`](https://seokhoonj.github.io/lossratio-r/ko/reference/dot-apply_regime_filter.md).

- by:

  Optional character vector of group columns the caller wants the change
  date dispatched on. When `NULL` (default) or empty, the function
  always returns a scalar (the maximum change date), preserving the
  historical single-value contract. When non-empty and `regime` is a
  multi-group `Regime` whose `$groups` intersect `by`, returns a
  `data.table` with `[intersect(by, regime$groups)..., change_date]`
  (one row per group combo, holding `max(change)`). Otherwise falls back
  to scalar.

## Value

One of:

- `NULL` when no change date is specified.

- A single Date (the latest change) – the scalar path.

- A `data.table` `[join_cols..., change_date]` – the per-group path.
