# Diagnosing loss ratio convergence with find_lr_convergence()

## Motivation

[`find_ata_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/find_ata_maturity.md)
answers the question *“from which development period are link factors
$`f_k`$ reproducible across cohorts?”*. That is necessary for
chain-ladder projection but not sufficient for declaring a portfolio’s
projected loss ratio converged: in long-duration health insurance both
$`f_k \to 1`$ and $`g_k \to 0`$ arise mechanically from cumulative
denominators growing, regardless of whether the underlying experience
has actually settled. A criterion built on those quantities passes
automatically with $`k`$, not because of true convergence — what we have
called the *inertia* failure mode.

[`find_lr_convergence()`](https://seokhoonj.github.io/lossratio/ko/reference/find_lr_convergence.md)
detects the **convergence point** $`k^{**}`$ — the first valuation
$`v \ge k^*`$ at which the projected loss ratio has predictively
converged. It is the natural counterpart to $`k^*`$ (maturity point,
from
[`find_ata_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/find_ata_maturity.md)):
$`k^*`$ marks where link factors $`f_k`$ become reproducible, while
$`k^{**}`$ marks where the projection itself stops moving with new data.
Long-duration health portfolios may cross $`k^*`$ early yet remain far
from $`k^{**}`$.

The detector combines two orthogonal conditions, both required to hold
for $`M`$ consecutive valuations:

1.  **Predictive revision** is small relative to its parameter SE:
    $`R_v < c \cdot \hat{SE}^{\mathrm{param}}_v`$, where
    $`R_v = |\hat{LR}^{\mathrm{proj}}_v(D_v) -
    \hat{LR}^{\mathrm{proj}}_v(D_{v-1})|`$ is the change in the
    projected portfolio LR caused by adding one new calendar diagonal.
2.  **Cross-cohort dispersion** of incremental LR is small:
    $`\hat{D}_v < \tau`$, where
    $`\hat{D}_v = 1.4826 \cdot \mathrm{MAD}_i(\hat{lr}_{i,v}) /
    |\mathrm{median}_i(\hat{lr}_{i,v})|`$.

Operating $`\hat{D}_v`$ on **incremental** rather than cumulative loss
ratio keeps it inertia-free — per-period quantities have no cumulative
denominator to dampen them. The two clauses guard against complementary
failure modes: $`R_v`$ checks that the *model output* has stopped
revising, while $`\hat{D}_v`$ checks that the *raw period-by-period
experience* is genuinely consistent across cohorts at that dev. Either
alone can be fooled — in chain-ladder projection the mechanical drift
$`\hat{f}_k \to 1`$ collapses $`R_v`$ regardless of true convergence,
and cross-cohort agreement on a single period’s level need not imply
that the projection has settled. The dual criterion closes both
inertia-leakage paths.

## Notation

