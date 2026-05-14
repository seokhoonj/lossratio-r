# Backtest a loss / premium / loss-ratio projection on existing data

Hold out the latest `holdout` calendar diagonals from the input
`Triangle`, refit a target-specific projection on the earlier portion,
project the held-out cells, and compare the projection to the actual
values that were withheld.

The target is selected with `target`:

- `target = "lr"` – score the loss-ratio projection from
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md).

- `target = "loss"` – score the loss projection from
  [`fit_loss()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_loss.md).

- `target = "premium"` – score the premium projection from
  [`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md).

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
  target = c("lr", "loss", "premium"),
  loss_method = c("sa", "ed", "cl"),
  premium_method = c("cl", "ed"),
  loss_alpha = 1,
  premium_alpha = 1,
  sigma_method = c("locf", "min_last2", "loglinear"),
  recent = NULL,
  loss_regime = NULL,
  premium_regime = NULL,
  maturity = "auto",
  se_method = c("fixed", "delta"),
  rho = 0.95,
  conf_level = 0.95,
  bootstrap = FALSE,
  B = 1000,
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

  Character scalar. Which projection to backtest. One of `"lr"`
  (default), `"loss"`, `"premium"`. Determines which fitter is called on
  the masked triangle and which column on `x` is treated as the held-out
  actual.

- loss_method:

  Method for the loss-side projection. Passed to
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
  /
  [`fit_loss()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_loss.md)
  as their `method` argument. One of `"sa"`, `"ed"`, `"cl"`. Unused for
  `target = "premium"`.

- premium_method:

  Method for the premium-side projection. Passed to
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
  /
  [`fit_loss()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_loss.md)
  /
  [`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md).
  One of `"cl"`, `"ed"`.

- loss_alpha, premium_alpha:

  Mack alpha for loss-side / premium-side chain-ladder estimation.

- sigma_method:

  Tail sigma extrapolation method. Forwarded to the underlying fitter.

- recent:

  Calendar-diagonal recency filter forwarded to the fitter.

- loss_regime, premium_regime:

  Regime spec for the loss / premium side. Each accepts one of four
  input types, dispatched by
  [`.resolve_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-resolve_regime.md):

  - `NULL` (default) – no regime filter.

  - A `Regime` object (e.g. from
    [`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md))
    – used as-is.

  - The string `"auto"` – runs
    [`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
    on the **masked** triangle (leakage-safe; uses only data available
    at the simulated backtest cutoff).

  - A function `function(tri) -> Regime` – called on the masked triangle
    for the same leakage-safe reason.

  `premium_regime` is resolved independently from `loss_regime`.

- maturity:

  Maturity input. Used only for `target = "lr"` and `target = "loss"`
  (stage-adaptive). Accepts one of four input types, dispatched by
  [`.resolve_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-resolve_maturity.md):

  - `NULL` – skip maturity filtering.

  - A `Maturity` object (e.g. from
    [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
    or
    [`maturity_at()`](https://seokhoonj.github.io/lossratio/ko/reference/maturity_at.md))
    – used as-is. Caller takes responsibility for any leakage in their
    pre-computation.

  - The string `"auto"` (default) – runs
    [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
    on the **masked** triangle (last `holdout` calendar diagonals
    removed), avoiding look-ahead leakage.

  - A function `function(tri) -> Maturity` (e.g. from
    [`maturity_spec()`](https://seokhoonj.github.io/lossratio/ko/reference/maturity_spec.md))
    – called on the masked triangle for the same leakage-safe reason.

- se_method:

  Standard-error composition for
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md).
  Unused for `target = "loss"` / `target = "premium"`.

- rho:

  Loss-premium correlation used by
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
  delta method. Unused for `target = "loss"` / `target = "premium"`.

- conf_level:

  Confidence level for
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
  /
  [`fit_loss()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_loss.md)
  intervals. Unused for `target = "premium"`.

- bootstrap, B, seed:

  Bootstrap controls for
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md).
  Unused for `target = "loss"` / `target = "premium"`.

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
  `(group, cohort, dev, actual, expected, aeg, ae_err, actual_incr, expected_incr, aeg_incr, ae_err_incr, calendar_idx)`.
  `aeg = actual - expected` (signed error in target units);
  `ae_err = actual / expected - 1` (relative error). `_incr` siblings
  are the same metrics on the incremental view.

- `col_summary`:

  Per-`dev` aggregate A/E Error and AEG (mean / median / weighted) with
  `_incr` variants and `n`.

- `diag_summary`:

  Per-calendar-diagonal aggregate A/E Error and AEG (same columns as
  `col_summary`, keyed by `calendar_idx`).

- `target`, `holdout`, `dispatcher`:

  Call metadata.

- `groups`, `cohort`, `dev`:

  Variable name relays from `x`.

## See also

[`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md),
[`fit_loss()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_loss.md),
[`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md),
[`plot.Backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Backtest.md)

## Examples

``` r
if (FALSE) { # \dontrun{
data(experience)
tri <- build_triangle(
  experience,
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "loss_incr",
  premium  = "premium_incr"
)

bt_lr      <- backtest(tri, holdout = 6L, target = "lr")
bt_loss    <- backtest(tri, holdout = 6L, target = "loss")
bt_premium <- backtest(tri, holdout = 6L, target = "premium")

print(bt_lr)
summary(bt_lr)
plot(bt_lr)
} # }
```
