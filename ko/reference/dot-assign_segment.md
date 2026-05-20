# Assign each cohort to a regime segment

Maps a cohort vector to integer segment ids (`1, 2, ..., K+1`) given a
`"Regime"` object whose `$changes` carries `K` change points. A cohort
earlier than the first change is segment 1; between the k-th and
(k+1)-th change is segment k+1; on or after the K-th change is segment
K+1.

Returns `rep(1L, length(coh_vals))` when `regime` is `NULL` or carries
no changes – every cohort is in the single (sole) segment.

Treatment-agnostic: this helper preserves all change points regardless
of `regime$treatment`. Callers decide whether to use the full partition
(`"segment_wise"`) or collapse to the latest change (`"latest_only"`).

## Usage

``` r
.assign_segment(coh_vals, regime, grp_cols = NULL)
```

## Arguments

- coh_vals:

  Date vector of cohort values.

- regime:

  A `"Regime"` object or `NULL`.

- grp_cols:

  Optional `data.table` (`nrow == length(coh_vals)`) carrying the group
  columns named in `regime$groups`. Required when `regime` is
  multi-group; ignored otherwise. Each row's segment is computed against
  the change points for that row's group.

## Value

Integer vector of segment ids, same length as `coh_vals`.
