# Detect structural regime shifts across underwriting cohorts

Detect structural change points in the sequence of cohort-level
development trajectories. Each underwriting cohort (indexed by the
`cohort_var` of a `"Triangle"` object) is treated as a feature vector
whose entries are the selected `target` metric observed at development
periods `1, ..., K`. Cohorts are then ordered by underwriting period and
tested for structural shifts in the multivariate sequence.

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
  K = 12L,
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

- K:

  Integer. Common development-period window used to build the cohort
  feature matrix. Cohorts with fewer than `K` observed periods are
  dropped. Default is `12`.

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

- `target`, `K`:

  Trajectory variable and window.

- `cohort_var`:

  Period variable from `x`.

- `labels`:

  `data.table` with one row per analysed cohort: period, regime id,
  regime label.

- `breakpoints`:

  `Date` vector of breakpoint dates (each is the first cohort of a new
  regime; excludes the initial regime start).

- `n_regimes`:

  Number of regimes detected (scalar integer).

- `trajectory`:

  Cohort feature matrix (rows = cohorts, columns = development periods
  `1, ..., K`).

- `pca`:

  `prcomp` object fitted to the feature matrix.

- `dropped`:

  Cohorts excluded due to the `K` window constraint.

For multi-group input the same fields are returned but with per-group
containers: `$breakpoints` is a `data.table` with columns
`{<group_var>, breakpoint}`; `$labels` gains a `<group_var>` column;
`$n_regimes` is a named integer vector; `$trajectory`, `$pca`, and
`$dropped` are named lists keyed by group value. The `$multi_group`
logical flag distinguishes the two layouts.

## See also

[`plot.Regime()`](https://seokhoonj.github.io/lossratio/ko/reference/plot.Regime.md),
[`build_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/build_triangle.md)

## Examples

``` r
if (FALSE) { # \dontrun{
data(experience)
tri_sur <- build_triangle(experience[coverage == "SUR"], groups = coverage)

# Hierarchical clustering (no extra package dependency)
r <- detect_regime(tri_sur, K = 12, method = "hclust",
                          n_regimes = 2L)
print(r)
summary(r)
plot(r)

# ecp divisive change-point detection (requires the ecp package)
r_ecp <- detect_regime(tri_sur, K = 12, method = "e_divisive")

# Multi-group: detection per coverage
tri_all <- build_triangle(experience, groups = coverage)
r_all <- detect_regime(tri_all, K = 12, method = "e_divisive")
print(r_all$breakpoints)
} # }
```
