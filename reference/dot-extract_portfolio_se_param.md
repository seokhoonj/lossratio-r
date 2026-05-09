# Extract portfolio-level parameter SE on the LR scale

Aggregates per-cohort parameter SE (on loss scale) to portfolio-level SE
on the LR scale assuming inter-cohort independence:

## Usage

``` r
.extract_portfolio_se_param(bt)
```

## Arguments

- bt:

  A `Backtest` object.

## Value

Numeric scalar. `NA_real_` when fields missing.

## Details

\$\$SE^{param}(LR\_{portfolio}) = \sqrt{\sum_i (param\\se_i)^2} / \sum_i
premium\_{ult,i}\$\$
