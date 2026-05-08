# Internal: row-level cohort vs calendar consistency check

Flag rows where `calendar_var < cohort_var` — claims/events recorded as
occurring before the cohort start, which is logically impossible.

## Usage

``` r
.validate_calendar_consistency_impl(dt, grp_var, coh_var, dev_var, cal_var)
```
