# Regime break filter: hybrid cohort + diagonal cut for fit\_\*

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

- **Pre-maturity (ED region):** horizontal cut — keep only post-break
  cohorts.
- **Post-maturity (CL region):** diagonal cut — keep only the recent `N`
  calendar diagonals.

`regime_break` implements that split.

## Two-axis asymmetry

| Axis                  | Number of changes      | Source                      |
|-----------------------|------------------------|-----------------------------|
| x (maturity, ED → CL) | exactly one per group  | `fit_ata$maturity`          |
| y (regime break)      | zero or many per group | `detect_regime$breakpoints` |

The maturity point $`k^*`$ is a single internal switch produced by
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md).
Regime breaks are exogenous events — there can be none, one, or several.
When `regime_break` receives multiple values, the **most recent** is
used, since post-break statistics are most stable when the post-break
window has accumulated the largest number of cohorts.

## API

`regime_break` is a shared argument on `fit_ata`, `fit_ed`, and
`fit_lr`. It accepts:

| Input | Behaviour |
|----|----|
| `NULL` (default) | no filtering — backwards compatible |
| `Date` or character scalar | single break date |
| Date/character vector | uses the latest entry |
| `Regime` object | output of [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md) passed in |

``` r

library(lossratio)
data(experience)
tri_sur <- build_triangle(experience[coverage == "SUR"], coverage)

# Single break date
fit_lr(tri_sur, method = "sa", recent = 18L,
       regime_break = "2024-07-01")

# Regime object directly
reg <- detect_regime(tri_sur)
fit_lr(tri_sur, method = "sa", recent = 18L, regime_break = reg)

# Vector — latest is used (= 2024-04-01)
fit_lr(tri_sur, method = "sa",
       regime_break = c("2022-06-01", "2024-07-01"))
```

In simple modes (`fit_ata`, `fit_ed`, or `fit_lr(method ∈ {"ed","cl"})`)
the same argument acts as a plain cohort cut.

## SA-mode hybrid behaviour

The hybrid split activates only for `fit_lr(method = "sa")` with both
`regime_break` and `recent`:

- dev ≤ $`k^*`$ — ED region: post-break cohorts only.
- dev \> $`k^*`$ — CL region: latest `recent` diagonals only (full
  triangle if `recent = NULL`).

The maturity point $`k^*`$ itself is found in a **two-pass** procedure:
first on the raw triangle (so noisy post-break windows do not
destabilise $`k^*`$), then the hybrid filter is applied to the actual
fit using the fixed $`k^*`$.

`plot_triangle(type = "usage")` visualises which cells each filter
configuration feeds to `fit_lr`:

``` r

plot_triangle(tri_sur, type = "usage", holdout = 6L)                                 # full
plot_triangle(tri_sur, type = "usage", recent = 12L, holdout = 6L)                   # recent
plot_triangle(tri_sur, type = "usage", regime_break = "2024-07-01", holdout = 6L)    # break
plot_triangle(tri_sur, type = "usage", recent = 12L,
              regime_break = "2024-07-01", holdout = 6L)                             # hybrid
```

![Cells used by each filter configuration on the SUR triangle. Blue =
fit data, red = held out (last 6 calendar diagonals), light grey =
excluded by the filter, white = future. Vertical dashed line marks the
maturity switch k^\*; horizontal dashed line marks the regime break
cohort.](articles/figs/regime_break_data_usage.png)

Cells used by each filter configuration on the SUR triangle. Blue = fit
data, red = held out (last 6 calendar diagonals), light grey = excluded
by the filter, white = future. Vertical dashed line marks the maturity
switch $`k^*`$; horizontal dashed line marks the regime break cohort.

The hybrid panel shows the dev-axis split that SA mode applies: a cohort
cut on the ED side and a calendar diagonal cut on the CL side, joined at
$`k^*`$.

## Case study — SUR cohort

The bundled `experience` dataset embeds a synthetic 2024-04 break in the
SUR coverage. Backtests on the same triangle with four variants:

``` r

reg <- detect_regime(tri_sur)

bt_full   <- backtest(tri_sur, holdout = 6L)
bt_recent <- backtest(tri_sur, holdout = 6L, recent = 18L)
bt_break  <- backtest(tri_sur, holdout = 6L,
                      regime_break = reg)
bt_hybrid <- backtest(tri_sur, holdout = 6L, recent = 18L,
                      regime_break = reg)
```

Reproduced from `dev/regime_backtest_hybrid.R`:

| Variant                        | drift (cal30 − cal25) | overall mean |
|--------------------------------|-----------------------|--------------|
| full                           | +4.50pp               | -1.25%       |
| recent = 18                    | +2.03pp               | -3.45%       |
| **regime_break + recent = 18** | **-0.69pp**           | **+0.03%**   |

Two columns summarise the A/E Error = `actual / pred − 1` (positive =
under-projection) measured on the held-out diagonals:

- **drift (cal30 − cal25)**: A/E Error aggregated by calendar diagonal,
  then the (latest − earliest) difference. Captures whether the
  prediction error is monotonically changing across the hold-out window
  — the signature of a regime that the static model has not absorbed.
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
  tri_g <- build_triangle(experience[coverage == g], coverage)
  reg_g <- detect_regime(tri_g)
  fit_lr(tri_g, method = "sa", recent = 18L,
         regime_break = reg_g)
})
```

A future extension may accept
`regime_break = list(SUR = "2024-07-01", CAN = "2022-12-01")`. Today
only scalar / vector / `Regime` are supported.

## Limitations

If the post-break window is too short (small `n_post`), the ED intensity
$`g_k`$ and link factors $`f_k`$ become noisy. A practical threshold is
`n_post ≳ 6`. Below that, prefer `recent` alone, or wait for
credibility-weighted blending of pre- and post-break factors (planned).

Note also that `regime_break` only filters the data feeding link factor
estimation. Once the factors are fixed, all cohorts share them, so
pre-break ultimates inherit the post-break dynamics.

## See also

- [`vignette("projection")`](https://seokhoonj.github.io/lossratio/articles/projection.md)
  —
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)
  and the `"sa"`, `"ed"`, `"cl"` methods.
- [`vignette("backtest")`](https://seokhoonj.github.io/lossratio/articles/backtest.md)
  — diagnosing the impact of `recent` and `regime_break`.
- [`vignette("regime")`](https://seokhoonj.github.io/lossratio/articles/regime.md)
  —
  [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  reference.
- [`?fit_lr`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md),
  [`?fit_ata`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md),
  [`?fit_ed`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md),
  [`?detect_regime`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md).
