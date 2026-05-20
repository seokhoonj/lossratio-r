# Build the internal exposure-side `ExposureFit` for a within-role composer

Within-role composers
([`fit_bf()`](https://seokhoonj.github.io/lossratio/reference/fit_bf.md),
[`fit_cc()`](https://seokhoonj.github.io/lossratio/reference/fit_cc.md))
need an ultimate exposure projection. They obtain it by calling the
worker
[`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md)
directly on the standardized `exposure` column – a downward worker-layer
dispatch, avoiding the upward dependency on the
[`fit_exposure()`](https://seokhoonj.github.io/lossratio/reference/fit_exposure.md)
dispatcher – then translating the worker's `loss_*` schema to
`exposure_*` and tagging the result as an `ExposureFit`. This helper
packages that shared three-step block.

## Usage

``` r
.build_internal_exposure_fit(
  x,
  alpha,
  sigma_method,
  recent = NULL,
  regime = NULL,
  groups = NULL,
  conf_level = 0.95
)
```

## Arguments

- x:

  A `Triangle`.

- alpha, sigma_method, recent, regime:

  Forwarded to
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md).

- groups:

  Group columns, for the incremental / CI derivation in
  [`.exposure_rename_full()`](https://seokhoonj.github.io/lossratio/reference/dot-exposure_rename_full.md).

- conf_level:

  Confidence level for the analytical CI columns.

## Value

A `CLFit` with `ExposureFit` prepended to its class and an
`exposure_*`-schema `$full`.
