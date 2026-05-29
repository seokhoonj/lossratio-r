# Filter and fill age-to-age factors for projection

Internal helper that produces a `f_sel` column by applying two steps:

1.  **Filter** – when `use_maturity = TRUE`, development links that
    precede the maturity point are excluded (`f_sel` set to `NA`).

2.  **Fill** – `NA` values in `f_sel` are forward-filled using LOCF, so
    that every link used in projection has a finite factor.

## Usage

``` r
.filter_ata(
  ata_summary,
  maturity = NULL,
  use_maturity = FALSE,
  groups = character(0),
  na_method = c("locf", "none")
)
```

## Arguments

- ata_summary:

  A `data.table` of class `"ATASummary"` from
  [`summary.Link()`](https://seokhoonj.github.io/lossratio-r/reference/summary.Link.md)
  with `model = "ata"`.

- maturity:

  A `data.table` from
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio-r/reference/detect_maturity.md),
  or `NULL` when `use_maturity = FALSE`.

- use_maturity:

  Logical; if `TRUE`, apply the maturity filter. When `FALSE`,
  `maturity` is ignored entirely.

- groups:

  Character vector of grouping variable names.

- na_method:

  One of `"locf"` or `"none"`.

## Value

A `data.table` with `selected` and `f_sel` columns added.
