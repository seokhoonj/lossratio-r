# Validate triangle structure before building a development

Check that each `(groups, cohort)` cohort has a consecutive `dev`
sequence within its observed range. Non-consecutive cohorts produce
non-consecutive age-to-age links downstream (e.g., `14 -> 17` instead of
`14 -> 15`), which breaks
[`summary.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md)
key uniqueness and causes cartesian joins in
[`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md).

This function inspects the raw data without modifying it. Use it before
[`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md)
to decide whether to fix the data source, drop offending cohorts, or
pass `fill_gaps = TRUE` to
[`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md).

Two checks are performed:

1.  **Cohort dev-sequence gaps** — for each `(group, cohort)`, report
    missing `dev` values within the observed range.

2.  **Row-level calendar consistency** — when `calendar` is supplied (or
    auto-detected as `"cy_m"` if present), report rows where
    `calendar < cohort`. Such rows are logically impossible (claims
    cannot precede policy issue) and downstream they show up as negative
    `dev_m`, polluting cohort dev sequences.

## Usage

``` r
validate_triangle(df, groups, cohort, dev, calendar = NULL)
```

## Arguments

- df:

  A data.frame.

- groups:

  Grouping variable(s).

- cohort:

  A single cohort variable (raw column name).

- dev:

  A single development variable (raw column name).

- calendar:

  Optional calendar period variable for row-level consistency check.
  When supplied, rows where `calendar < cohort` are flagged as invalid.
  Default `NULL` (skip this check).

## Value

A `data.table` of class `"TriangleValidation"` with one row per cohort
containing gaps. Columns:

- groups, cohort:

  Cohort identifier.

- `n_observed`:

  Number of distinct observed `dev` values.

- `n_expected`:

  `max(dev) - min(dev) + 1` for that cohort.

- `missing`:

  List column of missing `dev` values.

Returns a zero-row data.table when no gaps are found.

Row-level violations (when `calendar` is supplied and the check finds
any) are attached as the `"invalid_rows"` attribute — a `data.table`
with columns `[groups, cohort, calendar, dev (if present), reason]`. Use
`attr(out, "invalid_rows")` or rely on `print.TriangleValidation` which
displays both sections.

## See also

[`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md)
