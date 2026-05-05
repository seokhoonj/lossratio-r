# Filter a long-format table to recent calendar diagonals

Internal long-format analogue of
[`get_recent_weights()`](https://seokhoonj.github.io/lossratio/reference/get_recent_weights.md).
Returns a subset of the input `data.table` containing only rows whose
calendar position falls within the last `recent` calendar diagonals of
its group.

The matrix-form condition `row + col >= m - recent + 2` is translated to
the group-wise long-form condition
`rank(cohort) + dev - 1 > max(rank(cohort) + dev - 1) - recent`.

## Usage

``` r
.apply_recent_filter(
  dt,
  recent,
  group_var = character(0),
  cohort_var,
  dev_var,
  dev_min = NULL
)
```

## Arguments

- dt:

  A long-format development `data.table`.

- recent:

  Positive integer or `NULL`. When `NULL` or missing, `dt` is returned
  unchanged.

- group_var:

  Character vector of group columns (may be empty).

- cohort_var:

  Single column name for the cohort variable (e.g. `cohort`).

- dev_var:

  Single column name for the development variable (e.g. `dev` for
  `Triangle` objects, or `ata_from` for `ATA`/`ED` objects).

- dev_min:

  Optional numeric scalar. When supplied, the recent filter is applied
  only to rows where `dev_var > dev_min`; rows with `dev_var <= dev_min`
  are kept unconditionally (early-dev cells in the ED phase of
  stage-adaptive fits).

## Value

A filtered copy of `dt` (class preserved), keeping only rows within the
recent-diagonal window.
