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
valuation date?”. The cell-level metric (`ae_err`, “A/E Error”) follows
the standard actuarial A/E convention,
$`\mathrm{ae\_err} = v_{\mathrm{actual}} / v_{\mathrm{pred}} - 1`$,
where positive values flag under-projection (the model under-estimated;
actual exceeded expected) and negative values flag over-projection.

## Basic usage

``` r

library(lossratio)
data(experience)
tri_sur <- build_triangle(
  experience[coverage == "SUR"],
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "loss_incr",
  premium  = "premium_incr"
)

bt <- backtest(tri_sur, holdout = 6L)
print(bt)
#> <Backtest>
#>   fit_fn   : fit_lr
#>   target   : lr
#>   holdout  : 6 diagonals (159 cells)
#>   A/E Error: mean 0.21% / median -0.00%
```

The returned object is a `"Backtest"` list with these key slots:

- `ae_err` — per-cell `data.table` (cohort, dev, actual, pred, ae_err,
  calendar_idx).
- `col_summary` — A/E Error aggregated by `dev`.
- `diag_summary` — A/E Error aggregated by calendar diagonal.
- `masked` — the triangle the fit was trained on (latest diagonals
  removed).
- `fit` — the fit object returned by `fit_fn` (an `LRFit` or `CLFit`).

`summary(bt)` prints the two summary tables alongside the call metadata.

## Validation coverage after masking

Masking the latest `holdout` diagonals shortens the triangle’s
lower-right edge. Chain ladder can only project as far as the largest
dev still observed in the masked data, so cells beyond that range — the
oldest cohorts at their latest dev — have no projection to compare
against. These unreachable cells are silently dropped, so `bt$ae_err`
contains only cells where both an actual and a finite projection exist.

Practical takeaway: as `holdout` grows, the validation set shrinks
fastest in the oldest cohorts’ late-dev region — exactly where chain
ladder relies on extrapolation (projection beyond the observed dev
range), so it is the area most in need of validation yet the first to
disappear.

## Output interpretation

**`col_summary` — systematic bias by development period.** A
consistently signed A/E Error at a given dev signals a structural
mismatch between the model and that maturity. Early-dev positive values
usually reflect inflated link factors; late-dev values flag tail
miscalibration.

``` r

head(bt$col_summary, 8)
#>    coverage   dev     n ae_err_mean  ae_err_med    ae_err_wt
#>      <char> <int> <int>       <num>       <num>        <num>
#> 1:      SUR     2     1 -0.36674932 -0.36674932 -0.366749322
#> 2:      SUR     3     2 -0.09011955 -0.09011955 -0.154463503
#> 3:      SUR     4     3 -0.02300710  0.04378484 -0.065662205
#> 4:      SUR     5     4  0.01186458  0.01235174 -0.016264772
#> 5:      SUR     6     5  0.01349877  0.06211286 -0.022035200
#> 6:      SUR     7     6  0.03540917  0.07574468  0.008863285
#> 7:      SUR     8     6  0.05916242  0.07259077  0.055085668
#> 8:      SUR     9     6  0.02445333  0.02775188  0.022389147
```

`ae_err_mean` averages cell-level A/E Error, `ae_err_med` is the median,
and `ae_err_wt = sum(actual - pred) / sum(pred)` is the
exposure-weighted pooled A/E ratio minus 1. Comparing the three columns
flags whether a few large cells dominate (`ae_err_wt` very different
from `ae_err_med`) or the bias is uniform.

**`diag_summary` — calendar-year effect.** A single bad diagonal in
otherwise unbiased output points at a calendar event (a rate change,
claim handling shift, or one-off shock) that a static fitter cannot see
by construction.

``` r

bt$diag_summary
#>    coverage calendar_idx     n  ae_err_mean    ae_err_med     ae_err_wt
#>      <char>        <int> <int>        <num>         <num>         <num>
#> 1:      SUR           31    29 -0.011309409 -0.0036993121 -0.0107004532
#> 2:      SUR           32    28 -0.002794292 -0.0095889605 -0.0089044276
#> 3:      SUR           33    27  0.007666313  0.0061548319  0.0004012161
#> 4:      SUR           34    26  0.008094503  0.0004212464  0.0010973315
#> 5:      SUR           35    25  0.007408947  0.0094557038 -0.0005997011
#> 6:      SUR           36    24  0.005874139  0.0094502806 -0.0023535417
```

