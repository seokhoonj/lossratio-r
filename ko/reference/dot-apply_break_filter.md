# Apply regime-break (cohort) filter to a triangle-shaped data.table

Drops rows where `coh_var < break_date`. Optionally restrict the filter
to rows with `dev_var < dev_split` (the ED region of an SA fit); rows
with `dev_var >= dev_split` (CL region) are kept regardless of cohort.

## Usage

``` r
.apply_break_filter(
  dt,
  break_date,
  group_var = character(0),
  cohort_var,
  dev_var,
  dev_split = NULL
)
```

## Arguments

- dt:

  A data.table.

- break_date:

  The cohort cutoff. Accepts:

  - `NULL` – no filter (return copy of `dt` unchanged).

  - A single Date or character (coercible to Date).

  - A Date/character vector – uses the latest (max) date.

  - A `Regime` object – extracts the latest from `$breakpoints`.

- group_var:

  Character vector of group columns (may be empty).

- cohort_var:

  Single column name for the cohort variable.

- dev_var:

  Single column name for the development variable.

- dev_split:

  Optional numeric scalar — the maturity target dev (= `ata_to`,
  equivalently the first CL-region dev). When supplied, the cohort
  filter is only applied to rows where `dev_var < dev_split` (ED
  region); rows with `dev_var >= dev_split` (CL region) are kept
  regardless of cohort.

## Value

A filtered copy of `dt` (class preserved).
