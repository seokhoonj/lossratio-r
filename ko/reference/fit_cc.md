# Cape Cod projection (Stanard 1985)

Fit a Cape Cod projection from a `"Triangle"` object. Cape Cod is the
*prior-free* Bornhuetter-Ferguson variant introduced by Stanard (1985):
the a priori expected loss ratio is *estimated from the data itself* as
a portfolio-pooled quantity, then plugged into the BF formula.

\$\$\widehat{\mathrm{ELR}}^{CC} = \frac{\sum_i L\_{obs, i}}{\sum_i
E_i^{ult} \cdot q_i}\$\$

where

- \\L\_{obs, i}\\: cohort \\i\\'s observed cumulative loss at its latest
  observed development period.

- \\q_i = L\_{obs, i} / \hat L\_{ult, i}^{CL}\\: the expected emerged
  fraction (inverse of cumulative LDF).

- \\E_i^{ult}\\: cohort \\i\\'s ultimate premium (projected via chain
  ladder on premium).

Given \\\widehat{\mathrm{ELR}}^{CC}\\, the per-cohort ultimate is
obtained from the BF formula with this single pooled ELR:

\$\$\hat L\_{ult, i}^{CC} = L\_{obs, i} + (1 - q_i) \cdot
\widehat{\mathrm{ELR}}^{CC} \cdot E_i^{ult}\$\$

When multiple groups are present, \\\widehat{\mathrm{ELR}}^{CC}\\ is
computed *within group* (not pooled across groups) so each group retains
its own portfolio-level ELR estimate.

This is a peer worker alongside
[`fit_bf()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_bf.md)
/
[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
/
[`fit_ed()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ed.md).
Standalone for the Cape Cod recipe – composition with
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md)
is not part of this worker. Point projection is always computed;
bootstrap SE / CI is opt-in via `bootstrap = TRUE` (Phase 3b). The
bootstrap path also produces per-replicate pooled ELR draws
(`elr_cc_se`, `elr_cc_cv`, `elr_cc_ci_lo`, `elr_cc_ci_hi`) since the
Cape Cod ELR itself is data-driven and thus uncertain.

## Usage

``` r
fit_cc(
  x,
  loss = "loss",
  premium = "premium",
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
  credibility = NULL,
  conf_level = 0.95,
  ...
)
```

## Arguments

- x:

  A `Triangle` object.

- loss:

  A single cumulative loss variable. Default `"loss"`.

- premium:

  A single cumulative premium variable. Default `"premium"`.

- bootstrap:

  Bootstrap configuration. Same forms as
  [`fit_bf()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_bf.md)'s
  `bootstrap` arg – see there for the full description.

- B:

  Integer number of bootstrap replicates. Used only when `bootstrap`
  resolves to `"auto"`. Default `999`.

- seed:

  Optional integer seed for reproducible bootstrap. Default `NULL`.

- type:

  One of `"parametric"` (default), `"nonparametric"`, or `"analytical"`.
  `"parametric"` / `"nonparametric"` select the bootstrap residual
  paradigm; `"analytical"` skips simulation and uses the closed-form
  Mack (2008) MSEP decomposition (with `Var(ELR_cc)` from the delta
  method on the pooled ELR). When no bootstrap is requested the
  analytical path is used regardless of `type`.

- residual:

  Residual scope for `type = "nonparametric"`. One of `"cell"` (default)
  or `"link"`.

- process:

  One of `"gamma"` (default), `"od_pois"`, `"normal"`.

- alpha:

  Numeric scalar passed through to the inner
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
  /
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

- credibility:

  Optional credibility specification. `NULL` (default) gives the
  classical CC blend weighted by the emergence fraction `q`. A list
  `list(method = "bs", K = NULL)` switches to a Buehlmann-Straub
  credibility blend `ult = Z * CL + (1 - Z) * prior` with the pooled ELR
  as the prior; `Z = K / (K + s^2)` shrinks a green / rare-event cohort
  toward the pooled ELR. See
  [`fit_bf()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_bf.md)
  for the full description. A credibility blend uses the analytical SE
  path.

- conf_level:

  Confidence level for the SE-based CI (bootstrap quantile or analytical
  normal). Default `0.95`.

- ...:

  Reserved for future extension (currently unused).

## Value

An object of class `"CCFit"` containing:

- `call`:

  The matched call.

- `data`:

  The input `Triangle`.

- `method`:

  `"cc"`.

- `groups`, `cohort`, `dev`, `loss`, `premium`:

  Metadata.

- `full`, `proj`, `summary`:

  Same shape as `BFFit`. With bootstrap enabled, `$full` carries
  `loss_total_se`/`loss_total_cv`/`loss_ci_lo`/`loss_ci_hi` on projected
  cells, and `$summary` carries the same plus
  `elr_cc_se`/`elr_cc_cv`/`elr_cc_ci_lo`/`elr_cc_ci_hi` (uncertainty on
  the pooled ELR itself).

- `elr_cc`:

  `data.table(group..., elr_cc)` – the pooled ELR per group (or scalar
  if no group).

- `q`:

  Per-cohort emerged fraction.

- `credibility`:

  `NULL` for the classical blend, or a list `list(method, weights)` with
  the Buehlmann-Straub `Z` / `K` per cohort.

- `cl_fit`, `premium_fit`:

  Inner CL / Premium fits.

- `bootstrap`:

  When `bootstrap` is enabled, a `CCBootstrap` helper holding both
  Triangle-level `BootstrapTriangle` objects, the per-replicate ultimate
  replicates, and the per-replicate pooled ELR draws; `NULL` otherwise.

- `ci_type`:

  `"bootstrap"` when a bootstrap was run, `"analytical"` when the
  closed-form Mack (2008) MSEP was used. In the analytical case
  `$summary` carries `loss_total_se` / `loss_total_cv` / `loss_ci_lo` /
  `loss_ci_hi` plus the pooled-ELR columns `elr_cc_se` / `elr_cc_cv` /
  `elr_cc_ci_lo` / `elr_cc_ci_hi`.

- `alpha`, `sigma_method`, `recent`, `regime`:

  Inputs forwarded to the inner
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
  /
  [`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md)
  calls.

## References

Stanard, J. N. (1985). A simulation test of prediction errors of loss
reserve estimation techniques. *Proceedings of the Casualty Actuarial
Society*, 72, 124-148.

Bornhuetter, R. L. and Ferguson, R. E. (1972). The actuary and IBNR.
*Proceedings of the Casualty Actuarial Society*, 59, 181-195.

## See also

[`fit_bf()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_bf.md)
(Bornhuetter-Ferguson with user-supplied prior),
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
cc <- fit_cc(tri)
summary(cc)
cc$elr_cc   # pooled ELR per group
} # }
```
