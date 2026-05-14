# Fit a loss projection on a Triangle

Project cumulative loss across the cohort x development grid. Three
methods are supported via `method`:

- `"sa"` (default):

  Stage-adaptive. Exposure-driven (ED) before the maturity point, chain
  ladder (CL) after.

- `"ed"`:

  Pure exposure-driven (additive) across all dev periods.

- `"cl"`:

  Pure Mack chain ladder (multiplicative).

This function is the *loss-side* counterpart to
[`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md)
in the role-specific dispatcher layer (see `ARCHITECTURE.md`). It owns
loss projection only – premium projection is delegated to
[`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md)
(called internally when `premium_fit = NULL`), and the loss-ratio
composition with delta method is handled by
[`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md).

## Usage

``` r
fit_loss(
  x,
  method = c("sa", "ed", "cl"),
  alpha = 1,
  regime = NULL,
  premium_fit = NULL,
  premium_method = c("cl", "ed"),
  premium_alpha = 1,
  sigma_method = c("locf", "min_last2", "loglinear"),
  recent = NULL,
  maturity = "auto",
  conf_level = 0.95
)
```

## Arguments

- x:

  A `"Triangle"` object. The standardized `"loss"` and `"premium"`
  columns are used
  ([`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md)
  produces these).

- method:

  One of `"sa"` (default), `"ed"`, or `"cl"`.

- alpha:

  Variance-structure exponent for the loss fit. Default `1`.

- regime:

  Optional regime specification applied to both loss-side and
  premium-side estimation. Accepts four input types:

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
  [`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md)
  call – callers needing an asymmetric loss/premium split should use
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
  instead.

- premium_fit:

  Optional pre-built `PremiumFit` (from
  [`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md))
  supplying the premium projection. When `NULL`, `fit_loss()` calls
  [`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md)
  internally using `premium_method`, `premium_alpha`, and the resolved
  `regime`.

- premium_method:

  One of `"cl"` (default) or `"ed"`. Used only when
  `premium_fit = NULL`. The default matches the historical
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
  premium choice.

- premium_alpha:

  Variance-structure exponent for the premium fit. Default `1`.

- sigma_method:

  Sigma extrapolation. One of `"locf"` (default), `"min_last2"`,
  `"loglinear"`.

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
  (`loss_ci_lower`, `loss_ci_upper`). Default `0.95`.

## Value

An object of class `"LossFit"`. List with components: `full`, `proj`,
`maturity`, `loss_ata_fit`, `premium_ata_fit`, `premium_fit`, `ed`,
`factor`, `selected`, plus metadata.

## Internal columns

`$full` retains internal parameter columns (`g_selected`, `g_sigma2`,
`g_var`, `f_selected`, `f_sigma2`, `f_var`, `last_obs`) so that
[`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
can run bootstrap CI on top without re-fitting. Standalone callers see
them as implementation columns.

## See also

[`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md),
[`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md),
[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md),
[`fit_ed()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ed.md).

## Examples

``` r
if (FALSE) { # \dontrun{
data(experience)
tri <- build_triangle(
  experience[coverage == "SUR"],
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "loss_incr",
  premium  = "premium_incr"
)

lf    <- fit_loss(tri)                    # SA (default)
lf_ed <- fit_loss(tri, method = "ed")
lf_cl <- fit_loss(tri, method = "cl")
} # }
```
