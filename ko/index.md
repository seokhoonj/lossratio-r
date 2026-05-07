# lossratio

보험 경험 데이터의 손해율 분석과 추정.

## 개요

`lossratio`는 보험 경험 데이터로부터 **장기 건강보험** 손해율을
분석·추정하기 위한 도구 모음이다. 입력은 long-format 경험 데이터로, 한
행(코호트 × 경과 기간 × 인구통계)이 Triangle 셀 하나에 대응하며,
손해액과 위험보험료 컬럼을 가진다.

장기 건강보험에서는 코호트 내 신규 클레임과 위험보험료가 지속적으로
발생·유입되므로, 누적 손해와 익스포저가 함께 증가하는 구조를 가진다.
초기 경과 기간의 age-to-age (ATA) factor는 높은 변동성을 보일 수 있으며,
상대적으로 익스포저(≈ 위험보험료)가 보다 안정적이고 신뢰할 수 있는
기준이 된다. 또한 상품 개정, 인수 기준 변경, 규제 조치 등으로 인해
구조적 변화(structural break)가 발생할 수 있으며, 이는 코호트 전반에
걸쳐 누적된다.

`lossratio` 는 이러한 환경에 맞춰 단계 적응형(stage-adaptive, SA) 손해율
추정과 이를 뒷받침하는 성숙점(maturity point) 및 regime 탐지 도구를
제공한다. SA 는 성숙점 이전에는 노출 기반(exposure-driven, ED) 모형을,
이후에는 chain ladder(CL) 를 사용한다. regime 탐지는 유사한 손해 추이를
공유하는 인수 코호트들의 묶음(regime) 을 식별해 구조적 변화 시점을
분리하며, 어떤 셀을 추정에 활용할지 결정한다.

제공 기능:

- 경험 데이터의 세 가지 집계 프레임: 코호트 × 경과 기간 (`Triangle`),
  달력 기간 (`Calendar`), 포트폴리오 전체 (`Total`)
- age-to-age (`ATA`) 와 노출 기반 (`ED`) 의 경과 기간 모형화
- chain ladder 추정 (`fit_cl`) 과 손해율 추정 (`fit_lr`), 세 가지 method
  지원:
  - `"sa"` — **단계 적응형** (default): 성숙점 이전은 노출 기반, 이후는
    chain ladder
  - `"ed"` — 모든 경과 기간에 대해 노출 기반
  - `"cl"` — 고전적 chain ladder (Mack 모형)
- 구조적 변화에 대한 코호트 regime 탐지 (`detect_cohort_regime`)
- 진단 및 Triangle 시각화

## 입력 형식

최소한 다음 컬럼을 포함하는 long-format `data.frame` / `data.table`:

| 컬럼   | 의미                                       | 예시               |
|--------|--------------------------------------------|--------------------|
| cohort | 인수 / 사고 시점 (집계 주기 무관)          | `uym`, `uy`        |
| dev    | 코호트 시작 시점 이후 경과 기간            | `elap_m`, `elap_y` |
| `loss` | 셀 내 증가분 클레임 금액                   | numeric            |
| `rp`   | 셀 내 증가분 위험보험료 (기대손해액)       | numeric            |
| group  | 선택 — 상품, 담보, 연령, 성별, 가입금액 등 | character / factor |

