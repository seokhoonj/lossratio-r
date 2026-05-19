# Apply the ED additive variance recursion to a CL worker's `$full`

Point projection (`loss_proj`) is preserved – it is identical under both
CL and self-weighted ED. Only the variance accumulation differs:

- CL recursion: `proc_{k+1} = f^2 * proc_k + sigma^2 * C_k`
  (multiplicative scaling – prior variance amplified by f^2 each step).

- ED recursion: `proc_{k+1} = proc_k + sigma^2 * C_k` (additive – prior
  variance carried forward unchanged).

Both share the same per-link `sigma^2` and `f_var` (= `Var(f_hat_k)`)
estimates. The recursion is per (group, cohort).

## Usage

``` r
.apply_ed_variance(full, selected, triangle)
```

## Arguments

- full:

  The `$full` data.table from a `CLFit` (must contain `cohort`, `dev`,
  `loss_obs`, `loss_proj`).

- selected:

  The `$selected` data.table (must contain `f_sel`, `sigma2`, `f_var`).

- triangle:

  The original `Triangle` (for `groups` attribute).

## Value

Updated `full` data.table with `loss_proc_se2`, `loss_param_se2`,
`loss_total_se2`, `loss_proc_se`, `loss_param_se`, `loss_total_se`,
`loss_proc_cv`, `loss_param_cv`, `loss_total_cv` columns rebuilt under
the ED recursion (column names match the upstream `fit_cl` worker
convention; the dispatcher renames them to `exposure_*` afterwards).
