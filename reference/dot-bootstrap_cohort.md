# Parametric bootstrap for one cohort's loss and loss-ratio CI

Internal helper for bootstrap CI calculation used by
[`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)
when `bootstrap = TRUE`. For a single cohort, simulates `B` replicates
of the projected loss path using Mack-style variance estimates as
sampling inputs, and returns percentile-based CI bounds aligned with the
input rows.

Observed rows (index \<= `last_obs`) are returned with CI equal to the
observed value (no uncertainty). Projected rows get bootstrap
percentiles.

## Usage

``` r
.bootstrap_cohort(
  loss_obs,
  loss_proj,
  prem_proj,
  g_sel,
  f_sel,
  g_sigma2,
  f_sigma2,
  g_var,
  f_var,
  last_obs,
  maturity_from,
  B,
  loss_alpha,
  method,
  probs
)
```

## Value

A list with four vectors of length `length(prem_proj)`: `lr_ci_lo`,
`lr_ci_hi` (for LR), and `loss_ci_lo`, `loss_ci_hi` (for cumulative
loss).
