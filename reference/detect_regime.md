# Detect structural regime shifts across underwriting cohorts

Detect structural change points in the sequence of cohort-level
development trajectories. Each underwriting cohort (indexed by the
`cohort` of a `"Triangle"` object) is treated as a feature vector whose
entries are the selected `target` metric observed at development periods
`1, ..., window`. Cohorts are then ordered by underwriting period and
tested for structural shifts in the multivariate sequence.

Multi-group `Triangle` inputs are supported: detection runs
independently per group, and results are combined into a single `Regime`
object whose `$changes`, `$labels`, etc. carry the group column.
Single-group input retains the original scalar / Date-vector / matrix
layout for backward compatibility.

Three detection strategies are supported:

- `"e_divisive"`:

  Multivariate non-parametric divisive change-point detection via
  [`ecp::e.divisive()`](https://rdrr.io/pkg/ecp/man/e.divisive.html).
  The number of regimes is determined by the data; only significant
  changes at `sig_level` are retained. Preferred when the number of
  regimes is not known in advance.

- `"pelt"`:

  Univariate mean change-point detection via
  [`changepoint::cpt.mean()`](https://rdrr.io/pkg/changepoint/man/cpt.mean.html)
  with the PELT algorithm applied to the first principal component of
  the cohort feature matrix. Fast and may return multiple changes.

- `"hclust"`:

  Ward hierarchical clustering on the scaled cohort feature matrix, cut
  to `n_regimes` clusters. Ignores time ordering – useful as a sanity
  check since non-adjacent cohorts may cluster together if the
  trajectory pattern is not strictly chronological.

## Usage

``` r
detect_regime(
  x,
  target = "lr",
  by = NULL,
  window = "auto",
  method = c("e_divisive", "pelt", "hclust"),
  n_regimes = NULL,
  sig_level = 0.05,
  min_size = 3L,
  treatment = c("latest_only", "segment_wise"),
  ...
)

# S3 method for class 'Regime'
print(x, ...)

# S3 method for class 'Regime'
summary(object, ...)

# S3 method for class 'summary.Regime'
print(x, ...)
```

## Arguments

- x:

  An object of class `"Triangle"`. May contain one or more groups
  (per-group detection runs independently). Also used by S3
  [`print()`](https://rdrr.io/r/base/print.html) method on `Regime`
  objects.

- target:

  Trajectory variable. Default is `"lr"` (cumulative loss ratio).
  Accepts any column on the `Triangle` (e.g. `"lr"`, `"loss"`, `"prem"`,
  `"incr_loss"`, `"incr_prem"`), plus three *diagnostic* derived targets
  computed inline per (group, cohort):

  `"loss_ata"`

  :   Loss age-to-age factor `loss[k+1] / loss[k]` — multiplicative loss
      development speed (CL \$f_k\$).

  `"prem_ata"`

  :   Premium age-to-age factor — same form on prem.

  `"loss_ed"`

  :   Loss intensity `(loss[k] - loss[k-1]) / prem[k-1]` — additive,
      exposure-anchored (ED model's \$g_k\$).

  `"prem_ed"`

  :   Alias of `"prem_ata"` — the two differ only by a constant
      `(prem_ata - 1)`, and the PCA standardization in detection removes
      that shift, so they yield identical regime changes. Provided for
      API symmetry with the `loss_ata` / `loss_ed` pair.

  Derived targets drop the first dev row per cohort (no predecessor),
  then re-index `dev` so detection sees a contiguous sequence. See the
  [`vignette("regime")`](https://seokhoonj.github.io/lossratio/articles/regime.md)
  "Choice of target" section for guidance on which target matches which
  suspected event.

- by:

  Grouping column(s) for per-combination detection. `NULL` (default)
  reuses the Triangle's `attr(x, "groups")` when non-empty — so
  `detect_regime(tri)` dispatches per group automatically — and
  otherwise falls back to pooled detection. Pass `by = character(0)` to
  force pooled detection on a multi-group Triangle, or a character
  vector (subset of `names(x)`) to dispatch on an explicit combo, e.g.
  `by = "coverage"` or `by = c("channel", "coverage")`.

- window:

  Trajectory window. Integer (e.g., `12L`) for a fixed window, or the
  string `"auto"` (default) — resolves to each group's maturity via
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md),
  falling back to `6L` when maturity is unavailable (NA, pooled mode, or
  `by` mismatching the Triangle's `attr("groups")`). Cohorts with fewer
  than the resolved `window` observed periods are dropped.

- method:

  One of `"e_divisive"`, `"pelt"`, `"hclust"`.

- n_regimes:

  Integer. Number of regimes to force. `NULL` means auto-detect for
  `"e_divisive"` and `"pelt"`; ignored (required to equal the requested
  value) for `"hclust"`, where the default is `2`.

- sig_level:

  Significance level for `"e_divisive"`. Default `0.05`.

- min_size:

  Minimum segment size for `"e_divisive"`. Default `3`.

- treatment:

  How downstream fits should apply this Regime when `$changes` contains
  multiple change points. One of:

  `"latest_only"`

  :   (default) Collapse to the most recent change date and drop all
      pre-latest-change cohorts. Single pooled factor estimate over the
      surviving (post-latest-change) cohorts.

  `"segment_wise"`

  :   Preserve all change points. Each segment (consecutive cohorts
      between adjacent changes) gets its own factor estimate, and each
      cohort is projected using its own segment's factor. Recommended
      for multi-regime + long-tail data where opt `"latest_only"` would
      lose self-regime responsiveness on older cohorts.

- ...:

  Reserved for future use.

- object:

  An object of class `"Regime"`. Used by the S3
  [`summary()`](https://rdrr.io/r/base/summary.html) method.

## Value

An object of class `"Regime"`. For single-group input:

- `call`:

  Matched call.

- `method`:

  Detection method used.

- `target`:

  Trajectory variable used for detection.

- `window`:

  Trajectory window per combo. Scalar integer when a single combo was
  analysed; integer vector (one per surviving combo, in the order of
  `$labels` / `$changes` group rows) otherwise.

- `window_mode`:

  Either `"auto"` (resolved per group via
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md))
  or `"manual"` (user-supplied integer).

- `cohort`:

  Period variable from `x`.

- `labels`:

  `data.table` of one row per analysed cohort:
  `[by..., cohort, regime, regime_id]`. Group columns are prepended when
  `by` resolves to a non-empty vector.

- `changes`:

  `data.table` of detected regime changes with columns
  `[by..., change, regime_id, pre_value, post_value, magnitude]`.
  `regime_id` = id of the regime that STARTS at this change (the
  pre-change regime is `regime_id - 1`); matches `$labels$regime_id`.
  `pre_value` / `post_value` are the mean `target` over the cohort × dev
  trajectory windows in the pre- / post-change regimes;
  `magnitude = |post_value - pre_value|`. Empty (zero rows) when no
  change is detected.

- `n_regimes`:

  Number of regimes detected. Scalar integer for single-combo detection;
  named integer vector (keyed by combo) for multi-combo.

- `trajectory`:

  Cohort × dev feature matrix used for detection. Single matrix when
  single combo; named list of matrices for multi-combo.

- `pca`:

  `prcomp` object (single combo) or named list of `prcomp` objects
  (multi-combo).

- `dropped`:

  Cohorts excluded due to the `window` window constraint. Vector
  (single) / named list (multi).

- `multi_group`:

  Logical flag; `TRUE` when detection ran over multiple group combos.

- `treatment`:

  Either `"latest_only"` or `"segment_wise"` — the value supplied via
  the `treatment` argument. Read by downstream fits
  ([`fit_ata()`](https://seokhoonj.github.io/lossratio/reference/fit_ata.md),
  [`fit_intensity()`](https://seokhoonj.github.io/lossratio/reference/fit_intensity.md),
  [`fit_cl()`](https://seokhoonj.github.io/lossratio/reference/fit_cl.md),
  [`fit_ed()`](https://seokhoonj.github.io/lossratio/reference/fit_ed.md))
  to decide whether to collapse to the latest change (drop pre-change
  cohorts, single pooled factor) or estimate per-segment factors.

## See also

[`plot.Regime()`](https://seokhoonj.github.io/lossratio/reference/plot.Regime.md),
[`as_triangle()`](https://seokhoonj.github.io/lossratio/reference/as_triangle.md)

## Examples

``` r
if (FALSE) { # \dontrun{
data(experience)
tri_sur <- as_triangle(
  experience[coverage == "surgery"],
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  prem     = "incr_prem"
)

# Hierarchical clustering (no extra package dependency)
r <- detect_regime(tri_sur, method = "hclust",
                          n_regimes = 2L)
print(r)
summary(r)
plot(r)

# ecp divisive change-point detection (requires the ecp package)
r_ecp <- detect_regime(tri_sur, method = "e_divisive")

# Multi-group: detection per coverage
tri_all <- as_triangle(
  experience,
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "incr_loss",
  prem     = "incr_prem"
)
r_all <- detect_regime(tri_all, by = "coverage", method = "e_divisive")
print(r_all$changes)
} # }
```
