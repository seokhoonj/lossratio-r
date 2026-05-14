# Rename target\_\* columns to prem\_\* and add incr/CI columns

Translates the worker (`fit_cl`) output's `target_*` columns to the
dispatcher's role-specific `prem_*` names. Also derives `incr_prem_proj`
(per-cohort first difference of `prem_proj`) and analytical CI bounds
(`prem_ci_lo`, `prem_ci_hi`) from `prem_proj` +/- z \* `prem_total_se`.

## Usage

``` r
.prem_rename_full(full, grp, conf_level)
```
