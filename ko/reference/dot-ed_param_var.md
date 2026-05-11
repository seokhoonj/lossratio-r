# ED parameter variance for a single cohort

Additive recursion: `param_{k+1} = param_k + (exposure_k)^2 * Var(g_k)`.

## Usage

``` r
.ed_param_var(exposure_proj, g_var, last_obs)
```
