# Package index

## 입력 계층

원시 experience 데이터의 검증·grain 헬퍼.
[`as_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/as_triangle.md)
이 필수 검증·코어션을 내부에서 수행하므로 일반 흐름엔 불필요하며,
Triangle 을 만들지 않고 검증·enrichment 만 하고 싶을 때 사용한다.

- [`derive_grain_columns()`](https://seokhoonj.github.io/lossratio/ko/reference/derive_grain_columns.md)
  : Derive monthly / quarterly / semi-annual / annual grain columns
- [`validate_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/validate_triangle.md)
  : Validate triangle structure before building a development

## 집계 빌더

같은 long-format experience 데이터를 보는 세 가지 프레임워크 — cohort ×
dev (`Triangle`), 달력 기간 (`Calendar`), 포트폴리오 전체 (`Total`).

- [`as_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/as_triangle.md)
  : Coerce experience data to a Triangle object
- [`as_calendar()`](https://seokhoonj.github.io/lossratio/ko/reference/as_calendar.md)
  : Coerce experience data to a Calendar object
- [`as_total()`](https://seokhoonj.github.io/lossratio/ko/reference/as_total.md)
  : Coerce experience data to a Total object

## 단계 연결 테이블

Chain ladder (ATA) 와 노출 기반 (ED) 의 공통 long-format intermediate.
[`summary.Link()`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md)
의 `model` 인자로 두 모형의 진단을 분기.

- [`as_link()`](https://seokhoonj.github.io/lossratio/ko/reference/as_link.md)
  : Coerce a Triangle to a Link object

- [`summary(`*`<Link>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md)
  :

  Summarise a `Link` table

## 추정

Triangle 위에서 projection 을 산출하는 모형. 기본 알고리즘: `fit_cl`
(chain ladder / multiplicative), `fit_ed` (exposure-driven / additive).
ELR 기반 reserve 모형: `fit_bf` (외부 prior 를 받는
Bornhuetter-Ferguson), `fit_cc` (데이터에서 pooled ELR 을 추정하는 Cape
Cod). Role dispatcher: `fit_loss` (loss 측 sa/ed/cl), `fit_exposure`
(exposure 측 ed/cl). 합성: `fit_ratio` (손해율 통합 인터페이스,
delta-method SE). 모두 결과 객체에 `$full` projection table 을 보유.

- [`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
  :

  Fit chain ladder projection from a `Triangle` object

- [`fit_ed()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ed.md)
  : Fit ED intensity factors

- [`fit_bf()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_bf.md)
  : Bornhuetter-Ferguson projection

- [`fit_cc()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cc.md)
  : Cape Cod projection (Stanard 1985)

- [`fit_loss()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_loss.md)
  : Fit a loss projection on a Triangle

- [`fit_exposure()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_exposure.md)
  : Fit a chain ladder projection on the exposure triangle

- [`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md)
  : Fit loss ratio projection model

## 인자 진단

Factor level 의 링크별 인자 추정. `fit_ata` (multiplicative ATA 인자
`f_k`) 와 `fit_intensity` (ED 의 additive intensity `g_k`) 가 짝. 두
함수 모두 projection 은 산출하지 않고 인자·SE·진단 stat 만 반환.
`fit_ata` 는 `fit_cl`,
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md),
`fit_ratio(method = "sa")` 의 stage transition 에서 사용되고,
`fit_intensity` 는 `fit_ed` 의 짝 diagnostic.

- [`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md)
  : Fit age-to-age development factors
- [`fit_intensity()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_intensity.md)
  : Fit per-link ED intensity factors

## 추정 셀 선택 진단

Triangle 의 어떤 셀을 추정에 쓸지 결정. `detect_maturity` 는 dev 축 (ATA
인자가 안정화되는 링크 이후), `detect_regime` 은 cohort 축 (인수 코호트
간 구조적 변화). `*_at()` / `*_spec()` 헬퍼는 fit 함수의 `maturity` /
`loss_regime` / `exposure_regime` 인자에 들어갈 수동 (`_at()`) 혹은
lazy-detect (`_spec()`) 입력 객체를 만든다.

- [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
  : Find ata maturity by group
- [`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  [`print(`*`<Regime>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  [`summary(`*`<Regime>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  [`print(`*`<summary.Regime>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  : Detect structural regime shifts across underwriting cohorts
- [`maturity_at()`](https://seokhoonj.github.io/lossratio/ko/reference/maturity_at.md)
  : Construct a Maturity object from manually specified maturity points
- [`maturity_spec()`](https://seokhoonj.github.io/lossratio/ko/reference/maturity_spec.md)
  : Build a lazy maturity detection spec
- [`regime_at()`](https://seokhoonj.github.io/lossratio/ko/reference/regime_at.md)
  : Construct a Regime object from manually specified regime changes
- [`regime_spec()`](https://seokhoonj.github.io/lossratio/ko/reference/regime_spec.md)
  : Build a lazy regime detection spec

## 부트스트랩

cohort × dev 단위 표준오차 분해를 시뮬레이션으로 산출 (피타고라스 분해 —
parameter + process). 반환 객체는 `fit_loss` / `fit_exposure` /
`fit_ratio` 의 `bootstrap` 인자에 전달되어 분석식 SE / CI 를 경험적
값으로 교체.

- [`bootstrap()`](https://seokhoonj.github.io/lossratio/ko/reference/bootstrap.md)
  : Bootstrap a Triangle

## 예측 진단

적합 결과 `RatioFit` 위에서 동작 (raw Triangle 아님). 예측 손해율의
갱신이 멈추는 valuation 깊이 $`v`$ 를 dual criterion (예측 갱신이 잡음
수준 이하 AND 코호트 간 분산이 작음, M 회 연속) 으로 탐지.

- [`detect_convergence()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_convergence.md)
  : Find the development period at which the loss ratio estimate
  stabilises

## Backtest

Triangle 의 최근 대각선을 보류한 뒤 재적합·예측을 보류된 실제값과 비교.

- [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  [`print(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  [`summary(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  [`print(`*`<summary.Backtest>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  : Backtest a loss / exposure / loss-ratio projection on existing data

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

- [`plot(`*`<IntensityFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.IntensityFit.md)
  : Plot an Intensity fit

- [`plot(`*`<Link>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Link.md)
  : Plot link-factor diagnostics

- [`plot(`*`<RatioFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.RatioFit.md)
  : Plot a loss ratio fit

- [`plot(`*`<Regime>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Regime.md)
  : Plot a cohort regime detection result

- [`plot(`*`<RegimeOptimalWindow>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.RegimeOptimalWindow.md)
  : Plot change-count vs window with the elbow marker

- [`plot(`*`<Total>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Total.md)
  :

  Plot a `Total` object as a per-group bar chart

- [`plot(`*`<Triangle>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Triangle.md)
  : Plot development trajectories with optional summary overlay

- [`plot(`*`<TriangleValidation>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot.TriangleValidation.md)
  : Plot a TriangleValidation result

- [`plot_triangle(`*`<ATAFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.ATAFit.md)
  : Triangle heatmap for an ata fit

- [`plot_triangle(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.Backtest.md)
  : Triangle heatmap of backtest A/E Error

- [`plot_triangle(`*`<CLFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.CLFit.md)
  : Plot chain ladder results as a triangle table

- [`plot_triangle(`*`<EDFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.EDFit.md)
  : Triangle heatmap for an ED fit

- [`plot_triangle(`*`<IntensityFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.IntensityFit.md)
  : Triangle heatmap for an Intensity fit

- [`plot_triangle(`*`<Link>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.Link.md)
  : Plot a Link object as a triangle heatmap

- [`plot_triangle(`*`<RatioFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.RatioFit.md)
  : Plot loss ratio projection as a triangle heatmap

- [`plot_triangle(`*`<Triangle>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.Triangle.md)
  : Plot development values as a triangle table

- [`plot_triangle(`*`<TriangleValidation>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/plot_triangle.TriangleValidation.md)
  : Triangle-heatmap view of dev-sequence gaps

## 기타 S3 메서드

패키지 클래스에 등록된 print / summary / longer 메서드.

- [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  [`print(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  [`summary(`*`<Backtest>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  [`print(`*`<summary.Backtest>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
  : Backtest a loss / exposure / loss-ratio projection on existing data

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

- [`print(`*`<BFFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/print.BFFit.md)
  :

  Print method for `BFFit`

- [`print(`*`<BootstrapTriangle>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/print.BootstrapTriangle.md)
  : Print method for BootstrapTriangle

- [`print(`*`<CCFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/print.CCFit.md)
  :

  Print method for `CCFit`

- [`print(`*`<CLFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/print.CLFit.md)
  :

  Print a `CLFit` object

- [`print(`*`<EDFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/print.EDFit.md)
  :

  Print an `EDFit` object

- [`print(`*`<EDSummary>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/print.EDSummary.md)
  :

  Print method for `EDSummary`

- [`print(`*`<ExposureFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/print.ExposureFit.md)
  :

  Print method for `ExposureFit`

- [`print(`*`<IntensityFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/print.IntensityFit.md)
  :

  Print method for `IntensityFit`

- [`print(`*`<LossFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/print.LossFit.md)
  :

  Print method for `LossFit`

- [`print(`*`<RatioFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/print.RatioFit.md)
  :

  Print an `RatioFit` object

- [`summary(`*`<ATAFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.ATAFit.md)
  :

  Summary method for `ATAFit`

- [`summary(`*`<BFFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.BFFit.md)
  :

  Summary method for `BFFit`

- [`summary(`*`<CCFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.CCFit.md)
  :

  Summary method for `CCFit`

- [`summary(`*`<CLFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.CLFit.md)
  :

  Summary method for `CLFit`

- [`summary(`*`<Calendar>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Calendar.md)
  : Summarise calendar-development statistics (Mean, Median, Weighted)

- [`summary(`*`<EDFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.EDFit.md)
  :

  Summary method for `EDFit`

- [`summary(`*`<ExposureFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.ExposureFit.md)
  :

  Summary method for `ExposureFit`

- [`summary(`*`<IntensityFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.IntensityFit.md)
  :

  Summary method for `IntensityFit`

- [`summary(`*`<Link>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Link.md)
  :

  Summarise a `Link` table

- [`summary(`*`<LossFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.LossFit.md)
  :

  Summary method for `LossFit`

- [`summary(`*`<RatioFit>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.RatioFit.md)
  :

  Summary method for `RatioFit`

- [`summary(`*`<Total>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Total.md)
  :

  Summarise a `Total` object

- [`summary(`*`<Triangle>`*`)`](https://seokhoonj.github.io/lossratio/ko/reference/summary.Triangle.md)
  : Summarise development statistics (Mean, Median, Weighted)

## 헬퍼

- [`longer()`](https://seokhoonj.github.io/lossratio/ko/reference/longer.md)
  : Reshape an object to long form (S3 generic)
- [`mask_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/mask_triangle.md)
  : Mask the last N calendar diagonals from a Triangle

## 데이터셋

- [`experience`](https://seokhoonj.github.io/lossratio/ko/reference/experience.md)
  : Sample loss experience data
