# Coerce a Triangle to a Link object

Derive the development-link table from a `Triangle` and assign the
`Link` S3 class so the associated
[`summary.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md),
[`plot.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Link.md),
[`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md),
[`fit_intensity()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_intensity.md),
etc. methods dispatch on the result.

Unlike
[`as_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/as_triangle.md)
/
[`as_calendar()`](https://seokhoonj.github.io/lossratio/ko/reference/as_calendar.md)
/
[`as_total()`](https://seokhoonj.github.io/lossratio/ko/reference/as_total.md)
(which take raw experience data and validate/aggregate it), `as_link()`
operates *on a Triangle* (already validated upstream) and reshapes it
into link-pair rows. Each row corresponds to one development link
`(cohort, ata_from -> ata_to)`, the long-format intermediate underlying
both the chain ladder (CL) and exposure-driven (ED) workflows.

Two modes are produced depending on `exposure`:

- Single-variable mode (`exposure = NULL`):

  The age-to-age factor is \\ata = value\_{to} / value\_{from}\\, where
  \\value\\ is the column named by `target`.

- Dual-variable mode (`exposure` supplied):

  In addition to the loss-side ATA, the exposure-driven intensity \\g =
  \Delta loss / prem\_{from}\\ is computed and stored in the `intensity`
  column. Premium measure used as denominator for loss ratio
  calculations; for long-term health insurance applications, risk
  premium is commonly used.

## Usage

``` r
as_link(
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
  `"loss"`, `"prem"`, or `"lr"`. Default `"loss"`. Generic worker name;
  for loss-side ATA this is the cumulative loss column, but any
  cumulative metric on the Triangle may be supplied.

- exposure:

  Optional second cumulative metric, treated as the exposure anchor for
  the ED workflow. Must be one of `"loss"`, `"prem"`, `"lr"`, and must
  differ from `target`. When `NULL` (default), only the single-variable
  columns are produced.

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

- Always: `[group]`, `cohort`, `ata_from`, `ata_to`, `ata_link`,
  `target_from`, `target_to`, `target_delta`, `ata`.

- If `exposure` is set: also `exposure_from`, `exposure_to`,
  `exposure_delta`, `intensity`.

- If `weight` is set: also `weight`.

The returned object carries attributes `groups`, `cohort`, `dev`,
`target`, `exposure` (or `NULL`), `weight` (or `NULL`).

## See also

[`as_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/as_triangle.md),
[`summary.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md),
[`plot.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Link.md),
[`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md),
[`fit_ed()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ed.md)

## Examples

``` r
if (FALSE) { # \dontrun{
tri <- as_triangle(
  df,
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  prem     = "incr_prem"
)

# Single-variable: cumulative-loss link factors (ATA workflow)
link_loss <- as_link(tri, target = "loss")

# Dual-variable: ED-ready link table (loss + prem)
link_ed <- as_link(tri, target = "loss", exposure = "prem")
head(link_ed)
} # }
```
