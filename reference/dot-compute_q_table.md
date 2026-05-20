# Compute the per-cohort emergence table (q_i + ultimate exposure)

Shared by
[`fit_bf()`](https://seokhoonj.github.io/lossratio/reference/fit_bf.md)
and
[`fit_cc()`](https://seokhoonj.github.io/lossratio/reference/fit_cc.md).
From a loss-side `CLFit$full` and an exposure-side `ExposureFit$full`,
builds the per-cohort table of latest observed loss, CL-ultimate loss,
the emergence fraction \\q_i = L\_{obs} / L\_{ult}^{CL}\\, and ultimate
exposure – the inputs the Bornhuetter-Ferguson / Cape Cod blend
consumes.

## Usage

``` r
.compute_q_table(loss_full, exp_full, by_cols)
```

## Arguments

- loss_full:

  A loss-side `$full` grid (`is_observed`, `loss_obs`, `loss_proj`).

- exp_full:

  An exposure-side `$full` grid (`exposure_proj`).

- by_cols:

  Per-cohort key columns, `c(groups, "cohort")`.

## Value

A `data.table` keyed by `by_cols` with `loss_latest`, `loss_ult_cl`,
`q`, and `exposure_ult`.
