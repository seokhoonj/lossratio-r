# Package index

## Input layer

Validation and grain helpers for raw experience data.
[`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md)
already runs the required checks and coercions inline — these helpers
are exposed for users who want to validate or enrich without building a
triangle.

- [`derive_grain_columns()`](https://seokhoonj.github.io/lossratio/reference/derive_grain_columns.md)
  : Derive monthly / quarterly / semi-annual / annual grain columns
- [`validate_triangle()`](https://seokhoonj.github.io/lossratio/reference/validate_triangle.md)
  : Validate triangle structure before building a development

## Aggregation builders

Three frameworks for viewing the same long-format experience data —
cohort × dev (`Triangle`), calendar period (`Calendar`), or portfolio
total (`Total`).

- [`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md)
  : Coerce experience data to a Triangle object
- [`as_calendar()`](https://seokhoonj.github.io/lossratio/reference/as_calendar.md)
  : Coerce experience data to a Calendar object
- [`as_total()`](https://seokhoonj.github.io/lossratio/reference/as_total.md)
  : Coerce experience data to a Total object

## Link table

Long-format intermediate underlying both the chain-ladder (ATA) and
exposure-driven (ED) workflows. Built once, summarised differently via
[`summary.Link()`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md)’s
`model` argument.

- [`as_link()`](https://seokhoonj.github.io/lossratio/reference/as_link.md)
  : Coerce a Triangle to a Link object

- [`summary(`*`<Link>`*`)`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md)
  :

  Summarise a `Link` table

## Estimation

Models that produce full projections on a Triangle. Base algorithms:
`fit_cl` (chain ladder / multiplicative), `fit_ed` (exposure-driven /
additive). Role dispatchers: `fit_loss` (loss-side sa/ed/cl),
`fit_premium` (premium-side ed/cl). Composition: `fit_lr` (loss-ratio
umbrella with delta-method SE). All return an object carrying a `$full`
projection table.

- [`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md)
  :

  Fit chain ladder projection from a `Triangle` object

- [`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md)
  : Fit ED intensity factors

- [`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md)
  : Fit a loss projection on a Triangle

- [`fit_premium()`](https://seokhoonj.github.io/lossratio/reference/fit_premium.md)
  : Fit a chain ladder projection on the prem (exposure) triangle

- [`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)
  : Fit loss ratio projection model

## Factor diagnostics

Per-link factor estimation at the *factor level*. Both `fit_ata`
(multiplicative ATA factors `f_k`) and `fit_intensity` (ED-style
additive intensities `g_k`) return per-link factors with standard errors
and diagnostic stats — without producing a full projection. `fit_ata`
feeds into `fit_cl`,
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md),
and the SA stage transition in `fit_lr`; `fit_intensity` feeds into
`fit_ed` and is the ED counterpart diagnostic.

- [`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md)
  : Fit age-to-age development factors
- [`fit_intensity()`](https://seokhoonj.github.io/lossratio/reference/fit_intensity.md)
  : Fit per-link ED intensity factors

## Cell-selection diagnostics

Decide which cells of the triangle to use for estimation.
`detect_maturity` works along the dev axis (link beyond which ATA
factors are stable); `detect_regime` works along the cohort axis
(structural break across underwriting cohorts). The `*_at()` /
`*_spec()` helpers build manual / lazy-detect input objects for the
`maturity` / `loss_regime` / `premium_regime` arguments of the fit
functions.

- [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
  : Find ata maturity by group
- [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  [`print(`*`<Regime>`*`)`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  [`summary(`*`<Regime>`*`)`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  [`print(`*`<summary.Regime>`*`)`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  : Detect structural regime shifts across underwriting cohorts
- [`maturity_at()`](https://seokhoonj.github.io/lossratio/reference/maturity_at.md)
  : Construct a Maturity object from manually specified maturity points
- [`maturity_spec()`](https://seokhoonj.github.io/lossratio/reference/maturity_spec.md)
  : Build a lazy maturity detection spec
- [`regime_at()`](https://seokhoonj.github.io/lossratio/reference/regime_at.md)
  : Construct a Regime object from manually specified regime changes
- [`regime_spec()`](https://seokhoonj.github.io/lossratio/reference/regime_spec.md)
  : Build a lazy regime detection spec

## Bootstrap

Cohort × dev standard-error decomposition via simulation (Pythagorean
split into parameter and process components). Returned object is
consumed by `fit_loss` / `fit_premium` / `fit_lr` through their
`bootstrap` argument to replace analytical SE / CI with empirical
counterparts.

- [`bootstrap()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md)
  : Bootstrap a Triangle

## Projection diagnostic

Operates on a fitted `LRFit`, not on the raw triangle. Locates the
valuation depth $`v`$ at which the projected ultimate loss ratio stops
revising under a dual criterion (predictive revision below noise
threshold AND cross-cohort dispersion small, sustained over M
consecutive valuations).

- [`detect_convergence()`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md)
  : Find the development period at which the loss ratio estimate
  stabilises

## Backtest

Hold out the latest calendar diagonals from a triangle, refit, and
compare projections against the withheld actuals.

- [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  [`print(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  [`summary(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  [`print(`*`<summary.Backtest>`*`)`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  : Backtest a loss / prem / loss-ratio projection on existing data

## Visualisation

[`plot()`](https://rdrr.io/r/graphics/plot.default.html) (base generic)
and
[`plot_triangle()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.md)
(lossratio generic) dispatch on the object class.

- [`plot_triangle()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.md)
  : Triangle plot generic

- [`plot(`*`<ATAFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.ATAFit.md)
  : Plot an ata fit

- [`plot(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.Backtest.md)
  : Plot a backtest object

- [`plot(`*`<CLFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.CLFit.md)
  : Plot a chain ladder fit

- [`plot(`*`<Calendar>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.Calendar.md)
  : Plot calendar-based development statistics

- [`plot(`*`<Convergence>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.Convergence.md)
  : Plot the Convergence diagnostic

- [`plot(`*`<EDFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.EDFit.md)
  : Plot an ED fit

- [`plot(`*`<IntensityFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.IntensityFit.md)
  : Plot an Intensity fit

- [`plot(`*`<LRFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.LRFit.md)
  : Plot a loss ratio fit

- [`plot(`*`<Link>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.Link.md)
  : Plot link-factor diagnostics

- [`plot(`*`<Regime>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.Regime.md)
  : Plot a cohort regime detection result

- [`plot(`*`<RegimeOptimalWindow>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.RegimeOptimalWindow.md)
  : Plot change-count vs window with the elbow marker

- [`plot(`*`<Total>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.Total.md)
  :

  Plot a `Total` object as a per-group bar chart

- [`plot(`*`<Triangle>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.Triangle.md)
  : Plot development trajectories with optional summary overlay

- [`plot(`*`<TriangleValidation>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.TriangleValidation.md)
  : Plot a TriangleValidation result

- [`plot_triangle(`*`<ATAFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.ATAFit.md)
  : Triangle heatmap for an ata fit

- [`plot_triangle(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.Backtest.md)
  : Triangle heatmap of backtest A/E Error

- [`plot_triangle(`*`<CLFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.CLFit.md)
  : Plot chain ladder results as a triangle table

- [`plot_triangle(`*`<EDFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.EDFit.md)
  : Triangle heatmap for an ED fit

- [`plot_triangle(`*`<IntensityFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.IntensityFit.md)
  : Triangle heatmap for an Intensity fit

- [`plot_triangle(`*`<LRFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.LRFit.md)
  : Plot loss ratio projection as a triangle heatmap

- [`plot_triangle(`*`<Link>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.Link.md)
  : Plot a Link object as a triangle heatmap

- [`plot_triangle(`*`<Triangle>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.Triangle.md)
  : Plot development values as a triangle table

- [`plot_triangle(`*`<TriangleValidation>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.TriangleValidation.md)
  : Triangle-heatmap view of dev-sequence gaps

## Other S3 methods

print / summary / longer methods registered on package classes.

- [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  [`print(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  [`summary(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  [`print(`*`<summary.Backtest>`*`)`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  : Backtest a loss / prem / loss-ratio projection on existing data

- [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  [`print(`*`<Regime>`*`)`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  [`summary(`*`<Regime>`*`)`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  [`print(`*`<summary.Regime>`*`)`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  : Detect structural regime shifts across underwriting cohorts

- [`print(`*`<ATAFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/print.ATAFit.md)
  :

  Print an `ATAFit` object

- [`print(`*`<ATASummary>`*`)`](https://seokhoonj.github.io/lossratio/reference/print.ATASummary.md)
  :

  Print method for `ATASummary`

- [`print(`*`<BootstrapTriangle>`*`)`](https://seokhoonj.github.io/lossratio/reference/print.BootstrapTriangle.md)
  : Print method for BootstrapTriangle

- [`print(`*`<CLFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/print.CLFit.md)
  :

  Print a `CLFit` object

- [`print(`*`<EDFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/print.EDFit.md)
  :

  Print an `EDFit` object

- [`print(`*`<EDSummary>`*`)`](https://seokhoonj.github.io/lossratio/reference/print.EDSummary.md)
  :

  Print method for `EDSummary`

- [`print(`*`<IntensityFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/print.IntensityFit.md)
  :

  Print method for `IntensityFit`

- [`print(`*`<LRFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/print.LRFit.md)
  :

  Print an `LRFit` object

- [`print(`*`<LossFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/print.LossFit.md)
  :

  Print method for `LossFit`

- [`print(`*`<PremiumFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/print.PremiumFit.md)
  :

  Print method for `PremiumFit`

- [`summary(`*`<ATAFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/summary.ATAFit.md)
  :

  Summary method for `ATAFit`

- [`summary(`*`<CLFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/summary.CLFit.md)
  :

  Summary method for `CLFit`

- [`summary(`*`<Calendar>`*`)`](https://seokhoonj.github.io/lossratio/reference/summary.Calendar.md)
  : Summarise calendar-development statistics (Mean, Median, Weighted)

- [`summary(`*`<EDFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/summary.EDFit.md)
  :

  Summary method for `EDFit`

- [`summary(`*`<IntensityFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/summary.IntensityFit.md)
  :

  Summary method for `IntensityFit`

- [`summary(`*`<LRFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/summary.LRFit.md)
  :

  Summary method for `LRFit`

- [`summary(`*`<Link>`*`)`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md)
  :

  Summarise a `Link` table

- [`summary(`*`<LossFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/summary.LossFit.md)
  :

  Summary method for `LossFit`

- [`summary(`*`<PremiumFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/summary.PremiumFit.md)
  :

  Summary method for `PremiumFit`

- [`summary(`*`<Total>`*`)`](https://seokhoonj.github.io/lossratio/reference/summary.Total.md)
  :

  Summarise a `Total` object

- [`summary(`*`<Triangle>`*`)`](https://seokhoonj.github.io/lossratio/reference/summary.Triangle.md)
  : Summarise development statistics (Mean, Median, Weighted)

## Helpers

- [`longer()`](https://seokhoonj.github.io/lossratio/reference/longer.md)
  : Reshape an object to long form (S3 generic)
- [`mask_triangle()`](https://seokhoonj.github.io/lossratio/reference/mask_triangle.md)
  : Mask the last N calendar diagonals from a Triangle

## Datasets

- [`experience`](https://seokhoonj.github.io/lossratio/reference/experience.md)
  : Sample loss experience data
