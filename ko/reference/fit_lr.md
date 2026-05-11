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

## Usage

``` r
fit_lr(
  x,
  method = c("sa", "ed", "cl"),
  loss_var = "loss",
  premium_var = "premium",
  loss_alpha = 1,
  premium_alpha = 1,
  delta_method = c("simple", "full"),
  rho = 0,
  conf_level = 0.95,
  sigma_method = c("min_last2", "locf", "loglinear"),
  recent = NULL,
  regime_break = NULL,
  maturity_args = NULL,
  bootstrap = FALSE,
  B = 1000,
  seed = NULL
)
```

## Arguments

- x:

  An object of class `"Triangle"`.

- method:

  One of `"sa"`, `"ed"`, or `"cl"`. Default is `"sa"`.

- loss_var:

  Cumulative loss variable. Default is `"loss"`.

- premium_var:

  Cumulative exposure variable. Default is `"premium"`.

- loss_alpha:

  Numeric scalar controlling the variance structure for loss estimation.
  Default is `1`.

- premium_alpha:

  Numeric scalar for exposure chain ladder. Default is `1`.

- delta_method:

  Method for computing `se_lr = SE(L/E)`. One of:

  `"simple"` (default)

  :   `se_lr = se_proj / premium_proj`, treats exposure as fixed.

  `"full"`

  :   Full delta method with exposure uncertainty and loss-exposure
      correlation: \$\$\mathrm{Var}(L/E) \approx
      \frac{\mathrm{Var}(L)}{E^2} + \frac{L^2 \mathrm{Var}(E)}{E^4} -
      \frac{2 \rho L \mathrm{SE}(L) \mathrm{SE}(E)}{E^3}\$\$

- rho:

  Numeric scalar in `(-1, 1)`; assumed correlation between ultimate loss
  and ultimate exposure. Only used when `delta_method = "full"`. Default
  is `0`.

- conf_level:

  Confidence level used for `ci_lower`/`ci_upper` in the cohort summary.
  Default is `0.95`.

- sigma_method:

  Sigma extrapolation method. One of `"min_last2"` (default), `"locf"`,
  or `"loglinear"`.

- recent:

  Optional positive integer for estimation window. Default is `NULL`.

- regime_break:

  Optional cohort cutoff for the regime break. Accepts: `NULL` (default,
  no filter), a single `Date`/character coercible to Date, a vector of
  dates (uses the latest), or a `Regime` object (extracts the latest
  from `$breakpoints`). Behavior depends on `method`:

  `"sa"`

  :   Hybrid filter. Pre-break cohorts are dropped only for development
      periods at or before the maturity point (ED phase);
      post-maturity (CL) cells use the `recent`-diagonal window across
      all cohorts. This preserves CL stability while protecting the ED
      intensities from a regime shift.

  `"ed"`, `"cl"`

  :   Simple cohort cut: all cohorts strictly before the break date are
      excluded from estimation.

- maturity_args:

  A named list forwarded to
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md),
  or `NULL` (default) to skip maturity filtering. When `method = "sa"`,
  this also determines the switch point between ED and CL. Pass
  [`list()`](https://rdrr.io/r/base/list.html) to use all defaults.

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

[`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md),
[`build_link()`](https://seokhoonj.github.io/lossratio/ko/reference/build_link.md),
[`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md),
[`fit_ed()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ed.md),
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)

## Examples

``` r
if (FALSE) { # \dontrun{
data(experience)
tri <- build_triangle(experience[coverage == "SUR"], group_var = coverage)

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
