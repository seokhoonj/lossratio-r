# Replace CL multiplicative SE with ED additive SE on a CLFit's `$full`

Point projection (`target_proj`) is preserved – it is identical under
both CL and self-weighted ED. Only the variance accumulation differs:

- CL recursion: `proc_{k+1} = f^2 * proc_k + sigma^2 * C_k`
  (multiplicative scaling – prior variance amplified by f^2 each step).

- ED recursion: `proc_{k+1} = proc_k + sigma^2 * C_k` (additive – prior
  variance carried forward unchanged).

Both share the same per-link `sigma^2` and `f_var` (= `Var(f_hat_k)`)
estimates. The recursion is per (group, cohort).

## Usage

``` r
.ed_replace_se(full, selected, triangle)
```

## Arguments

- full:

  The `$full` data.table from a `CLFit` (must contain `cohort`, `dev`,
  `target_obs`, `target_proj`).

- selected:

  The `$selected` data.table (must contain `f_selected`, `sigma2`,
  `f_var`).

- triangle:

  The original `Triangle` (for `groups` attribute).

## Value

Updated `full` data.table with `target_proc_se2`, `target_param_se2`,
`target_total_se2`, `target_proc_se`, `target_param_se`,
`target_total_se`, `target_proc_cv`, `target_param_cv`,
`target_total_cv` columns rebuilt under the ED recursion (column names
match the upstream `fit_cl` worker convention; the dispatcher renames
them to `premium_*` afterwards).
