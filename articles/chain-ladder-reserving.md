# (Reference) Chain ladder reserving

> **Reference: P&C reserving context.** This article covers chain ladder
> *reserving* — projecting ultimate paid / incurred loss for an open
> accident year — which is a Property & Casualty (P&C, 손해보험) use
> case. The lossratio package’s primary focus is long-term health
> insurance loss ratio projection (`fit_lr`), where the reserving
> framing applies only loosely. We include this article so practitioners
> coming from a P&C background see how `fit_cl` maps to the classical
> Mack chain ladder workflow they’re already familiar with.

[`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md)
is the dedicated chain ladder fit for a single value column. Unlike
[`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)
(which projects loss / exposure jointly to get loss ratio),
[`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md)
projects one cumulative metric forward and computes Mack-style standard
errors per cohort.

## Basic usage

For brevity this vignette uses the `SUR` group only — every step
generalises to multi-group input.

``` r

library(lossratio)
data(experience)
exp <- as_experience(experience)
tri <- build_triangle(exp[cv_nm == "SUR"], group_var = cv_nm)

cl <- fit_cl(tri, loss_var = "loss", method = "mack")
print(cl)
#> <CLFit>
#> method      : mack 
#> loss_var   : loss 
#> weight_var  : none 
#> alpha       : 1 
#> sigma_method: min_last2 
#> recent      : all 
#> use_maturity: FALSE 
#> tail_factor : 1 
#> groups      : cv_nm 
#> periods     : 30
```

`loss_var` selects the cumulative column to project — typically `"loss"`
(cumulative loss) for reserving, or `"premium"` (cumulative risk
premium) for exposure projection.

## Method: basic vs Mack

Two estimation methods are available:

| `method`  | What it computes                                    |
|-----------|-----------------------------------------------------|
| `"basic"` | Point projection only (selected age-to-age factors) |
| `"mack"`  | Point projection + factor / process / parameter SE  |

``` r

cl_basic <- fit_cl(tri, loss_var = "loss", method = "basic")
cl_mack  <- fit_cl(tri, loss_var = "loss", method = "mack")

names(cl_basic)
#>  [1] "call"          "data"          "method"        "group_var"    
#>  [5] "cohort_var"    "dev_var"       "loss_var"      "full"         
#>  [9] "pred"          "link"          "summary"       "factor"       
#> [13] "selected"      "maturity"      "alpha"         "sigma_method" 
#> [17] "weight_var"    "recent"        "use_maturity"  "maturity_args"
#> [21] "tail"          "tail_factor"

# Mack adds variance estimates to $full and $summary
head(cl_mack$summary)
#>     cv_nm     cohort     latest   ultimate   reserve     proc_se    param_se
#>    <char>     <Date>      <num>      <num>     <num>       <num>       <num>
#> 1:    SUR 2023-04-01 2442597048 2442597048         0         0.0         0.0
#> 2:    SUR 2023-05-01 2423543638 2599392894 175849256    270043.0    278575.5
#> 3:    SUR 2023-06-01 3211045460 3634413301 423367841    461636.3    481485.0
#> 4:    SUR 2023-07-01 2552396709 3105056636 552659927 217928572.6 130370821.7
#> 5:    SUR 2023-08-01 2472997706 3157679354 684681648 235720815.8 139732312.3
#> 6:    SUR 2023-09-01 2014222417 2710936434 696714017 230845077.0 124116454.3
#>             se           cv
#>          <num>        <num>
#> 1:         0.0 0.0000000000
#> 2:    387978.8 0.0001492575
#> 3:    667035.2 0.0001835331
#> 4: 253947659.8 0.0817851942
#> 5: 274024491.8 0.0867803412
#> 6: 262096058.4 0.0966810048
```

`method = "mack"` enables the projection plot’s confidence bands
(`show_interval = TRUE`):

``` r

plot(cl_mack, type = "projection", show_interval = TRUE)
```

![](chain-ladder-reserving_files/figure-html/unnamed-chunk-3-1.png)

## Tail factor

For triangles where the latest observed development period is still
developing, an extrapolated tail factor estimates ultimate:

``` r

# Log-linear extrapolation from the selected ATA factors
cl_tail <- fit_cl(tri, loss_var = "loss", method = "mack", tail = TRUE)

# Or supply a literal tail factor
cl_tail <- fit_cl(tri, loss_var = "loss", method = "mack", tail = 1.025)
```

The extrapolation fits $`\log(f_k - 1) \sim k`$ to projected factors and
extends the projection by the cumulative product of extrapolated $`f_k`$
values. Disabled by default (`tail = FALSE`).

## Maturity filtering

If selected ATA factors are volatile, restrict projection to the mature
region only:

``` r

cl_mat <- fit_cl(
  tri,
  loss_var     = "loss",
  method        = "mack",
  maturity_args = list(cv_threshold = 0.10, rse_threshold = 0.05)
)

cl_mat$maturity
#> Key: <cv_nm>
#>     cv_nm ata_from ata_to ata_link     mean   median       wt         cv
#>    <char>    <int>  <int>   <char>    <num>    <num>    <num>      <num>
#> 1:    SUR        9     10     9-10 1.187815 1.172305 1.164727 0.09743995
#>           f       f_se        rse    sigma n_obs n_valid n_inf n_nan
#>       <num>      <num>      <num>    <num> <int>   <int> <int> <int>
#> 1: 1.164727 0.02218428 0.01904677 1774.278    21      21     0     0
#>    valid_ratio
#>          <num>
#> 1:           1
```

`maturity_args` is forwarded to
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md).

## Variance components (Mack)

`fit_cl(method = "mack")` decomposes the projection variance into:

- `proc_se` — process variance, from $`\sigma^2_k`$ (residual link
  variance per development period).
- `param_se` — parameter variance, from the uncertainty of the selected
  age-to-age factors $`\hat{f}_k`$.
- `se` — total standard error,
  $`\sqrt{\mathrm{proc\_se}^2 + \mathrm{param\_se}^2}`$.
- `cv` — coefficient of variation, `se / value_proj`.

``` r

summary(cl_mack)
#>      cv_nm     cohort     latest   ultimate    reserve      proc_se    param_se
#>     <char>     <Date>      <num>      <num>      <num>        <num>       <num>
#>  1:    SUR 2023-04-01 2442597048 2442597048          0          0.0         0.0
#>  2:    SUR 2023-05-01 2423543638 2599392894  175849256     270043.0    278575.5
#>  3:    SUR 2023-06-01 3211045460 3634413301  423367841     461636.3    481485.0
#>  4:    SUR 2023-07-01 2552396709 3105056636  552659927  217928572.6 130370821.7
#>  5:    SUR 2023-08-01 2472997706 3157679354  684681648  235720815.8 139732312.3
#>  6:    SUR 2023-09-01 2014222417 2710936434  696714017  230845077.0 124116454.3
#>  7:    SUR 2023-10-01 2422172254 3462559189 1040386935  276819957.3 163742309.0
#>  8:    SUR 2023-11-01 2157147612 3348092694 1190945082  347483087.7 180182622.2
#>  9:    SUR 2023-12-01 2062030017 3507124483 1445094466  378985928.3 195146699.1
#> 10:    SUR 2024-01-01 1803809914 3313648697 1509838783  371701492.0 185168311.6
#> 11:    SUR 2024-02-01 1627213157 3290864665 1663651508  405955551.7 191623873.4
#> 12:    SUR 2024-03-01 1006624213 2210412480 1203788267  347849334.7 131244972.2
#> 13:    SUR 2024-04-01  707083237 1710592304 1003509067  316404389.8 103039012.0
#> 14:    SUR 2024-05-01  398857325 1068197835  669340510  262427825.4  65699397.7
#> 15:    SUR 2024-06-01  558855276 1652370578 1093515302  342471145.7 103815507.7
#> 16:    SUR 2024-07-01  423131371 1376383783  953252412  336228946.0  89391221.1
#> 17:    SUR 2024-08-01  457705980 1640501164 1182795184  386922397.3 109216403.4
#> 18:    SUR 2024-09-01  278007651 1164532959  886525308  359836114.5  81374294.4
#> 19:    SUR 2024-10-01  214811381 1025645270  810833889  358331882.2  73898398.9
#> 20:    SUR 2024-11-01  251273971 1398034322 1146760351  451163265.1 104907142.4
#> 21:    SUR 2024-12-01  322678179 2164825908 1842147729  618759781.2 171617334.7
#> 22:    SUR 2025-01-01  179253475 1400699975 1221446500  522610781.9 114200956.7
#> 23:    SUR 2025-02-01  100816665  952319429  851502764  496360616.8  84576549.3
#> 24:    SUR 2025-03-01  111279087 1484998733 1373719646  841476045.1 163045250.9
#> 25:    SUR 2025-04-01   55914454  956257058  900342604  750361481.0 113691627.4
#> 26:    SUR 2025-05-01   41578391 1038872575  997294184  976468762.0 147438352.4
#> 27:    SUR 2025-06-01   14997314  483606876  468609562  811466344.3  81056315.8
#> 28:    SUR 2025-07-01    6232031  435403065  429171034 5614740016.5 494512960.5
#> 29:    SUR 2025-08-01          0          0          0          0.0         0.0
#> 30:    SUR 2025-09-01          0          0          0          0.0         0.0
#>      cv_nm     cohort     latest   ultimate    reserve      proc_se    param_se
#>     <char>     <Date>      <num>      <num>      <num>        <num>       <num>
#>               se           cv
#>            <num>        <num>
#>  1:          0.0 0.000000e+00
#>  2:     387978.8 1.492575e-04
#>  3:     667035.2 1.835331e-04
#>  4:  253947659.8 8.178519e-02
#>  5:  274024491.8 8.678034e-02
#>  6:  262096058.4 9.668100e-02
#>  7:  321622189.1 9.288569e-02
#>  8:  391420839.5 1.169086e-01
#>  9:  426277571.6 1.215462e-01
#> 10:  415270156.4 1.253211e-01
#> 11:  448909365.9 1.364108e-01
#> 12:  371785425.2 1.681973e-01
#> 13:  332759336.3 1.945287e-01
#> 14:  270526846.0 2.532554e-01
#> 15:  357860511.0 2.165740e-01
#> 16:  347909032.0 2.527704e-01
#> 17:  402041247.0 2.450722e-01
#> 18:  368922492.0 3.167987e-01
#> 19:  365872534.1 3.567242e-01
#> 20:  463199525.4 3.313220e-01
#> 21:  642118506.5 2.966144e-01
#> 22:  534942882.8 3.819111e-01
#> 23:  503514701.5 5.287246e-01
#> 24:  857126413.2 5.771900e-01
#> 25:  758925647.5 7.936419e-01
#> 26:  987536992.1 9.505853e-01
#> 27:  815504601.0 1.686297e+00
#> 28: 5636474831.0 1.294542e+01
#> 29:          0.0           NA
#> 30:          0.0           NA
#>               se           cv
#>            <num>        <num>
```

## Reserve plot

`type = "reserve"` shows reserve per cohort with optional error bars
(Mack only):

``` r

plot(cl_mack, type = "reserve", conf_level = 0.95)
```

![](chain-ladder-reserving_files/figure-html/unnamed-chunk-7-1.png)

## Triangle visualisation

[`plot_triangle()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.md)
displays the cohort × dev cells as a heatmap, distinguishing observed
cells from projected:

