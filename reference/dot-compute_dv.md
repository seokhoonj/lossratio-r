# Robust cross-cohort dispersion of incremental loss ratio

Internal helper. For each (group, dev) cell of a `Triangle`, computes a
robust scale-invariant dispersion of incremental loss ratio across
cohorts:

\$\$\hat{D}\_v = \frac{1.4826 \cdot
\mathrm{MAD}\_i(lr\_{i,v})}{\|\mathrm{median}\_i(lr\_{i,v})\|}\$\$

Operating on `lr` (incremental) rather than `lr` keeps the metric
inertia-free.

## Usage

``` r
.compute_dv(triangle, min_n_cohorts = 5L)
```

## Arguments

- triangle:

  A `Triangle` object.

- min_n_cohorts:

  Minimum number of cohorts required to compute `D_v`; below this
  threshold the row is flagged `"sparse"` and `D_v` is `NA`. Default
  `5L`.

## Value

data.table with columns `dev`, `n_cohorts`, `median_lr`, `mad_lr`,
`D_v`, `flag` (and grouping columns when present).
