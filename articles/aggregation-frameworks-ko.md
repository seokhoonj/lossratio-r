# Aggregation frameworks: 집계 프레임워크 (Triangle, Calendar, Total)

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

tri <- build_triangle(exp, group_var = coverage)
head(tri)
#>    coverage n_obs     cohort   dev     loss loss_incr   premium premium_incr
#>      <char> <int>     <Date> <int>    <num>     <num>     <num>        <num>
#> 1:       CI    36 2024-01-01     1  1262380   1262380  27993106     27993106
#> 2:       CI    35 2024-01-01     2 12518143  11255763  57177037     29183931
#> 3:       CI    34 2024-01-01     3 23799452  11281309  86579003     29401966
#> 4:       CI    33 2024-01-01     4 57401838  33602387 113149543     26570540
#> 5:       CI    32 2024-01-01     5 64554460   7152622 140621429     27471886
#> 6:       CI    31 2024-01-01     6 74664985  10110525 167390789     26769360
#>           lr   lr_incr   margin margin_incr profit profit_incr loss_prop
#>        <num>     <num>    <num>       <num> <fctr>      <fctr>     <num>
#> 1: 0.0450961 0.0450961 26730726    26730726    pos         pos 0.2745858
#> 2: 0.2189365 0.3856836 44658894    17928168    pos         pos 0.1681986
#> 3: 0.2748871 0.3836923 62779551    18120657    pos         pos 0.2132982
#> 4: 0.5073095 1.2646482 55747705    -7031846    pos         neg 0.3016874
#> 5: 0.4590656 0.2603615 76066969    20319264    pos         pos 0.2007284
#> 6: 0.4460519 0.3776902 92725804    16658835    pos         pos 0.2065480
#>    loss_incr_prop premium_prop premium_incr_prop
#>             <num>        <num>             <num>
#> 1:     0.27458584    0.3811712         0.3811712
#> 2:     0.16119409    0.3803460         0.3795578
#> 3:     0.30364018    0.3873522         0.4017435
#> 4:     0.42701714    0.3795353         0.3561180
#> 5:     0.05446224    0.3776462         0.3700598
#> 6:     0.25346878    0.3774003         0.3761138
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
tri_q <- build_triangle(exp, group_var = coverage,
                        cohort_var = "uyq", dev_var = "elap_q")
plot_triangle(tri_q)   # 코호트 × dev lr 히트맵
```

![](aggregation-frameworks-ko_files/figure-html/unnamed-chunk-2-2.png)

`Triangle` 은 다음 함수의 입력으로 사용된다.

- [`build_link()`](https://seokhoonj.github.io/lossratio/reference/build_link.md)
  — 발달 인자 (ATA / ED 는 `loss_var` + 선택적 `premium_var` 로 선택)
- [`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md),
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)
  — 추정
- [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  — 구조 변화 탐지

## 3. Calendar (달력 기간만)

``` r

cal <- build_calendar(exp, group_var = coverage, calendar_var = "cym")
head(cal)
#>    coverage   calendar   dev      loss loss_incr   premium premium_incr
#>      <char>     <Date> <int>     <num>     <num>     <num>        <num>
#> 1:      CAN 2024-01-01     1   1327186   1327186  36175141     36175141
#> 2:      CAN 2024-02-01     2  53881242  52554056  89468123     53292982
#> 3:      CAN 2024-03-01     3  86254932  32373690 169732522     80264399
#> 4:      CAN 2024-04-01     4 222577949 136323017 264457245     94724723
#> 5:      CAN 2024-05-01     5 358604650 136026701 373603000    109145755
#> 6:      CAN 2024-06-01     6 439679308  81074658 504742607    131139607
#>            lr    lr_incr   margin margin_incr profit profit_incr loss_prop
#>         <num>      <num>    <num>       <num> <fctr>      <fctr>     <num>
#> 1: 0.03668779 0.03668779 34847955  34847955.0    pos         pos 0.2886821
#> 2: 0.60223955 0.98613464 35586881    738926.1    pos         pos 0.6063314
#> 3: 0.50818152 0.40333810 83477590  47890709.1    pos         pos 0.4890990
#> 4: 0.84164058 1.43914928 41879296 -41598294.3    pos         neg 0.5008249
#> 5: 0.95985485 1.24628485 14998350 -26880946.3    pos         neg 0.4596116
#> 6: 0.87109608 0.61823167 65063299  50064949.1    pos         pos 0.3994334
#>    loss_incr_prop premium_prop premium_incr_prop
#>             <num>        <num>             <num>
#> 1:      0.2886821    0.4925828         0.4925828
#> 2:      0.6236615    0.4520297         0.4281056
#> 3:      0.3700256    0.4162566         0.3825138
#> 4:      0.5085391    0.3892024         0.3486040
#> 5:      0.4050687    0.3778725         0.3529756
#> 6:      0.2529446    0.3557249         0.3048260
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
  group_var = coverage,
  cohort_var = "uym",
  period_from = "2023-04-01",
  period_to   = "2024-03-01"
)
head(tot)
#>    coverage n_obs sales_start  sales_end       loss    premium        lr
#>      <char> <int>      <Date>     <Date>      <num>      <num>     <num>
#> 1:       CI    36  2024-01-01 2024-03-01 2064328135 2662203520 0.7754209
#> 2:      CAN    36  2024-01-01 2024-03-01 1977648787 2833911875 0.6978512
#> 3:      HOS    36  2024-01-01 2024-03-01   69154095  183995898 0.3758459
#> 4:      SUR    36  2024-01-01 2024-03-01 2365065013 1582851298 1.4941802
#>    loss_prop premium_prop
#>        <num>        <num>
#> 1: 0.3187563   0.36654512
#> 2: 0.3053720   0.39018676
#> 3: 0.0106782   0.02533345
#> 4: 0.3651935   0.21793466
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
