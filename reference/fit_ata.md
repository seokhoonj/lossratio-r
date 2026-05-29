# Fit age-to-age development factors

Estimate age-to-age (ata) development factors from an object of class
`"Link"` and return a unified `"ATAFit"` object that bundles:

- Summary statistics and WLS estimates (`summary`) from
  [`summary.Link()`](https://seokhoonj.github.io/lossratio-r/reference/summary.Link.md)
  with `model = "ata"`.

- Selected factors (`selected`) ready for chain ladder projection, after
  optional maturity filtering and LOCF fill.

- Maturity diagnostics (`maturity`) from
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio-r/reference/detect_maturity.md).

## Usage

``` r
fit_ata(
  x,
  loss = "loss",
  weight = NULL,
  alpha = 1,
  na_method = c("locf", "none"),
  sigma_method = c("locf", "min_last2", "loglinear", "mack", "none"),
  recent = NULL,
  regime = NULL,
  maturity = NULL,
  ...
)
```

## Arguments

- x:

  An object of class `"Link"`, typically produced by
  [`as_link()`](https://seokhoonj.github.io/lossratio-r/reference/as_link.md).

- loss:

  Cumulative metric for the link factor. Default `"loss"`. Forwarded to
  [`as_link()`](https://seokhoonj.github.io/lossratio-r/reference/as_link.md).

- weight:

  Optional WLS weight variable. Forwarded to
  [`as_link()`](https://seokhoonj.github.io/lossratio-r/reference/as_link.md).

- alpha:

  Numeric scalar controlling the variance structure. Default is `1`.

- na_method:

  Method used to fill `NA` values in `f_sel`. One of `"locf"` (default)
  or `"none"`. Passed to
  [`.filter_ata()`](https://seokhoonj.github.io/lossratio-r/reference/dot-filter_ata.md).

- sigma_method:

  Method used to extrapolate `sigma` for links where it cannot be
  estimated. One of `"locf"` (default), `"min_last2"`, `"loglinear"`,
  `"mack"`, or `"none"`. `"mack"` applies the Mack (1993, Appendix B)
  tail estimator to the last unestimated link only, falling back to LOCF
  for any earlier ones with a warning. `"none"` performs no
  extrapolation; `sigma` stays `NA` and downstream variance terms drop
  those links via finite-value guards. Passed to
  [`.extrapolate_sigma_ata()`](https://seokhoonj.github.io/lossratio-r/reference/dot-extrapolate_sigma_ata.md).

- recent:

  Optional positive integer. When supplied, only the most recent
  `recent` periods in the `Link` triangle are used for factor
  estimation. Applied before maturity filtering. Default is `NULL` (use
  all periods).

- regime:

  Optional regime specification for cohort cutoff. Accepts: `NULL`
  (default – no filter), a `Regime` object (from
  [`detect_regime()`](https://seokhoonj.github.io/lossratio-r/reference/detect_regime.md)
  or
  [`regime_at()`](https://seokhoonj.github.io/lossratio-r/reference/regime_at.md)),
  the string `"auto"` (internal `detect_regime(tri, loss = "ratio")`
  call), or a function `function(tri) -> Regime` for deferred
  custom-config detection. When supplied, cohorts strictly before the
  resolved change date are excluded from estimation.

- maturity:

  Optional maturity specification for filtering ata links. Accepts four
  input types:

  `NULL` (default)

  :   No maturity filter.

  `Maturity` object

  :   Use as-is. Typically built via
      [`detect_maturity()`](https://seokhoonj.github.io/lossratio-r/reference/detect_maturity.md)
      or
      [`maturity_at()`](https://seokhoonj.github.io/lossratio-r/reference/maturity_at.md).

  `"auto"`

  :   Detect maturity internally via `detect_maturity(x)` on the input
      triangle.

  Function / closure

  :   A user-supplied function taking the triangle and returning a
      `Maturity` object (e.g. from
      [`maturity_spec()`](https://seokhoonj.github.io/lossratio-r/reference/maturity_spec.md))
      for deferred custom-config detection.

  When the supplied `Maturity` carries `attr(., "groups")` that differs
  from the Triangle's grouping, the Triangle is rebucketed to the
  maturity partition before link construction.

- ...:

  Additional arguments passed to
  [`summary.Link()`](https://seokhoonj.github.io/lossratio-r/reference/summary.Link.md).

## Value

An object of class `"ATAFit"` (a named list) containing:

- `call`:

  The matched call.

- `link`:

  The input `"Link"` object.

- `summary`:

  `"ATASummary"` object from
  [`summary.Link()`](https://seokhoonj.github.io/lossratio-r/reference/summary.Link.md).

- `selected`:

  `data.table` of factors ready for projection, including `f_sel` and
  `sigma2`.

- `maturity`:

  Resolved `Maturity` object used for filtering, or `NULL` when maturity
  filtering was not applied.

- `alpha`:

  Value of `alpha` used.

- `na_method`:

  NA fill method used.

- `sigma_method`:

  Sigma extrapolation method used.

- `recent`:

  Number of recent periods used, or `NULL`.

- `regime`:

  Resolved `Regime` object, or `NULL`.

- `use_maturity`:

  Logical; whether maturity filtering was applied.

## See also

[`as_link()`](https://seokhoonj.github.io/lossratio-r/reference/as_link.md),
[`summary.Link()`](https://seokhoonj.github.io/lossratio-r/reference/summary.Link.md),
[`detect_maturity()`](https://seokhoonj.github.io/lossratio-r/reference/detect_maturity.md),
[`fit_cl()`](https://seokhoonj.github.io/lossratio-r/reference/fit_cl.md)
