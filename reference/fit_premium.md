# Fit a chain ladder projection on the prem (exposure) triangle

Project cumulative prem across the cohort x development grid with a
chain ladder estimator. Two variance recursions are supported:

- `"ed"` (default):

  Additive recursion. Empirically more robust on long-projection prem
  triangles – the multiplicative scaling of the classical CL recursion
  can blow up under cohort-wise heterogeneity (regime changes in
  premium, channel changes, amendments). See `dev/prem_projection.qmd`.

- `"cl"`:

  Mack (1993) multiplicative recursion. Point projection identical to
  ED; only the SE accumulation differs.

Both methods share the same point estimate – self-weighted ED on prem is
mathematically equivalent to chain ladder on the same column
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
  conf_level = 0.95,
  bootstrap = NULL,
  B = 999,
  seed = NULL
)
```

## Arguments

- x:

  A `"Triangle"` object. The standardized `"prem"` column is used as the
  projection target.

- method:

  One of `"ed"` (default) or `"cl"`.

- alpha:

  Numeric scalar controlling the variance structure passed through to
  [`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md).
  Default `1`.

- regime:

  Optional regime specification (prem side). Accepts four input types:

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

  Pre-change cohorts (cohorts before the resolved `Regime`'s change
  date) are excluded from prem factor estimation.

- sigma_method:

  Sigma extrapolation method. One of `"locf"` (default), `"min_last2"`,
  or `"loglinear"`.

- recent:

  Optional positive integer; recent calendar-diagonal filter for the
  underlying ATA fit. Default `NULL`.

- tail:

  Logical; whether to apply a tail factor. Default `FALSE`.

- conf_level:

  Confidence level for analytical CI on the prem projection
  (`prem_ci_lo`, `prem_ci_hi`). Default `0.95`.

- bootstrap:

  Bootstrap configuration. Five forms accepted:

  `NULL` (default)

  :   Auto-resolved by `method`: bootstrap for `"ed"`, analytical for
      `"cl"`. Same behavior as the legacy `bootstrap = NULL` shape.

  `TRUE` / `FALSE`

  :   Back-compat with the legacy logical arg. `TRUE` triggers
      `bootstrap = "auto"`; `FALSE` disables.

  `"auto"`

  :   Internal
      [`bootstrap()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md)
      call on the premium triangle with defaults
      `(type = "parametric", process = "normal", target = "prem")`.

  `BootstrapTriangle`

  :   Pre-built object from
      [`bootstrap()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md).
      Must have `meta$target == "prem"`.

  Function `function(tri) -> BootstrapTriangle`

  :   Lazy spec invoked on the input Triangle (leakage-safe for
      [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)).

  Regardless of `method`, the bootstrap path uses CL recursion –
  premium's self-anchor makes ED and CL algebraically equivalent
  (`g_k = f_k - 1`, `sigma^2_g = sigma^2_f`).

- B:

  Integer number of bootstrap replicates. Used only when `bootstrap`
  resolves to `"auto"`. Default `999`.

- seed:

  Optional integer seed for reproducible bootstrap. Default `NULL`.

## Value

An object of class `"PremiumFit"` (a list with the same structure as
`CLFit`). Components: `selected`, `full`, `data`, plus attribute
`premium_method`. The `$full` data.table uses role-specific column names
(`prem_obs`, `prem_proj`, `incr_prem_proj`, `prem_proc_se`,
`prem_param_se`, `prem_total_se`, `prem_proc_cv`, `prem_param_cv`,
`prem_total_cv`, `prem_ci_lo`, `prem_ci_hi`). Under `bootstrap = TRUE`,
`prem_ci_lo` / `prem_ci_hi` are bootstrap quantiles and `prem_total_se`
/ `prem_total_cv` are derived from the simulation SD; the analytical
proc/param decomposition is retained as diagnostic.

## See also

[`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md),
[`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md),
[`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md),
[`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md).

## Examples

``` r
if (FALSE) { # \dontrun{
data(experience)
tri <- as_triangle(
  experience[coverage == "surgery"],
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  premium  = "incr_prem"
)

# ED-additive recursion (default; robust on long projections)
pf <- fit_premium(tri)
summary(pf)

# CL-multiplicative recursion (Mack)
pf_cl <- fit_premium(tri, method = "cl")
} # }
```
