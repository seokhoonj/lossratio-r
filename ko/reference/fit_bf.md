# Bornhuetter-Ferguson projection

Fit a Bornhuetter-Ferguson (1972) projection from a `"Triangle"` object.
The BF estimator blends the *observed* cumulative loss for each cohort
with an *a priori* expected loss ratio (ELR) applied to the cohort's
ultimate premium, weighted by the expected unemerged fraction \\1 -
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

- \\E_i^{ult}\\: cohort \\i\\'s ultimate premium, projected via chain
  ladder on the `premium` column.

This is a peer worker alongside
[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
/
[`fit_ed()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ed.md)
/
[`fit_loss()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_loss.md).
Standalone for the BF recipe – composition with
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md)
is not part of this worker. Point projection is always computed;
bootstrap SE / CI is opt-in via `bootstrap = TRUE` (Phase 3b).
Closed-form Mack (2008) MSEP is not yet implemented.

## Usage

``` r
fit_bf(
  x,
  loss = "loss",
  premium = "premium",
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
  credibility = NULL,
  conf_level = 0.95,
  ...
)
```

## Arguments

- x:

  A `Triangle` object.

- loss:

  A single cumulative loss variable to project. Default `"loss"`.

- premium:

  A single cumulative premium variable used as the denominator of the
  prior ELR. Default `"premium"`.

- prior:

  The a priori expected loss ratio. Accepts:

  single numeric

  :   Applied uniformly to every cohort.

  per-cohort `data.frame` (`cohort` + `elr`)

  :   Per-cohort ELR. Must cover every cohort present in `x` (extras are
      silently dropped, missing cohorts raise an error).

  per-group `data.frame` (grouping columns + `elr`)

  :   One ELR per group, broadcast to every cohort in that group. Useful
      when a single a priori ELR is set per line of business. Must cover
      every group present in `x`.

  A `data.frame` prior may also carry an optional `elr_se` column – the
  standard error of the a priori ELR (a *distribution prior*). When
  supplied, the bootstrap path draws a per-replicate ELR from
  `Normal(elr, elr_se)` instead of treating the prior as a fixed point.
  Omit it (or leave `NA`) for a deterministic prior.

- bootstrap:

  Bootstrap configuration. Five forms accepted:

  `NULL` / `FALSE` (default)

  :   Point estimate only – no bootstrap SE/CI.

  `TRUE` / `"auto"`

  :   Internal
      [`bootstrap()`](https://seokhoonj.github.io/lossratio/ko/reference/bootstrap.md)
      calls (one for loss, one for premium) sharing `seed` so replicate
      indices align across the two simulations.

  Named list `list(loss = BootstrapTriangle, premium = BootstrapTriangle)`

  :   Pre-built objects from
      [`bootstrap()`](https://seokhoonj.github.io/lossratio/ko/reference/bootstrap.md).
      Must have matching `meta$B` / `meta$seed` so per-replicate
      composition is well-defined; `meta$target` must be `"loss"` and
      `"premium"` respectively.

  Function `function(tri) -> list(loss = ..., premium = ...)`

  :   Lazy spec invoked on the input Triangle (leakage-safe for
      [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)).

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
  `"parametric"` / `"nonparametric"` select the bootstrap residual
  paradigm; `"analytical"` skips simulation and uses the closed-form
  Mack (2008) BF MSEP decomposition for the cohort-level SE / CI. When
  no bootstrap is requested the analytical path is used regardless of
  `type`.

- residual:

  Residual scope for `type = "nonparametric"`. One of `"cell"` (default)
  or `"link"`. See
  [`bootstrap()`](https://seokhoonj.github.io/lossratio/ko/reference/bootstrap.md).

- process:

  One of `"gamma"` (default), `"od_pois"`, or `"normal"`. See
  [`bootstrap()`](https://seokhoonj.github.io/lossratio/ko/reference/bootstrap.md).

- alpha:

  Numeric scalar passed through to the inner
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
  and
  [`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md)
  calls. Default `1`.

- sigma_method:

  Sigma extrapolation method forwarded to
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
  /
  [`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md).
  Default `"locf"`.

- recent:

  Optional positive integer; calendar-diagonal filter forwarded to the
  inner fits. Default `NULL`.

- regime:

  Optional regime specification forwarded to the inner loss and premium
  fits. See
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
  for the four-type dispatch.

- maturity:

  Optional maturity specification forwarded to the inner loss fit. See
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
  for the four-type dispatch.

- credibility:

  Optional credibility specification. `NULL` (default) gives the
  classical BF blend with weight equal to the emergence fraction `q`. A
  list `list(method = "bs", K = NULL)` switches to a Buehlmann-Straub
  credibility blend `ult = Z * CL + (1 - Z) * prior`, where
  `Z = K / (K + s^2)`, `s^2` is the variance of the cohort's own CL
  loss-ratio estimate, and `K` is the variance of the hypothetical means
  (the genuine between-cohort spread). `K` is estimated per group when
  `NULL`, or supplied as a non-negative numeric scalar. The credibility
  weight protects rare-event cohorts: a green cohort with a CL estimate
  built on almost no data has a large `s^2`, so `Z` shrinks toward 0 and
  the cohort is pulled to the prior even when its `q` is high. A
  credibility blend always uses the analytical SE path (the SE is
  approximate – the credibility factor is treated as a fixed plug-in).

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

- `loss`, `premium`:

  Loss / premium variable names.

- `full`:

  `data.table`
  `[group, cohort, dev, loss_obs, loss_proj, premium_obs, premium_proj, is_observed, incr_loss_proj, incr_premium_proj]`.
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

- `credibility`:

  `NULL` for the classical blend, or a list `list(method, weights)`
  where `weights` is a `data.table` `[group..., cohort, Z, K]` of the
  Buehlmann-Straub credibility factors used in place of `q`.

- `cl_fit`:

  The inner `CLFit` used to derive \\q_i\\.

- `premium_fit`:

  The inner `PremiumFit` used to derive \\E_i^{ult}\\.

- `bootstrap`:

  When `bootstrap` is enabled, a `BFBootstrap` helper holding both
  Triangle-level `BootstrapTriangle` objects and the per-replicate
  ultimate replicates; `NULL` otherwise.

- `ci_type`:

  `"bootstrap"` when a bootstrap was run, `"analytical"` when the
  closed-form Mack (2008) MSEP was used. In the analytical case
  `$summary` carries `loss_total_se`, `loss_total_cv`, `loss_ci_lo`, and
  `loss_ci_hi`.

- `alpha`, `sigma_method`, `recent`, `regime`, `maturity`:

  Inputs forwarded to the inner
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
  /
  [`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md)
  calls.

## References

Bornhuetter, R. L. and Ferguson, R. E. (1972). The actuary and IBNR.
*Proceedings of the Casualty Actuarial Society*, 59, 181-195.

Mack, T. (2008). The prediction error of Bornhuetter/Ferguson. *ASTIN
Bulletin*, 38(1), 87-103. (MSEP – not yet implemented.)

## See also

[`fit_cc()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cc.md)
(pooled ELR variant),
[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md),
[`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md)

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
  premium = "incr_premium"
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
