# Robust cross-cohort dispersion of incremental loss ratio

Internal helper. For each (group, dev) cell of a `Triangle`, computes a
robust scale-invariant dispersion of incremental loss ratio across
cohorts:

\$\$\mathrm{dispersion} = \frac{1.4826 \cdot
\mathrm{MAD}\_i(lr\_{i,v})}{\|\mathrm{median}\_i(lr\_{i,v})\|}\$\$

Operating on incremental LR keeps the metric inertia-free.

## Usage

``` r
.compute_dispersion(triangle, min_n_cohorts = 5L)
```

## Arguments

- triangle:

  A `Triangle` object.

- min_n_cohorts:

  Minimum number of cohorts required to compute the dispersion; below
  this threshold the row is flagged `"sparse"` and `dispersion` is `NA`.
  Default `5L`.

## Value

data.table with columns `dev`, `n_cohorts`, `lr_median`, `lr_mad`,
`dispersion`, `flag` (and grouping columns when present).
