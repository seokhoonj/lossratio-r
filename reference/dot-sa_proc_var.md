# Hybrid process variance for a single cohort

Internal helper for process variance:

- ED phase (additive): \\\text{proc}\_{k+1} = \text{proc}\_k +
  g\_{\sigma^2,k} \cdot (C^P_k)^\alpha\\

- CL phase (multiplicative, Mack): \\\text{proc}\_{k+1} = f_k^2 \cdot
  \text{proc}\_k + f\_{\sigma^2,k} \cdot (C^L_k)^\alpha\\

## Usage

``` r
.sa_proc_var(
  loss_proj,
  premium_proj,
  g_sigma2,
  f_sigma2,
  f_selected,
  last_obs,
  maturity_from,
  alpha = 1,
  method = "sa"
)
```
