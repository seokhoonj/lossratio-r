# Bootstrap a Triangle

Generate `B` alternative realizations of a `Triangle` via nonparametric
(England-Verrall residual) or parametric (Mack normal closed-form) Stage
1 perturbation. The output is a model-agnostic `BootstrapTriangle`
object that downstream fit functions (`fit_cl` / `fit_ed` / `fit_ratio`)
consume to recover parameter and process risk decomposition.

This entry point sits at the Triangle level – it knows nothing about CL,
ED, or SA. Each fit method later refits its own model on every alt
triangle and adds Stage 2 process noise using its own variance recipe.
The same bootstrap object is therefore reusable across all fit methods.

Bootstrap proceeds in two conceptual stages (see `dev/BOOTSTRAP.md`):

1.  **Stage 1 – parameter uncertainty**: residual resample (or
    parametric Normal draw) propagated through the cumulative loss
    chain, refitted factors per replicate. This produces `B` alternative
    *mean* predictions per cell.

2.  **Stage 2 – process uncertainty**: added *inside the fit function*
    on demand, using the method-specific `sigma^2`. The `process`
    argument here is stored as metadata so the consuming fit method
    knows which distribution to use.

## Usage

``` r
bootstrap(x, ...)

# S3 method for class 'Triangle'
bootstrap(
  x,
  type = c("parametric", "nonparametric", "analytical"),
  residual = c("cell", "link"),
  hat_adj = TRUE,
  demean = TRUE,
  process = c("gamma", "od_pois", "normal", "lognormal"),
  method = c("ed", "cl", "sa"),
  pooling = c("pooled", "separated", "tail_pooled"),
  tail = c("auto", "maturity"),
  min_pool = 5L,
  maturity = NULL,
  target = c("loss", "premium"),
  B = 499L,
  seed = NULL,
  alpha = 1,
  quantile_ci = FALSE,
  keep_pseudo = FALSE,
  ...
)
```

## Arguments

- x:

  A `Triangle` object.

- ...:

  Reserved for future use.

- type:

  One of `"parametric"` (default), `"nonparametric"`, or `"analytical"`.
  `"analytical"` draws new link factors from
  `N(f_hat, sqrt(Var(f_hat)))` (Mack 1993 closed-form propagation; CL
  only). `"nonparametric"` resamples standardized residuals and
  reconstructs the pseudo triangle (England-Verrall / Pinheiro).
  `"parametric"` draws each active cell directly from
  `ProcessDist(mu_hat, phi)` and refits on the synthetic triangle
  (textbook England-Verrall 1999 parametric bootstrap; supports all
  three methods cl / ed / sa). When `type` is left unset, the function
  picks the type that best matches `method`: `cl` defaults to
  `"analytical"` (fastest), and `ed` / `sa` default to `"parametric"`
  (cleanest for their additive / stage-adaptive variance decomposition).

- residual:

  Residual scope for `type = "nonparametric"`. One of `"cell"` (default
  – England-Verrall 1999/2002, Pearson residuals on incremental cells;
  ODP GLM equivalent via Renshaw-Verrall 1998) or `"link"` (Mack 1993 /
  Pinheiro 2003, Pearson residuals on link factors).

- hat_adj:

  Logical. Hat-matrix leverage adjustment (`r_h = r / sqrt(1 - h_ii)`)
  for the cell residual path. Default `TRUE` (England-Verrall 2002
  Addendum); set `FALSE` to use the simpler degrees-of-freedom factor
  `sqrt(n / (n - p))` (England-Verrall 1999). Only defined for
  `residual = "cell"`; warned-ignored otherwise. Note that `hat_adj`
  drops corner cells where `h_ii = 1` (always `(I, 1)` and `(1, J)` of
  the upper triangle); on small triangles this can be a meaningful pool
  reduction – set `FALSE` if that matters.

- demean:

  Logical. Subtract the per-group residual mean from each residual in
  the cell-residual pool before resampling (`de-` + `mean`: remove the
  mean, leaving a zero-mean pool). Default `TRUE`. Shapland (2010,
  Sec.4.2) discusses this as one option among others – see the
  *Bootstrap SE decomposition* vignette for the trade-off. Only defined
  for `residual = "cell"`; warned-ignored otherwise.

- process:

  One of `"gamma"`, `"od_pois"`, `"normal"`, `"lognormal"`. Stored as
  metadata; downstream fit functions read this to choose the Stage 2
  noise distribution. `"gamma"` is the default for non-negative
  right-skewed loss data. `"lognormal"` is reserved for Phase 5b.3 and
  currently errors.

