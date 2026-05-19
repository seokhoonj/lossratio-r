# Fit loss ratio projection model

Unified interface for loss ratio projection from a `"Triangle"` object.
Three projection methods are available:

- `"ed"` (default):

  Exposure-driven for all development periods. All future increments are
  \\g_k \cdot C^P_k\\. Unconditional safe baseline – no maturity
  dependency, robust under early-dev ATA volatility.

- `"cl"`:

  Chain ladder for all development periods. Equivalent to the classical
  Mack (1993) recursion.

- `"sa"`:

  Stage-adaptive composition: ED before maturity, CL after maturity.
  Requires maturity detection (2-pass), uses age-to- age factors only
  once they have stabilised.

  - Before maturity: age-to-age factors are volatile, so exposure-driven
    projection \\\Delta C^L = g_k \cdot C^P_k\\ anchors the estimate to
    exposure volume.

  - After maturity: age-to-age factors are stable, so chain ladder
    projection \\C^L\_{k+1} = f_k \cdot C^L_k\\ preserves the cohort's
    observed level.

In all cases, exposure is projected forward using chain ladder:
\$\$\hat{C}^P\_{i,k+1} = f^P_k \cdot \hat{C}^P\_{i,k}\$\$

This function is the *composition* layer over
[`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md)
and
[`fit_exposure()`](https://seokhoonj.github.io/lossratio/reference/fit_exposure.md):
it delegates loss projection to
[`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md),
retrieves the embedded `ExposureFit`, and composes the loss-ratio
point + variance via the delta method (`se_method = "fixed"` or
`"delta"`). See `ARCHITECTURE.md` for the layered design.

## Usage

``` r
fit_ratio(
  x,
  method = c("ed", "cl", "sa"),
  loss_alpha = 1,
  loss_regime = NULL,
  exposure_method = c("cl", "ed"),
  exposure_alpha = 1,
  exposure_regime = NULL,
  sigma_method = c("locf", "min_last2", "loglinear", "mack", "none"),
  recent = NULL,
  maturity = "auto",
  se_method = c("fixed", "delta"),
  rho = 0.95,
  conf_level = 0.95,
  bootstrap = NULL,
  B = 999,
  seed = NULL
)
```

## Arguments

