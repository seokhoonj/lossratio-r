# Build a link table from `Triangle` data

Construct a development-link table from an object of class `Triangle`,
typically produced by
[`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md).
The link table is the long-format intermediate underlying both the chain
ladder (CL) and exposure-driven (ED) workflows. Each row corresponds to
one development link `(cohort, ata_from -> ata_to)`.

Two modes are produced depending on `premium_var`:

- Single-variable mode (`premium_var = NULL`):

  The age-to-age factor is \\ata = value\_{to} / value\_{from}\\, where
  \\value\\ is the column named by `loss_var`.

- Dual-variable mode (`premium_var` supplied):

  In addition to the loss-side ATA, the exposure-driven intensity \\g =
  \Delta loss / premium\_{from}\\ is computed. Premium measure used as
  denominator for loss ratio calculations; for long-term health
  insurance applications, risk premium is commonly used.

## Usage

``` r
build_link(
  x,
  loss_var = "loss",
  premium_var = NULL,
  weight_var = NULL,
  min_denom = 0,
  drop_invalid = FALSE
)
```

## Arguments

- x:

  A `Triangle` object.

- loss_var:

  A single cumulative metric used as the link numerator. Must be one of
  `"loss"`, `"premium"`, or `"lr"`. Default `"loss"`. Despite the name,
  this argument accepts any cumulative metric on the Triangle; `"loss"`
  reflects the most common use.

- premium_var:

  Optional second cumulative metric, treated as the exposure anchor for
  the ED workflow. Must be one of `"loss"`, `"premium"`, `"lr"`, and
  must differ from `loss_var`. When `NULL` (default), only the
  single-variable columns are produced.

- weight_var:

  Optional cumulative metric used as WLS weight in downstream `summary`
  / `fit_ata` calls. Must differ from `loss_var`. Cannot be combined
  with `premium_var` (the dual workflow has its own anchor).

- min_denom:

  Minimum denominator required to compute `ata` and `g`. If
  `value_from <= min_denom`, `ata` becomes `NA`; if
  `premium_from <= min_denom`, `g` becomes `NA`. Default `0`.

- drop_invalid:

  Logical; if `TRUE`, rows with non-finite `ata` (single-var) or
  non-finite `g` (dual-var) are dropped. Default `FALSE` so the full
  link grid is preserved for diagnostics.

## Value

A `data.table` of class `"Link"` with columns:

- Always: `[group_var]`, `cohort`, `ata_from`, `ata_to`, `ata_link`,
  `value_from`, `value_to`, `delta_value`, `ata`.

- If `premium_var` is set: also `premium_from`, `premium_to`,
  `delta_premium`, `g`.

- If `weight_var` is set: also `weight`.

The returned object carries attributes `group_var`, `cohort_var`,
`cohort_type`, `dev_var`, `dev_type`, `loss_var`, `premium_var` (or
`NULL`), `weight_var` (or `NULL`).

## See also

[`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md),
[`summary.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md),
[`plot.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Link.md),
[`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md),
[`fit_ed()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ed.md)

## Examples

``` r
if (FALSE) { # \dontrun{
tri <- build_triangle(df, group_var = cv_nm)

# Single-variable: cumulative-loss link factors (ATA workflow)
link_loss <- build_link(tri, loss_var = "loss")

# Dual-variable: ED-ready link table (loss + premium)
link_ed <- build_link(tri, loss_var = "loss", premium_var = "premium")
head(link_ed)
} # }
```
