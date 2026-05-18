# Methodology and design rationale

> Korean version: [방법론과 설계
> 근거](https://seokhoonj.github.io/lossratio/articles/articles/methodology-ko.md)

This document describes what `lossratio` is, why it is designed the way
it is, and where it is going. The intended reader is a practitioner
working on long-term health insurance loss ratios — across actuarial,
product, underwriting, claims, planning, and risk management functions.

## Why this package exists

Loss ratio is a daily task in long-term health insurance: analysing
cohort-level patterns, projecting ultimate outcomes, and monitoring
realised experience against expectations. Existing reserving toolkits
mostly trace back to property and casualty (P&C) origins, where the
following long-term health characteristics are not directly captured:

- **Denominator effect and inertia** — Cumulative loss ratio’s
  denominator grows mechanically with development, dampening the signal
  of recent experience.
- **Recurrent claims** — Hospitalisation, surgery (grade 1-5), and
  outpatient coverage allow a single insured to file multiple claims;
  cumulative claim count can exceed insured count.
- **Risk premium decomposition** — In Korea, long-term insurance premium
  splits into risk premium + savings premium + loading premium. The
  actuarially meaningful denominator for loss ratio is the *risk
  premium* portion alone.
- **Levelled premium** — Non-renewable contracts charge a level premium
  computed at issue as the lifetime average. The *charged premium* is
  not exposure; the *period risk premium* (morbidity rate × sum insured
  × persistency) must be constructed externally before being passed in.
- **Regime change** — Product redesigns, rate revisions, channel-mix
  shifts, and underwriting updates introduce *cohort-level* structural
  breaks in loss-ratio dynamics.

`lossratio` is a framework that transplants core P&C reserving
methodology — Mack (1993) chain ladder, Bornhuetter-Ferguson (1972),
Cape Cod (Stanard 1985), Bühlmann-Straub (1970) credibility, and Sherman
(1984) tail extrapolation — and adapts each piece to the five long-term
health issues above. The academic lineage is preserved; the goal is a
tool that domain practitioners can use immediately.

## P&C methodology lineage

The methodological roots of long-term loss-ratio estimation lie in the
following P&C reserving thread:

    1967  Bühlmann credibility           experience rating formalised
    1970  Bühlmann-Straub                exposure-varying credibility
                                         (volume-weighted estimator)
    1972  Bornhuetter-Ferguson           prior + observed loss blending
    1984  Sherman                        chain ladder tail extrapolation
    1985  Stanard (Cape Cod)             reserving application of B-S
                                         (named after workshop venue)
    1993  Mack                           distribution-free MSE for chain
                                         ladder

Two core ideas matter for long-term health:

- **Chain ladder (Mack 1993)** — Markov multiplicative recursion on
  cumulative loss $`C_k`$: $`C_{k+1} = f_k \cdot C_k`$ where
  $`f_k = \sum_i C_{i,k+1} / \sum_i C_{i,k}`$.
- **Cape Cod / Bühlmann-Straub** — Loss anchored to exposure (volume).
  $`\widehat{ELR} = \sum_i L_i / \sum_i \pi_i`$ yields a single ratio
  that drives ultimate estimation.

Both apply *partially* to long-term health, but both have cracks.

## Where P&C methodology cracks under long-term health

| Domain issue | Chain ladder | Cape Cod |
|----|----|----|
| Denominator effect / inertia | Early-dev $`f_k`$ over-volatile (small $`C_k`$) | Cohort-level ELR variation ignored |
| Levelled premium | Loss-only avoids it (but weak against incidence shifts) | Flat $`\pi`$ absorbs developing exposure |
| Recurrent claims | Works (freq × sev decoupled) | Works (volume measure only) |
| Developing risk premium | Not relevant | *Single $`\pi`$* assumption breaks |
| Cohort-level regime change | Violates Mack’s no-calendar-year-effect | Cohort heterogeneity averaged out |

→ Chain ladder is weak early, Cape Cod cannot track developing exposure.
Each paradigm is incomplete on its own.

## Six adaptations in lossratio — each maps to a domain issue

| \# | Adaptation | Domain issue it addresses |
|----|----|----|
| \(a\) | **2D exposure triangle** — extend Cape Cod’s single $`\pi`$ to a cohort × dev triangle | Developing risk premium |
| \(b\) | **per-link $`g_k`$** — refine Cape Cod’s cohort-level ELR to per-link intensity | Denominator effect / inertia (link-level variation) |
| \(c\) | **Stage-adaptive (SA) hybrid** — substitute exposure-driven (ED) for chain ladder in the early-dev unstable region; switch to chain ladder after maturity | Early-dev ATA volatility |
| \(d\) | **Regime detection** — automatic detection of structural break points on the cohort axis, with filter | Rate / underwriting changes |
| \(e\) | **Paradigm-matched bootstrap** — beyond Mack’s analytical SE, provide bootstrap tools matched to the paradigm (cell / link / parametric) | Robustness of variance estimation |
| \(f\) | **Sherman tail (planned)** — generic tail handling that applies to any dev-decay series, not chain ladder specifically | Extrapolation to true ultimate |

Each adaptation is a *targeted reuse* of a P&C method for a specific
long-term health issue — not a new paradigm built from scratch, but an
honest transplant + adaptation of the existing literature.

## Core framework — `loss / exposure / ratio`

All estimation rests on three observable quantities:

| Quantity | Meaning | Triangle column |
|----|----|----|
| **loss** | Cumulative loss | `loss`, `incr_loss` |
| **exposure** | Risk-bearing volume (risk premium for long-term health) | `exposure`, `incr_exposure` |
| **ratio** | Loss ratio (cumulative loss / cumulative exposure) | `ratio`, `incr_ratio` |

All three are *stochastic observables developing over the cohort × dev
grid*. Exposure is not a fixed underwriting volume; it is a developing
quantity driven by morbidity × sum insured × persistency — the *volume
measure* of Mack (1993), the *natural weight* of Bühlmann-Straub (1970).

## Estimation method library — `ed` / `cl` / `sa` (current) + `bf` / `cc` (planned)

### Current (three methods)

| Method | Point estimate | Variance helper | Domain character |
|----|----|----|----|
| **`"ed"`** (default) | $`\Delta L_{k+1} = g_k \cdot P_k`$ (additive) | `.ed_g_var` (B-S 1970) | Robust to early-dev ATA volatility |
| **`"cl"`** | $`L_{k+1} = f_k \cdot L_k`$ (multiplicative) | `.mack_f_var` (Mack 1993) | Natural after late-dev factor stabilisation |
| **`"sa"`** | ED before maturity $`k^*`$, CL after | Composition | Stage-adaptive composition of ED and CL |

The order `ed` → `cl` → `sa` mirrors the methodological progression:
*primitive (ED) → classical (CL) → composition (SA)*.

### Planned (two methods) — *prior-anchored family*

| Method | Point estimate | ELR source | Domain use case |
|----|----|----|----|
| **`"bf"`** | $`\text{Ult} = L_{\text{latest}} + (1 - 1/\text{LDF}) \cdot \pi \cdot \text{ELR}_{\text{prior}}`$ | External (user supplied) | Immature cohorts + post-rate-change cohorts — anchor on an external prior when observed data is thin (Bornhuetter-Ferguson 1972) |
| **`"cc"`** | Same form, ELR derived from data | Payout-weighted $`\sum L / \sum \pi \cdot \text{payout}`$ | Cohort-cohesive estimation — when pricing/industry suggests a natural single ELR target (Stanard 1985, Cape Cod) |

Three aggregation axes coexist:

- **ED**: per-link $`g_k`$ — dev-granular, cohort-uniform per link
- **CC**: cohort-level single ELR — cohort-uniform, dev-aggregated
- **BF**: external prior — bypasses data estimation altogether

→ The five-method library reconstructs the P&C reserving trinity for
long-term health; the three aggregation axes each serve distinct use
cases.

## Why ED is the default

Long-term health’s combination of denominator effect + early-dev ATA
volatility demands an *unconditional safe baseline*:

- **ED operates single-pass** — no maturity detection dependency.
- **ED anchors on exposure** — the small $`C_k`$ of early dev does not
  inflate the estimate (no $`C_k`$ in denominator).
- **SA is two-pass** (maturity detection → projection) — more refined
  but with infrastructure cost.
- **CL is natural only after late-dev stabilisation** — direct early-dev
  application is risky.

Making ED the unconditional default ensures predictable behaviour across
any cohort, with the more sophisticated methods (SA, BF, CC) reachable
through explicit user choice.

## Diagnostic toolkit

The methods are supported by a diagnostic surface that examines the data
along the cell, cohort, dev, and calendar-diagonal axes:

| Tool | What it diagnoses | Output |
|----|----|----|
| [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md) | dev axis — where age-to-age factors stabilise | `Maturity` object with per-cohort $`k^*`$ |
| [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md) | cohort axis — structural break points | `Regime` object with change dates |
| [`detect_convergence()`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md) | projected loss-ratio stability point $`k^{**}`$ | `Convergence` object with per-holdout fits |
| [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md) | calendar-diagonal hold-out | actual vs expected, by cohort × dev × calendar |
| [`bootstrap()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md) | variance — cell / link / parametric paradigm | pseudo-triangles + percentile CI |

## Variance estimation — analytical and bootstrap

Two paths for SE estimation:

- **Analytical** —
  [`.mack_f_var()`](https://seokhoonj.github.io/lossratio/reference/dot-mack_f_var.md)
  (Mack 1993) and
  [`.ed_g_var()`](https://seokhoonj.github.io/lossratio/reference/dot-ed_g_var.md)
  (B-S
  1970. provide closed-form per-link variance, distribution-free.
- **Bootstrap** — residual paradigm (`cell` / `link` / `parametric`)
  drives forward simulation. Captures distributional shape and enforces
  paradigm matching: residual choice determines both process variance
  scale and forward-sim model.

Large divergence between the two paths is a model-misspecification
signal; routinely computing both serves as a sanity check.

## Tail extrapolation (planned)

After
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)’s
$`k^*`$, the observed dev range ends short of the true ultimate. Tail
extrapolation is needed. The planned `fit_tail()` family covers two
paradigms: Sherman (1984)’s log-linear curve fit (exponential /
inverse-power / Weibull forms — descriptive), and Clark (2003)’s
parametric growth curve (loglogistic / Weibull MLE — stochastic). Both
reachable through one entry:

``` r

fit_tail(f_vec, devs, K_ultimate = 360,
         method        = "exponential",     # or "inverse_power",
                                            # "weibull", "loglogistic_mle"
         fit_dev_range = c(10, max_observed_dev))
```

For long-term health, the true ultimate is decades away, so the tail
extrapolation can account for a critical fraction of the reserve. Domain
expertise and sensitivity analysis are essential — running both the
Sherman descriptive fit and the Clark MLE form on the same series is a
natural cross-check.

## Roadmap

The current scope is loss-ratio analysis, projection, and monitoring.
The mathematical structure of the framework generalises naturally to
several adjacent areas:

- **BF / Cape Cod** — see Section *Estimation method library*; the
  prior-anchored family is the next planned addition.
- **Frequency-severity decomposition** —
  `fit_ed(loss = "claim_count", exposure = "insureds")` for frequency,
  `fit_ed(loss = "loss", exposure = "claim_count")` for severity. The
  framework works through slot reinterpretation alone.
- **Lifetime / cohort analysis** — full life-cycle loss-ratio tracking
  per issue-year cohort. A natural extension of the existing framework.
- **Sherman / Clark tail** — see *Tail extrapolation* above.
- **Python sibling** — `lossratio-py` will be aligned to the same naming
  and API.

## See also

- [`vignette("getting-started")`](https://seokhoonj.github.io/lossratio/articles/getting-started.md)
  — package quick-start guide.
- [`vignette("projection")`](https://seokhoonj.github.io/lossratio/articles/projection.md)
  — comparison of the three projection methods.
- [`vignette("regime")`](https://seokhoonj.github.io/lossratio/articles/regime.md)
  — regime detection and filtering.
- [`vignette("backtest")`](https://seokhoonj.github.io/lossratio/articles/backtest.md)
  — calendar-diagonal hold-out validation.
- [`vignette("convergence")`](https://seokhoonj.github.io/lossratio/articles/convergence.md)
  — projected loss-ratio convergence diagnostic.
- [`vignette("triangle-link-and-maturity")`](https://seokhoonj.github.io/lossratio/articles/triangle-link-and-maturity.md)
  — Triangle / Link / Maturity data flow.

## References

- Bornhuetter, R. L. and Ferguson, R. E. (1972). The actuary and IBNR.
  *Proceedings of the Casualty Actuarial Society*, 59, 181-195.
- Bühlmann, H. (1967). Experience rating and credibility. *ASTIN
  Bulletin*, 4(3), 199-207.
- Bühlmann, H. and Straub, E. (1970). Glaubwürdigkeit für Schadensätze.
  *Bulletin of the Swiss Association of Actuaries*, 70, 111-133.
- Clark, D. R. (2003). LDF curve-fitting and stochastic reserving: A
  maximum likelihood approach. *CAS Forum*, Fall 2003.
- Mack, T. (1993). Distribution-free calculation of the standard error
  of chain ladder reserve estimates. *ASTIN Bulletin*, 23(2), 213-225.
- Sherman, R. E. (1984). Extrapolating, smoothing, and interpolating
  development factors. *Proceedings of the Casualty Actuarial Society*,
  71, 122-155.
- Stanard, J. N. (1985). A simulation test of prediction errors of loss
  reserve estimation techniques. *Proceedings of the Casualty Actuarial
  Society*, 72, 124-153.
