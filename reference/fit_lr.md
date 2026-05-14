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
  loss_regime = NULL,
  premium_method = c("cl", "ed"),
  premium_alpha = 1,
  premium_regime = NULL,
  sigma_method = c("locf", "min_last2", "loglinear"),
  recent = NULL,
  maturity = "auto",
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

- premium_method:

  One of `"cl"` (default) or `"ed"`. Forwarded to
  [`fit_premium()`](https://seokhoonj.github.io/lossratio/reference/fit_premium.md)
  when constructing the premium projection.

- premium_alpha:

  Numeric scalar for premium chain ladder. Default is `1`.

- premium_regime:

  Premium-side regime specification. Same four input types as
  `loss_regime` (`NULL` / `Regime` / `"auto"` / function). Default
  `NULL` – premium is fit on the full triangle independently of
  `loss_regime` (no lazy default). Set explicitly when the regime shift
  affects premium accrual too.

- sigma_method:

  Sigma extrapolation method. One of `"locf"` (default), `"min_last2"`,
  or `"loglinear"`.

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
tri <- build_triangle(
  experience[coverage == "SUR"],
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "loss_incr",
  premium  = "premium_incr"
)

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
