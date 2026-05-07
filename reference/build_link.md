# Build a link table from `Triangle` data

Construct a development-link table from an object of class `Triangle`,
typically produced by
[`build_triangle()`](https://seokhoonj.github.io/lossratio/reference/build_triangle.md).
The link table is the long-format intermediate underlying both the chain
ladder (CL) and exposure-driven (ED) workflows. Each row corresponds to
one development link `(cohort, ata_from -> ata_to)`.

Two modes are produced depending on `exposure_var`:

- Single-variable mode (`exposure_var = NULL`):

  Replaces the former `build_ata()`. The age-to-age factor is \\ata =
  value\_{to} / value\_{from}\\.

- Dual-variable mode (`exposure_var` supplied):

  Replaces the former `build_ed()`. In addition to the loss-side ATA,
  the exposure-driven intensity \\g = \Delta value / exposure\_{from}\\
  is computed.

## Usage

``` r
build_link(
  x,
  value_var = "closs",
  exposure_var = NULL,
  weight_var = NULL,
  min_denom = 0,
  drop_invalid = FALSE
)
```

## Arguments

- x:

  A `Triangle` object.

- value_var:

  A single cumulative metric used as the link numerator. Must be one of
  `"closs"`, `"crp"`, or `"clr"`. Default `"closs"`.

- exposure_var:

  Optional second cumulative metric, treated as the exposure anchor for
  the ED workflow. Must be one of `"closs"`, `"crp"`, `"clr"`, and must
  differ from `value_var`. When `NULL` (default), only the
  single-variable columns are produced.

- weight_var:

  Optional cumulative metric used as WLS weight in downstream `summary`
  / `fit_ata` calls. Must differ from `value_var`. Cannot be combined
  with `exposure_var` (the dual workflow has its own anchor).

- min_denom:

  Minimum denominator required to compute `ata` and `g`. If
  `value_from <= min_denom`, `ata` becomes `NA`; if
  `exposure_from <= min_denom`, `g` becomes `NA`. Default `0`.

- drop_invalid:

  Logical; if `TRUE`, rows with non-finite `ata` (single-var) or
  non-finite `g` (dual-var) are dropped. Default `FALSE` so the full
  link grid is preserved for diagnostics.

## Value

A `data.table` of class `"Link"` with columns:

- Always: `[group_var]`, `cohort`, `ata_from`, `ata_to`, `ata_link`,
  `value_from`, `value_to`, `delta_value`, `ata`.

- If `exposure_var` is set: also `exposure_from`, `exposure_to`,
  `delta_exposure`, `g`.

- If `weight_var` is set: also `weight`.

The returned object carries attributes `group_var`, `cohort_var`,
`cohort_type`, `dev_var`, `dev_type`, `value_var`, `exposure_var` (or
`NULL`), `weight_var` (or `NULL`).

## See also

[`build_triangle()`](https://seokhoonj.github.io/lossratio/reference/build_triangle.md),
[`summary.Link()`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md),
[`plot.Link()`](https://seokhoonj.github.io/lossratio/reference/plot.Link.md),
[`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md),
[`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md)

## Examples

``` r
if (FALSE) { # \dontrun{
tri <- build_triangle(df, group_var = cv_nm)

# Single-variable: closs link factors (ATA workflow)
link_loss <- build_link(tri, value_var = "closs")

# Dual-variable: ED-ready link table (loss + exposure)
link_ed <- build_link(tri, value_var = "closs", exposure_var = "crp")
head(link_ed)
} # }
```
