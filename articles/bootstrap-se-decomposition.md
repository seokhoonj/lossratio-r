# Decomposing bootstrap standard errors: parameter vs process uncertainty

## Two kinds of uncertainty

When projecting future loss from a chain-ladder model, the reported
standard error of an unknown future cell `Y_{i, j}` mixes *two* distinct
sources of uncertainty:

1.  **Parameter uncertainty** — we don’t know the *true* development
    factors `f_k`. We estimated them from a finite triangle, and a
    slightly different sample of past data would have given slightly
    different `f̂_k`. The standard error of `f̂_k` propagates forward into
    the projection.
2.  **Process uncertainty** — even if the *true* `f_k` were known, the
    next observed cell is not deterministic. It’s a single realisation
    from a noisy stochastic process (ODP / Gamma / Normal etc.), and the
    noise of that process is irreducible.

Mack’s (1993) closed-form mean squared error of prediction (MSEP)
expresses this as an *additive* decomposition:

``` math
\mathrm{MSEP}(Y_{i,j}) \;=\;
\underbrace{\mathrm{Var}_{\theta}(\hat\theta)}_{\substack{\text{parameter} \\ \text{(estimation) error}}}
\;+\;
\underbrace{\mathbb{E}_\theta[\mathrm{Var}(Y_{i,j}\mid\theta)]}_{\substack{\text{process} \\ \text{(irreducible) error}}}.
```

The bootstrap framework offers an *empirical* counterpart of the same
decomposition that doesn’t require closed-form variance formulas, and
applies even to stage-adaptive (ED + CL) hybrids where the Mack
analytical SE is awkward.

## Law of total variance — the math

Let `θ` denote the (unknown) model parameter vector and `Y` the forecast
at one cell. The law of total variance is

``` math
\mathrm{Var}(Y) \;=\;
\underbrace{\mathrm{Var}\bigl(\mathbb{E}[Y\mid\theta]\bigr)}_{\text{parameter variance}}
\;+\;
\underbrace{\mathbb{E}\bigl[\mathrm{Var}(Y\mid\theta)\bigr]}_{\text{process variance}}.
```

The two pieces are *orthogonal*: their contributions to total variance
add without interaction.

In bootstrap terms, with `b = 1, 2, …, B` replicates:

| symbol             | meaning                         | varies with         |
|--------------------|---------------------------------|---------------------|
| `μ_b = E[Y | θ_b]` | conditional mean under draw `b` | parameter only      |
| `Y_b = μ_b + ε_b`  | one realisation under draw `b`  | parameter + process |

The Pythagorean identity

``` math
\mathrm{Var}(Y_b) \;=\; \mathrm{Var}(\mu_b) \;+\; \mathrm{Var}(\varepsilon_b)
```

becomes the empirical estimator

``` math
\widehat{\mathrm{Var}}_{\text{total}}
\;=\;
\widehat{\mathrm{Var}}_{\text{param}}
\;+\;
\widehat{\mathrm{Var}}_{\text{proc}}
\quad\Longrightarrow\quad
\mathrm{se}_{\text{total}}^2
\;=\;
\mathrm{se}_{\text{param}}^2
\;+\;
\mathrm{se}_{\text{proc}}^2.
```

This is the *Pythagorean SE decomposition*. We need only sample standard
deviations:

``` math
\mathrm{se}_{\text{param}} \;=\; \mathrm{sd}(\mu_b\,;\,b = 1,\dots,B),\qquad
\mathrm{se}_{\text{total}} \;=\; \mathrm{sd}(Y_b\,;\,b = 1,\dots,B),\qquad
\mathrm{se}_{\text{proc}} \;=\; \sqrt{\,\mathrm{se}_{\text{total}}^2
                                       - \mathrm{se}_{\text{param}}^2}.
```

## How `bootstrap()` produces both pieces

