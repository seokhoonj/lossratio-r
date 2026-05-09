# Backtest: holding out the latest diagonals to validate projections

## Motivation

Reserving and projection methods are fitted on observed data, but their
practical value lies in how they would have performed at past valuation
dates.
[`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
answers that question by hiding the latest `holdout` calendar diagonals
from a triangle, refitting the model on the earlier portion, and
comparing its projection to the actuals that were withheld. This is
calendar-diagonal hold-out (rather than dev-period hold-out), because it
simulates “what would the model have said *K* months ago at the
valuation date?”. The cell-level metric follows the standard actuarial
A/E convention,
$`\mathrm{aeg} = v_{\mathrm{actual}} / v_{\mathrm{pred}} - 1`$, where
positive values flag under-projection (actual exceeded expected) and
negative values flag over-projection.

## Basic usage

``` r

library(lossratio)
data(experience)
exp     <- as_experience(experience)
tri_sur <- build_triangle(exp[cv_nm == "SUR"], cv_nm)

bt <- backtest(tri_sur, holdout = 6L)
print(bt)
#> <Backtest>
#>   fit_fn      : fit_lr
#>   loss_var   : lr
#>   holdout     : 6 calendar diagonals
#>   held-out    : 123 cells
#>   AEG         : mean -13.06% / median -7.37%
```

The returned object is a `"Backtest"` list with these key slots:

- `aeg` — per-cell `data.table` (cohort, dev, actual, pred, aeg,
  calendar_idx).
- `col_summary` — AEG aggregated by `dev`.
- `diag_summary` — AEG aggregated by calendar diagonal.
- `masked` — the triangle the fit was trained on (latest diagonals
  removed).
- `fit` — the fit object returned by `fit_fn` (an `LRFit` or `CLFit`).

`summary(bt)` prints the two summary tables alongside the call metadata.

## Validation coverage after masking

Masking the latest `holdout` diagonals shortens the triangle’s
lower-right edge. Chain ladder can only project as far as the largest
dev still observed in the masked data, so cells beyond that range — the
oldest cohorts at their latest dev — have no projection to compare
against. These unreachable cells are silently dropped, so `bt$aeg`
contains only cells where both an actual and a finite projection exist.

Practical takeaway: as `holdout` grows, the validation set shrinks
fastest in the oldest cohorts’ late-dev region — exactly where chain
ladder relies on extrapolation (projection beyond the observed dev
range), so it is the area most in need of validation yet the first to
disappear.

## Output interpretation

**`col_summary` — systematic bias by development period.** A
consistently signed AEG at a given dev signals a structural mismatch
between the model and that maturity. Early-dev positive values usually
reflect inflated link factors; late-dev values flag tail miscalibration.

``` r

head(bt$col_summary, 8)
#>     cv_nm   dev     n   aeg_mean    aeg_med     aeg_wt
#>    <char> <int> <int>      <num>      <num>      <num>
#> 1:    SUR     2     1 -0.2208792 -0.2208792 -0.2208792
#> 2:    SUR     3     2 -0.6437453 -0.6437453 -0.6163673
#> 3:    SUR     4     3 -0.3510508 -0.1160624 -0.3497066
#> 4:    SUR     5     4 -0.3148234 -0.2154987 -0.3169997
#> 5:    SUR     6     5 -0.4606402 -0.4013712 -0.4603512
#> 6:    SUR     7     6 -0.3178128 -0.3457778 -0.3292850
#> 7:    SUR     8     6 -0.3942605 -0.4362220 -0.3951000
#> 8:    SUR     9     6 -0.3181451 -0.3715525 -0.3080096
```

`aeg_mean` averages cell-level AEG, `aeg_med` is the median, and
`aeg_wt = sum(actual - pred) / sum(pred)` is the exposure-weighted
pooled A/E ratio minus 1. Comparing the three columns flags whether a
few large cells dominate (`aeg_wt` very different from `aeg_med`) or the
bias is uniform.

**`diag_summary` — calendar-year effect.** A single bad diagonal in
otherwise unbiased output points at a calendar event (a rate change,
claim handling shift, or one-off shock) that a static fitter cannot see
by construction.

``` r

bt$diag_summary
#>     cv_nm calendar_idx     n   aeg_mean     aeg_med      aeg_wt
#>    <char>        <int> <int>      <num>       <num>       <num>
#> 1:    SUR           25    23 -0.1066524 -0.03666962 -0.07019119
#> 2:    SUR           26    22 -0.1402247 -0.05155686 -0.11332892
#> 3:    SUR           27    21 -0.1091468 -0.05802823 -0.10411330
#> 4:    SUR           28    20 -0.1311544 -0.07713787 -0.12738203
#> 5:    SUR           29    19 -0.1621482 -0.15996777 -0.16736131
#> 6:    SUR           30    18 -0.1403813 -0.10594767 -0.16500512
```

A monotone drift across calendar diagonals (as in the SUR example above,
where AEG becomes increasingly positive across `25, ..., 30`) typically
indicates that actuals on the latest diagonals are running above what
the earlier-cohort link factors imply, i.e. a regime shift the static
model has not absorbed.

**`aeg` — cell-level outliers.** For diagnosing specific cohort × dev
cells, inspect `bt$aeg` directly:

``` r

head(bt$aeg, 5)
#> Key: <cv_nm>
#>     cv_nm     cohort   dev value_actual value_pred          aeg calendar_idx
#>    <char>     <Date> <int>        <num>      <num>        <num>        <int>
#> 1:    SUR 2023-05-01    24     1.030446   1.157413 -0.109698314           25
#> 2:    SUR 2023-06-01    23     1.175862   1.183114 -0.006130062           25
#> 3:    SUR 2023-06-01    24     1.198728   1.294051 -0.073662448           26
#> 4:    SUR 2023-07-01    22     1.105530   1.112573 -0.006330018           25
#> 5:    SUR 2023-07-01    23     1.106120   1.118239 -0.010837528           26
```

## Plot demos

Four plot views are registered on `"Backtest"`:

``` r

plot(bt, type = "col")    # AEG by dev (point + dashed zero line)
```

![](backtest_files/figure-html/unnamed-chunk-5-1.png)

``` r

plot(bt, type = "diag")   # AEG by calendar diagonal
```

![](backtest_files/figure-html/unnamed-chunk-5-2.png)

``` r

plot(bt, type = "cell")   # per-cohort AEG trajectories over dev
```

![](backtest_files/figure-html/unnamed-chunk-5-3.png)

``` r

plot_triangle(bt)         # diverging-color heatmap on the held-out wedge
```

![](backtest_files/figure-html/unnamed-chunk-5-4.png)

`type = "col"` is the right place to look for systematic dev-period
bias; `type = "diag"` reveals calendar-year drift; `type = "cell"`
exposes which cohorts contribute the bias;
[`plot_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.md)
puts the cell-level AEG values on the same triangular layout as
[`plot_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.md)
for the underlying fit, with a red/blue diverging palette where red
marks under-projection (actual \> pred).

## Holdout selection

Choose `holdout` to balance two opposing effects:

- Too large: the masked triangle loses its latest experience, so the
  oldest cohorts have few or no reachable cells in their later dev
  periods. The validation set shrinks unevenly, biased toward early dev.
- Too small: the held-out wedge is just a thin diagonal band, which may
  not capture enough cells to reveal systematic patterns.

Typical choices are `holdout = 6L` (half-year) for monthly triangles, or
`holdout = 12L` (full year) for stronger validation when the triangle
has at least 24–30 diagonals of history.

## Choosing the fit function

The default fitter is `fit_lr` with `method = "sa"` and
`loss_var = "lr"`. The loss ratio is unitless and dimension-free across
cohorts of very different volume, so `aeg_mean` and `aeg_med` carry a
consistent meaning across the triangle.

> **A note on `loss_var`.** `backtest(loss_var = ...)` is the **score
> column** — the column on which actual vs. predicted are compared
> cell-by-cell. It is *not*, in general, the same thing as the
> `loss_var` argument to a chain-ladder fitter (which selects which
> column of the triangle to accumulate). With `fit_fn = fit_cl`, the two
> coincide because
> [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
> forwards `loss_var` straight through to
> [`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md).
> With `fit_fn = fit_lr`, the fitter does not take a `loss_var` at all —
> it always projects `loss`, `premium`, and `lr` jointly — and
> `loss_var` here only chooses which of those three projection columns
> on `fit_lr$full` is compared against the held-out actuals:

| `loss_var`  | Compared column on `fit_lr$full` |
|-------------|----------------------------------|
| `"loss"`    | `loss_proj`                      |
| `"premium"` | `premium_proj`                   |
| `"lr"`      | `lr_proj`                        |

The `method` argument selects the underlying loss-ratio projection
strategy: `"sa"` (stage-adaptive, the default) blends exposure-driven
projections before the maturity point with chain ladder afterwards;
`"ed"` is purely exposure-driven; `"cl"` is the classical chain ladder
applied to `lr`.

``` r

bt_sa  <- backtest(tri_sur, holdout = 6L, method = "sa")   # default
bt_ed  <- backtest(tri_sur, holdout = 6L, method = "ed")
bt_cl  <- backtest(tri_sur, holdout = 6L, method = "cl")

bt_loss <- backtest(tri_sur, holdout = 6L, loss_var = "loss")
bt_rp   <- backtest(tri_sur, holdout = 6L, loss_var = "premium")

print(bt_sa)
#> <Backtest>
#>   fit_fn      : fit_lr
#>   loss_var   : lr
#>   holdout     : 6 calendar diagonals
#>   held-out    : 123 cells
#>   AEG         : mean -13.06% / median -7.37%
```

Backtesting `loss` weights the result toward whichever cohorts happen to
be the largest at the held-out diagonals, which is useful when monetary
impact matters more than a normalized comparison.

If you only need to project a single triangle column (e.g., raw
cumulative loss without forming a ratio), `fit_fn = fit_cl` is also
supported.

## See also

- [`vignette("chain-ladder-reserving")`](https://seokhoonj.github.io/lossratio/ko/articles/chain-ladder-reserving.md)
  —
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
  reference.
- [`vignette("projection")`](https://seokhoonj.github.io/lossratio/ko/articles/projection.md)
  —
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
  and the `"sa"`, `"ed"`, `"cl"` methods.
- [`?backtest`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md),
  [`?plot.Backtest`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Backtest.md),
  [`?plot_triangle.Backtest`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.Backtest.md).
