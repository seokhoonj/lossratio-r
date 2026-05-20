# Overlay bootstrap summary statistics onto a fit's `$full` grid

The shared core of every bootstrap-CI path
([`.lossfit_bootstrap()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-lossfit_bootstrap.md),
[`.exposurefit_bootstrap()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-exposurefit_bootstrap.md),
and the in-worker
[`fit_sa()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_sa.md)
/
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_ratio.md)
blocks). Given an already-resolved bootstrap result, it renames the
[`bootstrap()`](https://seokhoonj.github.io/lossratio/ko/reference/bootstrap.md)
summary columns to the caller's `<role>_*` schema, joins them onto
`full` by `(groups, cohort, dev)`, and – on projected cells only –
overlays the bootstrap SE / CV (and quantile CI when present) over the
analytical values.

Observed cells keep their analytical SE: the upper-triangle perturbation
is a parameter-uncertainty tool, not a claim about observed-cell
variability.

## Usage

``` r
.apply_bootstrap_overlay(full, boots, role, groups, se_cols)
```

## Arguments

- full:

  The fit's `$full` `data.table`.

- boots:

  A non-`NULL` resolved bootstrap result; `boots$summary` carries
  `mean_proj`, `param_se`, `proc_se`, `total_se`, `total_cv`, and
  optionally `ci_lo` / `ci_hi`.

- role:

  Column-name prefix, `"loss"` or `"exposure"`.

- groups:

  Group columns; the join key is `c(groups, "cohort", "dev")`.

- se_cols:

  Statistic suffixes to overlay – e.g.
  `c("param_se", "proc_se", "total_se", "total_cv")` for loss,
  `c("total_se", "total_cv")` for exposure. The point projection is
  never overlaid; it stays analytical.

## Value

`full` with the bootstrap values overlaid and the temporary `_boot`
columns dropped.
