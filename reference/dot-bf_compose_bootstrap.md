# Per-replicate BF / Cape Cod composition from two BootstrapTriangle

Given paired loss-side and exposure-side `BootstrapTriangle` objects
(with `keep_pseudo = TRUE` so the per-replicate cohort-by-dev cum loss /
cum exposure means are available), compose the BF / Cape Cod ultimate
distribution per replicate:

1.  For each replicate \\b\\, derive \\q_i^b = L\_{obs,i} /
    L\_{ult,i}^{CL,b}\\ from the loss-side Stage 1 mean trajectory
    (last-dev cell).

2.  Derive \\E_i^{ult,b}\\ from the exposure-side Stage 1 mean last-dev
    cell.

3.  For BF: \\L\_{ult,i}^{b} = L\_{obs,i} + (1 - q_i^b) \cdot
    \mathrm{ELR}\_i \cdot E_i^{ult,b}\\.

4.  For Cape Cod: per group \\\widehat{\mathrm{ELR}}^{CC,b} = \sum_i
    L\_{obs,i} / \sum_i E_i^{ult,b} \cdot q_i^b\\, then plug into the BF
    formula.

5.  Cell-level projection per replicate: scale the per-replicate CL
    emergence pattern to land at \\L\_{ult,i}^{b}\\ at the last dev.

Cell-level and cohort-level SE / CI are the SD / quantiles across
replicates.

## Usage

``` r
.bf_compose_bootstrap(
  boots,
  priors,
  groups,
  by_cols,
  full,
  summ,
  conf_level,
  cohorts_present,
  cape_cod = FALSE
)
```

## Arguments

- boots:

  A named list `list(loss = BT, exposure = BT)` from
  [`.resolve_bootstrap_bf()`](https://seokhoonj.github.io/lossratio/reference/dot-resolve_bootstrap_bf.md).

- priors:

  Per-cohort ELR table (see
  [`.resolve_bf_prior()`](https://seokhoonj.github.io/lossratio/reference/dot-resolve_bf_prior.md)).
  Pass `NULL` for the Cape Cod composition (ELR is data-pooled per
  replicate).

- groups:

  Group column character vector.

- by_cols:

  `c(groups, "cohort")`.

- full:

  The point-estimate `$full` data.table (used as the base for join-on
  bootstrap SE / CI columns).

- summ:

  The point-estimate cohort-level summary.

- conf_level:

  Confidence level for CI bounds.

- cohorts_present:

  Unique `[groups, cohort]` rows present in the triangle.

## Value

List `list(full, summary, bootstrap)` where `bootstrap` is the
`BFBootstrap` / `CCBootstrap` helper class.
