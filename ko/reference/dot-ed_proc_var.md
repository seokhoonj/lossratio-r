# ED process variance for a single cohort

Additive recursion:
`proc_{k+1} = proc_k + sigma^2_{g,k} * (premium_k)^alpha`.

## Usage

``` r
.ed_proc_var(premium_proj, g_sigma2, last_obs, alpha = 1)
```