``` r

plot_triangle(cl_mack, what = "full")    # observed + projected
```

![](chain-ladder-reserving_files/figure-html/unnamed-chunk-8-1.png)

``` r

plot_triangle(cl_mack, what = "pred")    # projected only
```

![](chain-ladder-reserving_files/figure-html/unnamed-chunk-8-2.png)

``` r

plot_triangle(cl_mack, what = "data")    # observed only
```

![](chain-ladder-reserving_files/figure-html/unnamed-chunk-8-3.png)

The `label_style = "cv"` mode shows coefficient of variation per cell,
useful for spotting unreliable cells:

``` r

plot_triangle(cl_mack, label_style = "cv")
```

![](chain-ladder-reserving_files/figure-html/unnamed-chunk-9-1.png)

``` r

plot_triangle(cl_mack, label_style = "se")
```

![](chain-ladder-reserving_files/figure-html/unnamed-chunk-9-2.png)

``` r

plot_triangle(cl_mack, label_style = "ci")
```

![](chain-ladder-reserving_files/figure-html/unnamed-chunk-9-3.png)

## Sigma extrapolation methods

Mack variance requires $`\sigma_k`$ at all development links, including
the last where it cannot be estimated directly. `sigma_method` controls
the extrapolation:

| `sigma_method` | Behaviour |
|----|----|
| `"min_last2"` | (default) min of the last two estimable $`\sigma`$ values — conservative |
| `"locf"` | Last observation carried forward |
| `"loglinear"` | Log-linear extrapolation from the observed $`\sigma_k`$ sequence |

``` r

fit_cl(tri, loss_var = "loss", method = "mack", sigma_method = "loglinear")
#> <CLFit>
#> method      : mack 
#> loss_var   : loss 
#> weight_var  : none 
#> alpha       : 1 
#> sigma_method: loglinear 
#> recent      : all 
#> use_maturity: FALSE 
#> tail_factor : 1 
#> groups      : cv_nm 
#> periods     : 30
```

## See also

- [`vignette("projection")`](https://seokhoonj.github.io/lossratio/articles/projection.md)
  — when to use
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)
  instead.
- [`vignette("triangle-link-and-maturity")`](https://seokhoonj.github.io/lossratio/articles/triangle-link-and-maturity.md)
  — [`summary()`](https://rdrr.io/r/base/summary.html),
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md),
  ata diagnostic plots.
- [`?fit_cl`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md),
  [`?detect_maturity`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md),
  [`?fit_ata`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md).
