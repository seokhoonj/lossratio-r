# Summarise ED intensity statistics

Internal helper that computes group-wise summary statistics for
incremental loss intensity \\g\\ from a dual-variable `Link` object
(built with `exposure` set). Dispatched via
[`summary.Link()`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md)
when `model = "ed"`.

Two purposes:

1.  **Diagnostics**: provides descriptive statistics (`mean`, `median`,
    `wt`, `cv`) that help the user assess the stability and consistency
    of observed \\g\\ values across cohorts.

2.  **Estimation**: fits a no-intercept weighted least squares model per
    development link to produce the WLS-estimated intensity (`g`), its
    standard error (`g_se`), relative standard error (`rse`), and
    residual sigma (`sigma`). These are used downstream by
    [`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md).

## Usage

``` r
.summarize_link_ed(object, alpha = 1, digits = 5, ...)
```

## Arguments

- object:

  A `Link` object built with `exposure` set, typically produced by
  [`as_link()`](https://seokhoonj.github.io/lossratio/reference/as_link.md).

- alpha:

  Numeric scalar controlling the variance structure in the WLS fit.
  Default is `1`.

- digits:

  Number of decimal places to round numeric columns. Default is `5`.
  Pass `NULL` to skip rounding.

- ...:

  Additional arguments passed to the internal WLS estimation.

## Value

A `data.table` with class `"EDSummary"` containing one row per
development link with descriptive statistics and WLS estimates.

## Relationship between `wt` and `g`

Both `wt` and `g` are weighted averages of the observed intensities, but
they differ in how weights are assigned:

- `wt`:

  Exposure-weighted mean: \\wt = \sum \Delta C^L\_{i,k+1} / \sum
  C^P\_{i,k}\\. Computed from all rows where both values are finite.
  Independent of `alpha`.

- `g`:

  WLS-estimated intensity from `lm(target_delta ~ exposure_from + 0)`.
  Only rows where `exposure_from > 0` are used. When `alpha = 2`, `g`
  and `wt` are numerically equivalent.

## See also

[`as_link()`](https://seokhoonj.github.io/lossratio/reference/as_link.md),
[`summary.Link()`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md),
[`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md)