- method:

  Fit-model paradigm whose lower-triangle forward projection the
  bootstrap should produce. One of `"ed"` (default – exposure-driven
  additive recursion across all dev; Phase 1 keeps premium fixed,
  projected once via CL), `"cl"` (chain-ladder multiplicative recursion
  across all dev), `"sa"` (stage-adaptive – ED before maturity, CL
  after; currently routes through the CL kernel pending Phase 4 SA
  bootstrap). Mirrors the `method` argument of
  [`fit_loss()`](https://seokhoonj.github.io/lossratio-r/reference/fit_loss.md);
  the resulting `BootstrapTriangle` is consumed by the corresponding
  `fit_*(..., bootstrap = bt)` branch. `"ed"` requires
  `residual = "cell"`; ED + `residual = "link"` is not implemented.

- pooling:

  Residual-pool grouping. One of `"pooled"`, `"separated"`,
  `"tail_pooled"`. `"pooled"` shares residuals across all links;
  `"separated"` keeps each development link independent (Mack-faithful);
  `"tail_pooled"` uses per-link pools before a cut and a single pooled
  bucket after.

- tail:

  Tail-cut rule for `pooling = "tail_pooled"`. One of `"auto"` (cut at
  the smallest `ata_to` whose residual count drops below `min_pool`) or
  `"maturity"` (cut at the resolved `Maturity` change point).

- min_pool:

  Minimum residual count per per-link pool under
  `pooling = "tail_pooled" && tail = "auto"`. Default `5`.

- maturity:

  Required only when `pooling = "tail_pooled" && tail = "maturity"`.
  Four-type dispatch: `NULL`, a `Maturity` object, the string `"auto"`,
  or a function `function(tri) -> Maturity`.

- target:

  Cumulative metric to perturb. One of `"loss"` (default) or
  `"premium"`. The value column in `$pseudo_triangles` is named after
  this target so downstream refit helpers know which column to read.

- B:

  Number of bootstrap replicates. Default `499` – the Davison &
  Hinkley (1997) convention picks `B` so that `(B + 1) p` is an integer
  for the target quantile `p`. With `B = 499` (so `B + 1 = 500`), every
  one-sided VaR commonly reported in reserving –
  `p = 0.50, 0.75, 0.90, 0.95, 0.99` – lands on an exact integer ordinal
  index, so the empirical CI is exact without interpolation. For
  Solvency II / K-ICS 99.5% TVaR reporting pass `B = 1999`; for the
  gold-standard published convention pass `B = 999`.

- seed:

  Optional integer seed for reproducibility.

- alpha:

  Variance exponent in Mack's
  `Var(C_{k+1} | C_k) = sigma_k^2 C_k^alpha`. Default `1`
  (volume-weighted).

- quantile_ci:

  Logical. Opt-in flag for the empirical percentile CI columns (`ci_lo`
  / `ci_hi` = 2.5% / 97.5% quantiles of `loss_sampled` across
  replicates, Davison & Hinkley (1997) type=1 ordinal) in the `$summary`
  slot. Default `FALSE`. The Normal- approximation CI
  (`mean_proj +/- 1.96 * total_se`) derivable from `total_se` is usually
  enough for interactive use; set `TRUE` for Solvency II / K-ICS VaR
  reporting where you need the empirical tail. The C kernel computes
  both CI bounds in the same pass as the SE decomposition (per-cell
  qsort dominated by Stage 1 work), so the marginal cost over `FALSE` is
  small.

- keep_pseudo:

  Logical. Whether to materialise the per-replicate long-format
  `pseudo_triangles` slot. Default `FALSE` (changed from `TRUE` in v0.x
  for performance). `TRUE` builds the long-format data.table for
  diagnostic inspection (e.g. raw replicate trajectories, custom
  quantile work). On a typical 4-group monthly triangle at `B = 999` the
  reshape costs ~250-300 ms and ~200 MB on top of `$summary`; users who
  only consume `$summary` (the common case) should leave this `FALSE`.
  [`fit_ratio()`](https://seokhoonj.github.io/lossratio-r/reference/fit_ratio.md)
  /
  [`fit_loss()`](https://seokhoonj.github.io/lossratio-r/reference/fit_loss.md)
  /
  [`fit_premium()`](https://seokhoonj.github.io/lossratio-r/reference/fit_premium.md)
  always pass `FALSE` internally because they only read `$summary`. Set
  `TRUE` explicitly if you want to inspect `$pseudo_triangles` directly.

## Value

An object of class `BootstrapTriangle` (a list) with elements:

- `pseudo_triangles`:

  Long-format `data.table` with columns `[groups]`, `cohort`, `dev`,
  `rep`, `loss`. `rep` ranges over `1..B`. Observed-region cells contain
  residual-perturbed (or original for `"analytical"`) cumulative loss;
  the missing region contains Stage 1 forward projection means.

- `residual_pool`:

  `data.table` of the standardized residuals used, with the `pool_id`
  column identifying which pool each residual belongs to (depends on
  `method`/`tail`). Schema differs by residual mode:
  `[groups, cohort, ata_from, ata_to, residual, pool_id]` for
  `residual = "link"`, and `[groups, cohort, dev, residual, pool_id]`
  for `residual = "cell"`.

- `f_anchor`:

  Per-link Mack factor estimates `f_hat` with `n_cohorts`.

- `sigma2_anchor`:

  Per-link Mack `sigma^2` and `Var(f_hat)`.

- `meta`:

  `list(type, residual, hat_adj, process, method, pooling, tail, min_pool, B, seed, alpha, target, groups, maturity)`.

## See also

`dev/BOOTSTRAP.md` for the full design rationale.

## Examples

``` r
if (FALSE) { # \dontrun{
data(experience)
tri <- as_triangle(
  experience[coverage == "surgery"],
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  premium = "incr_premium"
)

# Cell-residual bootstrap (default)
boots <- bootstrap(tri, type = "nonparametric", residual = "cell",
                   hat_adj = TRUE, process = "gamma",
                   B = 500, seed = 1)
print(boots)

# Link-residual bootstrap (Mack 1993 / Pinheiro 2003 path)
boots_link <- bootstrap(tri, type = "nonparametric", residual = "link",
                        pooling = "separated", process = "gamma",
                        B = 500, seed = 1)
} # }
```
