# Validate the bootstrap argument combination

Internal helper called by
[`bootstrap.Triangle()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md)
after [`match.arg()`](https://rdrr.io/r/base/match.arg.html). Enforces
the type/residual/process/method/pooling/tail combination matrix and
warns when an argument is silently ignored.

## Usage

``` r
.validate_bootstrap_args(
  type,
  residual,
  process,
  method,
  pooling,
  tail,
  min_pool,
  hat_adj,
  demean,
  maturity,
  residual_set,
  process_set,
  pooling_set,
  tail_set,
  hat_adj_set,
  demean_set,
  min_pool_set,
  method_set
)
```

## Arguments

- type, residual, process, method, pooling, tail:

  Resolved (post-match.arg) values.

- min_pool, hat_adj, demean, maturity:

  Scalar values to validate.

- residual_set, process_set, pooling_set, tail_set, hat_adj_set,
  demean_set, min_pool_set:

  Logicals indicating whether the user explicitly passed each argument
  (computed via [`match.call()`](https://rdrr.io/r/base/match.call.html)
  in the caller).

## Value

`invisible(TRUE)` after raising any errors / warnings.
