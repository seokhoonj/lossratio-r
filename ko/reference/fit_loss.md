# Fit a loss projection on a Triangle

Project cumulative loss across the cohort x development grid. Three
methods are supported via `method`:

- `"ed"` (default):

  Pure exposure-driven (additive) across all dev periods. Unconditional
  safe baseline – no maturity dependency.

- `"cl"`:

  Pure Mack chain ladder (multiplicative). Classical reference.

- `"sa"`:

  Stage-adaptive. ED before the maturity point, CL after – composition
  of ED + CL, requires maturity detection (2-pass).

This function is the *loss-side* counterpart to
[`fit_exposure()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_exposure.md)
in the role-specific dispatcher layer (see `ARCHITECTURE.md`). It owns
loss projection only – exposure projection is delegated to
[`fit_exposure()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_exposure.md)
(called internally when `exposure_fit = NULL`), and the loss-ratio
composition with delta method is handled by
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md).

## Usage

``` r
fit_loss(
  x,
  method = c("ed", "cl", "sa"),
  alpha = 1,
  regime = NULL,
  exposure_fit = NULL,
  exposure_method = c("cl", "ed"),
  exposure_alpha = 1,
  sigma_method = c("locf", "min_last2", "loglinear", "mack", "none"),
  recent = NULL,
  maturity = "auto",
  conf_level = 0.95,
  bootstrap = NULL,
  B = 999,
  seed = NULL
)
```

## Arguments

- x:

  A `"Triangle"` object. The standardized `"loss"` and `"exposure"`
  columns are used
  ([`as_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/as_triangle.md)
  produces these).

- method:

  One of `"ed"` (default), `"cl"`, or `"sa"`.

- alpha:

  Variance-structure exponent for the loss fit. Default `1`.

- regime:

  Optional regime specification applied to both loss-side and
  exposure-side estimation. Accepts four input types:

  `NULL` (default)

  :   No regime filter.

  `Regime` object

  :   Use as-is. Typically built via
      [`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
      or
      [`regime_at()`](https://seokhoonj.github.io/lossratio/ko/reference/regime_at.md).

  `"auto"`

  :   Detect regime internally via `detect_regime(x)` on the input
      triangle.

  Function / closure

  :   A user-supplied function taking the triangle and returning a
      `Regime` object (or `NULL`).

  Behavior depends on `method`: SA uses a hybrid 2-pass filter (cohort
  cut for the ED phase, calendar-diagonal wedge for the CL phase); ED/CL
  use a simple cohort cut. The same resolved `Regime` is applied to the
  internal
  [`fit_exposure()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_exposure.md)
  call – callers needing an asymmetric loss/exposure split should use
  [`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md)
  instead.

- exposure_fit:

  Optional pre-built `ExposureFit` (from
  [`fit_exposure()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_exposure.md))
  supplying the exposure projection. When `NULL`, `fit_loss()` calls
  [`fit_exposure()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_exposure.md)
  internally using `exposure_method`, `exposure_alpha`, and the resolved
  `regime`.

- exposure_method:

  One of `"cl"` (default) or `"ed"`. Used only when
  `exposure_fit = NULL`. The default matches the historical
  [`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md)
  exposure choice.

- exposure_alpha:

  Variance-structure exponent for the exposure fit. Default `1`.

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

  Optional positive integer; calendar-diagonal filter.

- maturity:

  Optional maturity specification. Accepts four input types:

  `NULL`

  :   No maturity filter. SA mode requires a maturity, so this disables
      only ED / CL modes.

  `Maturity` object

  :   Use as-is. Typically built via
      [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
      or
      [`maturity_at()`](https://seokhoonj.github.io/lossratio/ko/reference/maturity_at.md).

  `"auto"` (default)

  :   Detect maturity internally via `detect_maturity(x)` on the input
      triangle.

  Function / closure

  :   A user-supplied function taking the triangle and returning a
      `Maturity` object (e.g. from
      [`maturity_spec()`](https://seokhoonj.github.io/lossratio/ko/reference/maturity_spec.md))
      for deferred custom-config detection.

- conf_level:

  Confidence level for analytical CI on the loss projection
  (`loss_ci_lo`, `loss_ci_hi`). Default `0.95`.

- bootstrap:

  Bootstrap configuration. Five forms accepted:

  `NULL` (default)

  :   Auto-resolved by `method`: bootstrap for `"sa"`/`"ed"`, analytical
      for `"cl"`. Matches the legacy `bootstrap = NULL` behavior.

  `TRUE` / `FALSE`

  :   Back-compat with the legacy logical arg. `TRUE` triggers `"auto"`;
      `FALSE` disables.

  `"auto"`

  :   Internal
      [`bootstrap()`](https://seokhoonj.github.io/lossratio/ko/reference/bootstrap.md)
      call on the loss triangle with defaults
      `(type = "analytical", process = "normal", target = "loss")`.

  `BootstrapTriangle`

  :   Pre-built object from
      [`bootstrap()`](https://seokhoonj.github.io/lossratio/ko/reference/bootstrap.md).
      Must have `meta$target == "loss"`.

  Function `function(tri) -> BootstrapTriangle`

  :   Lazy spec invoked on the input Triangle (leakage-safe for
      [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)).

  Premium stays at its observed values during the bootstrap (the
  loss-only convention); exposure-side uncertainty is layered in by
  [`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md)
  via its own bootstrap.

- B:

  Integer number of bootstrap replicates. Used only when `bootstrap`
  resolves to `"auto"`. Default `999`.

- seed:

  Optional integer seed for reproducible bootstrap. Default `NULL`.

## Value

An object of class `"LossFit"`. List with components: `full`, `proj`,
`maturity`, `loss_ata_fit`, `exposure_ata_fit`, `exposure_fit`, `ed`,
`factor`, `selected`, plus metadata.

## Internal columns

`$full` retains internal parameter columns (`g_sel`, `g_sigma2`,
`g_var`, `f_sel`, `f_sigma2`, `f_var`, `last_obs`) so that
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md)
can run bootstrap CI on top without re-fitting. Standalone callers see
them as implementation columns.

## See also

[`fit_exposure()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_exposure.md),
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md),
[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md),
[`fit_ed()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ed.md).

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

lf    <- fit_loss(tri)                    # SA (default)
lf_ed <- fit_loss(tri, method = "ed")
lf_cl <- fit_loss(tri, method = "cl")
} # }
```
