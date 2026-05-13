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
  target = "loss",
  weight = NULL,
  alpha = 1,
  na_method = c("locf", "none"),
  sigma_method = c("locf", "min_last2", "loglinear"),
  recent = NULL,
  regime = NULL,
  maturity_args = NULL,
  ...
)
```

## Arguments

- x:

  An object of class `"Link"`, typically produced by
  [`build_link()`](https://seokhoonj.github.io/lossratio/ko/reference/build_link.md).

- target:

  Cumulative metric for the link factor. Default `"loss"`. Forwarded to
  [`build_link()`](https://seokhoonj.github.io/lossratio/ko/reference/build_link.md).

- weight:

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
  estimated. One of `"locf"` (default), `"min_last2"`, or `"loglinear"`.
  Passed to
  [`.extrapolate_sigma_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-extrapolate_sigma_ata.md).

- recent:

  Optional positive integer. When supplied, only the most recent
  `recent` periods in the `Link` triangle are used for factor
  estimation. Applied before maturity filtering. Default is `NULL` (use
  all periods).

- regime:

  Optional regime specification for cohort cutoff. Accepts: `NULL`
  (default — no filter), a `Regime` object (from
  [`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  or
  [`regime_at()`](https://seokhoonj.github.io/lossratio/ko/reference/regime_at.md)),
  the string `"auto"` (internal `detect_regime(tri, target = "lr")`
  call), or a function `function(tri) -> Regime` for deferred
  custom-config detection. When supplied, cohorts strictly before the
  resolved break date are excluded from estimation.

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
  with maturity filtering enabled. The list may also include `groups`,
  which re-aggregates the Triangle to a coarser partition before link
  construction and maturity detection. Same semantics as
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md):
  `NULL` (default) keeps the Triangle's current `attr(x, "groups")`,
  `character(0)` pools to a single global maturity, and a subset of
  `attr(x, "groups")` yields a coarser per-group result.

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

- `regime`:

  Resolved `Regime` object, or `NULL`.

- `use_maturity`:

  Logical; whether maturity filtering was applied.

- `maturity_args`:

  Resolved maturity arguments, or `NULL`.

## See also

[`build_link()`](https://seokhoonj.github.io/lossratio/ko/reference/build_link.md),
[`summary.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md),
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md),
[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
