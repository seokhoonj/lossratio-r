# Mask the last N calendar diagonals from a Triangle

Drops the most recent `holdout` calendar diagonals (per group) from a
`Triangle`, returning a new `Triangle` of the same class with all
attributes preserved. Useful for simulating a historical analyst's view
– the same masking
[`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
and `detect_regime(holdout=)` apply internally.

The calendar diagonal index is built as `rank(cohort) + dev - 1`, with
[`rank()`](https://rdrr.io/r/base/rank.html) computed within group. The
`holdout` most recent calendar indices are dropped.

## Usage

``` r
mask_triangle(x, holdout = 0L)
```

## Arguments

- x:

  A `Triangle` object.

- holdout:

  Non-negative integer. Number of latest calendar diagonals to mask.
  `0L` (default) returns a copy of `x` unchanged.

## Value

A `Triangle` with the held-out cells removed.

## Examples

``` r
if (FALSE) { # \dontrun{
data(experience)
tri <- build_triangle(experience, groups = "coverage",
                      cohort = "uy_m", calendar = "cy_m",
                      loss = "loss_incr", premium = "premium_incr")

# Inspect what the analyst at a 6-month historical cutoff would see
tri_masked <- mask_triangle(tri, holdout = 6L)
plot_triangle(tri_masked)

# Use same masked tri to detect regime + fit
r   <- detect_regime(tri_masked)
fit <- fit_lr(tri_masked, loss_regime_break = r)
} # }
```
