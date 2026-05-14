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
#>   dispatcher: fit_lr
#>   target    : lr
#>   holdout   : 6 diagonals (159 cells)
#>   A/E Error : mean 0.21% / median -0.00%
```

The returned object is a `"Backtest"` list with these key slots:

- `ae_err` — per-cell `data.table` (cohort, dev, actual, expected, aeg,
  ae_err + `_incr` siblings, calendar_idx).
- `col_summary` — A/E Error aggregated by `dev`.
- `diag_summary` — A/E Error aggregated by calendar diagonal.
- `masked` — the triangle the fit was trained on (latest diagonals
  removed).
- `fit` — the fit object returned by the target-specific dispatcher
  (`fit_lr` / `fit_loss` / `fit_premium`) chosen by `target=`.

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
#>    coverage   dev     n     aeg_mean      aeg_med ae_err_mean  ae_err_med
#>      <char> <int> <int>        <num>        <num>       <num>       <num>
#> 1:      SUR     2     1 -0.287972089 -0.287972089 -0.36674934 -0.36674934
#> 2:      SUR     3     2 -0.105823621 -0.105823621 -0.09011956 -0.09011956
#> 3:      SUR     4     3 -0.043897002  0.021766603 -0.02300711  0.04378485
#> 4:      SUR     5     4 -0.011055827  0.005435137  0.01186457  0.01235174
#> 5:      SUR     6     5 -0.016011400  0.037090206  0.01349876  0.06211287
#> 6:      SUR     7     6  0.006639057  0.052051927  0.03540917  0.07574468
#> 7:      SUR     8     6  0.038755683  0.046849343  0.05916241  0.07259077
#> 8:      SUR     9     6  0.016598376  0.018133964  0.02445333  0.02775188
#>      ae_err_wt aeg_incr_mean aeg_incr_med ae_err_incr_mean ae_err_incr_med
#>          <num>         <num>        <num>            <num>           <num>
#> 1: -0.36674934   -0.57495418 -0.574954175      -0.42911219    -0.429112189
#> 2: -0.15446352   -0.03295105 -0.032951048       0.03104206     0.031042058
#> 3: -0.06566221    0.03896663 -0.060404427       0.07170889    -0.051312889
#> 4: -0.01626478    0.07049188  0.081146126       0.09271533     0.101566115
#> 5: -0.02203521   -0.04049602  0.091444980       0.04486252     0.130130156
#> 6:  0.00886328    0.12761981  0.080299453       0.16250805     0.136743653
#> 7:  0.05508567    0.02069969  0.007197477       0.01564729     0.008088929
#> 8:  0.02238914   -0.10613396 -0.136121764      -0.13147267    -0.163940480
#>    ae_err_incr_wt
#>             <num>
#> 1:    -0.42911219
#> 2:    -0.03788330
#> 3:     0.04819216
#> 4:     0.08262484
#> 5:    -0.04711615
#> 6:     0.14894131
#> 7:     0.02505782
#> 8:    -0.12387084
```

`ae_err_mean` averages cell-level A/E Error, `ae_err_med` is the median,
and `ae_err_wt = sum(actual - proj) / sum(proj)` is the
exposure-weighted pooled A/E ratio minus 1. Comparing the three columns
flags whether a few large cells dominate (`ae_err_wt` very different
from `ae_err_med`) or the bias is uniform.

**`diag_summary` — calendar-year effect.** A single bad diagonal in
otherwise unbiased output points at a calendar event (a rate change,
claim handling shift, or one-off shock) that a static fitter cannot see
by construction.

``` r

bt$diag_summary
#>    coverage calendar_idx     n      aeg_mean       aeg_med  ae_err_mean
#>      <char>        <int> <int>         <num>         <num>        <num>
#> 1:      SUR           31    29 -0.0125686252 -0.0056732350 -0.011309410
#> 2:      SUR           32    28 -0.0104717812 -0.0114871218 -0.002794292
#> 3:      SUR           33    27  0.0004718616  0.0050471735  0.007666312
#> 4:      SUR           34    26  0.0012851467 -0.0002953897  0.008094503
#> 5:      SUR           35    25 -0.0006986581  0.0145835308  0.007408947
#> 6:      SUR           36    24 -0.0027175011  0.0105940082  0.005874139
#>      ae_err_med     ae_err_wt aeg_incr_mean aeg_incr_med ae_err_incr_mean
#>           <num>         <num>         <num>        <num>            <num>
#> 1: -0.003699313 -0.0107004533   -0.08350070  -0.07460811     -0.036347452
#> 2: -0.009588959 -0.0089044278   -0.07573837  -0.07440057     -0.003857981
#> 3:  0.006154835  0.0004012161    0.18105966   0.09849605      0.147072061
#> 4:  0.000421251  0.0010973317    0.01407124  -0.02312661      0.017058138
#> 5:  0.009455704 -0.0005997009   -0.03104560  -0.09210258     -0.008476082
#> 6:  0.009450279 -0.0023535415   -0.06224227  -0.09299902     -0.016968983
#>    ae_err_incr_med ae_err_incr_wt
#>              <num>          <num>
#> 1:     -0.06750071    -0.06558617
#> 2:     -0.07262916    -0.06014060
#> 3:      0.12954698     0.14477037
#> 4:     -0.02473897     0.01130928
#> 5:     -0.07819464    -0.02508022
#> 6:     -0.09358995    -0.05088339
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
#>    coverage     cohort   dev   actual expected          aeg       ae_err
#>      <char>     <Date> <int>    <num>    <num>        <num>        <num>
#> 1:      SUR 2023-02-01    30 1.474656 1.485094 -0.010438112 -0.007028587
#> 2:      SUR 2023-03-01    29 1.441826 1.414305  0.027520309  0.019458534
#> 3:      SUR 2023-03-01    30 1.441234 1.418776  0.022457560  0.015828823
#> 4:      SUR 2023-04-01    28 1.513021 1.510169  0.002851902  0.001888465
#> 5:      SUR 2023-04-01    29 1.531922 1.504873  0.027048593  0.017974003
#>    actual_incr expected_incr    aeg_incr ae_err_incr calendar_idx
#>          <num>         <num>       <num>       <num>        <int>
#> 1:    1.311699      1.616053 -0.30435387 -0.18833160           31
#> 2:    2.057141      1.271304  0.78583659  0.61813407           31
#> 3:    1.425549      1.543888 -0.11833820 -0.07664950           32
#> 4:    1.573801      1.498421  0.07537995  0.05030625           31
#> 5:    2.055572      1.352715  0.70285727  0.51959013           32
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
#>   dispatcher: fit_lr
#>   target    : lr
#>   holdout   : 6 diagonals (159 cells)
#>   A/E Error : mean 0.21% / median -0.00%
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
