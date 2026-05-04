# Apply regime-break (cohort) filter to a triangle-shaped data.table

Drops rows where `coh_var < break_date`. Optionally restrict the filter
to rows with `dev_var <= dev_max` (apply only to ED-phase cells); rows
with `dev_var > dev_max` are kept regardless of cohort.

## Usage

``` r
.apply_break_filter(
  dt,
  break_date,
  grp_var = character(0),
  coh_var,
  dev_var,
  dev_max = NULL
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

  - A `CohortRegime` object – extracts the latest from `$breakpoints`.

- grp_var:

  Character vector of group columns (may be empty).

- coh_var:

  Single column name for the cohort variable.

- dev_var:

  Single column name for the development variable.

- dev_max:

  Optional numeric scalar. When supplied, the cohort filter is only
  applied to rows where `dev_var <= dev_max`; rows with
  `dev_var > dev_max` are kept regardless of cohort.

## Value

A filtered copy of `dt` (class preserved).
