# Convergence: 예측 손해율 수렴 시점 진단

## 1. 동기

[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
는 *“어느 경과 기간부터 link factor $`f_k`$ 가 코호트 간에 재현
가능해지는가?”* 에 답한다. chain ladder 예측에는 필요하지만,
포트폴리오의 예측 손해율이 수렴했다고 선언하기에는 충분하지 않다 — 장기
건강보험에서 $`f_k \to 1`$ 과 $`g_k \to 0`$ 은 누적 분모가 자라면서
자동으로 발생하는 관성(inertia) 효과이지, 기저 경험이 실제로 수렴했다는
신호가 아니다. 그 위에 세운 단일 기준은 $`k`$ 가 커지기만 하면 자동으로
통과한다.

[`detect_convergence()`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md)
는 **수렴점**(convergence point) $`k^{**}`$ — 예측 포트폴리오 손해율이
안정하다고 *관찰되는* 첫 dev $`k \ge k^*`$ 를 검출한다. 어떤 의미의
“안정” 인지는 사용자가 `method =` 인자로 고른다.

성숙점(maturity point) $`k^*`$
([`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
산출) 와 자연스러운 짝이다:

- $`k^*`$: link factor $`f_k`$ 가 코호트 간에 재현 가능해지는 시점.
- $`k^{**}`$: 모형 출력 (예측 손해율) 이 새 데이터에도 거의 움직이지
  않는 시점.

장기 건강보험 portfolio 는 $`k^*`$ 를 일찍 지나도 $`k^{**}`$ 에 한참 못
미칠 수 있다.

## 2. 네 가지 안정성 기준

수렴은 finite data 로 *asymptotic 으로* 측정 불가능하다 — 관측 가능한
최대 dev `dev_max` ($`K_{\max}`$) 까지에 한해 *관찰* 만 가능. 검출기는
후보 시점 시퀀스 `dev_cand` $`\in [k^*, K_{\max}-2]`$ 위에서 rolling
[`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
를 돌려 각 시점의 예측 손해율 경로 `lr` 을 만들고, 그 경로 위에서 네
가지 안정성 지표를 평가한다. `method =` 가 어떤 지표가 `conv_k` 를
결정할지 선택한다. 네 지표 모두 항상 결과 객체에 반환되므로 사용자는
다른 기준도 동시에 확인 가능.

| Method | 지표 | 잡는 것 | 놓치는 것 |
|----|----|----|----|
| `"window"` | 다음 `window` 시점 동안 `lr` 의 범위 (max - min) | 국소 안정 (zig-zag 없음) | window 당 `max_drift` 이하로 떨어지는 *느린 단조 drift* |
| `"tail"` (default) | `[k, K_{\max}]` 동안 `lr` 의 범위 | 전역 안정. 단조 drift 잡음 | tail 길이 $`\ge 2`$ 필요. 가장 빠른 통과 시점이 `"window"` 보다 늦음 |
| `"slope"` | $`\|\hat\beta_k\|`$, `lr ~ k` 의 `[k, K_{\max}]` 위 OLS 회귀 기울기 | 체계적 trend (방향성 있음) | 평균이 0 인 oscillation 통과시킴 |
| `"all"` | `"window"` + `"tail"` + `"slope"` 모두 통과 | 위 셋 다 잡음 | (가장 strict) |

모든 method 에서 추가로 코호트 간 분산 조건
`dispersion[i] < max_dispersion` 도 함께 요구한다 — dev $`k`$ 에서의
*증분* 손해율이 코호트 간에 일치해야 함 (이전 패키지 버전과 동일한 강건
$`\hat{D}_v`$ metric).

**왜 paper 의 SE 정규화 기준을 안 쓰는가?**: 이전 버전은 원 논문
(Section 11) 의 $`R_k < c \cdot \hat{SE}^{\mathrm{param}}_k`$ 를
구현했다 (paper 는 $`v`$ 표기, 같은 축). *대규모 portfolio 에서 이
형태는 구조적으로 작동하지 않는다*. $`\hat{SE}^{\mathrm{param}}`$ 은
$`1/\sqrt{n}`$ 으로 줄어드는 반면 $`R_k`$ 는 numerical noise floor
(~$`10^{-3}`$ LR 단위) 가 있어, 비율 $`R_k / \hat{SE}^{\mathrm{param}}`$
가 발산하고 기준이 *절대 발동하지 않는다* — *육안으로 안정* 한 합성
데이터에서도. drift 기반 method 들은 SE 정규화를 데이터 사이즈 독립적인
절대 threshold 로 대체한다.

## 3. 기호

표준 chain ladder 컨벤션: $`i`$ = 코호트 (origin period), $`k`$ = 경과
기간.
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
가 $`k^*`$,
[`detect_convergence()`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md)
가 $`k^{**}`$ 를 반환한다 — 둘 다 같은 $`k`$ 축 위에 있다.

| Code | Math | 의미 |
|----|----|----|
| `dev_max` | $`K_{\max}`$ | 관측 가능한 최대 dev (스칼라) |
| `dev_cand` | $`k \in [k^*, K_{\max}-2]`$ | 후보 dev 정수 벡터 |
| `lr[i]` | $`LR_k`$ | dev = `dev_cand[i]` 에서의 portfolio LR 예측 |
| `revision[i]` | $`R_k = \|LR_k - LR_{k-1}\|`$ | 인접 step 갱신 (진단용) |
| `drift_window[i]` | $`[k, k+W-1]`$ 위 $`\max - \min`$ | 국소 윈도우 범위 |
| `drift_tail[i]` | $`[k, K_{\max}]`$ 위 $`\max - \min`$ | tail 범위 (전역 안정) |
| `slope[i]` | $`\hat\beta_k`$ | $`[k, K_{\max}]`$ 위 OLS 기울기 |
| `dispersion[i]` | $`\hat{D}_k`$ | 코호트 간 증분 LR 의 강건 분산 |
| `mat_k` | $`k^*`$ | 성숙점 (후보 하한) |
| `conv_k` | $`k^{**}`$ | 검출된 수렴점 |

`dispersion` 안의 상수 $`1.4826 \approx 1 / \Phi^{-1}(0.75)`$ 은 표준
MAD$`\to\sigma`$ 보정. 이 스케일링으로 $`\hat{D}_k`$ 는 증분 LR 의 강건
(이상치에 둔감한) 변동계수(CV) 로 읽힌다.

## 4. 기본 사용

``` r

library(lossratio)
data(experience)
tri <- as_triangle(
  experience[coverage == "surgery"],
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  premium  = "incr_prem"
)

res <- detect_convergence(tri)
print(res)
```

모의 출력 (이 데이터에서는 수렴 미검출):

    #> <Convergence>
    #>   method     : tail
    #>   conv_k     : NA
    #>   mat_k      : 4
    #>   dev_max    : 30
    #>   candidates : 25
    #>   passes :
    #>     window :  0/25 (drift_window < 0.01  & dispersion < 0.15)
    #>     tail   :  0/25 (drift_tail   < 0.01  & dispersion < 0.15)  <- method
    #>     slope  :  0/25 (|slope|      < 0.001 & dispersion < 0.15)
    #>     all    :  0/25 (window AND tail AND slope)

`summary(res)` 는 후보 시점별 한 행 + 모든 metric / per-method pass flag
컬럼이 있는 `data.table` 을 반환한다:

``` r

head(summary(res), 6)
```

    #>      dev    lr   revision  drift_window  drift_tail   slope  dispersion
    #>    <int> <num>      <num>         <num>       <num>   <num>       <num>
    #> 1:     4 0.62          NA          0.07        0.07   0.001        0.47
    #> 2:     5 0.63        0.01          0.06        0.06   0.001        0.47
    #> ...
    #>    pass_window  pass_tail  pass_slope  pass
    #>          <lgl>      <lgl>       <lgl> <lgl>
    #> 1:       FALSE      FALSE       FALSE FALSE
    #> 2:       FALSE      FALSE       FALSE FALSE

`Convergence` 객체에는 추가로 threshold 파라미터 (`max_drift`,
`max_slope`, `max_dispersion`, `window`, `holdout_max`, `min_n_cohorts`)
와 메타데이터 속성 (`groups`, `target`, `dispatcher`) 이 포함된다.

## 5. Reserving 주의사항

**검출된 `conv_k` 는 `dev_max` 까지에서 *관찰된* 안정성이지, asymptotic
보장이 아니다.** `dev_max` 이후의 development 는 알 수 없다. `conv_k` 는
*“여기서부터는 우리가 관찰한 한 안정이다”* 라는 진단으로 사용하고,
*“이후에도 예측이 흔들리지 않을 것이다”* 라고 해석하지 말 것.

Reserving 응용 시:

- `method = "tail"` (default) 또는 `"all"` 권장. `"window"` 는 *느린
  단조 drift* 가 window 당 `max_drift` 이하로 내려가면 너무 일찍 수렴
  선언 — 정확히 reserve 에 해로운 silent-revision 패턴.
- **evidence span** `dev_max - conv_k` 도 같이 확인. `conv_k` 가
  `dev_max` 근처 (span $`< 5`$) 면 tail point 가 매우 적어 결정된 거라
  실제로는 약한 증거; 한 diagonal 만 추가돼도 unconverge 가능.
- 예측 손해율의 점추정과 표준오차는 `fit_lr()$summary` 에서 직접 읽기.
  [`detect_convergence()`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md)
  는 *진단 도구* 이지 추정기 자체가 아니다. reserve 의 점추정과
  불확실성은 fit 객체에서 나온다.

## 6. 작동 메커니즘: 다중 holdout refit

`dev_cand[i]` 마다 `holdout = dev_max - dev_cand[i]` 로
[`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
를 돌려 portfolio LR 을 추출한다. 같은 holdout 깊이는 캐싱되므로 인접
후보 간 재계산이 없다.

예시: `dev_max = 30`, `mat_k = 4`, `holdout_max = 13` 일 때 — 후보는
$`k \in \{4, 5, \dots, 28\}`$ (총 25개) 지만
`holdout = dev_max - k <= holdout_max` 인 $`k`$ 만 finite `lr[i]` 값을
받고, 나머지는 `NA` 로 마스킹.

`holdout_max` 기본값은 `max(window, floor((dev_max - mat_k) / 2))`.
키우면 더 이른 시점까지 진단 가능 — 다만 refit 자료가 줄어들어 신뢰도가
떨어진다.

## 7. 시각화

``` r

plot(res)
```

dev 축을 공유하는 5개 패널:

1.  **`lr`** — metric 들이 계산되는 LR 궤적.
2.  **`drift_window`** — 국소 윈도우 metric, 가로 점선 `max_drift`.
3.  **`drift_tail`** — tail metric, 동일 점선.
4.  **`|slope|`** — 가로 점선 `max_slope`.
5.  **`dispersion`** — 가로 점선 `max_dispersion`.

세로 점선 `mat_k`, 세로 실선 `conv_k` (검출됐을 때만). 각 metric
패널에서 *빨간 점선 아래* 의 점이 그 절을 통과한 valuation. 부제목에
활성 `method` 표기. *어느 절이 binding 인지* 한눈에 보임 — threshold
위에 머무는 패널이 그 method 의 수렴을 막는 절.

## 8. 임계값 튜닝

| 인자 | default | 의미 |
|----|----|----|
| `method` | `"tail"` | `conv_k` 를 정의할 안정성 metric. |
| `max_drift` | `0.01` | `drift_window` / `drift_tail` 상한, LR 단위. 노이지하거나 long-tail 인 책은 `0.02`–`0.05` 정도로 키우는 것이 자연. |
| `max_slope` | `1e-3` | $`\|\hat\beta_k\|`$ 상한 (dev 당 LR 변화). |
| `max_dispersion` | `0.15` | 코호트 간 분산 상한. |
| `window` | `5L` | drift window 길이 $`W`$ — `"window"` method 가 `drift_window` 계산 시 스캔하는 연속 valuation 개수. `"tail"` / `"slope"` 에는 영향 없음. |
| `min_n_cohorts` | `5L` | 코호트 수가 이 값 미만이면 `dispersion` 은 `NA`. |

`max_drift` 를 sweep 해서 민감도 확인:

``` r

sapply(
  c(0.005, 0.01, 0.02, 0.05),
  function(d) detect_convergence(tri, method = "tail", max_drift = d)$conv_k
)
```

`max_dispersion` 이 $`\approx 0.05`$ 이하로 떨어지는 경우는 단일 기간
claim 노이즈 때문에 실 portfolio 에서 보기 어렵고, $`0.20`$ 이상이면
코호트 간 진성 이질성을 의심해야 한다 — 이 경우 모형 적합 전에
[`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
으로 그룹을 분리하는 것이 권장된다.

## 9. 성숙점 및 regime 탐지와의 관계

세 진단 도구는 서로 다른 질문을 다른 축에서 답한다:

| 도구 | 질문 | 결과 | 축 |
|----|----|----|----|
| [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md) | 코호트들이 동질적인가? | 코호트 그룹 | 인수 시기 |
| [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md) ($`k^*`$) | link factor 가 재현 가능해지는 시점? | dev 값 | 경과 기간 |
| [`detect_convergence()`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md) ($`k^{**}`$) | LR 추정이 갱신을 멈추는 시점? | dev 값 | 경과 기간 |

권장 워크플로:

1.  [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
    실행. 다중 regime 이 존재하면 그룹별로 분리해서 적합하거나, fit /
    backtest 호출에서
    [`regime_at()`](https://seokhoonj.github.io/lossratio/reference/regime_at.md)
    /
    [`regime_spec()`](https://seokhoonj.github.io/lossratio/reference/regime_spec.md)
    사용.
2.  각 동질 그룹에서
    [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
    로 $`k^*`$ 산출.
3.  [`detect_convergence()`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md)
    로 $`k^{**} \ge k^*`$ 검출. 예측 손해율은 `fit_lr()$summary` 에서
    읽고 위의 reserving 주의사항을 적용.

이 순서는 *코호트 동질성*, *link 재현성*, *level 수렴* 세 속성의 분리를
반영한다 — P&C run-off 에서는 한 점에 모이지만 장기 건강보험에서는 각각
독립적으로 검증해야 한다.

## 10. 한계

[`detect_convergence()`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md)
는 반복적인
[`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
호출 위의 얇은 layer 이며 그 제약을 그대로 상속한다:

- **식별 가능성**: `conv_k` 는 `dev_max - mat_k >= window` (또는 tail /
  slope 의 경우 2) 일 때만 선언 가능. 관측 기간이 짧으면 모든 method 가
  `NA` 반환.
- **모형 조건부**: 예측 LR 은
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)
  로 산출.
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md)
  이 내부적으로
  [`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md)
  (default `method = "sa"` — 단계 적응형) 와
  [`fit_premium()`](https://seokhoonj.github.io/lossratio/reference/fit_premium.md)
  을 합성하므로, 그 안의 선택 (loss method, regime 필터, maturity 인자)
  이 `conv_k` 로 흘러간다. 결과 해석 시 `fit_lr` 설정을 같이 확인할 것.
  `...` 으로 `loss_method =`, `loss_regime =` 등 override 가능.
- **포트폴리오 집계**: portfolio LR 은 그룹별 ultimate 의 익스포저 가중
  (`sum(loss_ult) / sum(premium_ult)`). 달력 연도 충격 (요율 개정,
  의료비 인플레) 은 모든 그룹을 동시에 움직일 수 있고, drift metric 들은
  이를 진짜 수렴과 구별하지 못한다.
- **다중 그룹 triangle**: 현재 구현은 `dispersion` 을 그룹 간 median
  으로 collapse. 그룹이 다르게 움직이면 분리 실행 권장.
- **Asymptotic vs 관측**: reserving 주의사항에서 언급한 대로, 모든
  method 는 *관측 가능한 history* 위에서의 안정만 측정. `dev_max` 이후의
  silent drift 는 이 도구만으로는 검출 불가능.

## 11. 함께 보기

- [`?detect_convergence`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md),
  [`?detect_maturity`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md),
  [`?backtest`](https://seokhoonj.github.io/lossratio/reference/backtest.md),
  [`?detect_regime`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md),
  [`?fit_lr`](https://seokhoonj.github.io/lossratio/reference/fit_lr.md).
- `vignette("regime-detection")` — 위 워크플로 1단계의 코호트 동질성
  진단.
- [`vignette("backtest")`](https://seokhoonj.github.io/lossratio/articles/backtest.md)
  —
  [`detect_convergence()`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md)
  가 그 위에 구축된 rolling holdout 메커니즘.
