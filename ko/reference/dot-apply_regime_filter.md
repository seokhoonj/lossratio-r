# Apply regime-change (cohort) filter to a triangle-shaped data.table

Drops rows where `coh < break_date`. Optionally restrict the filter to
rows with `dev < dev_split` (the ED region of an SA fit); rows with
`dev >= dev_split` (CL region) are kept regardless of cohort.

Supports both **scalar** dispatch (single break date applied to every
row) and **per-group** dispatch (different break date per group,
broadcast via left-join). The mode is auto-selected from `regime` and
`grp`: a multi-group `Regime` whose `$groups` intersect `grp` triggers
the per-group path. Groups in `dt` that have no matching break date (NA
after the left-join) are kept unfiltered.

## Usage

``` r
.apply_regime_filter(
  dt,
  regime,
  grp = character(0),
  coh,
  dev,
  dev_split = NULL
)
```

## Arguments

- dt:

  A data.table.

- regime:

  The cohort cutoff. Accepts:

  - `NULL` – no filter (return copy of `dt` unchanged).

  - A single Date or character (coercible to Date).

  - A Date/character vector – uses the latest (max) date.

  - A single-group `Regime` object – extracts the latest from
    `$changes`.

  - A multi-group `Regime` object – dispatches per group on the
    intersection of `Regime$groups` and `grp`.

- grp:

  Character vector of group columns (may be empty).

- coh:

  Single column name for the cohort variable.

- dev:

  Single column name for the development variable.

- dev_split:

  Optional numeric scalar — the maturity target dev (= `ata_to`,
  equivalently the first CL-region dev). When supplied, the cohort
  filter is only applied to rows where `dev < dev_split` (ED region);
  rows with `dev >= dev_split` (CL region) are kept regardless of
  cohort.

## Value

A filtered copy of `dt` (class preserved).
