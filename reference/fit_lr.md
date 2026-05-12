# Fit loss ratio projection model

Unified interface for loss ratio projection from a `"Triangle"` object.
Three projection methods are available:

- `"sa"` (default):

  Uses exposure-driven (ED) estimation before maturity and chain
  ladder (CL) after maturity.

  - Before maturity: age-to-age factors are volatile, so exposure-driven
    projection \\\Delta C^L = g_k \cdot C^P_k\\ anchors the estimate to
    premium volume.

  - After maturity: age-to-age factors are stable, so chain ladder
    projection \\C^L\_{k+1} = f_k \cdot C^L_k\\ preserves the cohort's
    observed level.

- `"ed"`:

  Exposure-driven for all development periods. All future increments are
  \\g_k \cdot C^P_k\\.

- `"cl"`:

  Chain ladder for all development periods. Equivalent to classical Mack
  model.

In all cases, exposure is projected forward using chain ladder:
\$\$\hat{C}^P\_{i,k+1} = f^P_k \cdot \hat{C}^P\_{i,k}\$\$

This function is the *composition* layer over
[`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md)
and
[`fit_premium()`](https://seokhoonj.github.io/lossratio/reference/fit_premium.md):
it delegates loss projection to
[`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md),
retrieves the embedded `PremiumFit`, and composes the loss-ratio point +
variance via the delta method (`se_method = "fixed"` or `"delta"`). See
`ARCHITECTURE.md` for the layered design.

## Usage

``` r
fit_lr(
  x,
  method = c("sa", "ed", "cl"),
  loss_alpha = 1,
  loss_regime_break = NULL,
  premium_method = c("cl", "ed"),
  premium_alpha = 1,
  premium_regime_break = loss_regime_break,
  sigma_method = c("locf", "min_last2", "loglinear"),
  recent = NULL,
  maturity_args = NULL,
  se_method = c("fixed", "delta"),
  rho = 0.95,
  conf_level = 0.95,
  bootstrap = FALSE,
  B = 1000,
  seed = NULL
)
```

## Arguments

- x:

  An object of class `"Triangle"`. The standardized `"loss"` and
  `"premium"` columns are used
  ([`build_triangle()`](https://seokhoonj.github.io/lossratio/reference/build_triangle.md)
  produces these).

- method:

  One of `"sa"` (default), `"ed"`, or `"cl"`.

- loss_alpha:

  Numeric scalar controlling the variance structure for loss estimation.
  Default is `1`.

- loss_regime_break:

  Optional cohort cutoff for the loss-side regime break. Accepts: `NULL`
  (default, no filter), a single `Date`/character coercible to Date, a
  vector of dates (uses the latest), or a `Regime` object (extracts the
  latest from `$breakpoints`). Behavior depends on `method`:

  `"sa"`

  :   Hybrid filter. Pre-break cohorts are dropped only for development
      periods at or before the maturity point (ED phase);
      post-maturity (CL) cells use the `recent`-diagonal window across
      all cohorts. This preserves CL stability while protecting the ED
      intensities from a regime shift.

  `"ed"`, `"cl"`

  :   Simple cohort cut: all cohorts strictly before the break date are
      excluded from estimation.

- premium_method:

  One of `"cl"` (default) or `"ed"`. Forwarded to
  [`fit_premium()`](https://seokhoonj.github.io/lossratio/reference/fit_premium.md)
  when constructing the premium projection.

- premium_alpha:

  Numeric scalar for premium chain ladder. Default is `1`.

- premium_regime_break:

  Premium-side regime break. Defaults to `loss_regime_break` (loss and
  premium share a cutoff unless explicitly separated).

- sigma_method:

  Sigma extrapolation method. One of `"locf"` (default), `"min_last2"`,
  or `"loglinear"`.

- recent:

  Optional positive integer for estimation window. Default is `NULL`.

- maturity_args:

  A named list forwarded to
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md),
  or `NULL` (default) to skip maturity filtering. When `method = "sa"`,
  this also determines the switch point between ED and CL. Pass
  [`list()`](https://rdrr.io/r/base/list.html) to use all defaults.

- se_method:

  Method for computing `lr_se = SE(L/P)`. One of:

  `"fixed"` (default)

  :   Premium treated as fixed (non-random). \\\mathrm{SE}(L/P) =
      \mathrm{SE}(L) / P\\. Strictly, this is the delta method with
      `Var(P) = 0` and `Cov(L,P) = 0`, i.e., a degenerate case under the
      assumption that premium is known.

  `"delta"`

  :   Full delta method including premium uncertainty and the
      loss-premium correlation `rho`: \$\$\mathrm{Var}(L/P) \approx
      \frac{\mathrm{Var}(L)}{P^2} + \frac{L^2 \mathrm{Var}(P)}{P^4} -
      \frac{2 \rho L \mathrm{SE}(L) \mathrm{SE}(P)}{P^3}\$\$

- rho:

  Numeric scalar in `(-1, 1)`; assumed correlation between ultimate loss
  and ultimate premium. Only used when `se_method = "delta"`. Default is
  `0.95`, matching the strong positive correlation typically observed
  between cumulative loss and cumulative premium in long-tail health
  portfolios (analogous to the paid/incurred correlation used in Munich
  chain ladder).

- conf_level:

  Confidence level used for `lr_ci_lower`/`lr_ci_upper` in the cohort
  summary. Default is `0.95`.

- bootstrap:

  Logical; if `TRUE`, parameter and process variance are derived via
  residual bootstrap rather than the analytical delta method. Default is
  `FALSE`.

- B:

  Integer number of bootstrap replications. Used only when
  `bootstrap = TRUE`. Default is `1000`.

- seed:

  Optional integer seed for reproducible bootstrap. Default is `NULL`.

## Value

An object of class `"LRFit"`.

## See also

[`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md),
[`fit_premium()`](https://seokhoonj.github.io/lossratio/reference/fit_premium.md),
[`build_triangle()`](https://seokhoonj.github.io/lossratio/reference/build_triangle.md),
[`build_link()`](https://seokhoonj.github.io/lossratio/reference/build_link.md),
[`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md),
[`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md),
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)

## Examples

``` r
if (FALSE) { # \dontrun{
data(experience)
tri <- build_triangle(experience[coverage == "SUR"], groups = coverage)

# Stage-adaptive (default): ED before maturity, CL after
lr_sa <- fit_lr(tri, method = "sa")
summary(lr_sa)
plot(lr_sa)

# Pure exposure-driven for all development periods
lr_ed <- fit_lr(tri, method = "ed")

# Pure chain ladder (Mack-style) for all development periods
lr_cl <- fit_lr(tri, method = "cl")
} # }
```
