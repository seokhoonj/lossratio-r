# Apply LOCF NA-fill to per-link selected intensities

Initialises `g_selected` from the WLS-fitted `g` and optionally fills
`NA` runs via `data.table::nafill(type = "locf")`. Mirrors the fill
phase of
[`.filter_ata()`](https://seokhoonj.github.io/lossratio/reference/dot-filter_ata.md)
without the maturity gate (ED has no maturity concept).

## Usage

``` r
.select_intensity(
  ed_summary,
  grp = character(0),
  na_method = c("zero", "locf", "none")
)
```

## Arguments

- ed_summary:

  An `EDSummary`.

- grp:

  Character vector of group columns.

- na_method:

  One of `"locf"` (default) or `"none"`.

## Value

A `data.table` with `g_selected` added.
