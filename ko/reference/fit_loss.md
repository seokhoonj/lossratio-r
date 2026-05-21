# Fit a loss projection on a Triangle

Project cumulative loss across the cohort x development grid.
`fit_loss()` is the role-specific *dispatcher* on the loss side – it
forwards to a worker selected by `method`:

- `"ed"` (default):

  [`fit_ed()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ed.md)
  – pure exposure-driven (additive). Unconditional safe baseline; no
  maturity dependency.

- `"cl"`:

  [`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
  – pure Mack chain ladder (multiplicative). Classical reference.

- `"sa"`:

  [`fit_sa()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_sa.md)
  – stage-adaptive composition: ED before the maturity point, CL after.

- `"bf"`:

  [`fit_bf()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_bf.md)
  – Bornhuetter-Ferguson; requires a `prior` ELR (scalar or per-cohort
  table) passed via `...`.

- `"cc"`:

  [`fit_cc()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cc.md)
  – Cape Cod (BF with a pooled ELR derived from the data).

The dispatcher returns a `LossFit` object whose `$full` schema is
uniform across methods (`loss_obs`, `loss_proj`, `loss_total_se`,
`loss_ci_lo`, `loss_ci_hi`, `premium_obs`, `premium_proj`,
`incr_premium_proj`, plus method-specific extras). Missing slots on
worker outputs (e.g. `loss_ata_fit` for ED, `ed`/`selected` for
CL/BF/CC) are synthesized as `NULL` so downstream code such as
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md)
can guard uniformly.

## Usage

``` r
fit_loss(
  x,
  method = c("ed", "cl", "sa", "bf", "cc"),
  alpha = 1,
  regime = NULL,
  premium_fit = NULL,
  premium_method = c("ed", "cl"),
  premium_alpha = 1,
  sigma_method = c("locf", "min_last2", "loglinear", "mack", "none"),
  recent = NULL,
  maturity = "auto",
  tail = FALSE,
  conf_level = 0.95,
  bootstrap = NULL,
  B = 999L,
  seed = NULL,
  type,
  ...
)
```

## Arguments

- x:

  A `"Triangle"` object. The standardized `"loss"` and `"premium"`
  columns are used
  ([`as_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/as_triangle.md)
  produces these).

- method:

  One of `"ed"` (default), `"cl"`, `"sa"`, `"bf"`, or `"cc"`.

- alpha:

  Variance-structure exponent for the loss fit. Default `1`.

- regime:

  Optional regime specification (loss-side). Accepts the standard 4-type
  dispatch (`NULL` / `Regime` / `"auto"` / function). Behavior depends
  on `method`: SA uses a hybrid 2-pass filter; ED / CL / BF / CC use a
  simple cohort cut. The same resolved regime is applied to the internal
  premium fit – callers needing an asymmetric loss/premium split should
  use
  [`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md).

- premium_fit:

  Optional pre-built `PremiumFit` supplying the premium projection. Only
  used by `"ed"` (via `fit_ed`'s internal premium handling) and `"sa"`.
  When `NULL`, the worker calls
  [`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md)
  internally.

- premium_method:

  One of `"ed"` (default) or `"cl"`. Used only when `premium_fit = NULL`
  for `"sa"`.

- premium_alpha:

  Variance-structure exponent for the premium fit. Default `1`.

- sigma_method:

  Method used to extrapolate `sigma` for links where it cannot be
  estimated. One of `"locf"` (default), `"min_last2"`, `"loglinear"`,
  `"mack"`, or `"none"`. `"mack"` applies the Mack (1993, Appendix B)
  tail estimator to the last unestimated link only, falling back to LOCF
  for any earlier ones with a warning. `"none"` performs no
  extrapolation; `sigma` stays `NA` and downstream variance terms drop
  those links via finite-value guards. Passed to
  [`.extrapolate_sigma_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-extrapolate_sigma_ata.md).

- recent:

  Optional positive integer; calendar-diagonal filter.

- maturity:

  Optional maturity specification. Accepts the standard 4-type dispatch
  (`NULL` / `Maturity` / `"auto"` / function). Only used by `"cl"`,
  `"sa"`, and `"bf"`. Default `"auto"`.

- tail:

  Tail factor (logical or numeric). Forwarded to `"cl"` / `"sa"`
  workers. Default `FALSE`.

- conf_level:

  Confidence level for analytical CI on the loss projection
  (`loss_ci_lo`, `loss_ci_hi`). Default `0.95`.

- bootstrap:

  Bootstrap configuration. Five forms accepted (see
  [`fit_sa()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_sa.md)
  /
  [`fit_ed()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ed.md)
  /
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
  for method-specific defaults).

- B:

  Integer number of bootstrap replicates. Default `999`.

- seed:

  Optional integer seed.

- type:

  Bootstrap process type. Forwarded where applicable (`"sa"`, `"bf"`,
  `"cc"`).

- ...:

  Method-specific arguments forwarded to the chosen worker. For
  `method = "bf"`, `prior` is required.

## Value

An object of class `"LossFit"`. List with components: `full`, `proj`,
`maturity`, `loss_ata_fit`, `premium_ata_fit`, `premium_fit`, `ed`,
`factor`, `selected`, plus metadata.

## See also

[`fit_ed()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ed.md),
[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md),
[`fit_sa()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_sa.md),
[`fit_bf()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_bf.md),
[`fit_cc()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cc.md),
[`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md),
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md).

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

lf    <- fit_loss(tri)                    # ED (default)
lf_cl <- fit_loss(tri, method = "cl")
lf_sa <- fit_loss(tri, method = "sa")
} # }
```
