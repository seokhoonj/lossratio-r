# Stage-adaptive (SA) point projection for a single cohort

Internal helper that projects cumulative loss with the SA rule: ED phase
before maturity (`k < maturity_from`), CL phase after.

Originally lived in `R/loss.R` – moved to `R/sa.R` alongside
[`fit_sa()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_sa.md)
in Phase 4a.

## Usage

``` r
.sa_proj(loss_obs, exposure_proj, g_sel, f_sel, maturity_from)
```

## Arguments

- loss_obs:

  Numeric vector of observed cumulative loss.

- exposure_proj:

  Numeric vector of projected cumulative exposure.

- g_sel:

  Numeric vector of ED intensities.

- f_sel:

  Numeric vector of CL factors.

- maturity_from:

  Numeric scalar; switch point. `NA` means ED-only (no switch).

## Value

A numeric vector with projected cumulative loss.
