# Triangle and Link: data structures and factor diagnostics

Before fitting a chain ladder or loss-ratio model, it pays to inspect
the underlying triangle and the per-link factor table derived from it.
This vignette covers the `Triangle` and `Link` data structures and their
diagnostic plots; for maturity detection see
[`vignette("maturity")`](https://seokhoonj.github.io/lossratio/ko/articles/maturity.md).

## Triangle-level diagnostics

For brevity this vignette uses the `SUR` group only — every step
generalises to multi-group input.

``` r

library(lossratio)
data(experience)
exp <- as_experience(experience)[cv_nm == "SUR"]
tri <- build_triangle(exp, group_var = cv_nm)
```

### Cohort trajectories

``` r

plot(tri)                              # cumulative loss-ratio trajectories per cohort
```

![](triangle-and-link_files/figure-html/unnamed-chunk-2-1.png)

``` r

plot(tri, value_var = "lr")            # incremental loss ratio instead of clr
```

![](triangle-and-link_files/figure-html/unnamed-chunk-2-2.png)

``` r

plot(tri, summary = TRUE)              # raw + overlay (mean / median / weighted)
```

![](triangle-and-link_files/figure-html/unnamed-chunk-2-3.png)

The `summary = TRUE` overlay computes mean, median, and weighted clr at
each dev and overlays them on the cohort lines. Useful for spotting
cohorts that deviate from the central tendency.

### Cell heatmap

``` r

plot_triangle(tri)                            # clr in each cell
```

![](triangle-and-link_files/figure-html/unnamed-chunk-3-1.png)

``` r

plot_triangle(tri, value_var = "lr")          # incremental loss ratio
```

![](triangle-and-link_files/figure-html/unnamed-chunk-3-2.png)

``` r


# detail labels (ratio + loss/rp amounts) are 2-line — use quarterly cells
tri_q <- build_triangle(exp, group_var = cv_nm,
                        cohort_var = "uyq", dev_var = "elap_q")
plot_triangle(tri_q, label_style = "detail")  # ratio + (loss / rp) amounts
```

![](triangle-and-link_files/figure-html/unnamed-chunk-3-3.png)

### Group statistics by dev

``` r

sm <- summary(tri)
head(sm)
#> Key: <cv_nm, dev>
#>     cv_nm   dev n_obs   lr_mean lr_median      lr_wt  clr_mean clr_median
#>    <char> <int> <int>     <num>     <num>      <num>     <num>      <num>
#> 1:    SUR     1    30 0.0738546 0.0000000 0.07343113 0.0738546  0.0000000
#> 2:    SUR     2    29 0.5365888 0.0992849 0.54126362 0.3512535  0.1120447
#> 3:    SUR     3    28 0.6201189 0.2472070 0.56590118 0.4521326  0.2618096
#> 4:    SUR     4    27 0.8852657 0.6387164 0.92060611 0.6327242  0.4798531
#> 5:    SUR     5    26 0.5767556 0.4828899 0.59880663 0.6369307  0.5641166
#> 6:    SUR     6    25 0.9314593 0.5431397 0.95085711 0.7264308  0.6191132
#>        clr_wt
#>         <num>
#> 1: 0.07343113
#> 2: 0.35150128
#> 3: 0.44744109
#> 4: 0.63467048
#> 5: 0.63999290
#> 6: 0.72781355
```

Returns a `TriangleSummary` object with mean / median / weighted loss
ratios per (group, dev) cell.

## Link / factor diagnostics

The `Link` object is the link table (age-to-age factor table) built from
the triangle. In single-variable mode it carries the observed ATA
factors; with `exposure_var` it carries the ED-style intensities
$`g_k = \Delta C^L_k / C^P_k`$.

``` r

ata <- build_link(tri, value_var = "closs")
sm  <- summary(ata, model = "ata", alpha = 1)
head(sm)
#> Key: <cv_nm>
#>     cv_nm ata_from ata_to ata_link   mean median     wt    cv     f  f_se   rse
#>    <char>    <num>  <num>   <fctr>  <num>  <num>  <num> <num> <num> <num> <num>
#> 1:    SUR        1      2      1-2 60.965  4.062 11.320 3.111 6.768 4.767 0.704
#> 2:    SUR        2      3      2-3 15.316  2.005  2.083 2.955 1.939 1.284 0.663
#> 3:    SUR        3      4      3-4 36.458  2.167  2.167 4.493 2.167 2.434 1.123
#> 4:    SUR        4      5      4-5  1.641  1.282  1.291 0.854 1.291 0.115 0.089
#> 5:    SUR        5      6      5-6  1.607  1.334  1.461 0.455 1.461 0.113 0.078
#> 6:    SUR        6      7      6-7  1.348  1.208  1.282 0.256 1.282 0.058 0.046
#>        sigma n_obs n_valid n_inf n_nan valid_ratio
#>        <num> <num>   <num> <num> <num>       <num>
#> 1: 27972.257    29      14     0     0       0.483
#> 2: 25358.337    28      24     0     0       0.857
#> 3: 69089.724    27      27     0     0       1.000
#> 4:  4787.739    26      26     0     0       1.000
#> 5:  5301.574    25      25     0     0       1.000
#> 6:  3279.239    24      24     0     0       1.000
```

The [`summary()`](https://rdrr.io/r/base/summary.html) method on a
`Link` object (single-variable mode) computes per-link statistics that
drive maturity detection:

- `mean`, `median`, `wt` — descriptive averages of observed ata factors
  at each link (excluding cohorts where the link is not observed).
- `cv` — coefficient of variation of the observed factors (relative
  spread, alpha-independent).
- `f` — WLS-estimated factor (volume-weighted by `value_from^alpha`).
- `f_se`, `rse` — WLS standard error and relative standard error.
- `sigma` — Mack residual sigma per link.
- `n_obs`, `n_valid`, `n_inf`, `n_nan`, `valid_ratio` — observation
  counts and the share of finite ATA factors per link.

### Diagnostic plots for the link table

``` r

plot(ata, type = "cv")            # CV vs ata link with maturity overlay
```

![](triangle-and-link_files/figure-html/unnamed-chunk-6-1.png)

``` r

plot(ata, type = "rse")           # RSE vs ata link
```

![](triangle-and-link_files/figure-html/unnamed-chunk-6-2.png)

``` r

plot(ata, type = "summary")       # mean / median / wt overlay per link
```

![](triangle-and-link_files/figure-html/unnamed-chunk-6-3.png)

``` r

plot(ata, type = "box")           # boxplot of observed ata per link
```

![](triangle-and-link_files/figure-html/unnamed-chunk-6-4.png)

``` r

plot(ata, type = "point")         # scatter of observed ata per link
```

![](triangle-and-link_files/figure-html/unnamed-chunk-6-5.png)

### Triangle of ATA factors

``` r

la <- list(size = 2.5)                            # shrink labels
plot_triangle(ata, label_args = la)               # heatmap of observed factors
```

![](triangle-and-link_files/figure-html/unnamed-chunk-7-1.png)

``` r

plot_triangle(ata, label_args = la, show_maturity = TRUE)    # overlay maturity line
```

![](triangle-and-link_files/figure-html/unnamed-chunk-7-2.png)

``` r


# detail labels are two lines and overlap on monthly cells — rebuild on the
# quarterly triangle so the labels fit
ata_q <- build_link(tri_q, value_var = "closs")
plot_triangle(ata_q, label_style = "detail")      # factor + (loss / rp) amounts
```

![](triangle-and-link_files/figure-html/unnamed-chunk-7-3.png)

The heatmap colours each cell by `log(ata / median(ata))` within its
link, so column-wise colour distinguishes cohorts that deviate from the
link’s median.

### ED diagnostics

``` r

ed <- build_link(tri, value_var = "closs", exposure_var = "crp")
sm <- summary(ed, model = "ed", alpha = 1)
head(sm)
#> Key: <cv_nm>
#>     cv_nm ata_from ata_to ata_link    mean  median      wt      cv       g
#>    <char>    <num>  <num>   <fctr>   <num>   <num>   <num>   <num>   <num>
#> 1:    SUR        1      2      1-2 0.83638 0.11124 0.78549 1.64664 0.78549
#> 2:    SUR        2      3      2-3 0.42921 0.19355 0.39517 1.28530 0.39517
#> 3:    SUR        3      4      3-4 0.57740 0.28022 0.54349 1.36754 0.54349
#> 4:    SUR        4      5      4-5 0.18873 0.13962 0.18976 0.90510 0.18976
#> 5:    SUR        5      6      5-6 0.29944 0.16294 0.30277 1.01004 0.30277
#> 6:    SUR        6      7      6-7 0.21583 0.18880 0.20988 0.85987 0.20988
#>       g_se     rse    sigma n_obs n_valid n_inf n_nan valid_ratio
#>      <num>   <num>    <num> <num>   <num> <num> <num>       <num>
#> 1: 0.24877 0.31671 5291.085    29      29     0     0           1
#> 2: 0.09984 0.25264 3263.751    28      28     0     0           1
#> 3: 0.14933 0.27477 6210.872    27      27     0     0           1
#> 4: 0.03343 0.17615 1720.934    26      26     0     0           1
#> 5: 0.06037 0.19939 3487.836    25      25     0     0           1
#> 6: 0.03771 0.17970 2450.547    24      24     0     0           1

plot(ed, type = "summary")
```

![](triangle-and-link_files/figure-html/unnamed-chunk-8-1.png)

``` r

plot(ed, type = "box")
```

![](triangle-and-link_files/figure-html/unnamed-chunk-8-2.png)

``` r

plot_triangle(ed, label_args = la)
```

![](triangle-and-link_files/figure-html/unnamed-chunk-8-3.png)

`summary(link, model = "ed")` is the ED-side analogue of the
single-variable [`summary()`](https://rdrr.io/r/base/summary.html),
computing per-link statistics for the intensity
$`g_k = \Delta C^L_k / C^P_k`$.

## Validation before building

If gaps in the development sequence are suspected, inspect them before
[`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md):

``` r

gaps <- validate_triangle(exp, group_var = cv_nm,
                          cohort_var = "uym", dev_var = "elap_m")
head(gaps)
#> Empty data.table (0 rows and 5 cols): cv_nm,uym,n_observed,n_expected,missing
```

Returns a `TriangleValidation` object with one row per cohort that has
non-consecutive development periods. An empty result means the triangle
is clean.

If gaps exist, options:

- Fix the data source (preferred).
- Drop offending cohorts.
- Pass `fill_gaps = TRUE` to
  [`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md)
  to zero-fill missing cells (use with care — inflates `n_obs`).

## Recent-diagonal subset

When older cohorts are no longer representative (rate change, reserving
regime shift), restrict estimation to the recent calendar diagonals:

``` r

fit_ata(tri, value_var = "closs", alpha = 1, recent = 12)  # last 12 calendar diagonals
#> <ATAFit>
#> alpha       : 1 
#> sigma_method: min_last2 
#> recent      : 12 
#> regime_break: none 
#> use_maturity: FALSE 
#> groups      : cv_nm 
#> n_groups    : 1 
#> ata links   : 29
fit_cl(tri, value_var = "closs", recent = 12)
#> <CLFit>
#> method      : basic 
#> value_var   : closs 
#> weight_var  : none 
#> alpha       : 1 
#> recent      : 12 
#> use_maturity: FALSE 
#> tail_factor : 1 
#> groups      : cv_nm 
#> periods     : 30
fit_lr(tri, recent = 12)
#> <LRFit>
#> method        : sa 
#> loss_var      : closs 
#> exposure_var  : crp 
#> loss_alpha    : 1 
#> exposure_alpha: 1 
#> delta_method  : simple 
#> conf_level    : 0.95 
#> ci_type       : analytical  
#> sigma_method  : min_last2 
#> recent        : 12 
#> regime_break  : none 
#> maturity[SUR] : 18
#> groups        : cv_nm 
#> periods       : 30
```

`recent = K` keeps only rows whose calendar position
(`rank(cohort) + dev - 1`) is among the latest `K` per group.

## Workflow checklist

Before fitting:

1.  [`validate_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/validate_triangle.md)
    — schema and gap check.
2.  [`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md)
    — canonical shape with derived columns.
3.  `plot(tri)` / `plot_triangle(tri)` — visual inspection.
4.  `summary(tri)` — group-level central tendency.
5.  [`build_link()`](https://seokhoonj.github.io/lossratio/ko/reference/build_link.md) +
    `plot(link, type = "cv")` — link stability.
6.  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
    — verify maturity detection produces a sensible point per group (see
    [`vignette("maturity")`](https://seokhoonj.github.io/lossratio/ko/articles/maturity.md)).
7.  [`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
    (optional) — structural change diagnosis.

Then fit
[`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
/
[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
with confidence in the input data.

## See also

- [`vignette("getting-started")`](https://seokhoonj.github.io/lossratio/ko/articles/getting-started.md)
  — full pipeline overview.
- [`vignette("maturity")`](https://seokhoonj.github.io/lossratio/ko/articles/maturity.md)
  — maturity detection from the link table.
- [`vignette("regime")`](https://seokhoonj.github.io/lossratio/ko/articles/regime.md)
  —
  [`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  deep dive.
- [`vignette("projection")`](https://seokhoonj.github.io/lossratio/ko/articles/projection.md)
  — projection method choice.
