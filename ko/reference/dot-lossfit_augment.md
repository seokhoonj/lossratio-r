# Augment a worker-fit to the LossFit schema

Worker fits (`CLFit`, `EDFit`, `SAFit`, `BFFit`, `CCFit`) each have
their own slot layouts. This helper adds missing slots (`loss_ata_fit`,
`exposure_ata_fit`, `exposure_fit`, `ed`, `factor`, `selected`, `usage`,
`ci_type`, `conf_level`, `bootstrap`) as `NULL` if absent, ensures
`$full` carries the dispatcher-uniform columns (`exposure_obs`,
`exposure_proj`, `incr_exposure_proj`, `loss_ci_lo`, `loss_ci_hi`,
`loss_total_cv`), and assigns class `"LossFit"`.

For `"cl"`, this synthesizes the exposure columns by running an
[`fit_exposure()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_exposure.md)
internally when none are present.

## Usage

``` r
.lossfit_augment(
  fit,
  triangle,
  method,
  exposure_fit,
  exposure_method,
  exposure_alpha,
  sigma_method,
  recent,
  regime,
  maturity_arg,
  conf_level
)
```
