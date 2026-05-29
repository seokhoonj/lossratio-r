# Resolve a bootstrap argument to a BootstrapTriangle (4-type dispatch)

Mirrors
[`.resolve_maturity()`](https://seokhoonj.github.io/lossratio-r/reference/dot-resolve_maturity.md)
/
[`.resolve_regime()`](https://seokhoonj.github.io/lossratio-r/reference/dot-resolve_regime.md)
pattern. Accepts:

## Usage

``` r
.resolve_bootstrap(
  arg,
  tri,
  B = 499L,
  seed = NULL,
  type = "analytical",
  residual = "cell",
  hat_adj = TRUE,
  demean = TRUE,
  process = "normal",
  method = "cl",
  pooling = "pooled",
  quantile_ci = FALSE,
  keep_pseudo = TRUE,
  tail = "auto",
  min_pool = 5L,
  maturity = NULL,
  target = "loss",
  alpha = 1
)
```

## Arguments

- arg:

  The bootstrap argument supplied by the user.

- tri:

  A `Triangle` object (the data the bootstrap will be computed on).

- B, seed, type, residual, hat_adj, process, method, pooling, tail,
  min_pool, maturity, target, alpha:

  Defaults forwarded to
  [`bootstrap.Triangle()`](https://seokhoonj.github.io/lossratio-r/reference/bootstrap.md)
  when `arg` resolves to `"auto"` or `TRUE`.

## Value

A `BootstrapTriangle` object or `NULL`.

## Details

- `NULL` (or `FALSE`, back-compat) – returns `NULL` (no bootstrap).

- `TRUE` (back-compat) – equivalent to `"auto"`.

- `"auto"` – internal `bootstrap(tri, ...)` call with supplied defaults.

- A `BootstrapTriangle` object – returned as-is.

- A function `function(tri) -> BootstrapTriangle` – invoked on `tri`.
