# Analytical BF / Cape Cod prediction error (Mack 2008 decomposition)

Closed-form mean squared error of prediction for the per-cohort BF /
Cape Cod ultimate, following the decomposition of Mack (2008, "The
Prediction Error of Bornhuetter/Ferguson", ASTIN Bulletin 38(1), Section
5):

\$\$\mathrm{msep}(R_i) = \mathrm{proc}\_i + (\hat U_i^2 +
\mathrm{Var}(\hat U_i))\\\mathrm{Var}(q_i) + \mathrm{Var}(\hat
U_i)\\(1 - q_i)^2\$\$

where the three terms are the process error, the development-pattern
estimation error, and the prior estimation error. The point estimate is
unchanged – only the variance is added (the "framework borrowed"
approach: Mack's three-term structure with the variances sourced from
`lossratio`'s own fits).

Variance inputs:

- \\\mathrm{Var}(\hat U_i)\\ – the prior ultimate \\\hat U_i =
  \mathrm{ELR}\_i \cdot E^{ult}\_i\\ is a product of two independent
  factors, so \\\mathrm{Var}(\hat U_i) =
  (E^{ult}\_i)^2\\\mathrm{Var}(\mathrm{ELR}\_i) +
  \mathrm{ELR}\_i^2\\\mathrm{Var}(E^{ult}\_i) +
  \mathrm{Var}(\mathrm{ELR}\_i)\\\mathrm{Var}(E^{ult}\_i)\\. `Var(ELR)`
  comes from the distribution prior's `elr_se` (0 for a deterministic
  prior); `Var(E_ult)` from the premium fit SE.

- \\\mathrm{Var}(q_i)\\ – delta method on \\q_i = L^{obs}\_i /
  L^{ult,CL}\_i\\, using the CL parameter SE.

- process – the CL process variance scaled by the BF / CL reserve ratio
  (process noise is taken proportional to the projected future-loss
  volume).

## Usage

``` r
.bf_analytical_se(per_cohort, by_cols, conf_level)
```

## Arguments

- per_cohort:

  A `data.table` with one row per cohort carrying `by_cols`, `q`,
  `loss_ult` (BF / CC ultimate), `loss_latest`, `reserve`, `elr`,
  `premium_ult`, `var_elr`, `var_eult`, `loss_ult_cl`, `loss_proc_se`,
  `loss_param_se`.

- by_cols:

  `c(groups, "cohort")`.

- conf_level:

  Confidence level for the normal CI bounds.

## Value

A `data.table` with columns
`by_cols + c("loss_total_se", "loss_total_cv", "loss_ci_lo", "loss_ci_hi")`.
