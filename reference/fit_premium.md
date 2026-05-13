# Fit a chain ladder projection on the premium (exposure) triangle

Project cumulative premium across the cohort x development grid with a
chain ladder estimator. Two variance recursions are supported:

- `"ed"` (default):

  Additive recursion. Empirically more robust on long-projection premium
  triangles – the multiplicative scaling of the classical CL recursion
  can blow up under cohort-wise heterogeneity (regime breaks in premium,
  channel changes, amendments). See `dev/premium_projection.qmd`.

- `"cl"`:

  Mack (1993) multiplicative recursion. Point projection identical to
  ED; only the SE accumulation differs.

Both methods share the same point estimate – self-weighted ED on premium
is mathematically equivalent to chain ladder on the same column
(`f_k = 1 + g_k`). The only operational difference is how cumulative
variance is propagated forward.

## Usage

``` r
fit_premium(
  x,
  method = c("ed", "cl"),
  alpha = 1,
  regime = NULL,
  sigma_method = c("locf", "min_last2", "loglinear"),
  recent = NULL,
  tail = FALSE,
  conf_level = 0.95
)
```

## Arguments

- x:

  A `"Triangle"` object. The standardized `"premium"` column is used as
  the projection target.

- method:

  One of `"ed"` (default) or `"cl"`.

- alpha:

  Numeric scalar controlling the variance structure passed through to
  [`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md).
  Default `1`.

- regime:

  Optional regime specification (premium side). Accepts four input
  types:

  `NULL` (default)

  :   No regime filter.

  `Regime` object

  :   Use as-is. Typically built via
      [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
      or
      [`regime_at()`](https://seokhoonj.github.io/lossratio/reference/regime_at.md).

  `"auto"`

  :   Detect regime internally via `detect_regime(x, target = "lr")` on
      the input triangle.

  Function / closure

  :   A user-supplied `function(tri) -> Regime` for deferred
      custom-config detection.

  Pre-break cohorts (cohorts before the resolved `Regime`'s breakpoint)
  are excluded from premium factor estimation.

- sigma_method:

  Sigma extrapolation method. One of `"locf"` (default), `"min_last2"`,
  or `"loglinear"`.

- recent:

  Optional positive integer; recent calendar-diagonal filter for the
  underlying ATA fit. Default `NULL`.

- tail:

  Logical; whether to apply a tail factor. Default `FALSE`.

- conf_level:

  Confidence level for analytical CI on the premium projection
  (`premium_ci_lower`, `premium_ci_upper`). Default `0.95`.

## Value

An object of class `"PremiumFit"` (a list with the same structure as
`CLFit`). Components: `selected`, `full`, `data`, plus attribute
`premium_method`. The `$full` data.table uses role-specific column names
(`premium_obs`, `premium_proj`, `premium_incr_proj`, `premium_proc_se`,
`premium_param_se`, `premium_total_se`, `premium_proc_cv`,
`premium_param_cv`, `premium_total_cv`, `premium_ci_lower`,
`premium_ci_upper`).

## See also

[`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md),
[`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md),
[`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md),
[`build_triangle()`](https://seokhoonj.github.io/lossratio/reference/build_triangle.md).

## Examples

``` r
if (FALSE) { # \dontrun{
data(experience)
tri <- build_triangle(
  experience[coverage == "SUR"],
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "loss_incr",
  premium  = "premium_incr"
)

# ED-additive recursion (default; robust on long projections)
pf <- fit_premium(tri)
summary(pf)

# CL-multiplicative recursion (Mack)
pf_cl <- fit_premium(tri, method = "cl")
} # }
```
