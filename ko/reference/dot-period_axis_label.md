# Period axis label with grain qualifier

Maps a raw period variable name (uy_m / uy_q / uy_h / uy or the calendar
siblings) to a heatmap-friendly label like `"cohort (month)"`,
`"calendar (quarter)"`, `"cohort (half-yearly)"`, `"calendar (yearly)"`.
Falls back to the bare `prefix` for unrecognised inputs.

## Usage

``` r
.period_axis_label(var, prefix = "cohort", grain = NULL)
```
