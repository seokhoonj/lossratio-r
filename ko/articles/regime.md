# Regime: detecting structural breaks across underwriting cohorts

## Motivation

When analysing a portfolio of long-duration health insurance cohorts, a
practitioner often asks two questions:

1.  Are recent underwriting cohorts behaving differently from earlier
    cohorts?
2.  If so, *when* did the change happen?

In long-term insurance, the cohort patterns most commonly break under
one of four triggers:

1.  **Drastic premium adjustment** — large up- or down-revision of rates
2.  **Product coverage content change** — restructuring of benefits,
    exclusions, or term
3.  **Sum insured limit change** — adjustment of per-policy maximum
4.  **Underwriting guideline change** — eligibility, declarations, or
    loading rule revisions

The bundled `experience` dataset’s SUR coverage carries a synthetic
2024-04 break representing one of these triggers, so the demonstration
below has a clear shift for
[`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
to find.

A visual inspection of `plot(tri_sur)` can suggest that recent cohorts
have lower early loss ratios than older ones, but eye-balling a bundle
of trajectories is an unreliable way to locate a structural shift —
especially when observation windows differ across cohorts.

[`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
answers both questions in one call — grouping underwriting cohorts into
**regimes** (groups of cohorts that share similar loss dynamics) and
reporting the break dates between groups. It treats each underwriting
cohort as a feature vector (its trajectory over development periods
`1, ..., K`), orders cohorts by underwriting date, and applies a
change-point or clustering method to the resulting multivariate
sequence.

## Data and setup

``` r

library(lossratio)

data(experience)
tri_sur <- build_triangle(experience[coverage == "SUR"], coverage)
```

## Detecting regimes

The default method is `"e_divisive"`, a non-parametric multivariate
change-point algorithm that determines the number of regimes from the
data:

``` r

r <- detect_regime(tri_sur, K = 12, method = "e_divisive")
r
#> <Regime>
#>   method      : e_divisive
#>   target      : lr
#>   window (K)  : dev_m 1-12
#>   cohorts     : 25 analysed (11 dropped)
#>   regimes     : 2
#>   breakpoints : 24.07
#>   PC1 / PC2   : 81.6% / 8.8%
```

The window `K` controls how many development periods define the cohort
feature vector. Only cohorts observed for at least `K` periods are
analysed; cohorts with shorter windows are dropped. Increasing `K`
captures more of the trajectory but drops more recent cohorts.

## Summary and per-regime membership

``` r

summary(r)
#> Cohort regime detection summary
#>   method    : e_divisive
#>   target    : lr
#>   window    : dev_m 1-12
#>   cohorts   : 25 analysed (11 dropped)
#> 
#> Regimes (2):
#>   1: 23.01-24.06 (18 cohorts)
#>   2: 24.07-25.01 (7 cohorts)
#> 
#> Breakpoints: 24.07

r$labels
#>         cohort      regime regime_id
#>         <Date>      <fctr>     <int>
#>  1: 2023-01-01 23.01-24.06         1
#>  2: 2023-02-01 23.01-24.06         1
#>  3: 2023-03-01 23.01-24.06         1
#>  4: 2023-04-01 23.01-24.06         1
#>  5: 2023-05-01 23.01-24.06         1
#>  6: 2023-06-01 23.01-24.06         1
#>  7: 2023-07-01 23.01-24.06         1
#>  8: 2023-08-01 23.01-24.06         1
#>  9: 2023-09-01 23.01-24.06         1
#> 10: 2023-10-01 23.01-24.06         1
#> 11: 2023-11-01 23.01-24.06         1
#> 12: 2023-12-01 23.01-24.06         1
#> 13: 2024-01-01 23.01-24.06         1
#> 14: 2024-02-01 23.01-24.06         1
#> 15: 2024-03-01 23.01-24.06         1
#> 16: 2024-04-01 23.01-24.06         1
#> 17: 2024-05-01 23.01-24.06         1
#> 18: 2024-06-01 23.01-24.06         1
#> 19: 2024-07-01 24.07-25.01         2
#> 20: 2024-08-01 24.07-25.01         2
#> 21: 2024-09-01 24.07-25.01         2
#> 22: 2024-10-01 24.07-25.01         2
#> 23: 2024-11-01 24.07-25.01         2
#> 24: 2024-12-01 24.07-25.01         2
#> 25: 2025-01-01 24.07-25.01         2
#>         cohort      regime regime_id
#>         <Date>      <fctr>     <int>
```

## Visualisation

`plot(r)` produces a PCA scatter of cohort trajectories coloured by
detected regime. If the regimes are well-separated in PCA space, the
structural shift is visually confirmed:

``` r

plot(r)
```

![](regime_files/figure-html/unnamed-chunk-4-1.png)

Arrows indicate the loadings of each development-period feature on the
PC axes — useful for reading *how* the regimes differ (e.g. whether the
shift primarily affects early or late development).

## Choice of method

- **`"e_divisive"`** — preferred default. Multivariate, non-parametric,
  auto-detects the number of regimes at a given significance level.
  Slightly slower than the alternatives but requires no a priori choice
  of `n_regimes`.

- **`"pelt"`** — fast univariate change-point detection applied to the
  first principal component. May return multiple breakpoints and is
  useful when the trajectory variation is dominated by one axis (check
  `PC1 %` in the [`print()`](https://rdrr.io/r/base/print.html) output —
  if \> 70%, PELT is reliable; if much lower, prefer `"e_divisive"`).

- **`"hclust"`** — Ward hierarchical clustering on the scaled feature
  matrix, cut to `n_regimes` clusters (default `2`). Ignores
  chronological order and is best used as a sanity check: if the
  chronological methods locate a breakpoint at time `t` and `hclust`
  produces the same two groups (all pre-`t` in one cluster, all post-`t`
  in the other), the shift is structural rather than an artefact of the
  method.

In practice, agreement across all three methods — as in the SUR example
above, where `"e_divisive"`, `"pelt"`, and `"hclust"` all locate `24.04`
as the regime boundary — is strong evidence of a real underwriting/rate
shift.

## Forcing the number of regimes

If you want to compare a fixed number of regimes — for example,
two-vs-three regime hypotheses — pass `n_regimes`:

``` r

r2 <- detect_regime(tri_sur, K = 12, method = "e_divisive", n_regimes = 3)
summary(r2)
#> Cohort regime detection summary
#>   method    : e_divisive
#>   target    : lr
#>   window    : dev_m 1-12
#>   cohorts   : 25 analysed (11 dropped)
#> 
#> Regimes (3):
#>   1: 23.01-23.08 (8 cohorts)
#>   2: 23.09-24.06 (10 cohorts)
#>   3: 24.07-25.01 (7 cohorts)
#> 
#> Breakpoints: 23.09, 24.07
```

For `"e_divisive"` and `"pelt"`, `n_regimes` is a request (the algorithm
will return up to that many regimes if supported by the data). For
`"hclust"`, it is a hard cut.

## Multi-group detection

A `Triangle` built with multiple groups can be passed directly —
detection runs independently per group and results are gathered into a
single `Regime` object.

``` r

tri_all <- build_triangle(experience, groups = coverage)
r_all   <- detect_regime(tri_all, K = 12, method = "e_divisive")
r_all$breakpoints
#>    coverage breakpoint
#>      <char>     <Date>
#> 1:      CAN 2023-09-01
#> 2:      SUR 2024-07-01
```

In multi-group mode `r_all$breakpoints` is a `data.table` with the group
column plus a `breakpoint` Date column; `r_all$labels` likewise gains
the group column; `r_all$n_regimes` is a named integer vector keyed by
group value. The `r_all$multi_group` flag distinguishes the layout from
the single-group scalar form.

If a group has too few cohorts for the chosen `K`, that group is skipped
with a warning (others continue). If *all* groups fail,
[`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
errors out.

`plot(r_all)` produces a per-group panel (composited via `patchwork`
when available).

## Relation to `fit_lr()`

[`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
is a *preprocessing diagnostic*, not a modification of the
[`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
framework. Its output is useful in two ways:

1.  **Stratified fitting**: if two clearly distinct regimes are
    detected, fitting
    [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
    separately on each regime subset often yields sharper stable-CLR
    estimates than a pooled fit.

2.  **Rate-change documentation**: a detected breakpoint provides a
    data-driven anchor for the preprocessing recommendations outlined in
    the *Limitations* section of the companion paper (premium
    on-leveling or exposure decomposition `V = C^P / r`).
