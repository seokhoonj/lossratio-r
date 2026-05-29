# Augment a worker-fit to the LossFit schema

Worker fits (`CLFit`, `EDFit`, `SAFit`, `BFFit`, `CCFit`) each have
their own slot layouts. This helper adds missing slots (`loss_ata_fit`,
`premium_ata_fit`, `premium_fit`, `ed`, `factor`, `selected`, `usage`,
`ci_type`, `conf_level`, `bootstrap`) as `NULL` if absent, ensures
`$full` carries the dispatcher-uniform columns (`premium_obs`,
`premium_proj`, `incr_premium_proj`, `loss_ci_lo`, `loss_ci_hi`,
`loss_total_cv`), and assigns class `"LossFit"`.

For `"cl"`, this synthesizes the premium columns by running an
[`fit_premium()`](https://seokhoonj.github.io/lossratio-r/ko/reference/fit_premium.md)
internally when none are present.

## Usage

``` r
.lossfit_augment(
  fit,
  triangle,
  method,
  premium_fit,
  premium_method,
  premium_alpha,
  sigma_method,
  recent,
  regime,
  maturity_arg,
  conf_level
)
```
