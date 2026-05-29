# Augment a CL worker result into the PremiumFit `$full` schema

Applies (1) the ED-variance overlay when `method = "ed"`, (2) the
`loss_*` -\> `premium_*` column rename, and (3) the analytical CI
bounds. Mirrors the
[`.lossfit_augment()`](https://seokhoonj.github.io/lossratio-r/ko/reference/dot-lossfit_augment.md)
helper in `R/loss.R`.

## Usage

``` r
.premiumfit_augment(result, x, method, groups, conf_level)
```

## Arguments

- result:

  A `CLFit` from `fit_cl(loss = "premium", ...)`.

- x:

  The original `Triangle`.

- method:

  One of `"cl"` / `"ed"`.

- groups:

  Character vector of group columns.

- conf_level:

  Confidence level for analytical CI bounds.

## Value

The augmented `CLFit` with `$full` carrying `premium_*` columns.
