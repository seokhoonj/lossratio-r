# (Reference) Chain ladder reserving

> **Reference: P&C reserving context.** This article covers chain ladder
> *reserving* — projecting ultimate paid / incurred loss for an open
> accident year — which is a Property & Casualty (P&C, 손해보험) use
> case. The lossratio package’s primary focus is long-term health
> insurance loss ratio projection (`fit_lr`), where the reserving
> framing applies only loosely. We include this article so practitioners
> coming from a P&C background see how `fit_cl` maps to the classical
> Mack chain ladder workflow they’re already familiar with.

[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
is the dedicated chain ladder fit for a single value column. Unlike
[`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
(which projects loss / exposure jointly to get loss ratio),
[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
projects one cumulative metric forward and computes Mack-style standard
errors per cohort.

## Basic usage

For brevity this vignette uses the `SUR` group only — every step
generalises to multi-group input.

``` r

library(lossratio)
data(experience)
tri <- build_triangle(experience[coverage == "SUR"], groups = coverage)

cl <- fit_cl(tri, target = "loss", method = "mack")
print(cl)
#> <CLFit>
#> method      : mack 
#> target      : loss 
#> weight      : none 
#> alpha       : 1 
#> sigma_method: locf 
#> recent      : all 
#> use_maturity: FALSE 
#> tail_factor : 1 
#> groups      : coverage 
#> periods     : 36
```

`target` selects the cumulative column to project — typically `"loss"`
(cumulative loss) for reserving, or `"premium"` (cumulative risk
premium) for exposure projection.

## Mack chain ladder

[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
implements the Mack (1993) chain ladder. Adjacent development links are
summarised by age-to-age factors $`f_k = C^L_{k+1} / C^L_k`$ — selected
per link and then chained to project each cohort forward to ultimate. On
top of the point projection, Mack’s formulae decompose the prediction
variance into process and parameter components, yielding per-cell
standard errors and confidence intervals.

``` r

cl_mack <- fit_cl(tri, target = "loss", method = "mack")

# $full and $summary carry both the projection and its variance
head(cl_mack$summary)
#>    coverage     cohort     latest   loss_ult   reserve target_proc_se
#>      <char>     <Date>      <num>      <num>     <num>          <num>
#> 1:      SUR 2023-01-01  410248523  410248523         0              0
#> 2:      SUR 2023-02-01  976330446 1001441304  25110859        2751818
#> 3:      SUR 2023-03-01  978486044 1026151241  47665197        3967868
#> 4:      SUR 2023-04-01 2029909922 2186771224 156861302        6942936
#> 5:      SUR 2023-05-01  624219442  697669308  73449866        4455635
#> 6:      SUR 2023-06-01  802880717  931393933 128513217       17869565
#>    target_param_se target_total_se target_total_cv
#>              <num>           <num>           <num>
#> 1:               0               0     0.000000000
#> 2:         4299411         5104649     0.005097302
#> 3:         5021194         6399717     0.006236621
#> 4:        11297884        13260714     0.006064061
#> 5:         3696917         5789636     0.008298539
#> 6:         8694892        19872657     0.021336468
```

The projection plot’s confidence bands (`show_interval = TRUE`) use
those variance estimates:

``` r

plot(cl_mack, type = "projection", show_interval = TRUE)
```

![](chain-ladder-reserving_files/figure-html/unnamed-chunk-3-1.png)

## Tail factor

For triangles where the latest observed development period is still
developing, an extrapolated tail factor estimates ultimate:

``` r

# Log-linear extrapolation from the selected ATA factors
cl_tail <- fit_cl(tri, target = "loss", method = "mack", tail = TRUE)

# Or supply a literal tail factor
cl_tail <- fit_cl(tri, target = "loss", method = "mack", tail = 1.025)
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
  target        = "loss",
  method        = "mack",
  maturity_args = list(max_cv = 0.10, max_rse = 0.05)
)

cl_mat$maturity
#> Key: <coverage>
#>    coverage ata_from ata_to ata_link     mean  median       wt         cv
#>      <char>    <int>  <int>   <char>    <num>   <num>    <num>      <num>
#> 1:      SUR        4      5      4-5 1.324091 1.33133 1.338896 0.06783671
#>           f       f_se        rse    sigma n_obs n_valid n_inf n_nan
#>       <num>      <num>      <num>    <num> <int>   <int> <int> <int>
#> 1: 1.338896 0.01808821 0.01350979 1105.053    32      32     0     0
#>    valid_ratio
#>          <num>
#> 1:           1
```

`maturity_args` is forwarded to
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md).

## Variance components (Mack)

`fit_cl(method = "mack")` decomposes the projection variance into:

- `target_proc_se` — process variance, from $`\sigma^2_k`$ (residual
  link variance per development period).
- `target_param_se` — parameter variance, from the uncertainty of the
  selected age-to-age factors $`\hat{f}_k`$.
- `target_total_se` — total standard error,
  $`\sqrt{\mathrm{target\_proc\_se}^2 + \mathrm{target\_param\_se}^2}`$.
- `target_total_cv` — coefficient of variation,
  `target_total_se / target_proj`.

``` r

summary(cl_mack)
#>     coverage     cohort     latest   loss_ult    reserve target_proc_se
#>       <char>     <Date>      <num>      <num>      <num>          <num>
#>  1:      SUR 2023-01-01  410248523  410248523          0              0
#>  2:      SUR 2023-02-01  976330446 1001441304   25110859        2751818
#>  3:      SUR 2023-03-01  978486044 1026151241   47665197        3967868
#>  4:      SUR 2023-04-01 2029909922 2186771224  156861302        6942936
#>  5:      SUR 2023-05-01  624219442  697669308   73449866        4455635
#>  6:      SUR 2023-06-01  802880717  931393933  128513217       17869565
#>  7:      SUR 2023-07-01 2539141550 3050990158  511848609       35918003
#>  8:      SUR 2023-08-01  393678329  488218204   94539875       15583801
#>  9:      SUR 2023-09-01 1364052543 1751869309  387816766       38001618
#> 10:      SUR 2023-10-01  979266044 1311793844  332527800       38496097
#> 11:      SUR 2023-11-01  604685680  848103124  243417444       35719580
#> 12:      SUR 2023-12-01 1026345365 1497869026  471523662       51405333
#> 13:      SUR 2024-01-01 1912177598 2901492850  989315252       75674312
#> 14:      SUR 2024-02-01  733902485 1160045952  426143467       51719398
#> 15:      SUR 2024-03-01  415459872  686574146  271114274       41313265
#> 16:      SUR 2024-04-01 3286053525 5687484009 2401430484      122770257
#> 17:      SUR 2024-05-01 1451731151 2645801834 1194070683       93024106
#> 18:      SUR 2024-06-01  629668308 1209024555  579356246       65346187
#> 19:      SUR 2024-07-01 1250954692 2542927187 1291972495      103136527
#> 20:      SUR 2024-08-01  425346694  918120581  492773887       65317866
#> 21:      SUR 2024-09-01  278156543  635470027  357313485       56737053
#> 22:      SUR 2024-10-01  352070325  856446527  504376201       68091257
#> 23:      SUR 2024-11-01   99050502  260916098  161865596       41787166
#> 24:      SUR 2024-12-01  103194015  295637302  192443287       49617196
#> 25:      SUR 2025-01-01  227089023  710560088  483471065       83635489
#> 26:      SUR 2025-02-01  939163073 3276849148 2337686075      192418633
#> 27:      SUR 2025-03-01  112828843  434950050  322121207       72345359
#> 28:      SUR 2025-04-01   82472453  356301149  273828696       68974257
#> 29:      SUR 2025-05-01  141214851  697290588  556075737      119238986
#> 30:      SUR 2025-06-01  136406104  789468809  653062706      136628653
#> 31:      SUR 2025-07-01  149144024 1040451732  891307708      167039609
#> 32:      SUR 2025-08-01  116327076 1008356737  892029661      183653360
#> 33:      SUR 2025-09-01   67465470  783000254  715534784      179947036
#> 34:      SUR 2025-10-01  121626172 2001214853 1879588681      337103186
#> 35:      SUR 2025-11-01   15716444  449653411  433936967      194100660
#> 36:      SUR 2025-12-01    4825085  850839165  846014080      472741777
#>     coverage     cohort     latest   loss_ult    reserve target_proc_se
#>       <char>     <Date>      <num>      <num>      <num>          <num>
#>     target_param_se target_total_se target_total_cv
#>               <num>           <num>           <num>
#>  1:               0               0     0.000000000
#>  2:         4299411         5104649     0.005097302
#>  3:         5021194         6399717     0.006236621
#>  4:        11297884        13260714     0.006064061
#>  5:         3696917         5789636     0.008298539
#>  6:         8694892        19872657     0.021336468
#>  7:        30501064        47121310     0.015444596
#>  8:         5072721        16388635     0.033568259
#>  9:        20827314        43334743     0.024736288
#> 10:        16992220        42079509     0.032077837
#> 11:        11901733        37650227     0.044393454
#> 12:        22008504        55918535     0.037332059
#> 13:        43971809        87522120     0.030164514
#> 14:        18269126        54851227     0.047283667
#> 15:        11014492        42756344     0.062274911
#> 16:        92689753       153830837     0.027047256
#> 17:        45040850       103354547     0.039063601
#> 18:        20907249        68609309     0.056747655
#> 19:        45568403       112754701     0.044340515
#> 20:        16819267        67448583     0.073463753
#> 21:        11859688        57963310     0.091213288
#> 22:        16219630        69996398     0.081728860
#> 23:         5190764        42108328     0.161386469
#> 24:         6221683        50005754     0.169145618
#> 25:        15668259        85090477     0.119751276
#> 26:        75222223       206599402     0.063048188
#> 27:        10161412        73055494     0.167962951
#> 28:         8575343        69505285     0.195074548
#> 29:        19174475       120770842     0.173200161
#> 30:        22834478       138523652     0.175464376
#> 31:        31445935       169973756     0.163365345
#> 32:        32987225       186592373     0.185045992
#> 33:        27713231       182068556     0.232526816
#> 34:        80113491       346492034     0.173140847
#> 35:        21034521       195237080     0.434194593
#> 36:        66075502       477337155     0.561019255
#>     target_param_se target_total_se target_total_cv
#>               <num>           <num>           <num>
```

## Reserve plot

`type = "reserve"` shows reserve per cohort with optional error bars
(Mack only):

``` r

plot(cl_mack, type = "reserve", conf_level = 0.95)
```

![](chain-ladder-reserving_files/figure-html/unnamed-chunk-7-1.png)

## Triangle visualisation

[`plot_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.md)
displays the cohort × dev cells as a heatmap, distinguishing observed
cells from projected:

