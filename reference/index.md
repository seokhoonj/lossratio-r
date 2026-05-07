# Package index

## Input layer

Validation, coercion, and helpers for raw experience data.

- [`check_experience()`](https://seokhoonj.github.io/lossratio/reference/check_experience.md)
  : Check an experience dataset

- [`is_experience()`](https://seokhoonj.github.io/lossratio/reference/is_experience.md)
  :

  Check whether an object is an `Experience`

- [`as_experience()`](https://seokhoonj.github.io/lossratio/reference/as_experience.md)
  :

  Coerce a dataset to an `Experience` object

- [`add_experience_period()`](https://seokhoonj.github.io/lossratio/reference/add_experience_period.md)
  : Add standard period variables to an experience dataset

- [`validate_triangle()`](https://seokhoonj.github.io/lossratio/reference/validate_triangle.md)
  : Validate triangle structure before building a development

## Aggregation builders

Three frameworks for viewing the same long-format experience data —
cohort × dev (`Triangle`), calendar period (`Calendar`), or portfolio
total (`Total`).

- [`build_triangle()`](https://seokhoonj.github.io/lossratio/reference/build_triangle.md)
  : Build a development structure from experience data
- [`build_calendar()`](https://seokhoonj.github.io/lossratio/reference/build_calendar.md)
  : Build a calendar-based development structure from experience data
- [`build_total()`](https://seokhoonj.github.io/lossratio/reference/build_total.md)
  : Build a total development summary from experience data

## Link table

Long-format intermediate underlying both the chain-ladder (ATA) and
exposure-driven (ED) workflows. Built once, summarised differently via
[`summary.Link()`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md)’s
`model` argument.

- [`build_link()`](https://seokhoonj.github.io/lossratio/reference/build_link.md)
  :

  Build a link table from `Triangle` data

- [`summary(`*`<Link>`*`)`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md)
  :

  Summarise a `Link` table

## Estimation

Per-link factor estimation (`fit_ata`, `fit_ed`) and full projection
(`fit_cl`, `fit_lr`). `fit_lr` supports three methods — `"sa"`
(stage-adaptive, default), `"ed"`, and `"cl"`.

- [`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md)
  : Fit age-to-age development factors

- [`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md)
  : Fit ED intensity factors

- [`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md)
  :

  Fit chain ladder projection from a `Triangle` object

- [`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)
  : Fit loss ratio projection model

## Cell-selection diagnostics

Decide which cells of the triangle to use for estimation.
`detect_maturity` works along the dev axis (link beyond which ATA
factors are stable); `detect_regime` works along the cohort axis
(structural break across underwriting cohorts).

- [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
  : Find ata maturity by group
- [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  [`print(`*`<Regime>`*`)`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  [`summary(`*`<Regime>`*`)`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  [`print(`*`<summary.Regime>`*`)`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  : Detect structural regime shifts across underwriting cohorts

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
  : Backtest a loss-ratio / chain ladder fit on existing data

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

- [`plot(`*`<LRFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.LRFit.md)
  : Plot a loss ratio fit

- [`plot(`*`<Link>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.Link.md)
  : Plot link-factor diagnostics

- [`plot(`*`<Regime>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.Regime.md)
  : Plot a cohort regime detection result

- [`plot(`*`<Total>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.Total.md)
  :

  Plot a `Total` object as a per-group bar chart

- [`plot(`*`<Triangle>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot.Triangle.md)
  : Plot development trajectories with optional summary overlay

- [`plot_triangle(`*`<ATAFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.ATAFit.md)
  : Triangle heatmap for an ata fit

- [`plot_triangle(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.Backtest.md)
  : Triangle heatmap of backtest AEG

- [`plot_triangle(`*`<CLFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.CLFit.md)
  : Plot chain ladder results as a triangle table

- [`plot_triangle(`*`<EDFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.EDFit.md)
  : Triangle heatmap for an ED fit

- [`plot_triangle(`*`<LRFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.LRFit.md)
  : Plot loss ratio projection as a triangle heatmap

- [`plot_triangle(`*`<Link>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.Link.md)
  : Plot a Link object as a triangle heatmap

- [`plot_triangle(`*`<Triangle>`*`)`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.Triangle.md)
  : Plot development values as a triangle table

## Other S3 methods

print / summary / longer methods registered on package classes.

- [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  [`print(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  [`summary(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  [`print(`*`<summary.Backtest>`*`)`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  : Backtest a loss-ratio / chain ladder fit on existing data

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

- [`print(`*`<CLFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/print.CLFit.md)
  :

  Print a `CLFit` object

- [`print(`*`<EDFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/print.EDFit.md)
  :

  Print an `EDFit` object

- [`print(`*`<EDSummary>`*`)`](https://seokhoonj.github.io/lossratio/reference/print.EDSummary.md)
  :

  Print method for `EDSummary`

- [`print(`*`<LRFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/print.LRFit.md)
  :

  Print an `LRFit` object

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

- [`summary(`*`<LRFit>`*`)`](https://seokhoonj.github.io/lossratio/reference/summary.LRFit.md)
  :

  Summary method for `LRFit`

- [`summary(`*`<Link>`*`)`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md)
  :

  Summarise a `Link` table

- [`summary(`*`<Total>`*`)`](https://seokhoonj.github.io/lossratio/reference/summary.Total.md)
  :

  Summarise a `Total` object

- [`summary(`*`<Triangle>`*`)`](https://seokhoonj.github.io/lossratio/reference/summary.Triangle.md)
  : Summarise development statistics (Mean, Median, Weighted)

## Helpers

- [`get_recent_weights()`](https://seokhoonj.github.io/lossratio/reference/get_recent_weights.md)
  : Recent-diagonal weights for a development triangle
- [`longer()`](https://seokhoonj.github.io/lossratio/reference/longer.md)
  : Reshape an object to long form (S3 generic)

## Datasets

- [`experience`](https://seokhoonj.github.io/lossratio/reference/experience.md)
  : Sample loss experience data
