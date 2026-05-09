# Convergence: 예측 손해율 수렴 시점 진단

## 1. 동기

[`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
는 *“어느 발전 기간부터 link factor $`f_k`$ 가 코호트 간에 재현
가능해지는가?”* 에 답한다. chain ladder 예측에는 필요하지만,
포트폴리오의 예측 손해율이 수렴했다고 선언하기에는 충분하지 않다 — 장기
건강보험에서 $`f_k \to 1`$ 과 $`g_k \to 0`$ 은 누적 분모가 자라면서
자동으로 발생하는 관성(inertia) 효과이지, 기저 경험이 실제로 수렴했다는
신호가 아니다. 그 위에 세운 기준은 $`k`$ 가 커지기만 하면 자동으로
통과한다.

[`detect_convergence()`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md)
는 **수렴점**(convergence point) $`k^{**}`$ 를 검출한다. $`k^{**}`$ 는
projected loss ratio 가 예측적으로 수렴하는 첫 평가 시점 ($`v \ge k^*`$)
이다.

$`k^{**}`$ 는 성숙점(maturity point) $`k^*`$
([`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
가 산출) 의 자연스러운 짝이다.

- $`k^*`$: link factor $`f_k`$ 가 재현 가능해지는 시점.
- $`k^{**}`$: 모형 출력 자체가 새 데이터에도 거의 움직이지 않는 시점.

장기 건강보험 portfolio 는 $`k^*`$ 를 일찍 지나도 $`k^{**}`$ 에 한참 못
미칠 수 있다.

검출은 $`M`$ 개 연속 평가 시점에서 다음 두 조건이 동시에 만족되는 최초의
$`v`$:

1.  **예측 갱신** 이 자체 파라미터 SE 대비 작음:
    $`R_v < c \cdot \hat{SE}^{\mathrm{param}}_v`$, 여기서
    $`R_v = |\hat{LR}^{\mathrm{proj}}_v(D_v) -
    \hat{LR}^{\mathrm{proj}}_v(D_{v-1})|`$ 는 새 calendar diagonal 한
    개가 추가될 때 portfolio 의 projected LR 이 변하는 크기.
2.  **코호트 간 분산** 이 작음: $`\hat{D}_v < \tau`$, 여기서
    $`\hat{D}_v = 1.4826 \cdot \mathrm{MAD}_i(\hat{lr}_{i,v}) /
    |\mathrm{median}_i(\hat{lr}_{i,v})|`$ 는 발전 기간 $`v`$ 에서 코호트
    간 *증분* 손해율의 강건 분산.

$`\hat{D}_v`$ 를 누적이 아닌 **증분** 손해율로 정의해 관성에서 자유롭다
— 기간별 값이라 누적 분모가 커져도 자동으로 감쇠되지 않는다. 두 절은
서로 다른 실패 양상을 막는다: $`R_v`$ 는 *모형 출력* 이 갱신을 멈췄는지,
$`\hat{D}_v`$ 는 *기간별 경험* 이 코호트 간에 일관되는지를 검사한다. 한
쪽만 봐서는 속을 수 있다 — chain ladder 의 기계적 $`\hat{f}_k \to 1`$
표류는 실제 수렴과 무관하게 $`R_v`$ 를 무너뜨릴 수 있고, 단일 기간의
코호트 간 일치만으로는 예측 수렴을 보장하지 않는다. 두 조건을 함께
적용해야 두 가지 관성 누출 경로를 동시에 막을 수 있다.

## 2. 왜 두 조건이 필요한가

**분모효과 (denominator effect)** 가 단일 진단을 무력화하기 때문이다.

장기 건강보험에서 누적 LR = 누적 손해 / 누적 위험보험료. dev 가 커지면
분모도 같이 커지므로, 새 calendar diagonal 한 개의 영향이 전체 비율에서
자동으로 작아진다 — **실제 경험 변화와 무관하게**. 이를 *관성* 효과라
부른다.

각 조건이 막는 함정:

