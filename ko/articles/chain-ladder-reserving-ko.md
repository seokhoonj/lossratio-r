# (참고) Chain ladder reserving: 손해보험 준비금 산출

> **참고: 손해보험 (P&C) 준비금 맥락의 글.** 이 글은 *chain ladder
> 준비금 산출* — 보고기간 미종료 사고연도의 ultimate 지급/발생 손해 추정
> — 을 다룬다. 이는 손해보험(P&C, Property & Casualty) 의 전형적 use
> case 이다. lossratio 패키지의 메인 초점은 *장기 건강 보험* 손해율 추정
> (`fit_lr`) 이며, 준비금 framing 은 거기서는 직접 적용되지 않는다. 이
> 글은 P&C 배경에서 오는 사용자가 `fit_cl` 을 익숙한 Mack chain ladder
> workflow 와 매핑해 볼 수 있도록 하는 참고 자료로 둔다.
>
> 영어 원본: [Chain ladder reserving with
> fit_cl](https://seokhoonj.github.io/lossratio/ko/chain-ladder-reserving.md)

[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
은 단일 값 컬럼에 대한 전용 chain ladder 적합 함수이다. 손해와
익스포저를 동시에 추정해 손해율을 산출하는
[`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
과 달리,
[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
은 하나의 누적 지표를 전방으로 추정하고 코호트별 Mack 방식 표준오차를
함께 계산한다.

## 1. 기본 사용법

이 문서는 간결성을 위해 `SUR` 그룹만 사용한다 — 모든 절차는 다중 그룹
입력에도 그대로 일반화된다.

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

`loss_var` 은 추정 대상 누적 컬럼을 선택한다 — 준비금 산출에는 보통
`"loss"` (누적 손해), 익스포저 추정에는 `"premium"` (누적 위험보험료) 를
쓴다.

## 2. 방법: basic vs Mack

두 가지 추정 방법이 제공된다. 두 방법 모두 인접 dev 의 누적 손해 비
$`f_k = C^L_{k+1} / C^L_k`$ — **ATA 인자**(age-to-age factor) — 를
링크별로 선택한 뒤 누적 추정에 사용한다.

| `method`  | 계산 내용                           |
|-----------|-------------------------------------|
| `"basic"` | 점 추정만 (선택된 ATA 인자)         |
| `"mack"`  | 점 추정 + 인자 / 프로세스 / 모수 SE |

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

# Mack 은 $full 과 $summary 에 분산 추정값을 추가한다
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

`method = "mack"` 으로 적합하면 추정 플롯의 신뢰 구간
(`show_interval = TRUE`) 을 사용할 수 있다.

``` r

plot(cl_mack, type = "projection", show_interval = TRUE)
```

![](chain-ladder-reserving-ko_files/figure-html/unnamed-chunk-3-1.png)

## 3. Tail 인자

마지막 관측 경과 기간에서도 손해가 여전히 발달 중인 triangle 의 경우,
외삽한 tail 인자(tail factor) 로 ultimate 를 추정한다.

``` r

# 선택된 ATA 인자로부터 로그 선형 외삽
cl_tail <- fit_cl(tri, loss_var = "loss", method = "mack", tail = TRUE)

# 또는 명시적인 tail 인자 값 지정
cl_tail <- fit_cl(tri, loss_var = "loss", method = "mack", tail = 1.025)
```

외삽은 추정된 ATA 인자에 대해 $`\log(f_k - 1) \sim k`$ 회귀를 적합한 뒤,
외삽된 $`f_k`$ 의 누적 곱만큼 추정 범위를 연장한다. 기본값은 비활성
(`tail = FALSE`) 이다.

## 4. Maturity 필터링

선택된 ATA 인자가 변동성이 크다면, 추정을 성숙(mature) 영역으로 제한할
수 있다.

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

`maturity_args` 는
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
로 그대로 전달된다.

## 5. 분산 성분 (Mack)

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

## 6. 준비금 플롯

`type = "reserve"` 는 코호트별 준비금을 (Mack 일 경우 선택적 오차 막대와
함께) 표시한다.

``` r

plot(cl_mack, type = "reserve", conf_level = 0.95)
```

![](chain-ladder-reserving-ko_files/figure-html/unnamed-chunk-7-1.png)

## 7. Triangle 시각화

[`plot_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.md)
은 코호트 × dev 셀을 히트맵으로 표시하며, 관측된 셀과 추정된 셀을
구분한다.

``` r

plot_triangle(cl_mack, what = "full")    # 관측 + 추정
```

![](chain-ladder-reserving-ko_files/figure-html/unnamed-chunk-8-1.png)

``` r

plot_triangle(cl_mack, what = "pred")    # 추정만
```

![](chain-ladder-reserving-ko_files/figure-html/unnamed-chunk-8-2.png)

``` r

plot_triangle(cl_mack, what = "data")    # 관측만
```

![](chain-ladder-reserving-ko_files/figure-html/unnamed-chunk-8-3.png)

`label_style = "cv"` 모드는 셀별 변동계수를 표시하며, 신뢰성이 낮은 셀을
식별하는 데 유용하다.

``` r

plot_triangle(cl_mack, label_style = "cv")
```

![](chain-ladder-reserving-ko_files/figure-html/unnamed-chunk-9-1.png)

``` r

plot_triangle(cl_mack, label_style = "se")
```

![](chain-ladder-reserving-ko_files/figure-html/unnamed-chunk-9-2.png)

``` r

plot_triangle(cl_mack, label_style = "ci")
```

![](chain-ladder-reserving-ko_files/figure-html/unnamed-chunk-9-3.png)

## 8. Sigma 외삽 방법

Mack 분산은 모든 발달 링크에서 $`\sigma_k`$ 가 필요한데, 마지막
링크에서는 직접 추정이 불가능하다. `sigma_method` 가 외삽 방식을
결정한다.

| `sigma_method` | 동작 |
|----|----|
| `"min_last2"` | (default) 추정 가능한 마지막 두 $`\sigma`$ 의 최솟값 — 보수적 |
| `"locf"` | 마지막 관측값 carried forward |
| `"loglinear"` | 관측된 $`\sigma_k`$ 시퀀스에 대한 로그 선형 외삽 |

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

## 9. 함께 보기

- [`vignette("projection")`](https://seokhoonj.github.io/lossratio/ko/articles/projection.md)
  —
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
  을 사용해야 할 때.
- [`vignette("triangle-link-and-maturity")`](https://seokhoonj.github.io/lossratio/ko/articles/triangle-link-and-maturity.md)
  — [`summary()`](https://rdrr.io/r/base/summary.html),
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md),
  ata 진단 플롯.
- [`?fit_cl`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md),
  [`?detect_maturity`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md),
  [`?fit_ata`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md).
