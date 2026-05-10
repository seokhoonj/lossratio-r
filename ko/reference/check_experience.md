# Check an experience dataset

Check that an experience dataset contains the required columns with the
expected classes, and validate the classes of optional columns when
present.

## Usage

``` r
check_experience(df)
```

## Arguments

- df:

  A data.frame containing experience data.

## Value

Invisibly returns the result of
[`.check_col_spec()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-check_col_spec.md).

## Required columns

These columns must be present:

- `cy_m` : Calendar year-month (`Date`)

- `uy_m` : Underwriting year-month (`Date`)

- `loss_incr` : Per-period loss amount (`numeric`)

- `premium_incr` : Per-period premium (`numeric`); for long-term health
  insurance, risk premium is commonly used

## Optional columns

These columns are validated only when present:

- `dev_m` : Development month (`integer`)

- `pd_tp_cd`, `pd_tp_nm`, `pd_cd`, `pd_nm`: Product type/product codes
  and names (`character`)

- `cv_tp_cd`, `cv_tp_nm`, `cv_cd`, `coverage`: Coverage type/coverage
  codes and names (`character`)

- `rd_tp_cd`, `rd_tp_nm`, `rd_cd`, `rd_nm`: Rider type/rider codes and
  names (`character`)

- `age_band` : Age band (`ordered`)

- `gender` : Gender (`factor`)

- `ch_cd`, `ch_nm` : Channel code and name (`character`)

- `n_policy` : Number of unique policies in the cell (`integer`)

## Derived columns

The following columns may be derived later by
[`add_experience_period()`](https://seokhoonj.github.io/lossratio/ko/reference/add_experience_period.md)
and are not validated here:

- `uy_a`, `uy_s`, `uy_q` : Underwriting year, half-year, quarter

- `cy_a`, `cy_s`, `cy_q` : Calendar year, half-year, quarter

- `dev_a`, `dev_s`, `dev_q` : Development year, half-year, quarter

## See also

[`as_experience()`](https://seokhoonj.github.io/lossratio/ko/reference/as_experience.md),
[`add_experience_period()`](https://seokhoonj.github.io/lossratio/ko/reference/add_experience_period.md),
[`.check_col_spec()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-check_col_spec.md)
