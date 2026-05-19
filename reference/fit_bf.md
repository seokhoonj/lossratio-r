# Bornhuetter-Ferguson projection

Fit a Bornhuetter-Ferguson (1972) projection from a `"Triangle"` object.
The BF estimator blends the *observed* cumulative loss for each cohort
with an *a priori* expected loss ratio (ELR) applied to the cohort's
ultimate exposure, weighted by the expected unemerged fraction \\1 -
q_i\\:

\$\$\hat L\_{ult, i}^{BF} = L\_{obs, i} + (1 - q_i) \cdot
\mathrm{ELR}\_i \cdot E_i^{ult}\$\$

where

- \\L\_{obs, i}\\: cohort \\i\\'s observed cumulative loss at its latest
  observed development period.

- \\q_i = L\_{obs, i} / \hat L\_{ult, i}^{CL}\\: the *expected emerged
  fraction*, equivalent to the inverse of the cumulative loss
  development factor (LDF) for cohort \\i\\.

- \\\mathrm{ELR}\_i\\: the user-supplied a priori expected loss ratio
  for cohort \\i\\ (`prior` argument).

- \\E_i^{ult}\\: cohort \\i\\'s ultimate exposure, projected via chain
  ladder on the `exposure` column.

This is a peer worker alongside
[`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md)
/
[`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md)
/
[`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md).
Standalone for the BF recipe – composition with
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md)
is not part of this worker. Point projection is always computed;
bootstrap SE / CI is opt-in via `bootstrap = TRUE` (Phase 3b).
Closed-form Mack (2008) MSEP is not yet implemented.

## Usage

``` r
fit_bf(
  x,
  loss = "loss",
  exposure = "exposure",
  prior,
  bootstrap = NULL,
  B = 999L,
  seed = NULL,
  type = c("parametric", "nonparametric", "analytical"),
  residual = c("cell", "link"),
  process = c("gamma", "od_pois", "normal"),
  alpha = 1,
  sigma_method = c("locf", "min_last2", "loglinear", "mack", "none"),
  recent = NULL,
  regime = NULL,
  maturity = NULL,
  conf_level = 0.95,
  ...
)
```

## Arguments

- x:

  A `Triangle` object.

- loss:

  A single cumulative loss variable to project. Default `"loss"`.

- exposure:

  A single cumulative exposure variable used as the denominator of the
  prior ELR. Default `"exposure"`.

- prior:

  The a priori expected loss ratio. Accepts:

  single numeric

  :   Applied uniformly to every cohort.

  `data.frame` with columns `cohort` and `elr`

  :   Per-cohort ELR. Must cover every cohort present in `x` (extras are
      silently dropped, missing cohorts raise an error).

- bootstrap:

  Bootstrap configuration. Five forms accepted:

  `NULL` / `FALSE` (default)

  :   Point estimate only – no bootstrap SE/CI.

  `TRUE` / `"auto"`

  :   Internal
      [`bootstrap()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md)
      calls (one for loss, one for exposure) sharing `seed` so replicate
      indices align across the two simulations.

  Named list `list(loss = BootstrapTriangle, exposure = BootstrapTriangle)`

  :   Pre-built objects from
      [`bootstrap()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md).
      Must have matching `meta$B` / `meta$seed` so per-replicate
      composition is well-defined; `meta$target` must be `"loss"` and
      `"exposure"` respectively.

  Function `function(tri) -> list(loss = ..., exposure = ...)`

  :   Lazy spec invoked on the input Triangle (leakage-safe for
      [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)).

  Latest observed cumulative loss is *not* perturbed in the BF recipe –
  it is treated as the cohort anchor, mirroring the point-estimate
  formula.

- B:

  Integer number of bootstrap replicates. Used only when `bootstrap`
  resolves to `"auto"`. Default `999`.

- seed:

  Optional integer seed for reproducible bootstrap. Default `NULL`.

- type:

  One of `"parametric"` (default), `"nonparametric"`, or `"analytical"`.
  The latter is reserved for Phase 3c (Mack 2008 closed-form MSEP) and
  currently errors.

- residual:

  Residual scope for `type = "nonparametric"`. One of `"cell"` (default)
  or `"link"`. See
  [`bootstrap()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md).

