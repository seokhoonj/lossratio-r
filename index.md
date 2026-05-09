# lossratio

Loss ratio analytics for **long-term health insurance** — cohort
development analysis, stage-adaptive projection, regime detection, and
backtest validation.

## Overview

`lossratio` is a loss ratio analytics toolkit for **long-term health
insurance**, covering cohort development analysis, stage-adaptive
projection, regime detection, and backtest validation. Input is
long-format experience data — each row (cohort × dev × demographic) maps
to one Triangle cell, with loss and premium columns (`loss`, `premium`).

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
- Age-to-age (`ATA`) and exposure-driven (`ED`) development modeling
- Chain ladder projection (`fit_cl`) and loss ratio projection
  (`fit_lr`) with three methods:
  - `"sa"` — **stage-adaptive** (default): exposure-driven before
    maturity, chain ladder after
  - `"ed"` — exposure-driven for all development periods
  - `"cl"` — classical chain ladder (Mack model)
- Cell-selection diagnostics — which cells to use for estimation:
  - `detect_maturity` — dev axis: link beyond which ATA factors are
    stable
  - `detect_regime` — cohort axis: structural breaks across underwriting
- Projection diagnostic:
  - `detect_convergence` — valuation $`v`$ at which the projected
    ultimate loss ratio stops revising (operates on a fitted `LRFit`)
- Backtest and triangle visualisations

## Expected input

A long-format `data.frame` / `data.table` with at minimum:

| Column | Meaning | Example |
|----|----|----|
| cohort | Underwriting / accident period (any granularity) | `uym`, `uy` |
| dev | Development period since cohort start | `elap_m`, `elap_y` |
| `loss_incr` | Per-period claim amount in the cell | numeric |
| `premium_incr` | Per-period premium in the cell (risk premium for long-term health) | numeric |
| group | Optional — product, coverage, age, gender, sum insured, etc. | character / factor |

[`as_experience()`](https://seokhoonj.github.io/lossratio/reference/as_experience.md)
validates the schema and coerces date columns;
[`build_triangle()`](https://seokhoonj.github.io/lossratio/reference/build_triangle.md)
then aggregates to the canonical cohort × dev structure with cumulative
columns and derived ratios.

### Column convention

Throughout the package, cumulative is the unmarked default and
per-period values carry an `_incr` (incremental) suffix:

| Metric     | Cumulative (default) | Per-period (`_incr`) |
|------------|----------------------|----------------------|
| Loss       | `loss`               | `loss_incr`          |
| Premium    | `premium`            | `premium_incr`       |
| Loss ratio | `lr`                 | `lr_incr`            |
| Margin     | `margin`             | `margin_incr`        |
| Profit     | `profit`             | `profit_incr`        |

Raw `experience` input is per-period only (`loss_incr`, `premium_incr`);
[`build_triangle()`](https://seokhoonj.github.io/lossratio/reference/build_triangle.md)
produces both forms in the output. Fit functions take `loss_var` and
`premium_var` arguments (defaults to the cumulative slot names).

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
exp <- as_experience(experience)

# Build the canonical cohort × dev structure
tri <- build_triangle(exp, group_var = cv_nm)

plot(tri)              # cohort trajectories
plot_triangle(tri)     # cell heatmap

# Exposure-driven fit (additive ED intensity)
ed <- fit_ed(tri, value_var = "loss", premium_var = "premium")

# Chain ladder fit (multiplicative ATA factors)
cl <- fit_cl(tri, value_var = "loss", method = "mack")
plot(cl, type = "projection")

# Loss ratio fit (stage-adaptive by default — ED before maturity, CL after)
lr <- fit_lr(tri, method = "sa")
plot(lr, type = "lr")
summary(lr)

# Cell selection: maturity (dev axis) + regime (cohort axis)
detect_maturity(tri[cv_nm == "SUR"])
detect_regime(tri[cv_nm == "SUR"], K = 12, method = "ecp")

# Projection diagnostic: when does the projected ultimate LR stop revising?
detect_convergence(lr)
```

## Aggregation Frameworks

The same long-format experience data can be viewed three ways:

| Builder | Output object | Dimension | Use case |
|----|----|----|----|
| [`build_triangle()`](https://seokhoonj.github.io/lossratio/reference/build_triangle.md) | `Triangle` | cohort × dev (2D) | Chain ladder, ED, SA projection |
| [`build_calendar()`](https://seokhoonj.github.io/lossratio/reference/build_calendar.md) | `Calendar` | calendar period (1D) | Calendar-year trend / diagonal effect |
| [`build_total()`](https://seokhoonj.github.io/lossratio/reference/build_total.md) | `Total` | portfolio total (0D, per group) | High-level comparison across groups |

After `build_triangle`, downstream columns are standardized to `cohort`
and `dev` regardless of input granularity (`uym` / `uyq` / `uy`, etc.).
Original column names and granularity are preserved as attributes
(`cohort_var`, `cohort_type`, `dev_var`, `dev_type`).

## Methods

### Stage-Adaptive

`fit_lr(method = "sa")` (default). Hybrid of exposure-driven and chain
ladder, switching at the maturity point per group:

- Before maturity: exposure-driven projection
  $`\Delta C^L = g_k \cdot C^P_k`$ — anchors the estimate to premium
  volume while age-to-age factors are volatile.
- After maturity: chain ladder projection
  $`C^L_{k+1} = f_k \cdot C^L_k`$ — preserves the cohort’s observed
  level once age-to-age factors stabilise.

### Exposure-Driven

`fit_lr(method = "ed")`. All future loss increments use exposure (risk
premium) as the denominator. Suitable when age-to-age factors are
uninformative or unstable across the full development.

### Chain Ladder

`fit_lr(method = "cl")` or
[`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md).
Classical Mack chain ladder with optional log-linear tail factor and
analytic Mack standard errors.

## Visualisation

Both S3 generics dispatch on object class:

``` r

plot(x)              # base plot generic — line / panel diagnostics
plot_triangle(x)     # lossratio generic — cell heatmap layout
```

[`plot()`](https://rdrr.io/r/graphics/plot.default.html) and
[`plot_triangle()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.md)
work uniformly across `Triangle`, `Calendar`, `Link`, `ATAFit`, `EDFit`,
`CLFit`, `LRFit`, `Maturity`, `Convergence`, and `Regime` objects.

## Documentation

``` r

?build_triangle
?fit_lr
?detect_regime
vignette("regime-detection", package = "lossratio")
```

## License

GPL (\>= 2). See
[LICENSE.md](https://seokhoonj.github.io/lossratio/LICENSE.md).

## Author

Seokhoon Joo (<seokhoonj@gmail.com>)
