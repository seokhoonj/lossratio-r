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

This is a *standalone* worker – it does not currently integrate with
[`fit_loss()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_loss.md)
/
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md).
Point projection only; analytical MSEP (Mack 2008) is not yet computed.

## Usage

``` r
fit_bf(x, loss = "loss", exposure = "exposure", prior, ...)
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
  `[group, cohort, dev, loss_obs, loss_proj, exposure_obs, exposure_proj, is_observed, incr_loss_proj, exposure_incr_proj]`.

- `proj`:

  Same shape as `full`, with observed-cell projection columns NA'd out.

- `summary`:

  Cohort-level reserve summary:
  `[group, cohort, latest, loss_ult, reserve, elr, q]`.

- `prior`:

  Resolved `data.table(group..., cohort, elr)`.

- `q`:

  `data.table(group..., cohort, q)` of expected emerged fractions.

- `cl_fit`:

  The inner `CLFit` used to derive \\q_i\\.

- `exposure_fit`:

  The inner `ExposureFit` used to derive \\E_i^{ult}\\.

## References

Bornhuetter, R. L. and Ferguson, R. E. (1972). The actuary and IBNR.
*Proceedings of the Casualty Actuarial Society*, 59, 181-195.

Mack, T. (2008). The prediction error of Bornhuetter/Ferguson. *ASTIN
Bulletin*, 38(1), 87-103. (MSEP – not yet implemented.)

## See also

[`fit_capecod()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_capecod.md)
(pooled ELR variant),
[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md),
[`fit_exposure()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_exposure.md)

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
