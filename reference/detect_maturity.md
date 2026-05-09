# Find ata maturity by group

Identify the first mature age-to-age (ata) link from a `Triangle`.
Internally builds a single-variable `Link` table, computes the per-link
diagnostic via
[`summary.Link()`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md)
with `model = "ata"`, and then locates the first link whose statistics
satisfy all maturity criteria.

Maturity is determined using a combination of:

- `cv < cv_threshold`

- `rse < rse_threshold`

- `valid_ratio >= min_valid_ratio`

- `n_valid >= min_n_valid`

- optional consecutive maturity over `min_run` ata links

Both `cv` and `rse` must be satisfied simultaneously. `cv` captures the
raw variability of observed ata factors across cohorts, while `rse`
reflects the precision of the WLS-estimated factor. Using both criteria
together provides a more robust maturity assessment than either alone.

## Usage

``` r
detect_maturity(
  x,
  loss_var = "loss",
  weight_var = NULL,
  alpha = 1,
  cv_threshold = 0.15,
  rse_threshold = 0.05,
  min_valid_ratio = 0.5,
  min_n_valid = 3L,
  min_run = 1L
)
```

## Arguments

- x:

  A `Triangle` object.

- loss_var:

  Cumulative metric for the link factor. Default `"loss"`. Forwarded to
  [`build_link()`](https://seokhoonj.github.io/lossratio/reference/build_link.md).

- weight_var:

  Optional WLS weight variable. Forwarded to
  [`build_link()`](https://seokhoonj.github.io/lossratio/reference/build_link.md).

- alpha:

  Numeric scalar controlling the variance structure in the underlying
  WLS fit. Default `1`. Forwarded to
  [`summary.Link()`](https://seokhoonj.github.io/lossratio/reference/summary.Link.md).

- cv_threshold:

  Maximum allowed coefficient of variation. Default is `0.10`.

- rse_threshold:

  Maximum allowed relative standard error. Default is `0.05`.

- min_valid_ratio:

  Minimum proportion of finite ata values required. Default is `0.5`.

- min_n_valid:

  Minimum number of finite ata factors required. Default is `3L`.

- min_run:

  Minimum number of consecutive ata links satisfying the maturity
  criteria. Default is `1L`.

## Value

A `data.table` with class `"Maturity"` containing one row per group. If
no mature link is found, all values for that group are `NA`.
