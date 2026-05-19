# Overlay bootstrap SE / CI onto an ExposureFit `$full`

Calls
[`.resolve_bootstrap()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-resolve_bootstrap.md)
to optionally build a `BootstrapTriangle` on the exposure target, then
maps its summary columns onto the projected cells of `result$full`. Sets
`result$ci_type` and a thin `result$bootstrap` metadata list. Mirrors
[`.lossfit_bootstrap()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-lossfit_bootstrap.md)
in `R/loss.R`.

## Usage

``` r
.exposurefit_bootstrap(result, x, grp, bootstrap, B, seed, alpha)
```

## Arguments

- result:

  An augmented exposure fit (post
  [`.exposurefit_augment()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-exposurefit_augment.md)).

- x:

  The original `Triangle`.

- grp:

  Character vector of group columns.

- bootstrap, B, seed, alpha:

  Forwarded to
  [`.resolve_bootstrap()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-resolve_bootstrap.md).

## Value

The updated fit with bootstrap CI overlaid on `$full` and `ci_type` /
`bootstrap` slots set.