``` r

plot_triangle(cl_mack, region = "full")    # observed + projected
```

![](chain-ladder-reserving_files/figure-html/unnamed-chunk-8-1.png)

``` r

plot_triangle(cl_mack, region = "pred")    # projected only
```

![](chain-ladder-reserving_files/figure-html/unnamed-chunk-8-2.png)

``` r

plot_triangle(cl_mack, region = "data")    # observed only
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
| `"locf"` | (default) last observation carried forward |
| `"min_last2"` | min of the last two estimable $`\sigma`$ values — conservative |
| `"loglinear"` | Log-linear extrapolation from the observed $`\sigma_k`$ sequence |

``` r

fit_cl(tri, target = "loss", method = "mack", sigma_method = "loglinear")
#> <CLFit>
#> method      : mack 
#> target      : loss 
#> weight      : none 
#> alpha       : 1 
#> sigma_method: loglinear 
#> recent      : all 
#> use_maturity: FALSE 
#> tail_factor : 1 
#> groups      : coverage 
#> periods     : 36
```

## See also

- [`vignette("projection")`](https://seokhoonj.github.io/lossratio/ko/articles/projection.md)
  — when to use
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
  instead.
- [`vignette("triangle-link-and-maturity")`](https://seokhoonj.github.io/lossratio/ko/articles/triangle-link-and-maturity.md)
  — [`summary()`](https://rdrr.io/r/base/summary.html),
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md),
  ata diagnostic plots.
- [`?fit_cl`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md),
  [`?detect_maturity`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md),
  [`?fit_ata`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md).