- x:

  An object of class `"Triangle"`. The standardized `"loss"` and
  `"exposure"` columns are used
  ([`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md)
  produces these).

- method:

  One of `"ed"` (default), `"cl"`, or `"sa"`.

- loss_alpha:

  Numeric scalar controlling the variance structure for loss estimation.
  Default is `1`.

- loss_regime:

  Optional regime specification for the loss-side filter. Accepts four
  input types:

  `NULL` (default)

  :   No regime filter.

  `Regime` object

  :   Use as-is. Typically built via
      [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
      or
      [`regime_at()`](https://seokhoonj.github.io/lossratio/reference/regime_at.md).

  `"auto"`

  :   Detect regime internally via `detect_regime(x)` on the input
      triangle.

  Function / closure

  :   A user-supplied function taking the triangle and returning a
      `Regime` object (or `NULL`).

  Behavior depends on `method`:

  `"sa"`

  :   Hybrid filter. Pre-change cohorts are dropped only for development
      periods at or before the maturity point (ED phase);
      post-maturity (CL) cells use the `recent`-diagonal window across
      all cohorts. This preserves CL stability while protecting the ED
      intensities from a regime change.

  `"ed"`, `"cl"`

  :   Simple cohort cut: all cohorts strictly before the change date are
      excluded from estimation.

- exposure_method:

  One of `"cl"` (default) or `"ed"`. Forwarded to
  [`fit_exposure()`](https://seokhoonj.github.io/lossratio/reference/fit_exposure.md)
  when constructing the exposure projection.

- exposure_alpha:

  Numeric scalar for exposure chain ladder. Default is `1`.

- exposure_regime:

  Exposure-side regime specification. Same four input types as
  `loss_regime` (`NULL` / `Regime` / `"auto"` / function). Default
  `NULL` – exposure is fit on the full triangle independently of
  `loss_regime` (no lazy default). Set explicitly when the regime shift
  affects exposure accrual too.

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

  Optional positive integer for estimation window. Default is `NULL`.

- maturity:

  Optional maturity specification. Accepts four input types:

  `NULL`

  :   No maturity filter. Disables SA-mode switch detection.

  `Maturity` object

  :   Use as-is. Typically built via
      [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
      or
      [`maturity_at()`](https://seokhoonj.github.io/lossratio/reference/maturity_at.md).

  `"auto"` (default)

  :   Detect maturity internally via `detect_maturity(x)` on the input
      triangle.

  Function / closure

  :   A user-supplied function taking the triangle and returning a
      `Maturity` object (e.g. from
      [`maturity_spec()`](https://seokhoonj.github.io/lossratio/reference/maturity_spec.md))
      for deferred custom-config detection.

  When `method = "sa"`, this also determines the switch point between ED
  and CL phases.

- se_method:

  Method for computing `ratio_se = SE(L/P)`. One of:

  `"fixed"` (default)

  :   Premium treated as fixed (non-random). \\\mathrm{SE}(L/P) =
      \mathrm{SE}(L) / P\\. Strictly, this is the delta method with
      `Var(P) = 0` and `Cov(L,P) = 0`, i.e., a degenerate case under the
      assumption that exposure is known.

  `"delta"`

  :   Full delta method including exposure uncertainty and the
      loss-exposure correlation `rho`: \$\$\mathrm{Var}(L/P) \approx
      \frac{\mathrm{Var}(L)}{P^2} + \frac{L^2 \mathrm{Var}(P)}{P^4} -
      \frac{2 \rho L \mathrm{SE}(L) \mathrm{SE}(P)}{P^3}\$\$

- rho:

  Numeric scalar in `(-1, 1)`; assumed correlation between ultimate loss
  and ultimate exposure. Only used when `se_method = "delta"`. Default
  is `0.95`, matching the strong positive correlation typically observed
  between cumulative loss and cumulative exposure in long-tail health
  portfolios (analogous to the paid/incurred correlation used in Munich
  chain ladder).

- conf_level:

  Confidence level used for `ratio_ci_lo`/`ratio_ci_hi` in the cohort
  summary. Default is `0.95`.

- bootstrap:

  Bootstrap configuration. Five forms accepted:

  `NULL` (default)

  :   Auto-resolved by `method`: bootstrap for `"sa"`/`"ed"`, analytical
      for `"cl"`. Matches legacy behavior.

  `TRUE` / `FALSE`

  :   Back-compat with the legacy logical arg. `TRUE` triggers `"auto"`;
      `FALSE` disables.

  `"auto"`

  :   Internal
      [`bootstrap()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md)
      call on the loss triangle with defaults
      `(type = "analytical", process = "normal", target = "loss")`.

  `BootstrapTriangle`

  :   Pre-built object from
      [`bootstrap()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md).
      Must have `meta$target == "loss"`.

  Function `function(tri) -> BootstrapTriangle`

  :   Lazy spec invoked on the input Triangle (leakage-safe for
      [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)).

  Premium is held at observed values during the bootstrap (loss-only
  convention). `ratio_se` is recomputed from the bootstrap-derived
  `loss_total_se` via
  [`.compute_ratio_se()`](https://seokhoonj.github.io/lossratio/reference/dot-compute_ratio_se.md),
  combined with the exposure-side SE per `se_method` (`"fixed"` ignores
  exposure SE; `"delta"` uses `exposure_total_se` from the inner
  [`fit_exposure()`](https://seokhoonj.github.io/lossratio/reference/fit_exposure.md)
  plus `rho` correlation).

- B:

  Integer number of bootstrap replications. Used only when `bootstrap`
  resolves to `"auto"`. Default is `999`.

- seed:

  Optional integer seed for reproducible bootstrap. Default is `NULL`.

## Value

An object of class `"RatioFit"`.

## See also

[`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md),
[`fit_exposure()`](https://seokhoonj.github.io/lossratio/reference/fit_exposure.md),
[`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md),
[`as_link()`](https://seokhoonj.github.io/lossratio/reference/as_link.md),
[`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md),
[`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md),
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)

## Examples

``` r
if (FALSE) { # \dontrun{
data(experience)
tri <- as_triangle(
  experience[coverage == "surgery"],
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  exposure = "incr_exposure"
)

# Stage-adaptive (default): ED before maturity, CL after
ratio_sa <- fit_ratio(tri, method = "sa")
summary(ratio_sa)
plot(ratio_sa)

# Pure exposure-driven for all development periods
ratio_ed <- fit_ratio(tri, method = "ed")

# Pure chain ladder (Mack-style) for all development periods
ratio_cl <- fit_ratio(tri, method = "cl")
} # }
```
