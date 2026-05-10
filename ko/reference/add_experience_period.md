# Add standard period variables to an experience dataset

Add underwriting, calendar, and development period variables to an
experience dataset using standard column conventions for loss ratio
analysis.

The function detects the presence of key source columns such as `uy_m`,
`cy_m`, and `dev_m`, and derives additional period variables when
possible.

## Usage

``` r
add_experience_period(df)
```

## Arguments

- df:

  A data.frame containing period variables such as `uy_m`, `cy_m`, and
  `dev_m`.

## Value

A data.frame (or tibble/data.table depending on input) with additional
period variables.

## Details

The following variables are added when the required source columns
exist:

**Underwriting period (from `uy_m`):**

- `uy_a` : underwriting year

- `uy_s` : underwriting half-year

- `uy_q` : underwriting quarter

**Calendar period (from `cy_m`):**

- `cy_a` : calendar year

- `cy_s` : calendar half-year

- `cy_q` : calendar quarter

**Development period:**

- `dev_a` is derived from `dev_m` as yearly development index, where
  months 1 to 12 map to 1, 13 to 24 map to 2, and so on.

- `dev_s` is derived from `uy_m` and `cy_m` using calendar half-year
  boundaries. For example, contracts issued in January to June are
  aligned to the same first development half-year block, and the next
  calendar half-year becomes development half-year 2.

- `dev_q` is derived from `uy_m` and `cy_m` using calendar quarter
  boundaries. For example, contracts issued in January to March are
  aligned to the same first development quarter block, and the next
  calendar quarter becomes development quarter 2.

Therefore, `dev_s` and `dev_q` are not simple grouped versions of
`dev_m`; they are aligned to calendar half-year and quarter boundaries
so that underwriting cohorts such as Q1, Q2, H1, and H2 are compared
consistently on the same cumulative development basis.

Newly created columns are inserted before their corresponding base
columns.

## Examples

``` r
if (FALSE) { # \dontrun{
df <- data.frame(
  uy_m  = as.Date("2023-01-01") + 0:5 * 30,
  cy_m  = as.Date("2023-01-01") + 0:5 * 30,
  dev_m = 1:6
)

df2 <- add_experience_period(df)
head(df2)
} # }
```