| 시나리오 | $`R_v`$ | $`\hat{D}_v`$ | 결과 |
|----|----|----|----|
| 진짜 수렴 (모형·경험 모두 안정) | 작음 | 작음 | **PASS** ✓ |
| chain ladder $`\hat{f}_k \to 1`$ 표류 (관성) | 작음 (위장) | 큼 | FAIL — 분산이 잡아냄 |
| 단일 시점 코호트 우연 일치 | 큼 | 작음 (snapshot) | FAIL — projection 변화가 잡아냄 |

- $`R_v`$ 단독은 chain ladder 의 mechanical drift ($`\hat{f}_k \to 1`$)
  가 누적 곱을 거의 정지시켜 false convergence 를 부를 수 있다.
- $`\hat{D}_v`$ 는 **증분** LR 을 사용하므로 누적 분모의 영향이 없다 →
  분모효과 자체에서 면역.
- 두 조건을 동시에 강제하면 분모효과로 인한 false PASS 의 주요 경로가
  모두 닫힌다. 이것이 dual criterion 의 핵심 설계 의도.

## 3. 기호

| 기호 | 의미 |
|----|----|
| $`i`$ | 코호트 인덱스 (UY) |
| $`v`$ | 평가 시점 인덱스 — calendar diagonal. “$`v`$ 번째 대각선까지 관측됨” |
| $`V`$ | 관측 가능한 최대 평가 시점 (triangle 의 max dev) |
| $`k^*`$ | 성숙점 ([`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md) 산출). 후보 $`v`$ 의 하한 |
| $`k^{**}`$ | 수렴점. [`detect_convergence()`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md) 가 반환하는 값 |
| $`\hat{LR}^{\mathrm{proj}}_v`$ | 평가 시점 $`v`$ 까지의 자료로 산출한 ultimate LR 예측 |
| $`R_v`$ | 갱신 (revision): $`\lvert\hat{LR}^{\mathrm{proj}}_v - \hat{LR}^{\mathrm{proj}}_{v-1}\rvert`$ |
| $`\hat{SE}^{\mathrm{param}}_v`$ | $`\hat{LR}^{\mathrm{proj}}_v`$ 의 파라미터 불확실성 SE (Mack-style) |
| $`\hat{lr}_{i,v}`$ | 코호트 $`i`$ 의 발전 기간 $`v`$ 에서의 증분 손해율 |
| $`\hat{D}_v`$ | 코호트 간 $`\hat{lr}_{i,v}`$ 의 강건 척도불변 분산 |
| $`c`$ | $`\hat{SE}^{\mathrm{param}}_v`$ 에 거는 배율, 갱신 절 임계 (default: `0.5`) |
| $`\tau`$ | $`\hat{D}_v`$ 상한, 분산 절 임계 (default: `0.15`) |
| $`M`$ | 두 절이 동시 만족해야 하는 연속 평가 시점 개수 (default: `3L`) |

$`\hat{D}_v`$ 안의 상수 $`1.4826 \approx 1 / \Phi^{-1}(0.75)`$ 은 표준
MAD$`\to\sigma`$ 보정 계수다. 이 스케일링으로 $`\mathrm{MAD}_i`$ 는 정규
가정 하에서 코호트 간 표준편차의 일치 추정량이 되며, 따라서
$`\hat{D}_v`$ 는 증분 손해율의 강건한 (이상치에 둔감한) 변동계수(CV) 로
읽힌다.

## 4. 기본 사용

``` r

library(lossratio)
data(experience)
exp <- as_experience(experience)
tri <- build_triangle(exp[coverage == "SUR"], coverage)

res <- detect_convergence(tri)
print(res)
```

모의 출력:

    #> <Convergence>
    #> k_conv       : NA
    #> k_star       : 9
    #> V (max dev)  : 30
    #> criterion    : R_v < 0.5 * SE_param_v  AND  D_v < 0.15  (run M = 3)
    #> fit_fn       : fit_lr
    #> v candidates : 19 ( 0  pass both clauses)

`Convergence` 객체의 주요 필드:

- `k_conv` — 검출된 $`k^{**}`$. 조건이 $`M`$ 개 연속 만족되는 시점이
  없으면 `NA`.
- `k_star` — 하한으로 사용된 성숙점. 함수 내부에서 lr 기반 ATA 에
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
  를 적용해 산출하거나, 호출 시 직접 전달할 수 있다.
- `V` — triangle 에서 관측 가능한 최대 발전 기간.
- `v`, `R_v`, `SE_param_v`, `D_v`, `pass_v` — 후보 평가 시점별 진단
  시퀀스.
- `se_mult`, `max_dv`, `min_run`, `holdout_max`, `min_n_cohorts` —
  사용된 설정값.
- attribute: `group_var`, `loss_var`, `fit_fn_name`, `dev_var`.

`summary(res)` 는 후보 시점별 한 행 + `R_over_SE = R_v / SE_param_v`
컬럼이 있는 `data.table` 을 반환한다:

``` r

head(summary(res), 6)
```

    #>        v    R_v   SE_param_v  R_over_SE   D_v     pass
    #> 1:     9     NA           NA         NA  0.90   FALSE
    #> 2:    10     NA           NA         NA  0.76   FALSE
    #> 3:    11     NA           NA         NA  0.56   FALSE
    #> 4:    12     NA           NA         NA  0.58   FALSE
    #> 5:    13     NA           NA         NA  0.81   FALSE
    #> 6:    14     NA           NA         NA  0.43   FALSE

## 5. 작동 메커니즘: 다중 holdout refit

[`detect_convergence()`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md)
는 candidate 평가 시점마다 모형을 다시 적합하면서 projection 의 변화를
추적한다.

예시: $`V = 30`$, $`k^* = 18`$, `holdout_max = 6` 일 때 — candidate 는
$`v \in \{24, 25, \dots, 30\}`$ (총 7개).

| $`v`$       | holdout 깊이 ($`V - v`$) | `R_v` 가능? |
|-------------|--------------------------|-------------|
| 30          | 0                        | ✓           |
| 28          | 2                        | ✓           |
| 24 (cutoff) | 6                        | ✓           |
| 22          | 8                        | `NA`        |
| 18          | 12                       | `NA`        |

각 $`v`$ 마다 한 번 refit (총 7번) + 인접 $`v`$ 간 $`R_v`$ 계산.
`holdout_max` 가 결정하는 cutoff 는 기본값으로 `floor((V - k_star) / 2)`
이며, holdout 깊이가 그 값을 넘으면 refit 자료가 너무 적어 `R_v` 와
`SE_param_v` 를 `NA` 로 마스킹한다.

`holdout_max` 를 키우면 더 이른 시점까지 진단 가능 — 다만 refit 자료가
줄어들어 신뢰도가 떨어진다.

## 6. 시각화

``` r

plot(res)
```

진단은 위아래 두 패널: 위 패널은 $`R_v / \hat{SE}^{\mathrm{param}}_v`$
대 $`v`$ 와 임계값 $`c`$ 의 가로 점선; 아래 패널은 $`\hat{D}_v`$ 대
$`v`$ 와 임계값 $`\tau`$ 의 가로 점선. $`k^*`$ 는 세로 점선, $`k^{**}`$
이 검출되면 세로 실선. **두 점선 모두 아래에 있는 점** 이 양 절을 통과한
valuation.

이 view 는 *어느 절이 binding 인지* 한눈에 보여준다. 위 패널이 임계값에
근접하지만 아래가 멀면 코호트 간 이질성이 문제, 아래가 멀쩡한데 위가
높으면 모형이 여전히 갱신 중이라는 뜻.

## 7. 임계값 튜닝

기본값은 의도적으로 보수적:

| 인자            | default | 의미                                              |
|-----------------|---------|---------------------------------------------------|
| `se_mult`       | `0.5`   | 갱신 크기가 파라미터 SE 의 절반 이하.             |
| `max_dv`        | `0.15`  | 코호트 간 분산이 median lr 의 15% 이하.           |
| `min_run`       | `3L`    | 두 절이 최소 3 개 연속 시점에서 동시 만족.        |
| `min_n_cohorts` | `5L`    | 코호트 수가 이 값 미만이면 $`\hat{D}_v`$ 는 `NA`. |

임계값을 조이면 $`k^{**}`$ 이 늦어지거나 NA 가 된다. 민감도는 sweep 으로
확인:

``` r

sapply(
  c(0.25, 0.5, 0.75, 1.0),
  function(cc) detect_convergence(tri, se_mult = cc)$k_conv
)
```

$`\hat{D}_v`$ 가 $`\tau \approx 0.05`$ 이하로 떨어지는 경우는 단일 기간
청구 노이즈 때문에 실 portfolio 에서 보기 어렵고, $`0.20`$ 이상이면
코호트 간 진성 이질성을 의심해야 한다 — 이 경우 모형 적합 전에
[`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
으로 그룹을 분리하는 것이 권장된다.

## 8. 성숙점 및 regime 탐지와의 관계

세 진단 도구는 서로 다른 질문을 다른 축에서 답한다:

| 도구 | 질문 | 결과 | 축 |
|----|----|----|----|
| [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md) | 코호트들이 동질적인가? | 코호트 그룹 | 인수 시기 |
| [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md) ($`k^*`$) | link factor 가 재현 가능해지는 시점? | dev 값 | 발전 기간 |
| [`detect_convergence()`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md) ($`k^{**}`$) | LR 추정이 갱신을 멈추는 시점? | dev 값 | 발전 기간 |

권장 워크플로:

1.  [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
    실행. 다중 레짐이 존재하면 그룹별로 분리해서 적합.
2.  각 동질 그룹에서
    [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
    로 $`k^*`$ 산출.
3.  [`detect_convergence()`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md)
    로 $`k^{**} \ge k^*`$ 검출. 수렴 영역의 예측 손해율 $`\hat{lr}`$ 은
    $`k \ge k^{**}`$ 에서의 평균 또는 `fit_lr()$summary` 의 ultimate 값.

이 순서는 *코호트 동질성*, *link 재현성*, *level 수렴* 세 속성의 분리를
반영한다 — P&C run-off 에서는 한 점에 모이지만 장기 건강보험에서는 각각
독립적으로 검증해야 한다.

## 9. 한계

[`detect_convergence()`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md)
는 반복적인
[`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
호출 위의 얇은 layer 이며 그 제약을 그대로 상속한다:

- **식별 가능성**: $`k^{**}`$ 는 $`V \ge k^* + M`$ 일 때만 선언 가능.
  관측 기간이 짧으면 `NA` 반환.
- **모형 조건부**: $`\hat{LR}^{\mathrm{proj}}_v`$ 는 `fit_fn` (default:
  `fit_lr`) 으로 산출. fitter 가 다르면 $`k^{**}`$ 도 달라짐. robustness
  를 위해 여러 `fit_fn` 하에서 결과 비교 권장.
- **포트폴리오 집계**: $`R_v`$ 와 $`\hat{SE}^{\mathrm{param}}_v`$ 는
  코호트 간 독립 가정 하에 익스포저 가중 집계. 달력 연도 충격 (요율
  개정, 의료비 인플레) 은 이 가정을 위배하며, 이 경우 두 절이 비코호트
  사유로 동시에 움직일 수 있음.
- **다중 그룹 triangle**: 현재 구현은 그룹 간 $`\hat{D}_v`$ 를 median
  으로 collapse. 그룹이 다르게 움직이면 분리 실행 권장.

## 10. 함께 보기

- [`?detect_convergence`](https://seokhoonj.github.io/lossratio/reference/detect_convergence.md),
  [`?detect_maturity`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md),
  [`?backtest`](https://seokhoonj.github.io/lossratio/reference/backtest.md),
  [`?detect_regime`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md).
- `regime-detection-ko` 문서 — 위 워크플로 1단계의 코호트 동질성 진단.
