# Compute Mack parameter variance for a single cohort

Internal helper computing:

\$\$ \mathrm{param}\_{i,k+1} = f_k^2 \cdot \mathrm{param}\_{i,k} +
\hat{C}\_{i,k}^2 \cdot \mathrm{Var}(\hat{f}\_k) \$\$

## Usage

``` r
.mack_param_var(target_proj, f_sel, f_var, last_obs)
```