| Symbol | Meaning |
|----|----|
| $`i`$ | cohort index (UY) |
| $`v`$ | valuation index — the calendar diagonal; “$`v`$ diagonals observed” |
| $`V`$ | maximum observed valuation (max dev in the triangle) |
| $`k^*`$ | maturity point (from [`find_ata_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/find_ata_maturity.md)); lower bound on candidate $`v`$ |
| $`k^{**}`$ | convergence point — the value [`find_lr_convergence()`](https://seokhoonj.github.io/lossratio/ko/reference/find_lr_convergence.md) returns |
| $`\hat{LR}^{\mathrm{proj}}_v`$ | projected ultimate LR using data through valuation $`v`$ |
| $`R_v`$ | revision: $`\lvert\hat{LR}^{\mathrm{proj}}_v - \hat{LR}^{\mathrm{proj}}_{v-1}\rvert`$ |
| $`\hat{SE}^{\mathrm{param}}_v`$ | parameter-uncertainty SE of $`\hat{LR}^{\mathrm{proj}}_v`$ (Mack-style) |
| $`\hat{lr}_{i,v}`$ | incremental loss ratio of cohort $`i`$ at dev $`v`$ |
| $`\hat{D}_v`$ | robust scale-invariant dispersion of $`\hat{lr}_{i,v}`$ across cohorts |
| $`c`$ | multiplier on $`\hat{SE}^{\mathrm{param}}_v`$ for the revision gate (default `0.5`) |
| $`\tau`$ | upper bound on $`\hat{D}_v`$ for the dispersion gate (default `0.15`) |
| $`M`$ | required run length of consecutive passing valuations (default `3L`) |

The constant $`1.4826 \approx 1 / \Phi^{-1}(0.75)`$ inside $`\hat{D}_v`$
is the standard MAD$`\to\sigma`$ correction: with this scaling
$`\mathrm{MAD}_i`$ becomes a consistent estimator of the cross-cohort
standard deviation under normality, so $`\hat{D}_v`$ reads as a robust,
outlier-resistant coefficient of variation of incremental LR.

## Basic usage

``` r

library(lossratio)
data(experience)
exp <- as_experience(experience)
tri <- build_triangle(exp[cv_nm == "SUR"], cv_nm)

res <- find_lr_convergence(tri)
print(res)
```

Mock output:

    #> <LRConvergence>
    #> k_conv       : NA
    #> k_star       : 9
    #> V (max dev)  : 30
    #> criterion    : R_v < 0.5 * SE_param_v  AND  D_v < 0.15  (run M = 3)
    #> fit_fn       : fit_lr
    #> v candidates : 19 ( 0  pass both clauses)

The returned `LRConvergence` object reports:

- `k_conv` — the detected $`k^{**}`$, or `NA` if no run of $`M`$
  consecutive passing valuations is found.
- `k_star` — the maturity point used as the lower bound (computed
  internally via
  [`find_ata_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/find_ata_maturity.md)
  on a clr-based ATA, or supplied by the caller).
- `V` — the maximum observable dev in the triangle.
- `v`, `R_v`, `SE_param_v`, `D_v`, `pass_v` — per-valuation diagnostic
  sequences indexed by $`v`$.
- `c`, `tau`, `M`, `holdout_max`, `min_n_cohorts` — settings used.
- attributes `group_var`, `value_var`, `fit_fn_name`, `dev_var`.

`summary(res)` returns a `data.table` with one row per candidate
valuation and an extra `R_over_SE = R_v / SE_param_v` column for
inspection:

``` r

head(summary(res), 6)
```

    #>        v    R_v   SE_param_v  R_over_SE   D_v     pass
    #> 1:     9     NA           NA         NA  0.90   FALSE
    #> 2:    10     NA           NA         NA  0.76   FALSE
    #> 3:    11     NA           NA         NA  0.56   FALSE
    #> 4:    12     NA           NA         NA  0.58   FALSE
    #> 5:    13     NA           NA         NA  0.81   FALSE
    #> 6:    14     NA           NA         NA  0.43   FALSE

`R_v` and `SE_param_v` are `NA` for early valuations whose holdout depth
exceeds `holdout_max`. The default
`holdout_max = floor((V - k_star) / 2)` keeps every backtest with a
reasonable refit window; relax it if you need diagnostics deeper into
the past.

## Plot

``` r

plot(res)
```

The diagnostic is two stacked panels: the upper panel shows
$`R_v / \hat{SE}^{\mathrm{param}}_v`$ against $`v`$ with a horizontal
guide at $`c`$; the lower panel shows $`\hat{D}_v`$ against $`v`$ with a
horizontal guide at $`\tau`$. A vertical dotted line marks $`k^*`$, and
a vertical solid line marks $`k^{**}`$ when one is detected. A point
falling **below both threshold lines** passes the joint criterion.

This view is also a quick way to see *which clause is binding*. If the
top panel hugs the threshold but the bottom is far above, the issue is
cross-cohort heterogeneity; if the bottom is fine but the top is high,
the model is still revising.

## Threshold tuning

The defaults are deliberately conservative:

