# Fit ED intensity factors

Estimate incremental loss intensities \\g_k\\ from a `"Triangle"` object
and return an `"EDFit"` object that bundles factor summaries, selected
intensities, and a cell-level projection of cumulative loss and exposure
(`$full`).

Two methods are supported via the `method` argument:

- `"basic"` (default):

  Factor estimation only. Returns `g_selected` and `sigma2` in
  `$selected`.

- `"mack"`:

  Basic plus factor variance \\\mathrm{Var}(\hat{g}\_k)\\ added as
  `g_var` column in `$selected`.

The `$full` projection table is produced by delegating to
[`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)
with `method = "ed"`, so cumulative loss / exposure / loss-ratio
projections and their standard errors are numerically identical to those
of `fit_lr(method = "ed")`. This makes
[`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
usable with `fit_fn = fit_ed`.

## Usage

``` r
fit_ed(
  x,
  value_var = "closs",
  exposure_var = "crp",
  method = c("basic", "mack"),
  alpha = 1,
  na_method = c("zero", "locf", "none"),
  sigma_method = c("min_last2", "locf", "loglinear"),
  recent = NULL,
  regime_break = NULL,
  ...
)
```

## Arguments

- x:

  A `"Triangle"` object.

- value_var:

  Cumulative loss variable. Default `"closs"`. Forwarded to
  [`build_link()`](https://seokhoonj.github.io/lossratio/reference/build_link.md)
  and to
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)
  as `loss_var`.

- exposure_var:

  Cumulative exposure variable. Default `"crp"`. Forwarded to
  [`build_link()`](https://seokhoonj.github.io/lossratio/reference/build_link.md)
  and to
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md).

- method:

  One of `"basic"` or `"mack"`. Default is `"basic"`.

- alpha:

  Numeric scalar controlling the variance structure. Default is `1`.

- na_method:

  Method used to fill `NA` values in `g_selected`. One of `"zero"`
  (default, set `NA` to 0 meaning no further development) or `"locf"` or
  `"none"`.

- sigma_method:

  Method used to extrapolate `sigma`. One of `"min_last2"` (default),
  `"locf"`, or `"loglinear"`.

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
  [`summary.Link()`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md).

## Value

An object of class `"EDFit"` (a named list) with components:

- `factor`:

  `EDSummary` of fitted intensities per development link.

- `selected`:

  `data.table` of selected `g_selected`, `sigma2` (and `g_var` when
  `method = "mack"`).

- `full`:

  `data.table` mirroring `LRFit$full` for `method = "ed"`: per-cell
  cumulative loss / exposure / loss-ratio projection plus SE columns
  (`closs_proj`, `exposure_proj`, `lr_proj`, `se_proj`, `se_lr`,
  `cv_lr`, ...). Available cells include both observed and projected;
  `is_observed` flags observed cells.

- `link`:

  `Link` object used for factor estimation.

## See also

[`build_link()`](https://seokhoonj.github.io/lossratio/reference/build_link.md),
[`summary.Link()`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md),
[`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md),
[`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
