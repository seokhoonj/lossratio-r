# Filter a long-format table to recent calendar diagonals

Returns a subset of the input `data.table` containing only rows whose
calendar position falls within the last `recent` calendar diagonals of
its group.

The group-wise long-form condition is
`rank(cohort) + dev - 1 > max(rank(cohort) + dev - 1) - recent`.

## Usage

``` r
.apply_recent_filter(
  dt,
  recent,
  grp = character(0),
  coh,
  dev,
  dev_split = NULL
)
```

## Arguments

- dt:

  A long-format development `data.table`.

- recent:

  Positive integer or `NULL`. When `NULL` or missing, `dt` is returned
  unchanged.

- grp:

  Character vector of group columns (may be empty).

- coh:

  Single column name for the cohort variable (e.g. `cohort`).

- dev:

  Single column name for the development variable (e.g. `dev` for
  `Triangle` objects, or `ata_from` for `ATA`/`ED` objects).

- dev_split:

  Optional SA-boundary specifier. Accepts:

  - `NULL` – no SA boundary; the recent wedge applies to every row.

  - A single non-NA numeric scalar – the maturity target dev (=
    `ata_to`, the first CL-region dev). The recent filter is applied
    only to rows where `dev >= dev_split` (CL region); rows with
    `dev < dev_split` (ED region) are kept unconditionally.

  - A `data.table` `[grp..., dev_split]` – per-group SA boundary
    (different `k*` per group). The group columns must be a subset of
    `grp`. Each row of `dt` looks up its `dev_split` via left-join; rows
    whose group has no matching entry (NA after the join) are treated as
    if `dev_split = NULL` for that row (recent wedge applies to all dev
    for them).

## Value

A filtered copy of `dt` (class preserved), keeping only rows within the
recent-diagonal window.
