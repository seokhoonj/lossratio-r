# Chain ladder를 이용한 준비금 산출

> 영어 원본 보기: [Chain ladder reserving with
> fit_cl](https://seokhoonj.github.io/lossratio/chain-ladder.md)

[`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md)
은 단일 값 컬럼에 대한 전용 chain ladder 적합 함수이다. 손해와
익스포저를 동시에 추정해 손해율을 산출하는
[`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)
과 달리,
[`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md)
은 하나의 누적 지표를 전방으로 추정하고 코호트별 Mack 방식 표준오차를
함께 계산한다.

## 기본 사용법

이 문서는 간결성을 위해 `SUR` 그룹만 사용한다 — 모든 절차는 다중 그룹
입력에도 그대로 일반화된다.

``` r

library(lossratio)
data(experience)
exp <- as_experience(experience)
tri <- build_triangle(exp[cv_nm == "SUR"], group_var = cv_nm)

cl <- fit_cl(tri, value_var = "closs", method = "mack")
print(cl)
#> <CLFit>
#> method      : mack 
#> value_var   : closs 
#> weight_var  : none 
#> alpha       : 1 
#> sigma_method: min_last2 
#> recent      : all 
#> use_maturity: FALSE 
#> tail_factor : 1 
#> groups      : cv_nm 
#> periods     : 30
```

`value_var` 은 추정 대상 누적 컬럼을 선택한다 — 준비금 산출에는 보통
`"closs"` (누적 손해), 익스포저 추정에는 `"crp"` (누적 위험보험료) 를
쓴다.

## 방법: basic vs Mack

두 가지 추정 방법이 제공된다. 두 방법 모두 인접 dev 의 누적 손해 비
$`f_k = C^L_{k+1} / C^L_k`$ — **ATA 인자**(age-to-age factor) — 를
링크별로 선택한 뒤 누적 추정에 사용한다.

| `method`  | 계산 내용                           |
|-----------|-------------------------------------|
| `"basic"` | 점 추정만 (선택된 ATA 인자)         |
| `"mack"`  | 점 추정 + 인자 / 프로세스 / 모수 SE |

``` r

cl_basic <- fit_cl(tri, value_var = "closs", method = "basic")
cl_mack  <- fit_cl(tri, value_var = "closs", method = "mack")

names(cl_basic)
#>  [1] "call"          "data"          "method"        "group_var"    
#>  [5] "cohort_var"    "dev_var"       "value_var"     "full"         
#>  [9] "pred"          "ata"           "summary"       "factor"       
#> [13] "selected"      "maturity"      "alpha"         "sigma_method" 
#> [17] "weight_var"    "recent"        "use_maturity"  "maturity_args"
#> [21] "tail"          "tail_factor"

# Mack 은 $full 과 $summary 에 분산 추정값을 추가한다
head(cl_mack$summary)
#>     cv_nm     cohort     latest   ultimate   reserve     proc_se    param_se
#>    <char>     <Date>      <num>      <num>     <num>       <num>       <num>
#> 1:    SUR 2023-04-01 2442597048 2442597048         0         0.0         0.0
#> 2:    SUR 2023-05-01 2423543638 2600462324 176918686    270023.8    278555.7
#> 3:    SUR 2023-06-01 3211045460 3634951626 423906166    461673.6    481436.4
#> 4:    SUR 2023-07-01 2552396709 3106052713 553656004 217960839.6 130390124.6
#> 5:    SUR 2023-08-01 2472997706 3159902325 686904619 235800277.9 139803599.9
#> 6:    SUR 2023-09-01 2014222417 2712676349 698453932 230925350.1 124174149.3
#>             se           cv
#>          <num>        <num>
#> 1:         0.0 0.0000000000
#> 2:    387951.2 0.0001491855
#> 3:    667025.8 0.0001835034
#> 4: 253985259.7 0.0817710719
#> 5: 274129198.7 0.0867524279
#> 6: 262194082.1 0.0966551289
```

`method = "mack"` 으로 적합하면 추정 플롯의 신뢰 구간
(`show_interval = TRUE`) 을 사용할 수 있다.

``` r

plot(cl_mack, type = "projection", show_interval = TRUE)
```

![](chain-ladder-ko_files/figure-html/unnamed-chunk-3-1.png)

## Tail 인자

마지막 관측 경과 기간에서도 손해가 여전히 발달 중인 triangle 의 경우,
외삽한 tail 인자(tail factor) 로 ultimate 를 추정한다.

``` r

# 선택된 ATA 인자로부터 로그 선형 외삽
cl_tail <- fit_cl(tri, value_var = "closs", method = "mack", tail = TRUE)

# 또는 명시적인 tail 인자 값 지정
cl_tail <- fit_cl(tri, value_var = "closs", method = "mack", tail = 1.025)
```

외삽은 추정된 ATA 인자에 대해 $`\log(f_k - 1) \sim k`$ 회귀를 적합한 뒤,
외삽된 $`f_k`$ 의 누적 곱만큼 추정 범위를 연장한다. 기본값은 비활성
(`tail = FALSE`) 이다.

## Maturity 필터링

선택된 ATA 인자가 변동성이 크다면, 추정을 성숙(mature) 영역으로 제한할
수 있다.

``` r

cl_mat <- fit_cl(
  tri,
  value_var     = "closs",
  method        = "mack",
  maturity_args = list(cv_threshold = 0.10, rse_threshold = 0.05)
)

cl_mat$maturity
#> Key: <cv_nm>
#>     cv_nm ata_from ata_to ata_link  mean median    wt    cv     f  f_se   rse
#>    <char>    <num>  <num>   <char> <num>  <num> <num> <num> <num> <num> <num>
#> 1:    SUR        9     10     9-10 1.188  1.172 1.165 0.097 1.165 0.022 0.019
#>       sigma n_obs n_valid n_inf n_nan valid_ratio
#>       <num> <num>   <num> <num> <num>       <num>
#> 1: 1774.278    21      21     0     0           1
```

`maturity_args` 는
[`find_ata_maturity()`](https://seokhoonj.github.io/lossratio/reference/find_ata_maturity.md)
로 그대로 전달된다.

## 분산 성분 (Mack)

`fit_cl(method = "mack")` 은 추정 분산을 다음과 같이 분해한다.

- `proc_se` — 프로세스 분산. $`\sigma^2_k`$ (경과 기간별 잔차 링크 분산)
  으로부터 도출.
- `param_se` — 모수 분산. 선택된 ATA 인자 $`\hat{f}_k`$ 의
  불확실성으로부터 도출.
- `se` — 총 표준오차,
  $`\sqrt{\mathrm{proc\_se}^2 + \mathrm{param\_se}^2}`$.
- `cv` — 변동계수, `se / value_proj`.

``` r

summary(cl_mack)
#>      cv_nm     cohort     latest   ultimate    reserve      proc_se    param_se
#>     <char>     <Date>      <num>      <num>      <num>        <num>       <num>
#>  1:    SUR 2023-04-01 2442597048 2442597048          0          0.0         0.0
#>  2:    SUR 2023-05-01 2423543638 2600462324  176918686     270023.8    278555.7
#>  3:    SUR 2023-06-01 3211045460 3634951626  423906166     461673.6    481436.4
#>  4:    SUR 2023-07-01 2552396709 3106052713  553656004  217960839.6 130390124.6
#>  5:    SUR 2023-08-01 2472997706 3159902325  686904619  235800277.9 139803599.9
#>  6:    SUR 2023-09-01 2014222417 2712676349  698453932  230925350.1 124174149.3
#>  7:    SUR 2023-10-01 2422172254 3464336723 1042164469  276909538.1 163800531.1
#>  8:    SUR 2023-11-01 2157147612 3350616805 1193469193  347646646.1 180286627.2
#>  9:    SUR 2023-12-01 2062030017 3510350121 1448320104  379204803.4 195291838.6
#> 10:    SUR 2024-01-01 1803809914 3316423447 1512613533  371903391.7 185291186.8
#> 11:    SUR 2024-02-01 1627213157 3293904272 1666691115  406210629.2 191768888.6
#> 12:    SUR 2024-03-01 1006624213 2212909862 1206285649  348109439.7 131371151.5
#> 13:    SUR 2024-04-01  707083237 1712964993 1005881756  316686848.8 103164315.5
#> 14:    SUR 2024-05-01  398857325 1069653556  670796231  262671178.8  65778222.8
#> 15:    SUR 2024-06-01  558855276 1654603718 1095748442  342800640.3 103939643.9
#> 16:    SUR 2024-07-01  423131371 1378042306  954910935  336548946.6  89486750.7
#> 17:    SUR 2024-08-01  457705980 1642689597 1184983617  387322897.0 109347246.8
#> 18:    SUR 2024-09-01  278007651 1166380310  888372659  360265104.1  81491440.0
#> 19:    SUR 2024-10-01  214811381 1027414214  812602833  358796880.9  74015042.1
#> 20:    SUR 2024-11-01  251273971 1400108561 1148834590  451728990.6 105050619.0
#> 21:    SUR 2024-12-01  322678179 2168358632 1845680453  619598522.3 171876903.1
#> 22:    SUR 2025-01-01  179253475 1403314539 1224061064  523388251.8 114399770.9
#> 23:    SUR 2025-02-01  100816665  954214626  853397961  497168458.4  84734261.7
#> 24:    SUR 2025-03-01  111279087 1488227953 1376948866  843027195.9 163376024.6
#> 25:    SUR 2025-04-01   55914454  958667529  902753075  751897091.4 113958278.9
#> 26:    SUR 2025-05-01   41578391 1041506115  999927724  978637599.4 147793339.1
#> 27:    SUR 2025-06-01   14997314  484991215  469993901  813441277.3  81273429.5
#> 28:    SUR 2025-07-01    6232031  436725855  430493824 5630776358.8 495928426.0
#> 29:    SUR 2025-08-01          0          0          0          0.0         0.0
#> 30:    SUR 2025-09-01          0          0          0          0.0         0.0
#>      cv_nm     cohort     latest   ultimate    reserve      proc_se    param_se
#>     <char>     <Date>      <num>      <num>      <num>        <num>       <num>
#>               se           cv
#>            <num>        <num>
#>  1:          0.0 0.000000e+00
#>  2:     387951.2 1.491855e-04
#>  3:     667025.8 1.835034e-04
#>  4:  253985259.7 8.177107e-02
#>  5:  274129198.7 8.675243e-02
#>  6:  262194082.1 9.665513e-02
#>  7:  321728932.9 9.286884e-02
#>  8:  391613915.1 1.168782e-01
#>  9:  426538609.2 1.215089e-01
#> 10:  415505663.8 1.252873e-01
#> 11:  449201938.9 1.363737e-01
#> 12:  372073328.0 1.681376e-01
#> 13:  333066714.3 1.944387e-01
#> 14:  270782057.7 2.531493e-01
#> 15:  358211848.8 2.164940e-01
#> 16:  348242834.9 2.527084e-01
#> 17:  402462230.4 2.450020e-01
#> 18:  369366755.4 3.166778e-01
#> 19:  366351509.1 3.565763e-01
#> 20:  463783045.7 3.312479e-01
#> 21:  642996110.9 2.965359e-01
#> 22:  535744873.7 3.817711e-01
#> 23:  504337556.8 5.285368e-01
#> 24:  858712162.8 5.770031e-01
#> 25:  760483875.8 7.932718e-01
#> 26:  989734521.0 9.502916e-01
#> 27:  817491334.5 1.685580e+00
#> 28: 5652573520.7 1.294307e+01
#> 29:          0.0           NA
#> 30:          0.0           NA
#>               se           cv
#>            <num>        <num>
```

## 준비금 플롯

`type = "reserve"` 는 코호트별 준비금을 (Mack 일 경우 선택적 오차 막대와
함께) 표시한다.

``` r

plot(cl_mack, type = "reserve", conf_level = 0.95)
```

![](chain-ladder-ko_files/figure-html/unnamed-chunk-7-1.png)

## Triangle 시각화

[`plot_triangle()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.md)
은 코호트 × dev 셀을 히트맵으로 표시하며, 관측된 셀과 추정된 셀을
구분한다.

``` r

plot_triangle(cl_mack, what = "full")    # 관측 + 추정
```

![](chain-ladder-ko_files/figure-html/unnamed-chunk-8-1.png)

``` r

plot_triangle(cl_mack, what = "pred")    # 추정만
```

![](chain-ladder-ko_files/figure-html/unnamed-chunk-8-2.png)

``` r

plot_triangle(cl_mack, what = "data")    # 관측만
```

![](chain-ladder-ko_files/figure-html/unnamed-chunk-8-3.png)

`label_style = "cv"` 모드는 셀별 변동계수를 표시하며, 신뢰성이 낮은 셀을
식별하는 데 유용하다.

``` r

plot_triangle(cl_mack, label_style = "cv")
```

![](chain-ladder-ko_files/figure-html/unnamed-chunk-9-1.png)

``` r

plot_triangle(cl_mack, label_style = "se")
```

![](chain-ladder-ko_files/figure-html/unnamed-chunk-9-2.png)

``` r

plot_triangle(cl_mack, label_style = "ci")
```

![](chain-ladder-ko_files/figure-html/unnamed-chunk-9-3.png)

## Sigma 외삽 방법

Mack 분산은 모든 발달 링크에서 $`\sigma_k`$ 가 필요한데, 마지막
링크에서는 직접 추정이 불가능하다. `sigma_method` 가 외삽 방식을
결정한다.

| `sigma_method` | 동작                                                       |
|----------------|------------------------------------------------------------|
| `"min_last2"`  | (기본) 추정 가능한 마지막 두 $`\sigma`$ 의 최솟값 — 보수적 |
| `"locf"`       | 마지막 관측값 carried forward                              |
| `"loglinear"`  | 관측된 $`\sigma_k`$ 시퀀스에 대한 로그 선형 외삽           |

``` r

fit_cl(tri, value_var = "closs", method = "mack", sigma_method = "loglinear")
#> <CLFit>
#> method      : mack 
#> value_var   : closs 
#> weight_var  : none 
#> alpha       : 1 
#> sigma_method: loglinear 
#> recent      : all 
#> use_maturity: FALSE 
#> tail_factor : 1 
#> groups      : cv_nm 
#> periods     : 30
```

## 함께 보기

- [`vignette("loss-ratio-methods")`](https://seokhoonj.github.io/lossratio/articles/loss-ratio-methods.md)
  —
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)
  을 사용해야 할 때.
- [`vignette("triangle-diagnostics")`](https://seokhoonj.github.io/lossratio/articles/triangle-diagnostics.md)
  — [`summary()`](https://rdrr.io/r/base/summary.html),
  [`find_ata_maturity()`](https://seokhoonj.github.io/lossratio/reference/find_ata_maturity.md),
  ata 진단 플롯.
- [`?fit_cl`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md),
  [`?find_ata_maturity`](https://seokhoonj.github.io/lossratio/reference/find_ata_maturity.md),
  [`?fit_ata`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md).
