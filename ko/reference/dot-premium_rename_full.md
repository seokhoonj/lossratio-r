# Rename target\_\* columns to premium\_\* and add incr/CI columns

Translates the worker (`fit_cl`) output's `target_*` columns to the
dispatcher's role-specific `premium_*` names. Also derives
`premium_incr_proj` (per-cohort first difference of `premium_proj`) and
analytical CI bounds (`premium_ci_lower`, `premium_ci_upper`) from
`premium_proj` +/- z \* `premium_total_se`.

## Usage

``` r
.premium_rename_full(full, grp_var, conf_level)
```
