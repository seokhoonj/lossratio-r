# Build a link table from `Triangle` data

Construct a development-link table from an object of class `Triangle`,
typically produced by
[`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md).
The link table is the long-format intermediate underlying both the chain
ladder (CL) and exposure-driven (ED) workflows. Each row corresponds to
one development link `(cohort, ata_from -> ata_to)`.

Two modes are produced depending on `exposure`:

- Single-variable mode (`exposure = NULL`):

  The age-to-age factor is \\ata = value\_{to} / value\_{from}\\, where
  \\value\\ is the column named by `target`.

- Dual-variable mode (`exposure` supplied):

  In addition to the loss-side ATA, the exposure-driven intensity \\g =
  \Delta loss / premium\_{from}\\ is computed and stored in the
  `intensity` column. Premium measure used as denominator for loss ratio
  calculations; for long-term health insurance applications, risk
  premium is commonly used.

## Usage

``` r
build_link(
  x,
  target = "loss",
  exposure = NULL,
  weight = NULL,
  min_denom = 0,
  drop_invalid = FALSE
)
```

## Arguments

- x:

  A `Triangle` object.

- target:

  A single cumulative metric used as the link numerator. Must be one of
  `"loss"`, `"premium"`, or `"lr"`. Default `"loss"`. Generic worker
  name; for loss-side ATA this is the cumulative loss column, but any
  cumulative metric on the Triangle may be supplied.

- exposure:

  Optional second cumulative metric, treated as the exposure anchor for
  the ED workflow. Must be one of `"loss"`, `"premium"`, `"lr"`, and
  must differ from `target`. When `NULL` (default), only the
  single-variable columns are produced.

- weight:

  Optional cumulative metric used as WLS weight in downstream `summary`
  / `fit_ata` calls. Must differ from `target`. Cannot be combined with
  `exposure` (the dual workflow has its own anchor).

- min_denom:

  Minimum denominator required to compute `ata` and `intensity`. If
  `target_from <= min_denom`, `ata` becomes `NA`; if
  `exposure_from <= min_denom`, `intensity` becomes `NA`. Default `0`.

- drop_invalid:

  Logical; if `TRUE`, rows with non-finite `ata` (single-var) or
  non-finite `intensity` (dual-var) are dropped. Default `FALSE` so the
  full link grid is preserved for diagnostics.

## Value

A `data.table` of class `"Link"` with columns:

- Always: `[group_var]`, `cohort`, `ata_from`, `ata_to`, `ata_link`,
  `target_from`, `target_to`, `target_delta`, `ata`.

- If `exposure` is set: also `exposure_from`, `exposure_to`,
  `exposure_delta`, `intensity`.

- If `weight` is set: also `weight`.

The returned object carries attributes `group_var`, `cohort_var`,
`dev_var`, `target`, `exposure` (or `NULL`), `weight` (or `NULL`).

## See also

[`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md),
[`summary.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md),
[`plot.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Link.md),
[`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md),
[`fit_ed()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ed.md)

## Examples

``` r
if (FALSE) { # \dontrun{
tri <- build_triangle(df, group_var = coverage)

# Single-variable: cumulative-loss link factors (ATA workflow)
link_loss <- build_link(tri, target = "loss")

# Dual-variable: ED-ready link table (loss + premium)
link_ed <- build_link(tri, target = "loss", exposure = "premium")
head(link_ed)
} # }
```
