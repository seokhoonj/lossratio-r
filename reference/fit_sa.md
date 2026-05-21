# Fit stage-adaptive (SA) loss projection on a Triangle

Project cumulative loss across the cohort x development grid using the
*stage-adaptive* (SA) method: ED before the maturity point, CL after. SA
composes both projection paradigms anchored on a per-group maturity
switch – a 2-pass fit (maturity detection via
[`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md),
then the SA projection itself).

SA is a worker – standalone, no internal method dispatch. The
role-specific entry point
[`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md)
dispatches `method = "sa"` to this function; users can also call
`fit_sa()` directly.

## Usage

``` r
fit_sa(
  x,
  loss = "loss",
  premium = "premium",
  alpha = 1,
  premium_fit = NULL,
  premium_method = c("ed", "cl"),
  premium_alpha = 1,
  sigma_method = c("locf", "min_last2", "loglinear", "mack", "none"),
  recent = NULL,
  regime = NULL,
  maturity = "auto",
  tail = FALSE,
  conf_level = 0.95,
  bootstrap = NULL,
  B = 999L,
  seed = NULL,
  type = c("parametric", "nonparametric", "analytical")
)
```

## Arguments

- x:

  A `"Triangle"` object. The standardized `"loss"` and `"premium"`
  columns are used
  ([`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md)
  produces these).

- loss:

  Cumulative loss column name. Default `"loss"`.

- premium:

  Cumulative premium column name. Default `"premium"`.

- alpha:

  Variance-structure exponent for the loss fit. Default `1`.

- premium_fit:

  Optional pre-built `PremiumFit` supplying the premium projection. When
  `NULL`, `fit_sa()` builds the premium projection internally – a
  worker-layer
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md)
  on the `premium` column – using `premium_method`, `premium_alpha`, and
  the resolved `regime`.

- premium_method:

  One of `"ed"` (default) or `"cl"`. Used only when
  `premium_fit = NULL`.

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
  [`.extrapolate_sigma_ata()`](https://seokhoonj.github.io/lossratio/reference/dot-extrapolate_sigma_ata.md).

- recent:

  Optional positive integer; calendar-diagonal filter.

- regime:

  Optional regime specification (loss-side). Accepts the standard 4-type
  dispatch (`NULL` / `Regime` / `"auto"` / function). In SA mode the
  resolved regime drives the hybrid 2-pass filter (cohort cut for the ED
  phase, calendar-diagonal wedge for the CL phase).

- maturity:

  Maturity specification. Default `"auto"`. Accepts the standard 4-type
  dispatch (`NULL` / `Maturity` / `"auto"` / function). SA requires a
  maturity – `NULL` disables SA entirely (use ED or CL directly in that
  case).

- tail:

  Logical or numeric; tail factor for the CL phase. Forwarded to the
  internal premium fit when relevant.

- conf_level:

  Confidence level for the analytical CI on the loss projection. Default
  `0.95`.

- bootstrap:

  Bootstrap configuration (NULL / TRUE / FALSE / "auto" /
  `BootstrapTriangle` / lazy function). Default `NULL` resolves to
  `"auto"` (residual bootstrap) for SA.

- B:

  Integer number of bootstrap replicates. Default `999`.

- seed:

  Optional integer seed.

- type:

  Bootstrap process type. Default `"parametric"`. (Only used when
  `bootstrap = "auto"`.)

## Value

An object of class `"SAFit"`. List with components mirroring `LossFit`:
`full`, `proj`, `maturity`, `loss_ata_fit`, `premium_ata_fit`,
`premium_fit`, `ed`, `factor`, `selected`, plus metadata
(`method = "sa"`, `alpha`, `sigma_method`, `recent`, `regime`,
`conf_level`, `ci_type`, `bootstrap`, `usage`).

## See also

[`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md),
[`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md),
[`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md),
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md).

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

sa <- fit_sa(tri)
summary(sa)
} # }
```
