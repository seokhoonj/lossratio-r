# Rename loss\_\* columns to exposure\_\* and add incr/CI columns

Translates the worker (`fit_cl`) output's `loss_*` columns to the
dispatcher's role-specific `exposure_*` names. Also derives
`incr_exposure_proj` (per-cohort first difference of `exposure_proj`)
and analytical CI bounds (`exposure_ci_lo`, `exposure_ci_hi`) from
`exposure_proj` +/- z \* `exposure_total_se`.

## Usage

``` r
.exposure_rename_full(full, grp, conf_level)
```
