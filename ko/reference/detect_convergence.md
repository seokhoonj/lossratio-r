# Find the development period at which the loss ratio estimate stabilises

Identify the first valuation \\k^{\*\*}\\ from which the projected loss
ratio is *predictively* stable, in the sense of the paper's Section 11
\\k^{\*\*}\\ criterion:

\$\$k^{\*\*} = \min\\v \in \[k^\*, V - M\] : R_v \< c \cdot
\hat{SE}^{param}\_v \text{ and } \hat{D}\_v \< \tau, \text{ for } M
\text{ consecutive valuations}\\\$\$

where \\R_v\\ is the predictive revision in the projected loss ratio
when calendar diagonal \\D_v\\ is added, \\\hat{SE}^{param}\_v\\ is the
parameter component of the Mack standard error of the projection,
\\\hat{D}\_v\\ is the robust cross-cohort dispersion of incremental loss
ratios at \\v\\, and \\k^\*\\ is the age-to-age maturity point from
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md).

Both clauses guard against complementary failure modes: \\R_v \< c \cdot
\hat{SE}^{param}\_v\\ requires the projection to stop responding to new
diagonals at a scale-relevant magnitude; \\\hat{D}\_v \< \tau\\ requires
cross-cohort agreement on the incremental-LR level (inertia-free
per-period quantity).

This function corresponds to the paper's *convergence point*
\\k^{\*\*}\\, paired with \\k^\*\\ (maturity point).

## Usage

``` r
detect_convergence(
  triangle,
  fit_fn = fit_lr,
  c = 0.5,
  tau = 0.15,
  M = 3L,
  k_star = NULL,
  holdout_max = NULL,
  min_n_cohorts = 5L,
  ...
)
```

## Arguments

- triangle:

  A `Triangle` object (typically from
  [`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md)).

- fit_fn:

  Fitting function used to project. Default
  [fit_lr](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md).
  [fit_cl](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
  is also accepted but `fit_lr` is recommended because it exposes both
  loss and exposure projections required for portfolio LR.

- c:

  Multiplier on \\\hat{SE}^{param}\_v\\. Default `0.5`.

- tau:

  Upper bound on \\\hat{D}\_v\\. Default `0.15`.

- M:

  Required run length of consecutive passing periods. Default `3L`.

- k_star:

  Pre-computed maturity point. When `NULL`, computed via
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
  applied to a clr-based ATA.

- holdout_max:

  Maximum holdout depth used for the rolling backtest. When `NULL`, set
  to `max(M, floor((V - k_star) / 2))`.

- min_n_cohorts:

  Minimum number of cohorts required to compute \\\hat{D}\_v\\. Default
  `5L`.

- ...:

  Additional arguments forwarded to `fit_fn`.

## Value

An object of class `Convergence` (named list) containing the detected
`k_conv`, the candidate sequence `v`, and the diagnostic sequences
`R_v`, `SE_param_v`, `D_v`, `pass_v`. Metadata is carried on attributes
(`group_var`, `value_var`, `fit_fn_name`).

## See also

[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md),
[`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md),
[`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
