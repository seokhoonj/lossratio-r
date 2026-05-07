# Maturity: ATA 인자가 안정화되는 dev 시점 탐지

> 영어 원본 보기: [Maturity: detecting when ATA factors stabilise across
> cohorts](https://seokhoonj.github.io/lossratio/ko/maturity.md)

성숙점(maturity point) 은 **ATA 인자**(age-to-age factor) 가 chain
ladder 추정에 신뢰할 만큼 안정화되는 경과 기간 링크이다.
`fit_lr(method = "sa")` 가 ED 에서 CL 로 전환할 때 내부적으로 사용한다.
탐지를 구동하는 인자 진단 통계는
[`vignette("triangle-and-link")`](https://seokhoonj.github.io/lossratio/ko/articles/triangle-and-link.md)
에서 다루며, 이 문서는
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
자체에 집중한다.

## 1. 셋업

이 문서는 간결성을 위해 `SUR` 그룹만 사용한다 — 모든 절차는 다중 그룹
입력에도 그대로 일반화된다.

``` r

library(lossratio)
data(experience)
exp <- as_experience(experience)[cv_nm == "SUR"]
tri <- build_triangle(exp, group_var = cv_nm)
```

## 2. 성숙점 탐지

[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
는 `Triangle` 을 직접 입력으로 받는다 — 내부에서 단일 변수 `Link` 와 그
WLS 요약을 자동으로 빌드한다.

``` r

mat <- detect_maturity(
  tri,
  value_var       = "closs",
  cv_threshold    = 0.10,    # CV 가 이 값보다 작아야 함
  rse_threshold   = 0.05,    # RSE 가 이 값보다 작아야 함
  min_valid_ratio = 0.5,     # 해당 링크에서 유한 코호트가 50% 이상
  min_n_valid     = 3L,      # 유한 코호트가 최소 3개
  min_run         = 1L       # 연속 성숙 링크 최소 1개
)

print(mat)
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

그룹별로 모든 임계값을 만족하는 첫 경과 기간 링크 한 행이 출력되며, 해당
링크의 전체 통계가 같이 실린다. 임계값 인자들은 반환된 `Maturity` 객체의
attribute 로도 저장된다.

## 3. 임계값의 의미

- `cv_threshold` — 해당 링크에서 관측된 ATA 인자의 변동계수. `alpha` 와
  무관하게 상대 산포를 제한한다.
- `rse_threshold` — WLS 추정 인자 `f` 의 상대 표준오차. 잔차 산포가
  아니라 파라미터 불확실성을 포착한다.
- `min_valid_ratio` — 해당 링크에서 유한 ATA 를 갖는 코호트의 최소 비율.
  대부분이 0 / NA / Inf 인 링크를 막는다.
- `min_n_valid` — 해당 링크에서 유한 코호트의 최소 개수. 데이터가 얇은
  꼬리 영역의 절대 하한.
- `min_run` — *연속* 성숙 링크의 최소 개수. `min_run = 1L` (default)
  이면 조건을 만족하는 첫 링크가 채택되고, `2L` 이상으로 두면 지속적인
  안정성을 요구한다.

포트폴리오의 변동성 프로파일에 맞춰 조정한다. 임계값을 빡빡하게 (예:
`cv_threshold = 0.05`) 잡으면 성숙점이 뒤로 밀리고, 느슨하게 잡으면
앞으로 당겨진다.

## 4. 적합 함수에서의 사용

[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
는 `maturity_args` 가 주어진 경우
[`fit_ata()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ata.md)
와
[`fit_cl()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_cl.md)
내부에서도 호출된다 (내부
[`summary()`](https://rdrr.io/r/base/summary.html) 단계의 `alpha` 는
호출자의 값을 그대로 받는다).

``` r

fit_ata(tri, value_var = "closs",
        maturity_args = list(cv_threshold = 0.08, min_run = 2L))

fit_cl(tri, value_var = "closs",
       maturity_args = list(cv_threshold = 0.08))

fit_lr(tri, method = "sa",
       maturity_args = list(cv_threshold = 0.08))
```

`fit_lr(method = "sa")` 에서는 탐지된 성숙점이 ED (초기 dev) 에서 CL
(이후 dev) 로 전환되는 dev 를 결정한다.

## 5. 그룹별 출력

다중 그룹 triangle 의 경우
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
는 그룹별로 한 행씩 반환한다.

``` r

tri_all <- build_triangle(as_experience(experience), group_var = cv_nm)
detect_maturity(tri_all, value_var = "closs")
```

각 그룹은 동일한 임계값 하에서 독립적으로 탐지된다.

## 6. 함께 보기

- [`vignette("triangle-and-link")`](https://seokhoonj.github.io/lossratio/ko/articles/triangle-and-link.md)
  — `Triangle` / `Link` 데이터 구조와
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
  가 사용하는 링크별 통계.
- [`vignette("projection")`](https://seokhoonj.github.io/lossratio/ko/articles/projection.md)
  — 성숙점이 `fit_lr(method = "sa")` 에서 어떻게 활용되는지.
- [`?detect_maturity`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
  — 인자 전체 레퍼런스.
