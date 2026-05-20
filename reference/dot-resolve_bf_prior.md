# Resolve `prior` input for `fit_bf()`

Coerce a `prior` argument (scalar numeric or `data.frame(cohort, elr)`)
into a per-cohort `data.table`. Validates ELR coverage of every cohort
present in the input triangle.

## Usage

``` r
.resolve_bf_prior(prior, dt, by_cols)
```

## Arguments

- prior:

  The user-supplied prior. See
  [`fit_bf()`](https://seokhoonj.github.io/lossratio/reference/fit_bf.md).

- dt:

  The per-cohort `data.table` (carrying `cohort` etc.).

- by_cols:

  Character vector of join columns (`c(grp, "cohort")`).

## Value

A `data.table` with columns `by_cols + "elr"`.
