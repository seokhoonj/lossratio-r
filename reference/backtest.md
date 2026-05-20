# Backtest a loss / exposure / loss-ratio projection on existing data

Hold out the latest `holdout` calendar diagonals from the input
`Triangle`, refit a target-specific projection on the earlier portion,
project the held-out cells, and compare the projection to the actual
values that were withheld.

The target is selected with `target`:

- `target = "ratio"` – score the loss-ratio projection from
  [`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md).

- `target = "loss"` – score the loss projection from
  [`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md).

- `target = "exposure"` – score the exposure projection from
  [`fit_exposure()`](https://seokhoonj.github.io/lossratio/reference/fit_exposure.md).

The A/E Error (`ae_err`) follows the standard actuarial A/E convention
and is computed cell-wise as \$\$ae\\err =
\frac{value\_{actual}}{value\_{proj}} - 1\$\$ so that positive values
flag under-projection (the model under-estimated; actual exceeded
expected) and negative values flag over-projection. Aggregated by
development period (`col_summary`) and by calendar diagonal
(`diag_summary`).

## Usage

``` r
backtest(
  x,
  holdout = 6L,
  target = c("ratio", "loss", "exposure"),
  loss_method = c("ed", "cl", "sa", "bf", "cc"),
  exposure_method = c("ed", "cl"),
  loss_alpha = 1,
  exposure_alpha = 1,
  sigma_method = c("locf", "min_last2", "loglinear", "mack", "none"),
  recent = NULL,
  loss_regime = NULL,
  exposure_regime = NULL,
  maturity = "auto",
  se_method = c("fixed", "delta"),
  rho = 0.95,
  conf_level = 0.95,
  bootstrap = NULL,
  B = 999L,
  seed = NULL,
  ...
)

# S3 method for class 'Backtest'
print(x, ...)

# S3 method for class 'Backtest'
summary(object, ...)

# S3 method for class 'summary.Backtest'
print(x, ...)
```

## Arguments

- x:

  A `"Triangle"` object (or a `"Backtest"` object for the S3
  [`print()`](https://rdrr.io/r/base/print.html) method).

- holdout:

  Integer. Number of latest calendar diagonals to mask before refitting.
  Default `6L`.

- target:

  Character scalar. Which projection to backtest. One of `"ratio"`
  (default), `"loss"`, `"exposure"`. Determines which fitter is called
  on the masked triangle and which column on `x` is treated as the
  held-out actual.

- loss_method:

  Method for the loss-side projection. Passed to
  [`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md)
  /
  [`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md)
  as their `method` argument. One of `"ed"` (default), `"cl"`, `"sa"`,
  `"bf"`, or `"cc"`. `"bf"` / `"cc"` need their prior arguments supplied
  through `...`. Unused for `target = "exposure"`.

- exposure_method:

  Method for the exposure-side projection. Passed to
  [`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md)
  /
  [`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md)
  /
  [`fit_exposure()`](https://seokhoonj.github.io/lossratio/reference/fit_exposure.md).
  One of `"ed"` (default) or `"cl"`.

- loss_alpha, exposure_alpha:

  Mack alpha for loss-side / exposure-side chain-ladder estimation.

- sigma_method:

  Method used to extrapolate `sigma` for links where it cannot be
  estimated. One of `"locf"` (default), `"min_last2"`, `"loglinear"`,
  `"mack"`, or `"none"`. `"mack"` applies the Mack (1993, Appendix B)
  tail estimator to the last unestimated link only, falling back to LOCF
  for any earlier ones with a warning. `"none"` performs no
  extrapolation; `sigma` stays `NA` and downstream variance terms drop
  those links via finite-value guards. Passed to
  [`.extrapolate_sigma_ata()`](https://seokhoonj.github.io/lossratio/reference/dot-extrapolate_sigma_ata.md).

- recent:

  Calendar-diagonal recency filter forwarded to the fitter.

- loss_regime, exposure_regime:

  Regime spec for the loss / exposure side. Each accepts one of four
  input types, dispatched by
  [`.resolve_regime()`](https://seokhoonj.github.io/lossratio/reference/dot-resolve_regime.md):

  - `NULL` (default) – no regime filter.

  - A `Regime` object (e.g. from
    [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md))
    – used as-is.

  - The string `"auto"` – runs
    [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
    on the **masked** triangle (leakage-safe; uses only data available
    at the simulated backtest cutoff).

  - A function `function(tri) -> Regime` – called on the masked triangle
    for the same leakage-safe reason.

  `exposure_regime` is resolved independently from `loss_regime`.

- maturity:

  Maturity input. Used only for `target = "ratio"` and `target = "loss"`
  (stage-adaptive). Accepts one of four input types, dispatched by
  [`.resolve_maturity()`](https://seokhoonj.github.io/lossratio/reference/dot-resolve_maturity.md):

  - `NULL` – skip maturity filtering.

  - A `Maturity` object (e.g. from
    [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
    or
    [`maturity_at()`](https://seokhoonj.github.io/lossratio/reference/maturity_at.md))
    – used as-is. Caller takes responsibility for any leakage in their
    pre-computation.

  - The string `"auto"` (default) – runs
    [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
    on the **masked** triangle (last `holdout` calendar diagonals
    removed), avoiding look-ahead leakage.

  - A function `function(tri) -> Maturity` (e.g. from
    [`maturity_spec()`](https://seokhoonj.github.io/lossratio/reference/maturity_spec.md))
    – called on the masked triangle for the same leakage-safe reason.

- se_method:

  Standard-error composition for
  [`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md).
  Unused for `target = "loss"` / `target = "exposure"`.

- rho:

  Loss-exposure correlation used by
  [`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md)
  delta method. Unused for `target = "loss"` / `target = "exposure"`.

- conf_level:

  Confidence level for
  [`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md)
  /
  [`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md)
  intervals. Unused for `target = "exposure"`.

- bootstrap, B, seed:

  Bootstrap controls forwarded to the target-specific fitter
  ([`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md)
  /
  [`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md)
  /
  [`fit_exposure()`](https://seokhoonj.github.io/lossratio/reference/fit_exposure.md)).
  `bootstrap = NULL` (default) defers to the fitter's method-dependent
  resolution: bootstrap for SA/ED methods, analytical for pure CL. The
  fitter accepts the full 4-type dispatch (`NULL` / logical / `"auto"` /
  `BootstrapTriangle` / function). For a leakage-safe backtest with a
  custom bootstrap configuration, prefer a function
  `function(tri) -> BootstrapTriangle` (it is invoked on the *masked*
  triangle, not the original) over a pre-built `BootstrapTriangle`
  object (which may have been built on the unmasked data and would leak
  hold-out cells into the residual pool).

- ...:

  Additional arguments passed to the underlying fitter.

- object:

  A `"Backtest"` object. Used by the S3
  [`summary()`](https://rdrr.io/r/base/summary.html) method.

## Value

An object of class `"Backtest"` with components:

- `call`:

  Matched call.

- `data`:

  Original `Triangle`.

- `masked`:

  Triangle used for fitting (with held-out cells removed).

- `fit`:

  The fit object returned by the target-specific fitter.

- `ae_err`:

  `data.table` of held-out cells with columns
  `(group, cohort, dev, actual, expected, aeg, ae_err, incr_actual, incr_expected, incr_aeg, incr_ae_err, cal_idx)`.
  `aeg = actual - expected` (signed error in target units);
  `ae_err = actual / expected - 1` (relative error). `incr_` siblings
  are the same metrics on the incremental view.

- `col_summary`:

  Per-`dev` aggregate A/E Error and AEG (mean / median / weighted) with
  `incr_` variants and `n`.

- `diag_summary`:

  Per-calendar-diagonal aggregate A/E Error and AEG (same columns as
  `col_summary`, keyed by `cal_idx`).

- `target`, `holdout`, `dispatcher`:

  Call metadata.

- `groups`, `cohort`, `dev`:

  Variable name relays from `x`.

## See also

[`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md),
[`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md),
[`fit_exposure()`](https://seokhoonj.github.io/lossratio/reference/fit_exposure.md),
[`plot.Backtest()`](https://seokhoonj.github.io/lossratio/reference/plot.Backtest.md)

## Examples

``` r
if (FALSE) { # \dontrun{
data(experience)
tri <- as_triangle(
  experience,
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  exposure = "incr_exposure"
)

bt_ratio    <- backtest(tri, holdout = 6L, target = "ratio")
bt_loss     <- backtest(tri, holdout = 6L, target = "loss")
bt_exposure <- backtest(tri, holdout = 6L, target = "exposure")

print(bt_ratio)
summary(bt_ratio)
plot(bt_ratio)
} # }
```
