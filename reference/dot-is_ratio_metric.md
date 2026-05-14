# Is the metric ratio-valued (LR or share)?

Internal helper: classifies a Triangle / Calendar / Total / fit output
metric as ratio (LR, share) vs amount (loss, premium, margin). Ratio
metrics never need an `amount_divisor` scaling (they live on \[0, 1\] or
thereabouts); amount metrics do.

## Usage

``` r
.is_ratio_metric(metric)
```

## Arguments

- metric:

  A single metric name.

## Value

`TRUE` for `lr` / `lr_incr` and any `_share` variant, `FALSE` otherwise.
