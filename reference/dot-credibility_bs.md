# Buehlmann-Straub credibility weight per cohort

Compute the per-cohort Buehlmann-Straub credibility factor

\$\$Z_i = \frac{K}{K + s_i^2}\$\$

that replaces the emergence fraction \\q_i\\ as the BF / CC blend
weight. \\s_i^2\\ is the variance of cohort \\i\\'s own chain ladder
loss-ratio estimate, and \\K\\ is the variance of the hypothetical means
(VHM) – the genuine between-cohort spread of the true loss ratios. This
is the standard credibility form \\Z = \tau^2 / (\tau^2 + \sigma^2/w)\\
written directly in terms of the per-cohort estimate variance.

The classical weight `q` only measures *how much has emerged*; a
rare-event or very green cohort can have a high `q` yet a chain ladder
estimate built on almost no data. There \\s_i^2\\ is large, so \\Z_i \to
0\\ and the cohort is pulled toward the prior – exactly the protection
the credibility blend is meant to give.

## Usage

``` r
.credibility_bs(per_cohort, groups, K = NULL)
```

## Arguments

- per_cohort:

  A `data.table` with one row per cohort carrying `by_cols`, `lr`
  (cohort CL ultimate loss ratio), and `s2` (the variance of that
  loss-ratio estimate).

- groups:

  Group column character vector.

- K:

  `NULL` (estimate the VHM per group) or a non-negative numeric scalar
  overriding it.

## Value

`per_cohort` with added columns `K` (the VHM scale used) and `Z` (the
credibility weight).
