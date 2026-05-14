# Coerce experience data to a Total object

Validate raw experience data, aggregate it to a single scalar row per
group (collapsing both the cohort and development axes), and assign the
`Total` S3 class so the associated
[`plot.Total()`](https://seokhoonj.github.io/lossratio/reference/plot.Total.md)
bar chart and other Total methods dispatch on the result.

Compared with
[`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md)
(two-dimensional `cohort x dev`) and
[`as_calendar()`](https://seokhoonj.github.io/lossratio/reference/as_calendar.md)
(one-dimensional time series), `as_total()` is *zero-dimensional* per
group – one row of portfolio aggregates. The typical use is high-level
portfolio comparison across products, coverages, or channels.

Total summarises:

- the number of observed cohorts (`n_cohorts`)

- the first and last observed cohort periods (`sales_start`,
  `sales_end`)

- total `loss` and total `prem` (sum over all cells)

- total loss ratio (`lr = loss / prem`)

- each group's share of total loss and total prem

Pre-filter the Triangle (e.g. by cohort range or coverage) before
calling `as_total()` if a subset summary is needed.

## Usage

``` r
as_total(x)
```

## Arguments

- x:

  A `Triangle` object (typically from
  [`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md)).

## Value

A data.frame with class `"Total"` containing:

- n_cohorts:

  Number of observed development periods

- sales_start:

  First observed period

- sales_end:

  Last observed period

- loss:

  Total loss

- prem:

  Total prem

- lr:

  Total loss ratio (`loss / prem`)

- loss_share:

  Share of total loss

- prem_share:

  Share of total prem

## Examples

``` r
if (FALSE) { # \dontrun{
tri <- as_triangle(
  experience,
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  premium  = "incr_prem"
)
as_total(tri)
} # }
```
