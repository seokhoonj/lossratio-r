# E-Divisive change-point detection (Matteson & James 2014)

Nonparametric multivariate change-point detection via the energy
statistic. A greedy divisive procedure: within every open segment find
the split that maximises the energy distance, accept the globally
largest candidate when a permutation test clears `sig_level` (or, when
`k` is supplied, accept the `k` largest unconditionally), and recurse on
the two new segments.

## Usage

``` r
.e_divisive(X, k = NULL, sig_level = 0.05, min_size = 3L, R = 199L, alpha = 1)
```

## Arguments

- X:

  Numeric matrix of observations; rows are ordered observations.

- k:

  Optional integer count of change points to force. `NULL` (default)
  lets the permutation test decide how many to keep.

- sig_level:

  Permutation-test significance threshold; used only when `k` is `NULL`.

- min_size:

  Minimum size of either side of any split.

- R:

  Number of permutations per significance test.

- alpha:

  Distance exponent; `1` gives plain Euclidean distance.

## Value

A list: `breakpoints` (sorted regime-start row indices) and `p_values`
(permutation p-value per breakpoint; `NA` for forced breaks).

## Details

Written from the paper: Matteson, D. S. & James, N. A. (2014), "A
nonparametric approach for multiple change point analysis of
multivariate data", JASA 109(505), 334-345. The greedy recursion and its
per-break permutation test run in the native kernel `C_e_divisive`
(`src/e_divisive.c`) – this is a thin wrapper. Permutations draw from
R's RNG, so [`set.seed()`](https://rdrr.io/r/base/Random.html) controls
reproducibility.
