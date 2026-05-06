# 집계 프레임워크: Triangle, Calendar, Total

> 영어 원본 보기: [Three aggregation
> frameworks](https://seokhoonj.github.io/lossratio/aggregation-frameworks.md)

동일한 long-format experience 데이터는 분석 질문에 따라 세 가지 방식으로
집계할 수 있다. `lossratio` 는 각 프레임워크별로 하나의 빌더를 제공한다.
이 문서는 셋을 비교한다.

## 1. 한눈에 보기

| 빌더 | 출력 객체 | 차원 | 사용 시점 |
|----|----|----|----|
| [`build_triangle()`](https://seokhoonj.github.io/lossratio/reference/build_triangle.md) | `Triangle` | 코호트 × dev (2D) | SA, ED, CL 추정 |
| [`build_calendar()`](https://seokhoonj.github.io/lossratio/reference/build_calendar.md) | `Calendar` | 달력 기간 (1D) | 달력 연도 추세, 대각선 효과 |
| [`build_total()`](https://seokhoonj.github.io/lossratio/reference/build_total.md) | `Total` | 포트폴리오 합계 (그룹별) | 상위 수준 손해율 비교 |

개념적으로 다음과 같다.

- `Triangle` 은 코호트 축 (계약 인수 시점) 과 경과 축 (경과 기간에 따라
  손해가 누적되는 양상) 을 모두 보존한다. Chain ladder 의 표준 데이터
  구조이다.
- `Calendar` 는 코호트를 대각선 위로 합산한다 — 각 행은 모든 인수
  코호트에 걸친 하나의 달력 기간이다. Triangle 의 대각선 합과 동치이다.
- `Total` 은 두 차원을 모두 합쳐 그룹당 하나의 값으로 축약한다.
  포트폴리오 수준 비교에 유용하다 (해당 기간에 어떤 상품이 가장 나쁜
  손해율을 보였는가?).

## 2. Triangle (코호트 × dev)

``` r

library(lossratio)
data(experience)
exp <- as_experience(experience)

tri <- build_triangle(exp, group_var = cv_nm)
head(tri)
#>     cv_nm n_obs     cohort   dev   loss       rp  closs      crp   margin
#>    <char> <int>     <Date> <int>  <num>    <num>  <num>    <num>    <num>
#> 1:    SUR    30 2023-04-01     1      0 11191622      0 11191622 11191622
#> 2:    CAN    30 2023-04-01     1   6445 12879191   6445 12879191 12872746
#> 3:    2CI    30 2023-04-01     1 468845  7567723 468845  7567723  7098878
#> 4:    HOS    30 2023-04-01     1      0 15273272      0 15273272 15273272
#> 5:    SUR    29 2023-04-01     2      0 14025885      0 25217507 14025885
#> 6:    CAN    29 2023-04-01     2      0 30821344   6445 43700535 30821344
#>     cmargin profit cprofit           lr          clr  loss_prop   rp_prop
#>       <num> <fctr>  <fctr>        <num>        <num>      <num>     <num>
#> 1: 11191622    pos     pos 0.0000000000 0.0000000000 0.00000000 0.2385673
#> 2: 12872746    pos     pos 0.0005004196 0.0005004196 0.01356014 0.2745405
#> 3:  7098878    pos     pos 0.0619532454 0.0619532454 0.98643986 0.1613181
#> 4: 15273272    pos     pos 0.0000000000 0.0000000000 0.00000000 0.3255741
#> 5: 25217507    pos     pos 0.0000000000 0.0000000000 0.00000000 0.1890296
#> 6: 43694090    pos     pos 0.0000000000 0.0001474810 0.00000000 0.4153853
#>     closs_prop  crp_prop
#>          <num>     <num>
#> 1: 0.000000000 0.2385673
#> 2: 0.013560142 0.2745405
#> 3: 0.986439858 0.1613181
#> 4: 0.000000000 0.3255741
#> 5: 0.000000000 0.2082178
#> 6: 0.008953204 0.3608298
```

각 행은 (코호트, dev) 셀 하나이며 누적 손해액 / 누적 위험보험료 값을
갖는다. 라인 플롯이나 히트맵으로 시각화할 수 있다.

``` r

plot(tri)              # 코호트별 궤적, 그룹별 facet
```

![](aggregation-frameworks-ko_files/figure-html/unnamed-chunk-2-1.png)

``` r


# 그룹이 여럿일 때는 패널마다 셀이 좁아져 가독성이 떨어지므로, 코호트와
# dev 축 모두 분기 단위로 다시 만들어 패널당 ~10 × 10 셀로 줄인다.
# 문서 표시 크기에 맞춘 처리이며, 실제 분석에서는 플롯을 키우면 월
# 단위 그대로 볼 수 있다.
tri_q <- build_triangle(exp, group_var = cv_nm,
                        cohort_var = "uyq", dev_var = "elap_q")
plot_triangle(tri_q)   # 코호트 × dev clr 히트맵
```

![](aggregation-frameworks-ko_files/figure-html/unnamed-chunk-2-2.png)

`Triangle` 은 다음 함수의 입력으로 사용된다.

- [`build_ata()`](https://seokhoonj.github.io/lossratio/reference/build_ata.md),
  [`build_ed()`](https://seokhoonj.github.io/lossratio/reference/build_ed.md)
  — 발달 인자
- [`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md),
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)
  — 추정
- [`detect_cohort_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_cohort_regime.md)
  — 구조 변화 탐지

## 3. Calendar (달력 기간만)

``` r

cal <- build_calendar(exp, group_var = cv_nm, calendar_var = "cym")
head(cal)
#>     cv_nm   calendar   dev     loss        rp     closs       crp   margin
#>    <char>     <Date> <int>    <num>     <num>     <num>     <num>    <num>
#> 1:    2CI 2023-04-01     1   468845   7567723    468845   7567723  7098878
#> 2:    2CI 2023-05-01     2   788082  27286688   1256927  34854411 26498606
#> 3:    2CI 2023-06-01     3 18122450  42665533  19379377  77519944 24543083
#> 4:    2CI 2023-07-01     4 70259233  68265637  89638610 145785581 -1993596
#> 5:    2CI 2023-08-01     5 32739949 110351072 122378559 256136653 77611123
#> 6:    2CI 2023-09-01     6 61587160 135154735 183965719 391291388 73567575
#>      cmargin profit cprofit         lr        clr loss_prop   rp_prop
#>        <num> <fctr>  <fctr>      <num>      <num>     <num>     <num>
#> 1:   7098878    pos     pos 0.06195325 0.06195325 0.9864399 0.1613181
#> 2:  33597484    pos     pos 0.02888156 0.03606221 0.9626040 0.2248381
#> 3:  58140567    pos     pos 0.42475621 0.24999214 0.3480569 0.1688936
#> 4:  56146971    neg     pos 1.02920351 0.61486609 0.4423512 0.2060648
#> 5: 133758094    pos     pos 0.29668900 0.47778620 0.2173682 0.2219566
#> 6: 207325669    pos     pos 0.45567889 0.47015019 0.2061898 0.2113124
#>    closs_prop  crp_prop
#>         <num>     <num>
#> 1:  0.9864399 0.1613181
#> 2:  0.9713591 0.2071298
#> 3:  0.3631717 0.1841805
#> 4:  0.4224394 0.1938191
#> 5:  0.3373051 0.2050163
#> 6:  0.2781021 0.2071482
```

각 행은 그룹별 달력 기간 하나이다. 여기서 `dev` 컬럼은 그룹 내부의 순차
인덱스 (1, 2, 3, …) 이며, “코호트 시작 이후의 경과 기간(development
period)” 이 아니다.

Calendar 집계는 수학적으로 Triangle 의 **대각선 합** 이다. 같은 `cym`
값을 갖는 셀 (`uym`/`elap_m` 와 무관하게) 이 합쳐진다.

활용 사례는 다음과 같다.

- 추세 분석 (“손해율이 달력 시간에 따라 상승 중”)
- 대각선 효과 (calendar-year effect) 탐지 (예: 규제 충격, 보험료
  on-leveling 이벤트)
- 포트폴리오 모니터링 대시보드

``` r

plot(cal)                       # x axis: calendar
```

![](aggregation-frameworks-ko_files/figure-html/unnamed-chunk-4-1.png)

``` r

plot(cal, x_by = "dev")         # x axis: 순차 인덱스
```

![](aggregation-frameworks-ko_files/figure-html/unnamed-chunk-4-2.png)

## 4. Total (포트폴리오 요약)

``` r

tot <- build_total(
  exp,
  group_var = cv_nm,
  cohort_var = "uym",
  period_from = "2023-04-01",
  period_to   = "2024-03-01"
)
head(tot)
#>     cv_nm n_obs sales_start  sales_end        loss          rp        lr
#>    <char> <int>      <Date>     <Date>       <num>       <num>     <num>
#> 1:    SUR    30  2023-04-01 2024-03-01 26195800145 23817090339 1.0998741
#> 2:    CAN    30  2023-04-01 2024-03-01 15036650678 24008537158 0.6263043
#> 3:    2CI    30  2023-04-01 2024-03-01 12482828960 18720199627 0.6668107
#> 4:    HOS    30  2023-04-01 2024-03-01  9737095690 25111393787 0.3877561
#>    loss_prop   rp_prop
#>        <num>     <num>
#> 1: 0.4128419 0.2598496
#> 2: 0.2369754 0.2619383
#> 3: 0.1967275 0.2042414
#> 4: 0.1534552 0.2739707
```

그룹당 한 행이며 해당 기간의 손해액 / 위험보험료 / 손해율을 요약한다.
`period_from` / `period_to` 인자로 기간을 지정해 그룹 간 비교 가능성을
확보한다.

활용 사례는 다음과 같다.

- 담보별 전체 손해율 비교
- 그룹별 준비금 / 포트폴리오 비중 순위
- 보고용 요약표 작성

## 5. 데이터 흐름으로 본 집계

                         experience (long, with demographics)
                                  │
             ┌────────────────────┼─────────────────────┐
             │                    │                     │
       build_triangle      build_calendar         build_total
       (cohort × dev)      (calendar series)     (portfolio total)
             │                    │                     │
             ▼                    ▼                     ▼
         Triangle             Calendar               Total
       (2D, projection)     (1D, trend)         (0D, comparison)

세 빌더 모두 동일한 `experience` 에서 출발해 인구통계 차원을 제거한다.
분석 질문에 맞춰 프레임워크를 선택한다.

## 6. 속성 스키마

집계 후 각 객체는 원본 컬럼 메타데이터를 속성으로 저장한다 — 플롯 라벨과
집계 주기에 맞는 날짜 표기에 사용된다.

``` r

attr(tri, "cohort_var")      # "uym"
#> [1] "uym"
attr(tri, "cohort_type")     # "month"
#> [1] "month"
attr(tri, "dev_var")         # "elap_m"
#> [1] "elap_m"
attr(tri, "dev_type")        # "month"
#> [1] NA

attr(cal, "calendar_var")    # "cym"
#> [1] "cym"
attr(cal, "calendar_type")   # "month"
#> [1] "month"
```

데이터 컬럼 자체는 `cohort` / `dev` / `calendar` 로 표준화되어 있으므로,
이후 처리는 집계 주기에 무관하다.