A monotone drift across calendar diagonals (as in the SUR example above,
where A/E Error becomes increasingly positive across `25, ..., 30`)
typically indicates that actuals on the latest diagonals are running
above what the earlier-cohort link factors imply, i.e. a regime shift
the static model has not absorbed.

**`ae_err` — cell-level outliers.** For diagnosing specific cohort × dev
cells, inspect `bt$ae_err` directly:

``` r

head(bt$ae_err, 5)
#> Key: <coverage>
#>    coverage     cohort   dev value_actual value_pred       ae_err calendar_idx
#>      <char>     <Date> <int>        <num>      <num>        <num>        <int>
#> 1:      SUR 2023-02-01    30     1.474656   1.485094 -0.007028587           31
#> 2:      SUR 2023-03-01    29     1.441826   1.414305  0.019458534           31
#> 3:      SUR 2023-03-01    30     1.441234   1.418776  0.015828824           32
#> 4:      SUR 2023-04-01    28     1.513021   1.510169  0.001888463           31
#> 5:      SUR 2023-04-01    29     1.531922   1.504873  0.017974002           32
```

## Plot demos

Four plot views are registered on `"Backtest"`:

``` r

plot(bt, type = "col")    # A/E Error by dev (point + dashed zero line)
```

![](backtest_files/figure-html/unnamed-chunk-5-1.png)

``` r

plot(bt, type = "diag")   # A/E Error by calendar diagonal
```

![](backtest_files/figure-html/unnamed-chunk-5-2.png)

``` r

plot(bt, type = "cell")   # per-cohort A/E Error trajectories over dev
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
puts the cell-level A/E Error values on the same triangular layout as
[`plot_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.md)
for the underlying fit, with a red/blue diverging palette where red
marks under-projection (actual \> pred) and blue marks over-projection
(actual \< pred).

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

## Choosing the projection target

The default is `target = "lr"` with `loss_method = "sa"`. The loss ratio
is unitless and dimension-free across cohorts of very different volume,
so `ae_err_mean` and `ae_err_med` carry a consistent meaning across the
triangle.

> **A note on `target`.** `target` is the **score column** — the column
> on which actual vs. predicted are compared cell-by-cell. It selects
> which role-specific fitter
> [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
> runs internally and which projection column on the fit’s `$full` table
> is compared against the held-out actuals:

| `target` | Internal fitter | Method arg | Compared column |
|----|----|----|----|
| `"lr"` | [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md) | `loss_method` | `lr_proj` |
| `"loss"` | [`fit_loss()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_loss.md) | `loss_method` | `loss_proj` |
| `"premium"` | [`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md) | `premium_method` | `premium_proj` |

The `loss_method` argument selects the underlying loss / loss-ratio
projection strategy: `"sa"` (stage-adaptive, the default) blends
exposure-driven projections before the maturity point with chain ladder
afterwards; `"ed"` is purely exposure-driven; `"cl"` is the classical
chain ladder. The `premium_method` argument selects the premium
projection strategy when `target = "premium"`.

``` r

bt_sa       <- backtest(tri_sur, holdout = 6L, loss_method = "sa")  # default
bt_ed       <- backtest(tri_sur, holdout = 6L, loss_method = "ed")
bt_cl       <- backtest(tri_sur, holdout = 6L, loss_method = "cl")

bt_loss     <- backtest(tri_sur, holdout = 6L,
                        target = "loss", loss_method = "cl")
bt_premium  <- backtest(tri_sur, holdout = 6L,
                        target = "premium", premium_method = "cl")

print(bt_sa)
#> <Backtest>
#>   fit_fn   : fit_lr
#>   target   : lr
#>   holdout  : 6 diagonals (159 cells)
#>   A/E Error: mean 0.21% / median -0.00%
```

For monetary impact (loss or premium) backtesting, set `target = "loss"`
or `target = "premium"` to score the corresponding projection lane
directly.

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
