# Stage-adaptive process variance for a single cohort

ED phase (additive): `proc_{k+1} = proc_k + g_sigma2_k * (C^P_k)^alpha`.
CL phase (Mack):
`proc_{k+1} = f_k^2 * proc_k + f_sigma2_k * (C^L_k)^alpha`.

## Usage

``` r
.sa_proc_var(
  loss_proj,
  premium_proj,
  g_sigma2,
  f_sigma2,
  f_sel,
  last_obs,
  maturity_from,
  alpha = 1
)
```
