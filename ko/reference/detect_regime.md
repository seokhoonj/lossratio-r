# Detect structural regime shifts across underwriting cohorts

Detect structural change points in the sequence of cohort-level
development trajectories. Each underwriting cohort (indexed by the
`cohort` of a `"Triangle"` object) is treated as a feature vector whose
entries are the selected `target` metric observed at development periods
`1, ..., K`. Cohorts are then ordered by underwriting period and tested
for structural shifts in the multivariate sequence.

Multi-group `Triangle` inputs are supported: detection runs
independently per group, and results are combined into a single `Regime`
object whose `$breakpoints`, `$labels`, etc. carry the group column.
Single-group input retains the original scalar / Date-vector / matrix
layout for backward compatibility.

Three detection strategies are supported:

- `"e_divisive"`:

  Multivariate non-parametric divisive change-point detection via
  [`ecp::e.divisive()`](https://rdrr.io/pkg/ecp/man/e.divisive.html).
  The number of regimes is determined by the data; only significant
  breakpoints at `sig_level` are retained. Preferred when the number of
  regimes is not known in advance.

- `"pelt"`:

  Univariate mean change-point detection via
  [`changepoint::cpt.mean()`](https://rdrr.io/pkg/changepoint/man/cpt.mean.html)
  with the PELT algorithm applied to the first principal component of
  the cohort feature matrix. Fast and may return multiple breakpoints.

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
  K = "auto",
  method = c("e_divisive", "pelt", "hclust"),
  n_regimes = NULL,
  sig_level = 0.05,
  min_size = 3L,
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

  Column name of the trajectory variable. Default is `"lr"` (cumulative
  loss ratio).

- by:

  Grouping column(s) for per-combination detection. `NULL` (default)
  runs pooled detection — all cohorts treated as a single sequence
  regardless of any group attribute on `x`. Supply a character vector
  (subset of `names(x)`) to dispatch per combo, e.g. `by = "coverage"`
  or `by = c("channel", "coverage")`. The Triangle's `attr(x, "groups")`
  is *not* used as a fallback — explicit `by` is required for per-group
  detection.

- K:

  Trajectory window. Integer (e.g., `12L`) for a fixed K, or the string
  `"auto"` (default) — resolves to each group's maturity via
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md),
  falling back to `6L` when maturity is unavailable (NA, pooled mode, or
  `by` mismatching the Triangle's `attr("groups")`). Cohorts with fewer
  than the resolved `K` observed periods are dropped.

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

- `K`:

  Trajectory window per combo. Scalar integer when a single combo was
  analysed; integer vector (one per surviving combo, in the order of
  `$labels` / `$breakpoints` group rows) otherwise.

- `K_mode`:

  Either `"auto"` (resolved per group via
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md))
  or `"manual"` (user-supplied integer).

- `cohort`:

  Period variable from `x`.

- `labels`:

  `data.table` of one row per analysed cohort:
  `[by..., cohort, regime, regime_id]`. Group columns are prepended when
  `by` resolves to a non-empty vector.

- `breakpoints`:

  `data.table` of detected breakpoints with columns
  `[by..., breakpoint, regime_id, pre_value, post_value, magnitude]`.
  `regime_id` = id of the regime that STARTS at this break (the
  pre-break regime is `regime_id - 1`); matches `$labels$regime_id`.
  `pre_value` / `post_value` are the mean `target` over the cohort × dev
  trajectory windows in the pre- / post-break regimes;
  `magnitude = |post_value - pre_value|`. Empty (zero rows) when no
  break is detected.

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

  Cohorts excluded due to the `K` window constraint. Vector (single) /
  named list (multi).

- `multi_group`:

  Logical flag; `TRUE` when detection ran over multiple group combos.

## See also

[`plot.Regime()`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Regime.md),
[`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md)

## Examples

``` r
if (FALSE) { # \dontrun{
data(experience)
tri_sur <- build_triangle(
  experience[coverage == "SUR"],
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "loss_incr",
  premium  = "premium_incr"
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
tri_all <- build_triangle(
  experience,
  groups   = "coverage",
  cohort   = "uy_m",
  calendar = "cy_m",
  loss     = "loss_incr",
  premium  = "premium_incr"
)
r_all <- detect_regime(tri_all, by = "coverage", method = "e_divisive")
print(r_all$breakpoints)
} # }
```
