# Maturity: detecting when ATA factors stabilise across cohorts

The maturity point is the development link beyond which age-to-age
factors are stable enough to trust for chain-ladder projection. Used
internally by `fit_lr(method = "sa")` to switch from ED to CL. The
factor diagnostics that drive detection are covered in
[`vignette("triangle-and-link")`](https://seokhoonj.github.io/lossratio/ko/articles/triangle-and-link.md);
this article focuses on
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
itself.

## Setup

For brevity this vignette uses the `SUR` group only — every step
generalises to multi-group input.

``` r

library(lossratio)
data(experience)
exp <- as_experience(experience)[cv_nm == "SUR"]
tri <- build_triangle(exp, group_var = cv_nm)
```

## Detecting maturity

[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
takes a `Triangle` directly — the underlying single-variable `Link` and
its WLS summary are built internally:

``` r

mat <- detect_maturity(
  tri,
  value_var       = "closs",
  cv_threshold    = 0.10,    # CV must be below this
  rse_threshold   = 0.05,    # RSE must be below this
  min_valid_ratio = 0.5,     # at least 50% finite cohorts at the link
  min_n_valid     = 3L,      # at least 3 finite cohorts
  min_run         = 1L       # at least 1 consecutive mature link
)

print(mat)
#> Key: <cv_nm>
#>     cv_nm ata_from ata_to ata_link     mean   median       wt         cv
#>    <char>    <int>  <int>   <char>    <num>    <num>    <num>      <num>
#> 1:    SUR        9     10     9-10 1.187815 1.172305 1.164727 0.09743995
#>           f       f_se        rse    sigma n_obs n_valid n_inf n_nan
#>       <num>      <num>      <num>    <num> <int>   <int> <int> <int>
#> 1: 1.164727 0.02218428 0.01904677 1774.278    21      21     0     0
#>    valid_ratio
#>          <num>
#> 1:           1
```

A row per group with the first development link satisfying all
thresholds, carrying the link’s full statistics. The threshold arguments
are also stored as attributes on the returned `Maturity` object.

## Threshold semantics

- `cv_threshold` — coefficient of variation of the observed ATA factors
  at the link. Caps relative spread regardless of `alpha`.
- `rse_threshold` — relative standard error of the WLS-estimated factor
  `f`. Captures parameter uncertainty rather than residual spread.
- `min_valid_ratio` — minimum share of cohorts with a finite ATA at the
  link. Guards against links where most observations are zero / NA /
  Inf.
- `min_n_valid` — minimum count of finite cohorts at the link. Absolute
  floor for thin-data tails.
- `min_run` — minimum number of *consecutive* mature links. With
  `min_run = 1L` (default) the first qualifying link wins; setting it to
  `2L` or higher requires sustained stability.

Tune these to your portfolio’s volatility profile. Tight thresholds
(e.g. `cv_threshold = 0.05`) push maturity later; loose thresholds push
it earlier.

## Use in fitting

[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
is also called internally by
[`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md)
and
[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
when `maturity_args` is supplied (the `alpha` of the internal
[`summary()`](https://rdrr.io/r/base/summary.html) step is taken from
those callers):

``` r

fit_ata(tri, value_var = "closs",
        maturity_args = list(cv_threshold = 0.08, min_run = 2L))

fit_cl(tri, value_var = "closs",
       maturity_args = list(cv_threshold = 0.08))

fit_lr(tri, method = "sa",
       maturity_args = list(cv_threshold = 0.08))
```

For `fit_lr(method = "sa")` the detected maturity point determines the
dev at which the projection switches from ED (early dev) to CL (later
dev).

## Group-wise output

For multi-group triangles
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
returns one row per group:

``` r

tri_all <- build_triangle(as_experience(experience), group_var = cv_nm)
detect_maturity(tri_all, value_var = "closs")
```

Each group is detected independently with the same thresholds.

## See also

- [`vignette("triangle-and-link")`](https://seokhoonj.github.io/lossratio/ko/articles/triangle-and-link.md)
  — `Triangle` / `Link` data structures and the per-link statistics used
  by
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md).
- [`vignette("projection")`](https://seokhoonj.github.io/lossratio/ko/articles/projection.md)
  — how the maturity point feeds into `fit_lr(method = "sa")`.
- [`?detect_maturity`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
  — full argument reference.
