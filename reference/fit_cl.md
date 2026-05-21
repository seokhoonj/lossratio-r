# Fit chain ladder projection from a `Triangle` object

Fit a Mack (1993) chain ladder projection from an object of class
`"Triangle"`. The function works on long-form cumulative data and does
not require a complete triangle. Age-to-age factors are estimated
through
[`as_link()`](https://seokhoonj.github.io/lossratio/reference/as_link.md)
and
[`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md),
then applied recursively. The point forecast follows the standard
recursion, and prediction uncertainty is decomposed into process
variance and parameter variance.

When `weight` is supplied (e.g. `"premium"`), age-to-age factors and
their variance are estimated using the supplied WLS weights.

## Usage

``` r
fit_cl(
  x,
  method = c("mack"),
  loss = "loss",
  weight = NULL,
  alpha = 1,
  sigma_method = c("locf", "min_last2", "loglinear", "mack", "none"),
  recent = NULL,
  regime = NULL,
  maturity = NULL,
  tail = FALSE,
  bootstrap = NULL,
  B = 999L,
  seed = NULL,
  conf_level = 0.95
)
```

## Arguments

- x:

  An object of class `"Triangle"`.

- method:

  One of `"mack"`. Default is `"mack"`. The argument is retained for
  future extensibility.

- loss:

  A single cumulative loss variable (column to project). Typical choices
  are `"loss"`, `"premium"`, or `"ratio"`.

- weight:

  An optional column name passed to
  [`as_link()`](https://seokhoonj.github.io/lossratio/reference/as_link.md)
  as the WLS weight variable. Typically `"premium"` when
  `loss = "ratio"`. Default is `NULL`.

- alpha:

  Numeric scalar controlling the variance structure in
  [`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md).
  Default is `1`.

- sigma_method:

  Method used to extrapolate `sigma` for links where it cannot be
  estimated. One of `"locf"` (default), `"min_last2"`, `"loglinear"`,
  `"mack"`, or `"none"`. `"mack"` applies the Mack (1993, Appendix B)
  tail estimator to the last unestimated link only, falling back to LOCF
  for any earlier ones with a warning. `"none"` performs no
  extrapolation; `sigma` stays `NA` and downstream variance terms drop
  those links via finite-value guards. Passed to
  [`.extrapolate_sigma_ata()`](https://seokhoonj.github.io/lossratio/reference/dot-extrapolate_sigma_ata.md).

- recent:

  Optional positive integer. When supplied, only the most recent
  `recent` periods are used for factor estimation. Default is `NULL`
  (use all periods).

- regime:

  Optional regime specification for cohort cutoff. Accepts: `NULL`
  (default – no filter), a `Regime` object (from
  [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  or
  [`regime_at()`](https://seokhoonj.github.io/lossratio/reference/regime_at.md)),
  the string `"auto"` (internal `detect_regime(tri, loss = "ratio")`
  call), or a function `function(tri) -> Regime` for deferred
  custom-config detection. When supplied, cohorts strictly before the
  resolved change date are excluded from factor estimation.

- maturity:

  Maturity input forwarded to
  [`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md).
  Accepts four forms:

  `NULL` (default)

  :   No maturity filtering.

  `Maturity` object

  :   Pre-built (e.g. from
      [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
      or
      [`maturity_at()`](https://seokhoonj.github.io/lossratio/reference/maturity_at.md))
      – used as-is.

  `"auto"`

  :   Internal
      [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
      call with defaults (loss inferred from `loss`).

  function `function(tri) -> Maturity`

  :   Lazy spec, typically built with
      [`maturity_spec()`](https://seokhoonj.github.io/lossratio/reference/maturity_spec.md),
      invoked on the triangle at fit time (leakage-safe for
      [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)).

- tail:

  Logical or numeric. If `FALSE`, no tail factor is applied. If `TRUE`,
  a log-linear tail factor is estimated from selected factors. If
  numeric, the supplied value is used as the tail factor.

- bootstrap:

  Optional bootstrap specification. Accepts `NULL` (default, analytical
  Mack SE only), a `BootstrapTriangle` object produced by
  [`bootstrap()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md)
  (replayed for SE / CI), or the string `"auto"` to run an internal
  nonparametric bootstrap at fit time.

- B:

  Integer number of bootstrap replicates when `bootstrap = "auto"`.
  Default `999L`.

- seed:

  Optional integer seed for reproducible bootstrap draws. Default
  `NULL`.

- conf_level:

  Numeric in `(0, 1)`. Confidence level used for bootstrap-derived CI
  columns. Default `0.95`.

## Value

An object of class `"CLFit"` containing:

- `call`:

  The matched call.

- `data`:

  The input `"Triangle"` object.

- `method`:

  The method used (`"mack"`).

- `groups`:

  Character vector of grouping variable names.

- `cohort`:

  Character scalar of period variable name.

- `dev`:

  Character scalar of development variable name.

- `loss`:

  Character scalar of loss column name.

- `full`:

  `data.table` with observed and projected values, including
  process/parameter SE and CV columns.

- `proj`:

  `data.table` identical to `full` with observed cells set to `NA`.

- `link`:

  The `"Link"` object produced by
  [`as_link()`](https://seokhoonj.github.io/lossratio/reference/as_link.md).

- `summary`:

  Cohort-level summary with latest, ultimate, reserve, and Mack standard
  errors.

- `selected`:

  `data.table` of selected factors used for projection.

- `factor`:

  `data.table` of fitted factors from
  [`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md).

- `maturity`:

  Maturity diagnostics from
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md),
  or `NULL` when maturity filtering was not applied.

- `alpha`:

  Value of `alpha` used.

- `sigma_method`:

  Sigma extrapolation method.

- `weight`:

  Weight variable name used, or `NULL`.

- `recent`:

  Number of recent periods used, or `NULL`.

- `regime`:

  Resolved `Regime` object, or `NULL`.

- `use_maturity`:

  Logical; whether maturity filtering was applied.

- `tail`:

  Tail factor argument supplied by the user.

- `tail_factor`:

  Numeric tail factor applied.

## See also

[`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md),
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md)

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
  premium = "incr_premium"
)

# Mack chain ladder with process / parameter standard errors
cl_mack <- fit_cl(tri, loss = "loss", method = "mack")
summary(cl_mack)
plot(cl_mack)

# WLS factors for ratio (loss ratio) using premium as the weight
cl_ratio <- fit_cl(tri, loss = "ratio", weight = "premium")
} # }
```
