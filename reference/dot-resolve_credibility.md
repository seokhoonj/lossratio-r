# Resolve the `credibility` argument for `fit_bf()` / `fit_cc()`

Validate and normalise the `credibility` argument into a spec list or
`NULL` (classical BF / CC, weight = emergence fraction `q`).

## Usage

``` r
.resolve_credibility(credibility)
```

## Arguments

- credibility:

  `NULL` or a list `list(method = "bs", K = ...)`.

## Value

`NULL` or `list(method = "bs", K = <NULL or numeric>)`.
