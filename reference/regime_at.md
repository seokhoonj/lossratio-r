# Construct a Regime object from manually specified regime changes

User-facing helper for hand-specifying a regime change (or a set of
per-group changes) without running
[`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md).
The returned `"Regime"` object plugs into any function that consumes a
Regime —
[`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md),
[`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md),
[`fit_premium()`](https://seokhoonj.github.io/lossratio/reference/fit_premium.md),
[`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md),
and the regime-change resolver — by carrying the same `$changes` schema
as
[`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
output.

Argument syntax mirrors
[`data.frame()`](https://rdrr.io/r/base/data.frame.html) /
`data.table()`: named vectors of equal length, one of which **must** be
`change`. Any other named arguments are treated as group columns.

## Usage

``` r
regime_at(...)
```

## Arguments

- ...:

  Named vectors of equal length. Must include `change` (coercible to
  `Date`; the start-of-regime date for the post-change regime). Any
  other named arguments are interpreted as group column values (e.g.
  `coverage`, `channel`). With no group columns the result is a pooled
  (single-row) Regime.

## Value

An object of class `"Regime"` with the minimal schema needed by
downstream consumers:

- `method`:

  `"manual"`.

- `target`:

  `NA_character_` (no detection target).

- `changes`:

  `data.table` with columns
  `[<group cols>..., change, regime_id, pre_value, post_value, magnitude]`.
  `regime_id` is `2L` (post-change regime) for each row; the stats
  columns are `NA_real_`.

- `groups`:

  Character vector of group column names (possibly empty).

- `multi_group`:

  `TRUE` when there are group columns *and* more than one unique group
  row.

Detection-specific slots (`labels`, `trajectory`, `pca`, `dropped`,
`n_regimes`, `window`, `window_mode`, `pca`) are left empty / `NA` so
the object can still be printed and consumed but is clearly
distinguishable from a detected Regime.

## See also

[`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Pooled change (no group columns)
regime_at(change = "2024-07-01")

# Single-group change
regime_at(coverage = "SUR", change = "2024-04-01")

# Multiple groups, one column
regime_at(coverage = c("SUR", "CAN"),
          change   = c("2024-04-01", "2023-09-01"))

# Multi-dimensional group keys
regime_at(coverage = c("SUR", "SUR"),
          channel  = c("online", "agent"),
          change   = c("2024-04-01", "2024-05-01"))
} # }
```
