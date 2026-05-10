# Validate triangle structure before building a development

Check that each `(group_var, cohort_var)` cohort has a consecutive
`dev_var` sequence within its observed range. Non-consecutive cohorts
produce non-consecutive age-to-age links downstream (e.g., `14 -> 17`
instead of `14 -> 15`), which breaks
[`summary.Link()`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md)
key uniqueness and causes cartesian joins in
[`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md).

This function inspects the raw data without modifying it. Use it before
[`build_triangle()`](https://seokhoonj.github.io/lossratio/reference/build_triangle.md)
to decide whether to fix the data source, drop offending cohorts, or
pass `fill_gaps = TRUE` to
[`build_triangle()`](https://seokhoonj.github.io/lossratio/reference/build_triangle.md).

Two checks are performed:

1.  **Cohort dev-sequence gaps** — for each `(group, cohort)`, report
    missing `dev_var` values within the observed range.

2.  **Row-level calendar consistency** — when `calendar_var` is supplied
    (or auto-detected as `"cy_m"` if present), report rows where
    `calendar_var < cohort_var`. Such rows are logically impossible
    (claims cannot precede policy issue) and downstream they show up as
    negative `dev_m`, polluting cohort dev sequences.

## Usage

``` r
validate_triangle(
  df,
  group_var,
  cohort_var = "uy_m",
  dev_var = "dev_m",
  calendar_var = "cy_m"
)
```

## Arguments

- df:

  A data.frame.

- group_var:

  Grouping variable(s).

- cohort_var:

  A single cohort variable. Default `"uy_m"`.

- dev_var:

  A single development variable. Default `"dev_m"`.

- calendar_var:

  Optional calendar period variable for row-level consistency check.
  When supplied, rows where `calendar_var < cohort_var` are flagged as
  invalid. Default `"cy_m"`; pass `NULL` to skip this check, or a column
  name to override.

## Value

A `data.table` of class `"TriangleValidation"` with one row per cohort
containing gaps. Columns:

- group_var(s), cohort_var:

  Cohort identifier.

- `n_observed`:

  Number of distinct observed `dev_var` values.

- `n_expected`:

  `max(dev_m) - min(dev_m) + 1` for that cohort.

- `missing`:

  List column of missing `dev_var` values.

Returns a zero-row data.table when no gaps are found.

Row-level violations (when `calendar_var` is supplied and the check
finds any) are attached as the `"invalid_rows"` attribute — a
`data.table` with columns
`[group_var, cohort_var, calendar_var, dev_var (if present), reason]`.
Use `attr(out, "invalid_rows")` or rely on `print.TriangleValidation`
which displays both sections.

## See also

[`build_triangle()`](https://seokhoonj.github.io/lossratio/reference/build_triangle.md)
