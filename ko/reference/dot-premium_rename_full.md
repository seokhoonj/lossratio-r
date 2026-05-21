# Rename loss\_\* columns to premium\_\* and add incr/CI columns

Translates the worker (`fit_cl`) output's `loss_*` columns to the
dispatcher's role-specific `premium_*` names. Also derives
`incr_premium_proj` (per-cohort first difference of `premium_proj`) and
analytical CI bounds (`premium_ci_lo`, `premium_ci_hi`) from
`premium_proj` +/- z \* `premium_total_se`.

## Usage

``` r
.premium_rename_full(full, groups, conf_level)
```
