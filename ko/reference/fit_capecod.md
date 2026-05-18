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

- \\E_i^{ult}\\: cohort \\i\\'s ultimate exposure (projected via chain
  ladder on exposure).

Given \\\widehat{\mathrm{ELR}}^{CC}\\, the per-cohort ultimate is
obtained from the BF formula with this single pooled ELR:

\$\$\hat L\_{ult, i}^{CC} = L\_{obs, i} + (1 - q_i) \cdot
\widehat{\mathrm{ELR}}^{CC} \cdot E_i^{ult}\$\$

When multiple groups are present, \\\widehat{\mathrm{ELR}}^{CC}\\ is
computed *within group* (not pooled across groups) so each group retains
its own portfolio-level ELR estimate.

This is a *standalone* worker – it does not currently integrate with
[`fit_loss()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_loss.md)
/
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md).
Point projection only.

## Usage

``` r
fit_capecod(x, loss = "loss", exposure = "exposure", ...)
```

## Arguments

- x:

  A `Triangle` object.

- loss:

  A single cumulative loss variable. Default `"loss"`.

- exposure:

  A single cumulative exposure variable. Default `"exposure"`.

- ...:

  Reserved for future extension (currently unused).

## Value

An object of class `"CapeCodFit"` containing:

- `call`:

  The matched call.

- `data`:

  The input `Triangle`.

- `method`:

  `"capecod"`.

- `groups`, `cohort`, `dev`, `loss`, `exposure`:

  Metadata.

- `full`, `proj`, `summary`:

  Same shape as `BFFit`.

- `elr_cc`:

  `data.table(group..., elr_cc)` – the pooled ELR per group (or scalar
  if no group).

- `q`:

  Per-cohort emerged fraction.

- `cl_fit`, `exposure_fit`:

  Inner CL / Exposure fits.

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
cc <- fit_capecod(tri)
summary(cc)
cc$elr_cc   # pooled ELR per group
} # }
```
