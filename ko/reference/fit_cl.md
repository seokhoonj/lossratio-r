# Fit chain ladder projection from a `Triangle` object

Fit a Mack (1993) chain ladder projection from an object of class
`"Triangle"`. The function works on long-form cumulative data and does
not require a complete triangle. Age-to-age factors are estimated
through
[`build_link()`](https://seokhoonj.github.io/lossratio/ko/reference/build_link.md)
and
[`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md),
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
  target = "loss",
  weight = NULL,
  alpha = 1,
  sigma_method = c("locf", "min_last2", "loglinear"),
  recent = NULL,
  regime_break = NULL,
  maturity_args = NULL,
  tail = FALSE
)
```

## Arguments

- x:

  An object of class `"Triangle"`.

- method:

  One of `"mack"`. Default is `"mack"`. The argument is retained for
  future extensibility.

- target:

  A single cumulative target variable (column to project). Typical
  choices are `"loss"`, `"premium"`, or `"lr"`.

- weight:

  An optional column name passed to
  [`build_link()`](https://seokhoonj.github.io/lossratio/ko/reference/build_link.md)
  as the WLS weight variable. Typically `"premium"` when
  `target = "lr"`. Default is `NULL`.

- alpha:

  Numeric scalar controlling the variance structure in
  [`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md).
  Default is `1`.

- sigma_method:

  Sigma extrapolation method passed to
  [`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md).
  One of `"locf"` (default), `"min_last2"`, or `"loglinear"`.

- recent:

  Optional positive integer. When supplied, only the most recent
  `recent` periods are used for factor estimation. Default is `NULL`
  (use all periods).

- regime_break:

  Optional cohort cutoff for a regime break. `NULL` (default), a
  `Date`/character coercible to Date, a vector of dates (uses the
  latest), or a `Regime` object. Cohorts strictly before the break are
  excluded from factor estimation.

- maturity_args:

  A named list of arguments forwarded to
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
  via
  [`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md),
  or `NULL` (default) to skip maturity filtering. Pass
  [`list()`](https://rdrr.io/r/base/list.html) to use all defaults with
  maturity filtering enabled.

- tail:

  Logical or numeric. If `FALSE`, no tail factor is applied. If `TRUE`,
  a log-linear tail factor is estimated from selected factors. If
  numeric, the supplied value is used as the tail factor.

## Value

An object of class `"CLFit"` containing:

- `call`:

  The matched call.

- `data`:

  The input `"Triangle"` object.

- `method`:

  The method used (`"mack"`).

- `group_var`:

  Character vector of grouping variable names.

- `cohort_var`:

  Character scalar of period variable name.

- `dev_var`:

  Character scalar of development variable name.

- `target`:

  Character scalar of target variable name.

- `full`:

  `data.table` with observed and projected values, including
  process/parameter SE and CV columns.

- `pred`:

  `data.table` identical to `full` with observed cells set to `NA`.

- `link`:

  The `"Link"` object produced by
  [`build_link()`](https://seokhoonj.github.io/lossratio/ko/reference/build_link.md).

- `summary`:

  Cohort-level summary with latest, ultimate, reserve, and Mack standard
  errors.

- `selected`:

  `data.table` of selected factors used for projection.

- `factor`:

  `data.table` of fitted factors from
  [`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md).

- `maturity`:

  Maturity diagnostics from
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md),
  or `NULL` when maturity filtering was not applied.

- `alpha`:

  Value of `alpha` used.

- `sigma_method`:

  Sigma extrapolation method.

- `weight`:

  Weight variable name used, or `NULL`.

- `recent`:

  Number of recent periods used, or `NULL`.

- `use_maturity`:

  Logical; whether maturity filtering was applied.

- `maturity_args`:

  Resolved maturity arguments, or `NULL`.

- `tail`:

  Tail factor argument supplied by the user.

- `tail_factor`:

  Numeric tail factor applied.

## See also

[`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md),
[`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)

## Examples

``` r
if (FALSE) { # \dontrun{
data(experience)
tri <- build_triangle(experience[coverage == "SUR"], groups = coverage)

# Mack chain ladder with process / parameter standard errors
cl_mack <- fit_cl(tri, target = "loss", method = "mack")
summary(cl_mack)
plot(cl_mack)

# WLS factors for lr (loss ratio) using premium as the weight
cl_clr <- fit_cl(tri, target = "lr", weight = "premium")
} # }
```
