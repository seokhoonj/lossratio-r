# Fit age-to-age development factors

Estimate age-to-age (ata) development factors from an object of class
`"Link"` and return a unified `"ATAFit"` object that bundles:

- Summary statistics and WLS estimates (`summary`) from
  [`summary.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md)
  with `model = "ata"`.

- Selected factors (`selected`) ready for chain ladder projection, after
  optional maturity filtering and LOCF fill.

- Maturity diagnostics (`maturity`) from
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md).

## Usage

``` r
fit_ata(
  x,
  loss_var = "loss",
  weight_var = NULL,
  alpha = 1,
  na_method = c("locf", "none"),
  sigma_method = c("min_last2", "locf", "loglinear"),
  recent = NULL,
  regime_break = NULL,
  maturity_args = NULL,
  ...
)
```

## Arguments

- x:

  An object of class `"Link"`, typically produced by
  [`build_link()`](https://seokhoonj.github.io/lossratio/ko/reference/build_link.md).

- loss_var:

  Cumulative metric for the link factor. Default `"loss"`. Forwarded to
  [`build_link()`](https://seokhoonj.github.io/lossratio/ko/reference/build_link.md).

- weight_var:

  Optional WLS weight variable. Forwarded to
  [`build_link()`](https://seokhoonj.github.io/lossratio/ko/reference/build_link.md).

- alpha:

  Numeric scalar controlling the variance structure. Default is `1`.

- na_method:

  Method used to fill `NA` values in `f_selected`. One of `"locf"`
  (default) or `"none"`. Passed to
  [`.filter_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-filter_ata.md).

- sigma_method:

  Method used to extrapolate `sigma` for links where it cannot be
  estimated. One of `"min_last2"` (default), `"locf"`, or `"loglinear"`.
  Passed to
  [`.extrapolate_sigma_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-extrapolate_sigma_ata.md).

- recent:

  Optional positive integer. When supplied, only the most recent
  `recent` periods in the `Link` triangle are used for factor
  estimation. Applied before maturity filtering. Default is `NULL` (use
  all periods).

- regime_break:

  Optional cohort cutoff for the regime break. Accepts: `NULL` (default,
  no filter), a single `Date`/character coercible to Date, a vector of
  dates (uses the latest), or a `Regime` object (extracts the latest
  from `$breakpoints`). When supplied, cohorts with
  `cohort < break_date` are excluded from estimation. Default is `NULL`.

- maturity_args:

  A named list of arguments forwarded to
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md),
  or `NULL` (default) to skip maturity filtering. When a list is
  supplied, missing elements are filled with package defaults via
  [`utils::modifyList()`](https://rdrr.io/r/utils/modifyList.html):

  `max_cv`

  :   Default `0.15`.

  `max_rse`

  :   Default `0.05`.

  `min_valid_ratio`

  :   Default `0.5`.

  `min_n_valid`

  :   Default `3L`.

  `min_run`

  :   Default `2L`.

  Pass [`list()`](https://rdrr.io/r/base/list.html) to use all defaults
  with maturity filtering enabled.

- ...:

  Additional arguments passed to
  [`summary.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md).

## Value

An object of class `"ATAFit"` (a named list) containing:

- `call`:

  The matched call.

- `link`:

  The input `"Link"` object.

- `summary`:

  `"ATASummary"` object from
  [`summary.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md).

- `selected`:

  `data.table` of factors ready for projection, including `f_selected`
  and `sigma2`.

- `maturity`:

  Maturity diagnostics from
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md),
  or `NULL` when maturity filtering was not applied.

- `alpha`:

  Value of `alpha` used.

- `na_method`:

  NA fill method used.

- `sigma_method`:

  Sigma extrapolation method used.

- `recent`:

  Number of recent periods used, or `NULL`.

- `regime_break`:

  Resolved regime-break cutoff (`Date`), or `NULL`.

- `use_maturity`:

  Logical; whether maturity filtering was applied.

- `maturity_args`:

  Resolved maturity arguments, or `NULL`.

## See also

[`build_link()`](https://seokhoonj.github.io/lossratio/ko/reference/build_link.md),
[`summary.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md),
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md),
[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
