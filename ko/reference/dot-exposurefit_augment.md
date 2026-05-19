# Augment a CL worker result into the ExposureFit `$full` schema

Applies (1) the ED-variance overlay when `method = "ed"`, (2) the
`loss_*` -\> `exposure_*` column rename, and (3) the analytical CI
bounds. Mirrors the
[`.lossfit_augment()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-lossfit_augment.md)
helper in `R/loss.R`.

## Usage

``` r
.exposurefit_augment(result, x, method, grp, conf_level)
```

## Arguments

- result:

  A `CLFit` from `fit_cl(loss = "exposure", ...)`.

- x:

  The original `Triangle`.

- method:

  One of `"cl"` / `"ed"`.

- grp:

  Character vector of group columns.

- conf_level:

  Confidence level for analytical CI bounds.

## Value

The augmented `CLFit` with `$full` carrying `exposure_*` columns.
