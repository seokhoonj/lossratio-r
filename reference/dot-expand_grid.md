# Expand a `Triangle` object to a full projection grid (loss + premium)

Internal helper used by
[`fit_sa()`](https://seokhoonj.github.io/lossratio/reference/fit_sa.md)
and
[`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md).
Builds a complete cohort x dev grid plus the projected premium path (CL
projection anchored on the supplied `premium_ata_fit`). The ED loss-side
projection is added downstream by the caller.

Lives here because both
[`fit_sa()`](https://seokhoonj.github.io/lossratio/reference/fit_sa.md)
(R/sa.R) and
[`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md)
(R/ed.R) need a single source of truth for the grid layout. Future
cleanup may relocate it to a dedicated helper file.

## Usage

``` r
.expand_grid(triangle, ed_fit, premium_ata_fit, loss, premium)
```
