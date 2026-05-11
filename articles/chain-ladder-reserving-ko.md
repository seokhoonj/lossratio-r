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
> fit_cl](https://seokhoonj.github.io/lossratio/chain-ladder-reserving.md)

[`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md)
은 단일 값 컬럼에 대한 전용 chain ladder 적합 함수이다. 손해와
익스포저를 동시에 추정해 손해율을 산출하는
[`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)
과 달리,
[`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md)
은 하나의 누적 지표를 전방으로 추정하고 코호트별 Mack 방식 표준오차를
함께 계산한다.

## 1. 기본 사용법

이 문서는 간결성을 위해 `SUR` 그룹만 사용한다 — 모든 절차는 다중 그룹
입력에도 그대로 일반화된다.

``` r

library(lossratio)
data(experience)
tri <- build_triangle(experience[coverage == "SUR"], group_var = coverage)

cl <- fit_cl(tri, loss_var = "loss", method = "mack")
print(cl)
#> <CLFit>
#> method      : mack 
#> loss_var   : loss 
#> weight_var  : none 
#> alpha       : 1 
#> sigma_method: locf 
#> recent      : all 
#> use_maturity: FALSE 
#> tail_factor : 1 
#> groups      : coverage 
#> periods     : 36
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
#>    coverage     cohort     latest   loss_ult   reserve  proc_se param_se
#>      <char>     <Date>      <num>      <num>     <num>    <num>    <num>
#> 1:      SUR 2023-01-01  410248523  410248523         0        0        0
#> 2:      SUR 2023-02-01  976330446 1001441304  25110859  2751818  4299411
#> 3:      SUR 2023-03-01  978486044 1026151241  47665197  3967868  5021194
#> 4:      SUR 2023-04-01 2029909922 2186771224 156861302  6942936 11297884
#> 5:      SUR 2023-05-01  624219442  697669308  73449866  4455635  3696917
#> 6:      SUR 2023-06-01  802880717  931393933 128513217 17869565  8694892
#>          se          cv
#>       <num>       <num>
#> 1:        0 0.000000000
#> 2:  5104649 0.005097302
#> 3:  6399717 0.006236621
#> 4: 13260714 0.006064061
#> 5:  5789636 0.008298539
#> 6: 19872657 0.021336468
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

`maturity_args` 는
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
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
#>     coverage     cohort     latest   loss_ult    reserve   proc_se param_se
#>       <char>     <Date>      <num>      <num>      <num>     <num>    <num>
#>  1:      SUR 2023-01-01  410248523  410248523          0         0        0
#>  2:      SUR 2023-02-01  976330446 1001441304   25110859   2751818  4299411
#>  3:      SUR 2023-03-01  978486044 1026151241   47665197   3967868  5021194
#>  4:      SUR 2023-04-01 2029909922 2186771224  156861302   6942936 11297884
#>  5:      SUR 2023-05-01  624219442  697669308   73449866   4455635  3696917
#>  6:      SUR 2023-06-01  802880717  931393933  128513217  17869565  8694892
#>  7:      SUR 2023-07-01 2539141550 3050990158  511848609  35918003 30501064
#>  8:      SUR 2023-08-01  393678329  488218204   94539875  15583801  5072721
#>  9:      SUR 2023-09-01 1364052543 1751869309  387816766  38001618 20827314
#> 10:      SUR 2023-10-01  979266044 1311793844  332527800  38496097 16992220
#> 11:      SUR 2023-11-01  604685680  848103124  243417444  35719580 11901733
#> 12:      SUR 2023-12-01 1026345365 1497869026  471523662  51405333 22008504
#> 13:      SUR 2024-01-01 1912177598 2901492850  989315252  75674312 43971809
#> 14:      SUR 2024-02-01  733902485 1160045952  426143467  51719398 18269126
#> 15:      SUR 2024-03-01  415459872  686574146  271114274  41313265 11014492
#> 16:      SUR 2024-04-01 3286053525 5687484009 2401430484 122770257 92689753
#> 17:      SUR 2024-05-01 1451731151 2645801834 1194070683  93024106 45040850
#> 18:      SUR 2024-06-01  629668308 1209024555  579356246  65346187 20907249
#> 19:      SUR 2024-07-01 1250954692 2542927187 1291972495 103136527 45568403
#> 20:      SUR 2024-08-01  425346694  918120581  492773887  65317866 16819267
#> 21:      SUR 2024-09-01  278156543  635470027  357313485  56737053 11859688
#> 22:      SUR 2024-10-01  352070325  856446527  504376201  68091257 16219630
#> 23:      SUR 2024-11-01   99050502  260916098  161865596  41787166  5190764
#> 24:      SUR 2024-12-01  103194015  295637302  192443287  49617196  6221683
#> 25:      SUR 2025-01-01  227089023  710560088  483471065  83635489 15668259
#> 26:      SUR 2025-02-01  939163073 3276849148 2337686075 192418633 75222223
#> 27:      SUR 2025-03-01  112828843  434950050  322121207  72345359 10161412
#> 28:      SUR 2025-04-01   82472453  356301149  273828696  68974257  8575343
#> 29:      SUR 2025-05-01  141214851  697290588  556075737 119238986 19174475
#> 30:      SUR 2025-06-01  136406104  789468809  653062706 136628653 22834478
#> 31:      SUR 2025-07-01  149144024 1040451732  891307708 167039609 31445935
#> 32:      SUR 2025-08-01  116327076 1008356737  892029661 183653360 32987225
#> 33:      SUR 2025-09-01   67465470  783000254  715534784 179947036 27713231
#> 34:      SUR 2025-10-01  121626172 2001214853 1879588681 337103186 80113491
#> 35:      SUR 2025-11-01   15716444  449653411  433936967 194100660 21034521
#> 36:      SUR 2025-12-01    4825085  850839165  846014080 472741777 66075502
#>     coverage     cohort     latest   loss_ult    reserve   proc_se param_se
#>       <char>     <Date>      <num>      <num>      <num>     <num>    <num>
#>            se          cv
#>         <num>       <num>
#>  1:         0 0.000000000
#>  2:   5104649 0.005097302
#>  3:   6399717 0.006236621
#>  4:  13260714 0.006064061
#>  5:   5789636 0.008298539
#>  6:  19872657 0.021336468
#>  7:  47121310 0.015444596
#>  8:  16388635 0.033568259
#>  9:  43334743 0.024736288
#> 10:  42079509 0.032077837
#> 11:  37650227 0.044393454
#> 12:  55918535 0.037332059
#> 13:  87522120 0.030164514
#> 14:  54851227 0.047283667
#> 15:  42756344 0.062274911
#> 16: 153830837 0.027047256
#> 17: 103354547 0.039063601
#> 18:  68609309 0.056747655
#> 19: 112754701 0.044340515
#> 20:  67448583 0.073463753
#> 21:  57963310 0.091213288
#> 22:  69996398 0.081728860
#> 23:  42108328 0.161386469
#> 24:  50005754 0.169145618
#> 25:  85090477 0.119751276
#> 26: 206599402 0.063048188
#> 27:  73055494 0.167962951
#> 28:  69505285 0.195074548
#> 29: 120770842 0.173200161
#> 30: 138523652 0.175464376
#> 31: 169973756 0.163365345
#> 32: 186592373 0.185045992
#> 33: 182068556 0.232526816
#> 34: 346492034 0.173140847
#> 35: 195237080 0.434194593
#> 36: 477337155 0.561019255
#>            se          cv
#>         <num>       <num>
```

## 6. 준비금 플롯

`type = "reserve"` 는 코호트별 준비금을 (Mack 일 경우 선택적 오차 막대와
함께) 표시한다.

``` r

plot(cl_mack, type = "reserve", conf_level = 0.95)
```

![](chain-ladder-reserving-ko_files/figure-html/unnamed-chunk-7-1.png)

## 7. Triangle 시각화

[`plot_triangle()`](https://seokhoonj.github.io/lossratio/reference/plot_triangle.md)
은 코호트 × dev 셀을 히트맵으로 표시하며, 관측된 셀과 추정된 셀을
구분한다.

``` r

plot_triangle(cl_mack, region = "full")    # 관측 + 추정
```

![](chain-ladder-reserving-ko_files/figure-html/unnamed-chunk-8-1.png)

``` r

plot_triangle(cl_mack, region = "pred")    # 추정만
```

![](chain-ladder-reserving-ko_files/figure-html/unnamed-chunk-8-2.png)

``` r

plot_triangle(cl_mack, region = "data")    # 관측만
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
#> groups      : coverage 
#> periods     : 36
```

## 9. 함께 보기

- [`vignette("projection")`](https://seokhoonj.github.io/lossratio/articles/projection.md)
  —
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)
  을 사용해야 할 때.
- [`vignette("triangle-link-and-maturity")`](https://seokhoonj.github.io/lossratio/articles/triangle-link-and-maturity.md)
  — [`summary()`](https://rdrr.io/r/base/summary.html),
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md),
  ata 진단 플롯.
- [`?fit_cl`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md),
  [`?detect_maturity`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md),
  [`?fit_ata`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md).
