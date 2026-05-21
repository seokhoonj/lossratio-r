# Regime change filter: hybrid cohort + diagonal cut for fit\_\*

## Motivation

When a long-term health portfolio undergoes a rate revision, coverage
restructure, or underwriting overhaul, cohorts after that event behave
differently from earlier ones. Fitting chain ladder on the full triangle
lets old-cohort link factors leak into the new-cohort projections, which
shows up as a monotone drift across `diag_summary` in
[`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md).

The `recent = N` argument suppresses some of this drift, but a
calendar-diagonal cut is symmetric across both axes — it discards older
cohorts’ young-dev cells too, where the ED region was already stable.
The natural fix is asymmetric:

- **Pre-maturity (ED region):** horizontal cut — keep only post-change
  cohorts.
- **Post-maturity (CL region):** diagonal cut — keep only the recent `N`
  calendar diagonals.

`loss_regime` (and its premium-side sibling `premium_regime`) implements
that split.

## Two-axis asymmetry

| Axis                  | Number of changes      | Source                  |
|-----------------------|------------------------|-------------------------|
| x (maturity, ED → CL) | exactly one per group  | `fit_ata$maturity`      |
| y (regime change)     | zero or many per group | `detect_regime$changes` |

The maturity point $`k^*`$ is a single internal switch produced by
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md).
Regime changes are exogenous events — there can be none, one, or
several. When a `Regime` object carries multiple changes, the
`treatment` slot decides how downstream fits use them:

- `treatment = "latest_only"` (default): collapse to the most recent
  change and drop all pre-latest cohorts. A single pooled factor is
  estimated over the surviving (post-latest) cohorts. Stable when the
  post-change window has accumulated enough cohorts and earlier regimes
  are not informative for the current one.
- `treatment = "segment_wise"`: preserve every change. Each segment
  (consecutive cohorts between adjacent changes) gets its own factor
  estimate, and each cohort is projected with its own segment’s factor.
  Use this when older regimes still need their own development tail —
  e.g., multi-regime + long-tail data where the latest regime hasn’t yet
  observed late-dev development.

Pick the treatment when constructing the Regime:

``` r

# Latest-only (default — drop pre-latest cohorts)
regime_at(change = c("2022-01-01", "2024-04-01"))

# Segment-wise (each segment gets its own factor)
regime_at(change = c("2022-01-01", "2024-04-01"),
          treatment = "segment_wise")

detect_regime(tri, treatment = "segment_wise")
```

## API

[`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md)
takes two role-specific regime arguments — `loss_regime` (loss-side
filter) and `premium_regime` (premium-side filter; defaults to
`loss_regime`).
[`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md)
/
[`fit_premium()`](https://seokhoonj.github.io/lossratio/reference/fit_premium.md)
take a single `regime` argument.
[`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
mirrors `fit_ratio` with `loss_regime` / `premium_regime`. All four
accept the same input types:

| Input | Behaviour |
|----|----|
| `NULL` (default) | no filtering — backwards compatible |
| `Regime` object | output of [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md) or [`regime_at()`](https://seokhoonj.github.io/lossratio/reference/regime_at.md) |
| `"auto"` sentinel | calls [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md) internally on the triangle |
| `function(tri) -> Regime` | closure that returns a `Regime` from a triangle |

Raw `Date` / character / vector input is no longer accepted — wrap it in
[`regime_at()`](https://seokhoonj.github.io/lossratio/reference/regime_at.md)
first to make the change explicit:

``` r

library(lossratio)
data(experience)
tri_sur <- as_triangle(
  experience[coverage == "surgery"],
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  premium  = "incr_premium"
)

# Manual change date via regime_at() — wrap a literal date in a Regime
fit_ratio(tri_sur, method = "sa", recent = 18L,
          loss_regime = regime_at(change = "2024-07-01"))

# Regime object from detect_regime() directly
reg <- detect_regime(tri_sur)
fit_ratio(tri_sur, method = "sa", recent = 18L, loss_regime = reg)

# "auto" sentinel — detect_regime() is run internally
fit_ratio(tri_sur, method = "sa", recent = 18L, loss_regime = "auto")

# Closure — defers detection until the fit sees the (filtered) triangle
fit_ratio(tri_sur, method = "sa", recent = 18L,
          loss_regime = function(tri) detect_regime(tri))
```

In simple modes (`fit_ratio(method ∈ {"ed","cl"})`) the same argument
acts as a plain cohort cut. The workers (`fit_ata`, `fit_ed`, `fit_cl`,
`fit_intensity`) expose the same 4-type `regime` argument (`NULL` /
`Regime` / `"auto"` / closure). Wrap a domain-knowledge date with
`regime_at(change = "2024-07-01")` to construct a `Regime` without
running detection.

## SA-mode hybrid behaviour

The hybrid split activates only for `fit_ratio(method = "sa")` with both
`loss_regime` and `recent`:

- dev ≤ $`k^*`$ — ED region: post-change cohorts only.
- dev \> $`k^*`$ — CL region: latest `recent` diagonals only (full
  triangle if `recent = NULL`).

The maturity point $`k^*`$ itself is found in a **two-pass** procedure:
first on the raw triangle (so noisy post-change windows do not
destabilise $`k^*`$), then the hybrid filter is applied to the actual
fit using the fixed $`k^*`$.

`plot_triangle(view = "usage")` visualises which cells each filter
configuration feeds to `fit_ratio`:

``` r

plot_triangle(tri_sur, view = "usage", holdout = 6L)                            # full
plot_triangle(tri_sur, view = "usage", recent = 12L, holdout = 6L)              # recent
plot_triangle(tri_sur, view = "usage", regime = "2024-07-01", holdout = 6L)     # change
plot_triangle(tri_sur, view = "usage", recent = 12L,
              regime = "2024-07-01", holdout = 6L)                              # hybrid
```

![Cells used by each filter configuration on the surgery triangle. Blue
= fit data, red = held out (last 6 calendar diagonals), light grey =
excluded by the filter, white = future. Vertical dashed line marks the
maturity switch k^\*; horizontal dashed line marks the regime change
cohort.](articles/figs/triangle_usage_panels.png)

Cells used by each filter configuration on the surgery triangle. Blue =
fit data, red = held out (last 6 calendar diagonals), light grey =
excluded by the filter, white = future. Vertical dashed line marks the
maturity switch $`k^*`$; horizontal dashed line marks the regime change
cohort.

The hybrid panel shows the dev-axis split that SA mode applies: a cohort
cut on the ED side and a calendar diagonal cut on the CL side, joined at
$`k^*`$.

## Case study — surgery cohort

The bundled `experience` dataset embeds a synthetic 2024-04 regime
change in the surgery coverage. Backtests on the same triangle with four
variants:

``` r

reg <- detect_regime(tri_sur)

bt_full   <- backtest(tri_sur, holdout = 6L)
bt_recent <- backtest(tri_sur, holdout = 6L, recent = 18L)
bt_change <- backtest(tri_sur, holdout = 6L,
                      loss_regime = reg)
bt_hybrid <- backtest(tri_sur, holdout = 6L, recent = 18L,
                      loss_regime = reg)
```

Reproduced from `dev/regime_backtest_hybrid.R`:

| Variant                       | drift (cal30 − cal25) | overall mean |
|-------------------------------|-----------------------|--------------|
| full                          | +4.50pp               | -1.25%       |
| recent = 18                   | +2.03pp               | -3.45%       |
| **loss_regime + recent = 18** | **-0.69pp**           | **+0.03%**   |

Two columns summarise the A/E Error = `actual / proj − 1` (positive =
under-projection) measured on the held-out diagonals:

- **drift (cal30 − cal25)**: A/E Error aggregated by calendar diagonal,
  then the (latest − earliest) difference. Captures whether the
  prediction error is monotonically changing across the hold-out window
  — the signature of a regime change that the static model has not
  absorbed.
- **overall mean**: cell-level mean A/E Error across all held-out cells
  — the model’s directional bias.

Drift collapses from +4.50pp under `full` to -0.69pp under the hybrid
filter; the overall mean returns to ~0. The hybrid joins two axis cuts
at $`k^*`$: a cohort cut on the ED side (dev ≤ k\*) and a calendar
diagonal cut on the CL side (dev \> k\*).

## Multi-group handling

[`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
assumes a single-group triangle. For a portfolio with multiple
`coverage` groups, call it per group:

``` r

fits <- lapply(unique(exp$coverage), function(g) {
  tri_g <- as_triangle(
    experience[coverage == g],
    groups   = "coverage",
    cohort   = "uy_m",
    calendar = "cy_m",
    loss     = "incr_loss",
    premium  = "incr_premium"
  )
  reg_g <- detect_regime(tri_g)
  fit_ratio(tri_g, method = "sa", recent = 18L,
            loss_regime = reg_g)
})
```

A future extension may accept
`loss_regime = list(surgery = regime_at(...), cancer = regime_at(...))`.
Today only `NULL` / `Regime` / `"auto"` / closure are supported.

## Limitations

If the post-change window is too short (small `n_post`), the ED
intensity $`g_k`$ and link factors $`f_k`$ become noisy. A practical
threshold is `n_post ≳ 6`. Below that, prefer `recent` alone, or wait
for credibility-weighted blending of pre- and post-change factors
(planned).

Note also that `loss_regime` / `premium_regime` only filter the data
feeding link factor estimation. Once the factors are fixed, all cohorts
share them, so pre-change ultimates inherit the post-change dynamics.

## See also

- [`vignette("projection")`](https://seokhoonj.github.io/lossratio/articles/projection.md)
  —
  [`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md)
  and the `"sa"`, `"ed"`, `"cl"` methods.
- [`vignette("backtest")`](https://seokhoonj.github.io/lossratio/articles/backtest.md)
  — diagnosing the impact of `recent` and `loss_regime`.
- [`vignette("regime")`](https://seokhoonj.github.io/lossratio/articles/regime.md)
  —
  [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  reference.
- [`?fit_ratio`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md),
  [`?fit_ata`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md),
  [`?fit_ed`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md),
  [`?detect_regime`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md),
  [`?regime_at`](https://seokhoonj.github.io/lossratio/reference/regime_at.md).
