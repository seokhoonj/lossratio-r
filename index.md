# lossratio

Loss ratio analytics for **long-term health insurance** — cohort
development analysis, stage-adaptive projection, regime detection, and
backtest validation.

## Overview

`lossratio` is a loss ratio analytics toolkit for **long-term health
insurance**, covering cohort development analysis, stage-adaptive
projection, regime detection, and backtest validation. Input is
long-format experience data — each row (cohort × dev × demographic) maps
to one Triangle cell, with loss and exposure columns (`loss`,
`exposure`).

In long-term health insurance, new claims and premium are generated and
earned continuously within each cohort, so cumulative loss and exposure
grow together. Age-to-age (ATA) factors tend to show high variability in
early development, and exposure (≈ risk premium) becomes a more stable
and reliable anchor. Product redesigns, underwriting changes, or
regulatory actions can also produce structural breaks that accumulate
across cohorts.

In this setting, lossratio provides stage-adaptive (SA) loss-ratio
projection, supported by maturity point and regime detection. SA uses an
exposure-driven (ED) model before the maturity point and chain ladder
(CL) after it. Regime detection identifies homogeneous groups of cohorts
(regimes) that share similar loss dynamics, separating structural break
points and determining which cells to use for estimation.

It provides:

- Three aggregation frameworks of the experience data: cohort × dev
  (`Triangle`), calendar period (`Calendar`), and portfolio total
  (`Total`)
- Age-to-age (`ATA`) and exposure-driven (`ED`) development modeling via
  the worker layer (`fit_cl`, `fit_ed`, `fit_ata`, `fit_intensity`)
- Role-specific dispatchers (`fit_loss`, `fit_exposure`) that project a
  single side with standard errors and confidence intervals
- Loss ratio projection (`fit_ratio`) composes loss and premium fits
  with three methods:
  - `"ed"` — **exposure-driven** (default): additive recursion across
    all dev — unconditional safe baseline
  - `"cl"` — classical chain ladder (Mack model)
  - `"sa"` — stage-adaptive: ED before maturity, CL after — a
    composition of the above two (requires maturity detection) Standard
    errors via `se_method = "fixed"` (premium treated as known) or
    `"delta"` (delta method on `L / P`); CIs via `conf_level`; bootstrap
    option for empirical CIs.
- Cell-selection diagnostics — which cells to use for estimation:
  - `detect_maturity` — dev axis: link beyond which ATA factors are
    stable
  - `detect_regime` — cohort axis: structural breaks across underwriting
- Projection diagnostic:
  - `detect_convergence` — valuation $`v`$ at which the projected
    ultimate loss ratio stops revising (operates on a fitted `RatioFit`)
- Backtest and triangle visualisations

## Expected input

A long-format `data.frame` / `data.table`. Column names are configurable
– pass them via
[`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md)
arguments and the function standardises internally.

| [`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md) argument | Meaning | Example |
|----|----|----|
| `cohort` | Cohort period (typically UY for long-term health) (Date) | `"uy_m"`, `"uy"` |
| `calendar` *or* `dev` | Calendar period (Date) *or* `dev` period (integer) | `"cy_m"` / `"dev_m"` |
| `loss` | Per-period *or* cumulative claim amount | `"incr_loss"` / `"loss"` |
| `exposure` | Per-period *or* cumulative exposure (risk premium) | `"incr_exposure"` / `"exposure"` |
| `cell_type` *(default)* | Interpretation of `loss` / `exposure` values | `"incremental"` / `"cumulative"` |
| `groups` *(optional)* | Grouping column(s): product, coverage, age, … | `"coverage"` |

Two more arguments govern interpretation:

- **`cell_type`** – `"incremental"` (default) or `"cumulative"`. Raw
  experience is typically incremental; if your data is pre-summed
  cumulative, pass `cell_type = "cumulative"` and
  [`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md)
  derives the incremental form via per-cohort diff.
- **`grain`** – `"auto"` (default, inferred from `cohort` dates) or
  `"M"` / `"Q"` / `"H"` / `"Y"`. Aggregates to monthly / quarterly /
  half-yearly / yearly granularity.

[`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md)
validates the schema, coerces date columns, derives the missing axis
when one of `calendar` / `dev` is supplied, bins to `grain`, and emits
cumulative + incremental cell values plus the derived `ratio`, `margin`,
`profit` columns.

### Column convention

Throughout the package, cumulative is the unmarked default and
per-period values carry an `incr_` (incremental) prefix:

| Metric   | Cumulative (default) | Per-period (`incr_`) |
|----------|----------------------|----------------------|
| Loss     | `loss`               | `incr_loss`          |
| Exposure | `exposure`           | `incr_exposure`      |
| Ratio    | `ratio`              | `incr_ratio`         |
| Margin   | `margin`             | `incr_margin`        |
| Profit   | `profit`             | `incr_profit`        |

