# Coerce a Triangle to a Link object

Derive the development-link table from a `Triangle` and assign the
`Link` S3 class so the associated
[`summary.Link()`](https://seokhoonj.github.io/lossratio-r/reference/summary.Link.md),
[`plot.Link()`](https://seokhoonj.github.io/lossratio-r/reference/plot.Link.md),
[`fit_ata()`](https://seokhoonj.github.io/lossratio-r/reference/fit_ata.md),
[`fit_intensity()`](https://seokhoonj.github.io/lossratio-r/reference/fit_intensity.md),
etc. methods dispatch on the result.

Unlike
[`as_triangle()`](https://seokhoonj.github.io/lossratio-r/reference/as_triangle.md)
/
[`as_calendar()`](https://seokhoonj.github.io/lossratio-r/reference/as_calendar.md)
/
[`as_total()`](https://seokhoonj.github.io/lossratio-r/reference/as_total.md)
(which take raw experience data and validate/aggregate it), `as_link()`
operates *on a Triangle* (already validated upstream) and reshapes it
into link-pair rows. Each row corresponds to one development link
`(cohort, ata_from -> ata_to)`, the long-format intermediate underlying
both the chain ladder (CL) and exposure-driven (ED) workflows.

Two modes are produced depending on `exposure`:

- Single-variable mode (`exposure = NULL`):

  The age-to-age factor is \\ata = value\_{to} / value\_{from}\\, where
  \\value\\ is the column named by `loss`.

- Dual-variable mode (`exposure` supplied):

  In addition to the loss-side ATA, the exposure-driven intensity \\g =
  \Delta loss / premium\_{from}\\ is computed and stored in the
  `intensity` column. The exposure measure is the denominator for loss
  ratio calculations; for long-term health insurance applications, risk
  premium is commonly used.

## Usage

``` r
as_link(
  x,
  loss = "loss",
  exposure = NULL,
  weight = NULL,
  min_denom = 0,
  drop_invalid = FALSE
)
```

## Arguments

- x:

  A `Triangle` object.

- loss:

  A single cumulative metric used as the link numerator. Must be one of
  `"loss"`, `"premium"`, or `"ratio"`. Default `"loss"`. For loss-side
  ATA this is the cumulative loss column, but any cumulative metric on
  the Triangle may be supplied.

- exposure:

  Optional second cumulative metric, treated as the exposure base
  (denominator anchor) for the ED workflow. Must be one of `"loss"`,
  `"premium"`, `"ratio"`, and must differ from `loss`. When `NULL`
  (default), only the single-variable columns are produced.

- weight:

  Optional cumulative metric used as WLS weight in downstream `summary`
  / `fit_ata` calls. Must differ from `loss`. Cannot be combined with
  `exposure` (the dual workflow has its own anchor).

- min_denom:

  Minimum denominator required to compute `ata` and `intensity`. If
  `loss_from <= min_denom`, `ata` becomes `NA`; if
  `premium_from <= min_denom`, `intensity` becomes `NA`. Default `0`.

- drop_invalid:

  Logical; if `TRUE`, rows with non-finite `ata` (single-var) or
  non-finite `intensity` (dual-var) are dropped. Default `FALSE` so the
  full link grid is preserved for diagnostics.

## Value

A `data.table` of class `"Link"` with columns:

- Always: `[group]`, `cohort`, `ata_from`, `ata_to`, `ata_link`,
  `loss_from`, `loss_to`, `loss_delta`, `ata`.

- If `exposure` is set: also `premium_from`, `premium_to`,
  `premium_delta`, `intensity`.

- If `weight` is set: also `weight`.

The returned object carries attributes `groups`, `cohort`, `dev`,
`loss`, `premium` (or `NULL`), `weight` (or `NULL`).

## See also

[`as_triangle()`](https://seokhoonj.github.io/lossratio-r/reference/as_triangle.md),
[`summary.Link()`](https://seokhoonj.github.io/lossratio-r/reference/summary.Link.md),
[`plot.Link()`](https://seokhoonj.github.io/lossratio-r/reference/plot.Link.md),
[`fit_ata()`](https://seokhoonj.github.io/lossratio-r/reference/fit_ata.md),
[`fit_ed()`](https://seokhoonj.github.io/lossratio-r/reference/fit_ed.md)

## Examples

``` r
if (FALSE) { # \dontrun{
tri <- as_triangle(
  df,
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  premium  = "incr_premium"
)

# Single-variable: cumulative-loss link factors (ATA workflow)
link_loss <- as_link(tri, loss = "loss")

# Dual-variable: ED-ready link table (loss + premium)
link_ed <- as_link(tri, loss = "loss", exposure = "premium")
head(link_ed)
} # }
```
