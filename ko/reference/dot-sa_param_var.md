# Stage-adaptive parameter variance for a single cohort

ED phase: `param_{k+1} = param_k + (C^P_k)^2 * Var(g_k)`. CL phase:
`param_{k+1} = f_k^2 * param_k + (C^L_k)^2 * Var(f_k)`.

## Usage

``` r
.sa_param_var(
  loss_proj,
  premium_proj,
  g_var,
  f_var,
  f_sel,
  last_obs,
  maturity_from
)
```
