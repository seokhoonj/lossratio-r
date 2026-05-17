# Fit per-link ED intensity factors

Estimate per-development-link incremental loss intensities \\g_k =
\mathbb{E}\[\Delta L_k / C^P_k\]\\ from a `"Triangle"` and return an
`"IntensityFit"` object that bundles the link-level WLS-estimated
intensities along with their standard errors and diagnostic statistics.

This is the factor-level diagnostic for the exposure-driven (ED)
workflow, parallel to
[`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md)
for the multiplicative (chain ladder) side. Both operate at the *factor
level* without producing a full projection. For full ED projection
(cumulative loss / prem / lr), use
[`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md)
which accepts either a `Triangle` or an `IntensityFit` (skipping a
rebuild of the link table when factors are already computed).

## Usage

``` r
fit_intensity(
  x,
  target = "loss",
  exposure = "prem",
  alpha = 1,
  na_method = c("locf", "zero", "none"),
  sigma_method = c("locf", "min_last2", "loglinear"),
  recent = NULL,
  regime = NULL,
  ...
)
```

## Arguments

- x:

  A `Triangle` object.

- target:

  A single cumulative metric used as the link numerator. Default
  `"loss"`.

- exposure:

  A single cumulative metric used as the exposure anchor. Default
  `"prem"`.

- alpha:

  WLS weight exponent. Default `1`.

- na_method:

  NA fill method for the selected intensity series used downstream by
  [`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md).
  One of `"locf"` (default — carries the last observed intensity
  forward, appropriate for long-term health where ageing keeps \\g_k\\
  elevated rather than decaying to 0), `"zero"` (sets late-dev NAs to 0;
  suits short-tail lines where claims fully settle), or `"none"`.

- sigma_method:

  Method for extrapolating missing or non-positive `sigma` values across
  links. One of `"min_last2"` (default), `"locf"`, `"loglinear"`.

- recent:

  Optional positive integer. When supplied, restricts estimation to rows
  within the last `recent` calendar diagonals (calendar-diagonal wedge
  filter; see
  [`.apply_recent_filter()`](https://seokhoonj.github.io/lossratio/reference/dot-apply_recent_filter.md)).

- regime:

  Optional regime specification for cohort cutoff. Accepts: `NULL`
  (default — no filter), a `"Regime"` object (from
  [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)),
  the string `"auto"` (internal `detect_regime(tri, target = "lr")`
  call), or a function `function(tri) -> Regime`. Resolved internally
  via
  [`.resolve_regime()`](https://seokhoonj.github.io/lossratio/reference/dot-resolve_regime.md).
  When supplied, cohorts strictly before the change are dropped before
  estimation.

- ...:

  Passed to
  [`summary.Link()`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md)
  (e.g. `digits`).

## Value

A list of class `"IntensityFit"` with components:

- `call`:

  The matched call.

- `data`:

  The (possibly filtered) `Link` object used for estimation.

- `groups`, `cohort`, `dev`, `target`, `exposure`:

  Variable name relays from the input `Triangle`.

- `link`:

  Alias of `data` for parallelism with
  [`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md).

- `factor`:

  The `EDSummary` returned by
  [`summary.Link()`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md)
  — one row per link with WLS-estimated `g`, `g_se`, `rse`, `sigma`,
  plus descriptive statistics.

- `selected`:

  `data.table` of selected intensities per link (`g_sel`, `sigma`,
  `sigma2`, `sigma_extrapolated`). LOCF NA-fill is applied when
  `na_method = "locf"`; sigma extrapolation is applied per
  `sigma_method`.

- `alpha`, `na_method`, `sigma_method`, `recent`, `regime`:

  Call metadata. `regime` is the resolved `"Regime"` object (or `NULL`)
  returned by
  [`.resolve_regime()`](https://seokhoonj.github.io/lossratio/reference/dot-resolve_regime.md).

## ED has no maturity concept

Unlike ATA factors, where CV / RSE drive a
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
threshold, ED intensities behave differently — as \\g_k \to 0\\ in late
development the CV / RSE blow up by construction, not by instability.
`fit_intensity()` therefore deliberately omits a `maturity` parameter,
and
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
rejects `IntensityFit` input with an informative error.

## See also

[`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md),
[`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md),
[`as_link()`](https://seokhoonj.github.io/lossratio/reference/as_link.md),
[`summary.Link()`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md)

## Examples

``` r
if (FALSE) { # \dontrun{
tri <- as_triangle(
  df,
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  prem     = "incr_prem"
)
intensity_fit <- fit_intensity(tri, target = "loss", exposure = "prem")
summary(intensity_fit)
} # }
```
