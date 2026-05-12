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
  loss_regime_break = NULL,
  premium_fit = NULL,
  premium_method = c("cl", "ed"),
  premium_alpha = 1,
  premium_regime_break = loss_regime_break,
  sigma_method = c("locf", "min_last2", "loglinear"),
  recent = NULL,
  maturity_args = NULL,
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

- loss_regime_break:

  Optional cohort cutoff for the loss-side regime break. `NULL`
  (default), a `Date`/character coercible to Date, a vector of dates
  (uses the latest), or a `Regime` object. Behavior depends on `method`:
  SA uses a hybrid 2-pass filter (cohort cut for ED phase,
  calendar-diagonal wedge for CL phase); ED/CL use a simple cohort cut.

- premium_fit:

  Optional pre-built `PremiumFit` (from
  [`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md))
  supplying the premium projection. When `NULL`, `fit_loss()` calls
  [`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md)
  internally using `premium_method`, `premium_alpha`, and
  `premium_regime_break`.

- premium_method:

  One of `"cl"` (default) or `"ed"`. Used only when
  `premium_fit = NULL`. The default matches the historical
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
  premium choice.

- premium_alpha:

  Variance-structure exponent for the premium fit. Default `1`.

- premium_regime_break:

  Premium-side regime break. Defaults to `loss_regime_break` (loss-side
  and premium-side share a cutoff unless explicitly separated).

- sigma_method:

  Sigma extrapolation. One of `"locf"` (default), `"min_last2"`,
  `"loglinear"`.

- recent:

  Optional positive integer; calendar-diagonal filter.

- maturity_args:

  A named list forwarded to
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md),
  or `NULL` (default) to skip maturity filtering. SA auto-defaults to
  [`list()`](https://rdrr.io/r/base/list.html).

- conf_level:

  Confidence level for analytical CI on the loss projection
  (`loss_ci_lower`, `loss_ci_upper`). Default `0.95`.

## Value

An object of class `"LossFit"`. List with components: `full`, `pred`,
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