[`bootstrap()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md)
simulates `B` pseudo triangles. Each replicate `b` does two things:

1.  **Stage 1 — parameter perturbation.** Residuals are resampled (or
    parametric `f*_k ~ N(f̂_k, sqrt(Var(f̂_k)))` are drawn) to produce a
    different set of factor estimates `θ_b`. The forward-projected mean
    `μ_b` is then computed from `θ_b`.
2.  **Stage 2 — process noise.** A single draw `ε_b` from the chosen
    process distribution (`gamma` / `od_pois` / `normal`) is added on
    top of `μ_b` to give `Y_b`.

Both values are returned, one per replicate per cell:

``` r

library(lossratio)

data(experience)
tri <- as_triangle(
  experience[experience$coverage == "surgery", ],
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  premium  = "incr_prem"
)

set.seed(42)
bt <- bootstrap(tri,
                residual    = "cell",
                method      = "sa",
                pooling     = "tail_pooled", tail = "auto",
                process     = "gamma",
                B           = 499,
                keep_pseudo = TRUE)   # opt in to long-format $pseudo_triangles
head(bt$pseudo_triangles)
#>    coverage     cohort   dev   rep loss_mean loss_sampled
#>      <char>     <Date> <int> <int>     <num>        <num>
#> 1:  surgery 2023-01-01     1     1   1504024      1504024
#> 2:  surgery 2023-02-01     1     1   4394106      4394106
#> 3:  surgery 2023-03-01     1     1   6981562      6981562
#> 4:  surgery 2023-04-01     1     1  13485841     13485841
#> 5:  surgery 2023-05-01     1     1   4038010      4038010
#> 6:  surgery 2023-06-01     1     1  10065395     10065395
```

The `pseudo_triangles` long-format table has two value columns:

- `loss_mean` — the Stage-1 mean projection `μ_b` (parameter only)
- `loss_sampled` — the Stage-1 + Stage-2 realisation `Y_b`

On the upper triangle (observed region), both columns agree — the
bootstrap perturbation has already absorbed the data variability there.
On the lower triangle (projected region), the two diverge by exactly the
process-noise draw.

## The `$summary` slot

[`bootstrap()`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md)
computes the cohort × dev decomposition once and exposes it as a
precomputed summary, so downstream fit functions can wrap-only the
columns without re-running the per-replicate sample-variance loops:

``` r

head(bt$summary)
#>    coverage     cohort   dev mean_proj param_se proc_se total_se  total_cv
#>      <char>     <Date> <int>     <num>    <num>   <num>    <num>     <num>
#> 1:  surgery 2023-01-01     1   2413024  1168569       0  1168569 0.4842756
#> 2:  surgery 2023-02-01     1   5701565  1891996       0  1891996 0.3318379
#> 3:  surgery 2023-03-01     1   5914391  1927010       0  1927010 0.3258171
#> 4:  surgery 2023-04-01     1  12424938  2802696       0  2802696 0.2255702
#> 5:  surgery 2023-05-01     1   4045507  1583080       0  1583080 0.3913180
#> 6:  surgery 2023-06-01     1   5386669  1858674       0  1858674 0.3450507
```

Column meaning:

| column | formula | interpretation |
|----|----|----|
| `mean_proj` | `mean(loss_mean across b)` | point estimate (Stage 1 average) |
| `param_se` | `sd(loss_mean across b)` | estimation error |
| `total_se` | `sd(loss_sampled across b)` | full predictive error |
| `proc_se` | `sqrt(pmax(total² − param², 0))` | irreducible process error |
| `total_cv` | `total_se / mean_proj` | coefficient of variation |
| `ci_lo` / `ci_hi` | `quantile(loss_sampled, 0.025 / 0.975, type = 1)` | empirical 95 % CI |

The `pmax(·, 0)` clamp on `proc_se` protects against finite-B noise: in
rare cells where `param_se > total_se` is observed (a sample artifact
from too few replicates), `proc_se` is set to zero rather than producing
a negative variance.

## Correspondence with Mack (1993)

The bootstrap decomposition is the empirical, simulation-based
counterpart of Mack’s analytical MSEP:

- The Mack closed-form needs explicit variance formulas (`σ²_k`,
  `Var(f̂_k)`) and requires the Mack 1993 chain-ladder paradigm —
  multiplicative recursion only.
- The bootstrap decomposition works on *any* forward simulation
  (chain-ladder, exposure-driven, stage-adaptive) and any process
  distribution (gamma / over-dispersed Poisson / normal), without
  requiring closed-form variance derivations.

For pure chain-ladder fits on small triangles, the two approaches agree
within finite-B sampling error. For stage-adaptive (ED + CL) hybrids,
the bootstrap decomposition is the *only* well-defined option, because
the Mack analytical formulas don’t compose cleanly across the
maturity-point boundary.

The decomposition is exposed as a default summary slot (`bt$summary`
columns above), so downstream `fit_*(bootstrap = bt)` calls can map it
directly into the standard fit schema (`*_param_se`, `*_proc_se`,
`*_total_se`, `*_total_cv`, `*_ci_lo`, `*_ci_hi`). The default reporting
flow includes the decomposition without the user having to assemble it.

The cell-residual mode mean-centres the residual pool within each group
before resampling. Shapland (2010, §4.2 “Negative Incremental Losses”)
discusses this adjustment as *one* option — observing that a non-zero
residual mean may equally be treated as a characteristic of the data set
and left in place.

## Picking `B` — the Davison & Hinkley convention

For an empirical percentile CI to land on an *exact* sample position
without interpolation, `(B + 1) p` should be an integer for the target
quantile probability `p`. The packaged defaults reflect this:

| `B`  | `(B+1)` | suitable for                                             |
|------|---------|----------------------------------------------------------|
| 99   | 100     | quick spot-checks, 5 % / 1 % CI                          |
| 199  | 200     | light analyses                                           |
| 499  | 500     | **default — one-sided VaR (75 %, 95 %, 99 %) all exact** |
| 999  | 1000    | published “gold standard” 95 % CI                        |
| 1999 | 2000    | Solvency II / K-ICS 99.5 % TVaR                          |

`B = 499` is the package default — it makes every commonly reported
one-sided VaR percentile (75 %, 95 %, 99 %) land on an integer ordinal
index, keeping the empirical CI exact for the standard reserving
percentile reports.

## See also

[`vignette("backtest")`](https://seokhoonj.github.io/lossratio/articles/backtest.md)
for hold-out-based bootstrap validation,
[`vignette("chain-ladder-reserving")`](https://seokhoonj.github.io/lossratio/articles/chain-ladder-reserving.md)
for the underlying CL machinery, and
[`?bootstrap`](https://seokhoonj.github.io/lossratio/reference/bootstrap.md)
for the full argument reference.