| Argument | Default | Meaning |
|----|----|----|
| `c` | `0.5` | Revision must be smaller than half the parameter SE. |
| `tau` | `0.15` | Cross-cohort dispersion must be below 15% of the median lr. |
| `M` | `3L` | Both clauses must hold for at least 3 consecutive valuations. |
| `min_n_cohorts` | `5L` | Below this cohort count, $`\hat{D}_v`$ is `NA` (insufficient sample). |

Tighter thresholds yield later (or no) $`k^{**}`$; sweep a range to
inspect sensitivity:

``` r

sapply(
  c(0.25, 0.5, 0.75, 1.0),
  function(cc) find_lr_convergence(tri, c = cc)$k_conv
)
```

Values of $`\hat{D}_v`$ below $`\tau \approx 0.05`$ are difficult to
attain in real portfolios because of single-period claim noise; values
above $`0.20`$ usually indicate genuine cohort heterogeneity that
warrants
[`detect_cohort_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_cohort_regime.md)
before further modelling.

## Relation to `k^*` and `detect_cohort_regime()`

The three diagnostics answer different questions and operate on
different axes:

| Tool | Question | Result | Axis |
|----|----|----|----|
| [`detect_cohort_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_cohort_regime.md) | Are cohorts homogeneous? | cohort groups | underwriting period |
| [`find_ata_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/find_ata_maturity.md) ($`k^*`$) | When are link factors reproducible? | a dev value | development period |
| [`find_lr_convergence()`](https://seokhoonj.github.io/lossratio/ko/reference/find_lr_convergence.md) ($`k^{**}`$) | When does the LR estimate stop revising? | a dev value | development period |

A defensible workflow is:

1.  Run
    [`detect_cohort_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_cohort_regime.md).
    If multiple regimes exist, fit each group separately.
2.  For each homogeneous group, compute $`k^*`$ via
    [`find_ata_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/find_ata_maturity.md).
3.  Run
    [`find_lr_convergence()`](https://seokhoonj.github.io/lossratio/ko/reference/find_lr_convergence.md)
    to obtain $`k^{**} \ge k^*`$. The reported
    $`\hat{clr}^{\mathrm{stable}}`$ is the LR averaged over
    $`k \ge k^{**}`$ (or projected via
    [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)).

The sequence separates *cohort homogeneity*, *link reproducibility*, and
*level convergence* — three properties that coincide in P&C run-off but
must be verified independently in long-duration health insurance.

## Limitations

[`find_lr_convergence()`](https://seokhoonj.github.io/lossratio/ko/reference/find_lr_convergence.md)
is a thin layer over repeated
[`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
calls and inherits their constraints:

- **Identifiability**: $`k^{**}`$ can be declared only when
  $`V \ge k^* + M`$; short observation windows return `NA`.
- **Model conditioning**: $`\hat{LR}^{\mathrm{proj}}_v`$ is computed by
  `fit_fn` (default `fit_lr`). Different fitters yield different
  $`k^{**}`$. Reporting under multiple `fit_fn` is recommended for
  robustness.
- **Portfolio aggregation**: $`R_v`$ and $`\hat{SE}^{\mathrm{param}}_v`$
  are exposure-weighted across cohorts assuming inter-cohort
  independence. Calendar-year shocks (regulatory, healthcare cost trend)
  violate this assumption; both clauses can move together for non-cohort
  reasons.
- **Multi-group triangles**: the helper currently collapses
  $`\hat{D}_v`$ across groups by median; running each group separately
  is recommended when groups behave differently.

## See also

- [`?find_lr_convergence`](https://seokhoonj.github.io/lossratio/ko/reference/find_lr_convergence.md),
  [`?find_ata_maturity`](https://seokhoonj.github.io/lossratio/ko/reference/find_ata_maturity.md),
  [`?backtest`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md),
  [`?detect_cohort_regime`](https://seokhoonj.github.io/lossratio/ko/reference/detect_cohort_regime.md).
- Vignette `regime-detection` — cohort homogeneity diagnostics that feed
  step 1 of the workflow above.
