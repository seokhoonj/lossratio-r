# Internal: row-level cohort vs calendar consistency check

Flag rows where `calendar < cohort` – claims/events recorded as
occurring before the cohort start, which is logically impossible.

## Usage

``` r
.validate_calendar_consistency_impl(dt, groups, cohort, dev, calendar)
```
