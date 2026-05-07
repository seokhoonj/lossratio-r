# Package index

## 입력 계층

원시 experience 데이터의 검증·코어션 헬퍼.

- [`check_experience()`](https://seokhoonj.github.io/lossratio/ko/reference/check_experience.md)
  : Check an experience dataset

- [`is_experience()`](https://seokhoonj.github.io/lossratio/ko/reference/is_experience.md)
  :

  Check whether an object is an `Experience`

- [`as_experience()`](https://seokhoonj.github.io/lossratio/ko/reference/as_experience.md)
  :

  Coerce a dataset to an `Experience` object

- [`add_experience_period()`](https://seokhoonj.github.io/lossratio/ko/reference/add_experience_period.md)
  : Add standard period variables to an experience dataset

- [`validate_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/validate_triangle.md)
  : Validate triangle structure before building a development

## 집계 빌더

같은 long-format experience 데이터를 보는 세 가지 프레임워크 — cohort ×
dev (`Triangle`), 달력 기간 (`Calendar`), 포트폴리오 전체 (`Total`).

- [`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md)
  : Build a development structure from experience data
- [`build_calendar()`](https://seokhoonj.github.io/lossratio/ko/reference/build_calendar.md)
  : Build a calendar-based development structure from experience data
- [`build_total()`](https://seokhoonj.github.io/lossratio/ko/reference/build_total.md)
  : Build a total development summary from experience data

## 단계 연결 테이블

Chain ladder (ATA) 와 노출 기반 (ED) 의 공통 long-format intermediate.
[`summary.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md)
의 `model` 인자로 두 모형의 진단을 분기.

- [`build_link()`](https://seokhoonj.github.io/lossratio/ko/reference/build_link.md)
  :

  Build a link table from `Triangle` data

- [`summary(`*`<Link>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md)
  :

  Summarise a `Link` table

## 추정

링크별 인자 추정 (`fit_ata`, `fit_ed`) 과 전체 예측 (`fit_cl`,
`fit_lr`). `fit_lr` 은 세 가지 method 지원 — `"sa"` (단계 적응형,
default), `"ed"`, `"cl"`.

- [`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md)
  : Fit age-to-age development factors

- [`fit_ed()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ed.md)
  : Fit ED intensity factors

- [`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
  :

  Fit chain ladder projection from a `Triangle` object

- [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
  : Fit loss ratio projection model

## 추정 셀 선택 진단

Triangle 의 어떤 셀을 추정에 쓸지 결정. `detect_maturity` 는 dev 축 (ATA
인자가 안정화되는 링크 이후), `detect_regime` 은 cohort 축 (인수 코호트
간 구조적 변화).

- [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
  : Find ata maturity by group
- [`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  [`print(`*`<Regime>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  [`summary(`*`<Regime>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  [`print(`*`<summary.Regime>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  : Detect structural regime shifts across underwriting cohorts

## 예측 진단

적합 결과 `LRFit` 위에서 동작 (raw Triangle 아님). 예측 손해율의 갱신이
멈추는 valuation 깊이 $`v`$ 를 dual criterion (예측 갱신이 잡음 수준
이하 AND 코호트 간 분산이 작음, M 회 연속) 으로 탐지.

- [`detect_convergence()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_convergence.md)
  : Find the development period at which the loss ratio estimate
  stabilises

## Backtest

Triangle 의 최근 대각선을 보류한 뒤 재적합·예측을 보류된 실제값과 비교.

- [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  [`print(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  [`summary(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  [`print(`*`<summary.Backtest>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  : Backtest a loss-ratio / chain ladder fit on existing data

## 시각화

[`plot()`](https://rdrr.io/r/graphics/plot.default.html) (base generic)
과
[`plot_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.md)
(lossratio generic) 이 객체 클래스에 따라 dispatch.

- [`plot_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.md)
  : Triangle plot generic

- [`plot(`*`<ATAFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.ATAFit.md)
  : Plot an ata fit

- [`plot(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Backtest.md)
  : Plot a backtest object

- [`plot(`*`<CLFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.CLFit.md)
  : Plot a chain ladder fit

- [`plot(`*`<Calendar>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Calendar.md)
  : Plot calendar-based development statistics

- [`plot(`*`<Convergence>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Convergence.md)
  : Plot the Convergence diagnostic

- [`plot(`*`<EDFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.EDFit.md)
  : Plot an ED fit

- [`plot(`*`<LRFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.LRFit.md)
  : Plot a loss ratio fit

- [`plot(`*`<Link>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Link.md)
  : Plot link-factor diagnostics

- [`plot(`*`<Regime>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Regime.md)
  : Plot a cohort regime detection result

- [`plot(`*`<Total>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Total.md)
  :

  Plot a `Total` object as a per-group bar chart

- [`plot(`*`<Triangle>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Triangle.md)
  : Plot development trajectories with optional summary overlay

- [`plot_triangle(`*`<ATAFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.ATAFit.md)
  : Triangle heatmap for an ata fit

- [`plot_triangle(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.Backtest.md)
  : Triangle heatmap of backtest AEG

- [`plot_triangle(`*`<CLFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.CLFit.md)
  : Plot chain ladder results as a triangle table

- [`plot_triangle(`*`<EDFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.EDFit.md)
  : Triangle heatmap for an ED fit

- [`plot_triangle(`*`<LRFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.LRFit.md)
  : Plot loss ratio projection as a triangle heatmap

- [`plot_triangle(`*`<Link>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.Link.md)
  : Plot a Link object as a triangle heatmap

- [`plot_triangle(`*`<Triangle>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.Triangle.md)
  : Plot development values as a triangle table

## 기타 S3 메서드

패키지 클래스에 등록된 print / summary / longer 메서드.

- [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  [`print(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  [`summary(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  [`print(`*`<summary.Backtest>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  : Backtest a loss-ratio / chain ladder fit on existing data

- [`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  [`print(`*`<Regime>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  [`summary(`*`<Regime>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  [`print(`*`<summary.Regime>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  : Detect structural regime shifts across underwriting cohorts

- [`print(`*`<ATAFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/print.ATAFit.md)
  :

  Print an `ATAFit` object

- [`print(`*`<ATASummary>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/print.ATASummary.md)
  :

  Print method for `ATASummary`

- [`print(`*`<CLFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/print.CLFit.md)
  :

  Print a `CLFit` object

- [`print(`*`<EDFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/print.EDFit.md)
  :

  Print an `EDFit` object

- [`print(`*`<EDSummary>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/print.EDSummary.md)
  :

  Print method for `EDSummary`

- [`print(`*`<LRFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/print.LRFit.md)
  :

  Print an `LRFit` object

- [`summary(`*`<ATAFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.ATAFit.md)
  :

  Summary method for `ATAFit`

- [`summary(`*`<CLFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.CLFit.md)
  :

  Summary method for `CLFit`

- [`summary(`*`<Calendar>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Calendar.md)
  : Summarise calendar-development statistics (Mean, Median, Weighted)

- [`summary(`*`<EDFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.EDFit.md)
  :

  Summary method for `EDFit`

- [`summary(`*`<LRFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.LRFit.md)
  :

  Summary method for `LRFit`

- [`summary(`*`<Link>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md)
  :

  Summarise a `Link` table

- [`summary(`*`<Total>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Total.md)
  :

  Summarise a `Total` object

- [`summary(`*`<Triangle>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Triangle.md)
  : Summarise development statistics (Mean, Median, Weighted)

## 헬퍼

- [`get_recent_weights()`](https://seokhoonj.github.io/lossratio/ko/reference/get_recent_weights.md)
  : Recent-diagonal weights for a development triangle
- [`longer()`](https://seokhoonj.github.io/lossratio/ko/reference/longer.md)
  : Reshape an object to long form (S3 generic)

## 데이터셋

- [`experience`](https://seokhoonj.github.io/lossratio/ko/reference/experience.md)
  : Sample loss experience data
