# Build the internal premium-side `PremiumFit` for a within-role composer

Within-role composers
([`fit_bf()`](https://seokhoonj.github.io/lossratio-r/ko/reference/fit_bf.md),
[`fit_cc()`](https://seokhoonj.github.io/lossratio-r/ko/reference/fit_cc.md))
need an ultimate premium projection. They obtain it by calling the
worker
[`fit_cl()`](https://seokhoonj.github.io/lossratio-r/ko/reference/fit_cl.md)
directly on the standardized `premium` column – a downward worker-layer
dispatch, avoiding the upward dependency on the
[`fit_premium()`](https://seokhoonj.github.io/lossratio-r/ko/reference/fit_premium.md)
dispatcher – then translating the worker's `loss_*` schema to
`premium_*` and tagging the result as an `PremiumFit`. This helper
packages that shared three-step block.

## Usage

``` r
.build_internal_premium_fit(
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
  [`fit_cl()`](https://seokhoonj.github.io/lossratio-r/ko/reference/fit_cl.md).

- groups:

  Group columns, for the incremental / CI derivation in
  [`.premium_rename_full()`](https://seokhoonj.github.io/lossratio-r/ko/reference/dot-premium_rename_full.md).

- conf_level:

  Confidence level for the analytical CI columns.

## Value

A `CLFit` with `PremiumFit` prepended to its class and an
`premium_*`-schema `$full`.
