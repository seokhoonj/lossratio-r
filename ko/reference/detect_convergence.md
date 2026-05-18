# Find the development period at which the loss ratio estimate stabilises

Identify the first dev \\k^{\*\*}\\ from which the projected portfolio
loss ratio is observed to be stable up to the maximum available
development period \\V\\. Three complementary stability criteria are
computed on the LR backtest path; the user selects which one defines
\\k^{\*\*}\\ via `method =`.

*Notation mapping (code \<-\> math)*:

Standard chain-ladder convention: \\i\\ indexes cohort (origin period),
\\k\\ indexes development period. The maturity point \\k^\*\\ and
convergence point \\k^{\*\*}\\ live on the \\k\\ axis. Earlier paper
drafts used \\v\\ (valuation) for the same index in Section 11; we unify
on \\k\\ for consistency.

|  |  |  |
|----|----|----|
| `dev_max` | \\K\_{\max}\\ | Maximum observable dev (a scalar) |
| `dev_cand` | \\k \in \[k^\*, K\_{\max}-2\]\\ | Integer vector of candidate dev points |
| `ratio[i]` | \\LR_k\\ | Portfolio LR projection at dev = `dev_cand[i]` |
| `revision[i]` | \\R_k = \|LR_k - LR\_{k-1}\|\\ | Adjacent-step revision (diagnostic) |
| `drift_window[i]` | \\\max - \min\\ of \\LR\\ over \\\[k, k+W-1\]\\ | Local window range |
| `drift_tail[i]` | \\\max - \min\\ of \\LR\\ over \\\[k, K\_{\max}\]\\ | Tail range |
| `slope[i]` | \\\hat\beta_k\\, OLS slope of \\LR \sim k\\ on \\\[k, K\_{\max}\]\\ | Trend test |
| `dispersion[i]` | \\\hat{D}\_k\\ | Robust cross-cohort spread of incremental LR |

Stability methods (which sequence drives `pass`):

- `"window"`:

  Local stability: `drift_window[i] < max_drift`. Fast, but misses a
  slow monotone drift that fits under `max_drift` per step.

- `"tail"`:

  (default, *reserving-safe*) Global stability:
  `drift_tail[i] < max_drift`. Catches monotone drift. The first passing
  dev is later (more conservative) than `"window"`.

- `"slope"`:

  Trend test: `|slope[i]| < max_slope`. Explicit no-trend check;
  sensitive to non-linear trajectories.

- `"all"`:

  Strictest: all three pass simultaneously.

All four pass vectors (`pass_window`, `pass_tail`, `pass_slope`, `pass`)
and the underlying diagnostic series are returned regardless of the
chosen `method`, so the analyst can inspect every criterion and
re-decide.

Across all methods, a cross-cohort agreement clause
`dispersion[i] < max_dispersion` is required in addition.

This replaces an earlier formulation \\R_k \< c \cdot
\hat{SE}^{param}\_k\\ (paper Section 11). The paper's SE-normalised form
is asymptotically broken on large portfolios: \\\hat{SE}^{param}\\
shrinks as \\1/\sqrt{n}\\ while \\R_k\\ has a structural noise floor, so
the ratio diverges and the criterion never fires.

**Caveat (reserving)**: detected `conv_k` reflects stability *up to*
`dev_max` (\\K\_{\max}\\) only – it is *not* an asymptotic guarantee
that the projection will not drift past \\K\_{\max}\\. Treat `conv_k` as
a diagnostic for "from here on, what we observe is stable", not as a
guarantee of future stability. For reserving applications, prefer
`method = "tail"` or `"all"` over `"window"`, attach an IBNR margin via
`fit_ratio$summary` SE/CI columns, and weigh the *evidence span*
(`dev_max - conv_k`): a `conv_k` near `dev_max` has thin evidence.

## Usage

``` r
detect_convergence(
  triangle,
  method = c("tail", "window", "slope", "all"),
  max_drift = 0.01,
  max_slope = 0.001,
  max_dispersion = 0.15,
  window = 5L,
  mat_k = NULL,
  holdout_max = NULL,
  min_n_cohorts = 5L,
  ...
)
```

## Arguments

- triangle:

  A `Triangle` object (typically from
  [`as_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/as_triangle.md)).

- method:

  Which stability criterion defines `conv_k`. One of `"tail"` (default),
  `"window"`, `"slope"`, or `"all"`. See the description for semantics
  and the reserving caveat.

- max_drift:

  Upper bound on the drift metric (window or tail), in LR units. Default
  `0.01` (1pp). Raise for noisier or longer-tail books.

- max_slope:

  Upper bound on `|slope[i]|`, the OLS slope of \\LR \sim k\\ on \\\[k,
  K\_{\max}\]\\, in LR-per-dev units. Default `1e-3` (0.1pp per dev).
  Used by `method = "slope"` / `"all"`.

- max_dispersion:

  Upper bound on the cross-cohort dispersion \\\hat{D}\_k\\. Default
  `0.15`.

- window:

  Drift window length \\W\\ (in dev steps): the number of consecutive
  valuations used by the `"window"` method to compute `drift_window`.
  Default `5L`. Note: other functions in the package also expose a
  `window` argument (e.g.
  [`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  for e-divisive segment width); here it controls *only* the drift
  metric, not the e-divisive algorithm.

- mat_k:

  Pre-computed maturity point. When `NULL`, computed via
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
  applied to a ratio-based ATA.

- holdout_max:

  Maximum holdout depth used for the rolling backtest. When `NULL`, set
  to `max(window, floor((dev_max - mat_k) / 2))`.

- min_n_cohorts:

  Minimum number of cohorts required to compute \\\hat{D}\_v\\. Default
  `5L`.

- ...:

  Additional arguments forwarded to
  [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  (and thence to
  [`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md)),
  e.g. `loss_method`, `recent`, `loss_regime`.

## Value

An object of class `Convergence` (named list). Includes the slots
tabulated in the notation mapping above (`dev_max`, `dev_cand`, `ratio`,
`revision`, `drift_window`, `drift_tail`, `slope`, `dispersion`),
per-method pass vectors (`pass_window`, `pass_tail`, `pass_slope`,
`pass`), the threshold parameters, and metadata attributes (`groups`,
`loss`, `dispatcher`).

## See also

[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md),
[`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md),
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md)