- process:

  One of `"gamma"` (default), `"od_pois"`, or `"normal"`. See
  [`bootstrap()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md).

- alpha:

  Numeric scalar passed through to the inner
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md)
  and
  [`fit_exposure()`](https://seokhoonj.github.io/lossratio/reference/fit_exposure.md)
  calls. Default `1`.

- sigma_method:

  Sigma extrapolation method forwarded to
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md)
  /
  [`fit_exposure()`](https://seokhoonj.github.io/lossratio/reference/fit_exposure.md).
  Default `"locf"`.

- recent:

  Optional positive integer; calendar-diagonal filter forwarded to the
  inner fits. Default `NULL`.

- regime:

  Optional regime specification forwarded to the inner loss and exposure
  fits. See
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md)
  for the four-type dispatch.

- maturity:

  Optional maturity specification forwarded to the inner loss fit. See
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md)
  for the four-type dispatch.

- conf_level:

  Confidence level for the bootstrap quantile CI on `loss_ult`. Default
  `0.95`.

- ...:

  Reserved for future extension (currently unused).

## Value

An object of class `"BFFit"` containing:

- `call`:

  The matched call.

- `data`:

  The input `Triangle`.

- `method`:

  `"bf"`.

- `groups`:

  Grouping variable names.

- `cohort`:

  Raw cohort variable name.

- `dev`:

  Raw development variable name.

- `loss`, `exposure`:

  Loss / exposure variable names.

- `full`:

  `data.table`
  `[group, cohort, dev, loss_obs, loss_proj, exposure_obs, exposure_proj, is_observed, incr_loss_proj, incr_exposure_proj]`.
  When `bootstrap` is enabled, additional columns `loss_total_se`,
  `loss_total_cv`, `loss_ci_lo`, `loss_ci_hi` carry per-cell bootstrap
  SE / CI on projected cells (observed cells stay `NA`).

- `proj`:

  Same shape as `full`, with observed-cell projection columns NA'd out.

- `summary`:

  Cohort-level reserve summary:
  `[group, cohort, latest, loss_ult, reserve, elr, q]`. When `bootstrap`
  is enabled, additional columns `loss_total_se`, `loss_total_cv`,
  `loss_ci_lo`, `loss_ci_hi` carry bootstrap SE / CI on `loss_ult`.

- `prior`:

  Resolved `data.table(group..., cohort, elr)`.

- `q`:

  `data.table(group..., cohort, q)` of expected emerged fractions.

- `cl_fit`:

  The inner `CLFit` used to derive \\q_i\\.

- `exposure_fit`:

  The inner `ExposureFit` used to derive \\E_i^{ult}\\.

- `bootstrap`:

  When `bootstrap` is enabled, a `BFBootstrap` helper holding both
  Triangle-level `BootstrapTriangle` objects and the per-replicate
  ultimate replicates; `NULL` otherwise.

- `ci_type`:

  `"bootstrap"` when `bootstrap` is enabled, `"analytical"`
  (placeholder) otherwise.

- `alpha`, `sigma_method`, `recent`, `regime`, `maturity`:

  Inputs forwarded to the inner
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md)
  /
  [`fit_exposure()`](https://seokhoonj.github.io/lossratio/reference/fit_exposure.md)
  calls.

## References

Bornhuetter, R. L. and Ferguson, R. E. (1972). The actuary and IBNR.
*Proceedings of the Casualty Actuarial Society*, 59, 181-195.

Mack, T. (2008). The prediction error of Bornhuetter/Ferguson. *ASTIN
Bulletin*, 38(1), 87-103. (MSEP – not yet implemented.)

## See also

[`fit_cc()`](https://seokhoonj.github.io/lossratio/reference/fit_cc.md)
(pooled ELR variant),
[`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md),
[`fit_exposure()`](https://seokhoonj.github.io/lossratio/reference/fit_exposure.md)

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

# Scalar prior: 0.7 ELR for every cohort
bf1 <- fit_bf(tri, prior = 0.7)
summary(bf1)

# Per-cohort prior table
prior_tbl <- data.frame(
  cohort = unique(tri$cohort),
  elr    = c(0.6, 0.65, 0.7, 0.72, 0.75)
)
bf2 <- fit_bf(tri, prior = prior_tbl)
} # }
```