[`as_experience()`](https://seokhoonj.github.io/lossratio/ko/reference/as_experience.md)
는 스키마를 검증하고 날짜 컬럼을 코어션한다. 이어서
[`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md)
은 표준 코호트 × 경과 기간 구조로 집계하며, 누적 컬럼과 파생 비율을 함께
산출한다.

## 설치

``` r

# pak (recommended)
pak::pak("seokhoonj/lossratio")

# remotes (alternative)
remotes::install_github("seokhoonj/lossratio")
```

이 패키지는 현재 seokhoonj/instead 와 seokhoonj/ggshort 에 의존한다
(Remotes: 를 통해 자동 설치, 추후 의존성 제거 예정).

## Quick Start

``` r

library(lossratio)

# 번들로 제공되는 합성 경험 데이터
# 경과에 따른 곡선 형태는 실제 포트폴리오의 전체 형태에 맞춰 보정
# 셀 값과 코호트 패턴은 무작위 생성
data(experience)
exp <- as_experience(experience)

# 표준 코호트 × dev 구조 구축
tri <- build_triangle(exp, group_var = cv_nm)

plot(tri)              # cohort trajectories
plot_triangle(tri)     # cell heatmap

# ATA 와 노출 기반 발전 모형
ata <- build_ata(tri, value_var = "closs"); fit_ata(ata)
ed  <- build_ed(tri);                       fit_ed(ed)

# Chain ladder 적합
cl <- fit_cl(tri, value_var = "closs", method = "mack")
plot(cl, type = "projection")

# 손해율 적합 (default: 단계 적응형)
lr <- fit_lr(tri, method = "sa")
plot(lr, type = "clr")
summary(lr)

# 코호트 간 구조적 변화 탐지
detect_cohort_regime(tri[cv_nm == "SUR"], K = 12, method = "ecp")
```

## 집계 프레임

동일한 long-format 경험 데이터를 세 가지 관점으로 본다:

| Builder | 출력 객체 | 차원 | 활용 |
|----|----|----|----|
| [`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md) | `Triangle` | 코호트 × 경과 기간 (2D) | Chain ladder, ED, SA 추정 |
| [`build_calendar()`](https://seokhoonj.github.io/lossratio/ko/reference/build_calendar.md) | `Calendar` | 달력 기간 (1D) | 달력연도 추세 / 대각선 효과 |
| [`build_total()`](https://seokhoonj.github.io/lossratio/ko/reference/build_total.md) | `Total` | 포트폴리오 전체 (0D, 그룹별) | 그룹 간 고수준 비교 |

`build_triangle` 이후의 컬럼은 입력된 집계 주기 (`uym` / `uyq` / `uy`
등) 와 무관하게 `cohort` 와 `dev` 로 표준화된다. 원본 컬럼명과 집계
주기는 attribute (`cohort_var`, `cohort_type`, `dev_var`, `dev_type`) 로
보존된다.

## Methods

### 단계 적응형

`fit_lr(method = "sa")` (default). 노출 기반과 chain ladder 의 결합으로,
그룹별 성숙점에서 전환된다:

- 성숙점 이전: 노출 기반 추정 $`\Delta C^L = g_k \cdot C^P_k`$ — ATA
  인자가 변동성이 큰 구간에서 추정값을 보험료 규모에 고정한다.
- 성숙점 이후: chain ladder 추정 $`C^L_{k+1} = f_k \cdot C^L_k`$ — ATA
  인자가 안정된 이후 코호트의 관측 수준을 보존한다.

### 노출 기반

`fit_lr(method = "ed")`. 모든 미래 손해 증가분이 익스포저(≈
위험보험료)를 분모로 사용한다. ATA 인자가 정보량이 부족하거나 전 구간에
걸쳐 불안정할 때 적합하다.

### Chain Ladder

`fit_lr(method = "cl")` 또는
[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md).
고전적 Mack chain ladder. 선택적 log-linear tail factor 와 해석적 Mack
표준오차를 지원한다.

## 시각화

두 S3 generic 모두 객체 클래스에 따라 dispatch 된다:

``` r

plot(x)              # base plot generic — line / panel diagnostics
plot_triangle(x)     # lossratio generic — cell heatmap layout
```

[`plot()`](https://rdrr.io/r/graphics/plot.default.html) 과
[`plot_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.md)
은 `Triangle`, `Calendar`, `ATA`, `ATAFit`, `ED`, `EDFit`, `CLFit`,
`LRFit`, `CohortRegime` 객체 전반에 일관되게 작동한다.

## 문서

``` r

?build_triangle
?fit_lr
?detect_cohort_regime
vignette("regime-detection", package = "lossratio")
```

## 라이선스

GPL (\>= 2).
[LICENSE.md](https://seokhoonj.github.io/lossratio/ko/LICENSE.md) 참조.

## Author

Seokhoon Joo (<seokhoonj@gmail.com>)
