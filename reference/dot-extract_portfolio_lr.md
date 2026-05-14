# Extract portfolio-level projected loss ratio from a Backtest fit object

Aggregates per-cohort projected ultimate to a single portfolio LR via
exposure-weighting: \\\sum_i loss\_{ult,i} / \sum_i prem\_{ult,i}\\.

## Usage

``` r
.extract_portfolio_lr(bt)
```

## Arguments

- bt:

  A `Backtest` object (result of
  [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)).

## Value

Numeric scalar. `NA_real_` when fields missing.