Raw `experience` input is per-period only (`incr_loss`,
`incr_exposure`);
[`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md)
produces both forms in the output. Worker fit functions (`fit_cl`,
`fit_ed`, `fit_ata`, `fit_intensity`) take `loss` / `exposure` /
`weight` arguments; dispatcher functions (`fit_loss`, `fit_exposure`)
and the composition `fit_ratio` use role-specific `loss_*` /
`exposure_*` argument names. Cumulative slots (`"loss"`, `"exposure"`)
are the defaults.

## Installation

``` r

# pak (recommended)
pak::pak("seokhoonj/lossratio")

# remotes (alternative)
remotes::install_github("seokhoonj/lossratio")
```

The package currently depends on seokhoonj/instead and seokhoonj/ggshort
(installed automatically via Remotes:; planned for removal in a future
release).

## Quick Start

``` r

library(lossratio)

# Built-in calibrated synthetic experience data
# (per-coverage dev curve calibrated to a real portfolio's broad shape;
# cell-level values and cohort patterns are randomly generated)
data(experience)

# Build the canonical cohort × dev structure
tri <- as_triangle(
  experience,
  groups    = "coverage",
  cohort    = "uy_m",
  calendar  = "cy_m",
  loss      = "incr_loss",
  exposure  = "incr_exposure",
  cell_type = "incremental"   # default; use "cumulative" for pre-summed cells
)

plot(tri)              # cohort trajectories
plot_triangle(tri)     # cell heatmap

# Exposure-driven fit (additive ED intensity)
ed <- fit_ed(tri, loss = "loss", exposure = "exposure")

# Chain ladder fit (multiplicative ATA factors)
cl <- fit_cl(tri, loss = "loss")
plot(cl, type = "projection")

# Ratio fit (default: ED — exposure-driven baseline.
# Switch to method = "cl" or "sa" for cohort-anchored projection.)
ratio <- fit_ratio(tri)
plot(ratio, metric = "ratio", cell_type = "cumulative")
summary(ratio)

# Cell selection: maturity (dev axis) + regime (cohort axis)
detect_maturity(tri[coverage == "surgery"])
detect_regime(tri[coverage == "surgery"], method = "e_divisive")

# Projection diagnostic: when does the projected ultimate LR stop revising?
detect_convergence(ratio)
```

## Aggregation Frameworks

The same long-format experience data can be viewed three ways:

| Builder | Output object | Dimension | Use case |
|----|----|----|----|
| [`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md) | `Triangle` | cohort × dev (2D) | Chain ladder, ED, SA projection |
| [`as_calendar()`](https://seokhoonj.github.io/lossratio/reference/as_calendar.md) | `Calendar` | calendar period (1D) | Calendar-year trend / diagonal effect |
| [`as_total()`](https://seokhoonj.github.io/lossratio/reference/as_total.md) | `Total` | portfolio total (0D, per group) | High-level comparison across groups |

After `as_triangle`, downstream columns are standardized to `cohort` and
`dev` regardless of input granularity (`uy_m` / `uy_q` / `uy`, etc.).
Original column names are preserved as attributes (`cohort`, `calendar`,
`dev`); grain is stored as `grain` (`"M"`/`"Q"`/ `"H"`/`"Y"`).

## Methods

### Exposure-Driven (default)

`fit_ratio(method = "ed")` (default) or
[`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md).
All loss increments use exposure (risk premium) as the denominator:
$`\Delta C^L = g_k \cdot C^P_k`$. Unconditional safe baseline – no
maturity dependency, robust under early-dev age-to-age volatility.

*When to use*: as a baseline. The pooled intensity $`g_k`$ assumes
cohorts are reasonably homogeneous in loss-per-exposure level; under
cohort-level drift (e.g., underwriting / coverage regime change), the
projection biases toward the pooled mean and may over-project
post-change cohorts. See the `regime` argument for explicit filtering.

### Chain Ladder

`fit_ratio(method = "cl")` or
[`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md).
Classical Mack (1993) chain ladder $`C^L_{k+1} = f_k \cdot C^L_k`$ with
analytic standard errors. The cohort’s own cum_loss acts as the anchor,
so cohort-level drift propagates naturally without explicit regime
detection.

*When to use*: once age-to-age factors stabilise; particularly suited to
cohort-level drift scenarios because the cohort’s observed trajectory
anchors the projection.

### Stage-Adaptive

`fit_ratio(method = "sa")`. Composition of the two: ED before maturity,
CL after. Combines ED’s early-dev stability with CL’s cohort-anchored
later-dev behaviour.

*When to use*: long-tail portfolios where early dev is volatile (ED
phase) but cohort-level drift needs cohort-anchored projection in later
dev (CL phase).

## Visualisation

Both S3 generics dispatch on object class:

``` r

plot(x)              # base plot generic — line / panel diagnostics
plot_triangle(x)     # lossratio generic — cell heatmap layout
```

[`plot()`](https://rdrr.io/r/graphics/plot.default.html) and
[`plot_triangle()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.md)
work uniformly across `Triangle`, `Calendar`, `Link`, `ATAFit`, `EDFit`,
`CLFit`, `RatioFit`, `Maturity`, `Convergence`, and `Regime` objects.

## Documentation

``` r

?as_triangle
?fit_ratio
?detect_regime
vignette("regime-detection", package = "lossratio")
```

## License

GPL (\>= 2). See
[LICENSE.md](https://seokhoonj.github.io/lossratio/LICENSE.md).

## Author

Seokhoon Joo (<seokhoonj@gmail.com>)
