# Fit ED intensity factors

Estimate incremental loss intensities \\g_k\\ from a `"Triangle"` object
and return an `"EDFit"` object that bundles factor summaries, selected
intensities, and a cell-level projection of cumulative loss and exposure
(`$full`).

Returns `g_sel`, `sigma2`, and factor variance
\\\mathrm{Var}(\hat{g}\_k)\\ (column `g_var`) in `$selected`.

The `$full` projection table holds cumulative loss / exposure
projections and their standard errors, computed directly from the
Mack-style ED recursion (see `.ed_proj`, `.ed_proc_var`,
`.ed_param_var`). To validate an ED projection via
[`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md),
call `backtest(tri, target = "ratio", loss_method = "ed")`.

## Usage

``` r
fit_ed(
  x,
  loss = "loss",
  exposure = "exposure",
  method = c("mack"),
  alpha = 1,
  na_method = c("locf", "zero", "none"),
  sigma_method = c("locf", "min_last2", "loglinear", "mack", "none"),
  recent = NULL,
  regime = NULL,
  bootstrap = NULL,
  B = 999L,
  seed = NULL,
  conf_level = 0.95,
  ...
)
```

## Arguments

- x:

  A `"Triangle"` object.

- loss:

  Cumulative loss variable. Default `"loss"`. Forwarded to
  [`as_link()`](https://seokhoonj.github.io/lossratio/ko/reference/as_link.md)
  and to downstream workers.

- exposure:

  Cumulative exposure variable. Default `"exposure"`. Forwarded to
  [`as_link()`](https://seokhoonj.github.io/lossratio/ko/reference/as_link.md)
  and to downstream workers.

- method:

  Estimation method. Currently only `"mack"` is supported.

- alpha:

  Numeric scalar controlling the variance structure. Default is `1`.

- na_method:

  Method used to fill `NA` values in `g_sel`. One of `"zero"` (default,
  set `NA` to 0 meaning no further development) or `"locf"` or `"none"`.

- sigma_method:

  Method used to extrapolate `sigma` for links where it cannot be
  estimated. One of `"locf"` (default), `"min_last2"`, `"loglinear"`,
  `"mack"`, or `"none"`. `"mack"` applies the Mack (1993, Appendix B)
  tail estimator to the last unestimated link only, falling back to LOCF
  for any earlier ones with a warning. `"none"` performs no
  extrapolation; `sigma` stays `NA` and downstream variance terms drop
  those links via finite-value guards. Passed to
  [`.extrapolate_sigma_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-extrapolate_sigma_ata.md).

- recent:

  Optional positive integer. When supplied, only the most recent
  `recent` periods are used for estimation. Default is `NULL`.

- regime:

  Optional regime specification for cohort cutoff. Accepts: `NULL`
  (default – no filter), a `"Regime"` object (from
  [`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)),
  the string `"auto"` (internal `detect_regime(tri, loss = "ratio")`
  call), or a function `function(tri) -> Regime`. Resolved internally
  via
  [`.resolve_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-resolve_regime.md).
  When supplied, cohorts with `cohort < change_date` are excluded from
  estimation. Default is `NULL`.

- ...:

  Additional arguments passed to
  [`summary.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md).

## Value

An object of class `"EDFit"` (a named list) with components:

- `factor`:

  `EDSummary` of fitted intensities per development link.

- `selected`:

  `data.table` of selected `g_sel`, `sigma2`, and `g_var`.

- `full`:

  `data.table` of per-cell cumulative loss / exposure projection plus
  role-prefixed SE / CV columns (`loss_proj`, `incr_loss_proj`,
  `exposure_proj`, `incr_exposure_proj`, `loss_proc_se2`,
  `loss_param_se2`, `loss_total_se2`, `loss_proc_se`, `loss_param_se`,
  `loss_total_se`, `loss_total_cv`). Available cells include both
  observed and projected; `is_observed` flags observed cells.

- `link`:

  `Link` object used for factor estimation.

## See also

[`as_link()`](https://seokhoonj.github.io/lossratio/ko/reference/as_link.md),
[`summary.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md),
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md),
[`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
