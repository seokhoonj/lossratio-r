# Fit ED intensity factors

Estimate incremental loss intensities \\g_k\\ from a `"Triangle"` object
and return an `"EDFit"` object that bundles factor summaries, selected
intensities, and a cell-level projection of cumulative loss and exposure
(`$full`).

Returns `g_selected`, `sigma2`, and factor variance
\\\mathrm{Var}(\hat{g}\_k)\\ (column `g_var`) in `$selected`.

The `$full` projection table is produced by delegating to
[`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
with `method = "ed"`, so cumulative loss / exposure / loss-ratio
projections and their standard errors are numerically identical to those
of `fit_lr(method = "ed")`. To validate an ED projection via
[`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md),
call `backtest(tri, target = "lr", loss_method = "ed")`.

## Usage

``` r
fit_ed(
  x,
  target = "loss",
  exposure = "premium",
  method = c("mack"),
  alpha = 1,
  na_method = c("locf", "zero", "none"),
  sigma_method = c("locf", "min_last2", "loglinear"),
  recent = NULL,
  regime_break = NULL,
  ...
)
```

## Arguments

- x:

  A `"Triangle"` object.

- target:

  Cumulative loss variable. Default `"loss"`. Forwarded to
  [`build_link()`](https://seokhoonj.github.io/lossratio/ko/reference/build_link.md)
  and to downstream workers.

- exposure:

  Cumulative exposure variable. Default `"premium"`. Forwarded to
  [`build_link()`](https://seokhoonj.github.io/lossratio/ko/reference/build_link.md)
  and to downstream workers.

- method:

  Estimation method. Currently only `"mack"` is supported.

- alpha:

  Numeric scalar controlling the variance structure. Default is `1`.

- na_method:

  Method used to fill `NA` values in `g_selected`. One of `"zero"`
  (default, set `NA` to 0 meaning no further development) or `"locf"` or
  `"none"`.

- sigma_method:

  Method used to extrapolate `sigma`. One of `"locf"` (default),
  `"min_last2"`, or `"loglinear"`.

- recent:

  Optional positive integer. When supplied, only the most recent
  `recent` periods are used for estimation. Default is `NULL`.

- regime_break:

  Optional cohort cutoff for the regime break. Accepts: `NULL` (default,
  no filter), a single `Date`/character coercible to Date, a vector of
  dates (uses the latest), or a `Regime` object (extracts the latest
  from `$breakpoints`). When supplied, cohorts with
  `cohort < break_date` are excluded from estimation. Default is `NULL`.

- ...:

  Additional arguments passed to
  [`summary.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md).

## Value

An object of class `"EDFit"` (a named list) with components:

- `factor`:

  `EDSummary` of fitted intensities per development link.

- `selected`:

  `data.table` of selected `g_selected`, `sigma2`, and `g_var`.

- `full`:

  `data.table` of per-cell cumulative target / exposure projection plus
  role-prefixed SE / CV columns (`target_proj`, `target_incr_proj`,
  `exposure_proj`, `exposure_incr_proj`, `target_proc_se2`,
  `target_param_se2`, `target_total_se2`, `target_proc_se`,
  `target_param_se`, `target_total_se`, `target_total_cv`). Available
  cells include both observed and projected; `is_observed` flags
  observed cells.

- `link`:

  `Link` object used for factor estimation.

## See also

[`build_link()`](https://seokhoonj.github.io/lossratio/ko/reference/build_link.md),
[`summary.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md),
[`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md),
[`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
