# Resolve `prior` input for `fit_bf()`

Coerce a `prior` argument into a per-cohort `data.table`. Three input
shapes are accepted:

- scalar numeric – applied uniformly to every cohort;

- per-cohort `data.frame` – carries a `cohort` column plus `elr`
  (optionally group-qualified);

- per-group `data.frame` – carries all grouping columns plus `elr` but
  no `cohort`; the group's ELR is broadcast to every cohort in that
  group.

ELR coverage of every cohort present in the input triangle is validated
regardless of shape.

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

  Character vector of join columns (`c(groups, "cohort")`).

## Value

A `data.table` with columns `by_cols + "elr"`.
