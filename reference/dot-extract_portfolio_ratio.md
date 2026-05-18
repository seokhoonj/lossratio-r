# Extract portfolio-level projected loss ratio from a Backtest fit object

Aggregates per-cohort projected ultimate to a single portfolio loss
ratio via exposure-weighting: \\\sum_i loss\_{ult,i} / \sum_i
exposure\_{ult,i}\\.

## Usage

``` r
.extract_portfolio_ratio(bt)
```

## Arguments

- bt:

  A `Backtest` object (result of
  [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)).

## Value

Numeric scalar. `NA_real_` when fields missing.
