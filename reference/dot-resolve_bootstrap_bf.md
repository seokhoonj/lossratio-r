# Resolve `bootstrap` input for `fit_bf()` / `fit_cc()`

Four-type dispatch mirroring
[`.resolve_bootstrap()`](https://seokhoonj.github.io/lossratio-r/reference/dot-resolve_bootstrap.md)
but returning a *pair* of `BootstrapTriangle` objects (loss + premium) –
BF / Cape Cod compose loss-side parameter uncertainty (via \\q_i^b\\)
and premium-side parameter uncertainty (via \\E_i^{ult,b}\\) into a
single ultimate distribution.

Accepts:

- `NULL` / `FALSE` – returns `NULL` (point estimate only).

- `TRUE` / `"auto"` – two internal
  [`bootstrap()`](https://seokhoonj.github.io/lossratio-r/reference/bootstrap.md)
  calls (one per target) sharing `seed` so replicate indices align.

- Named list `list(loss = BT, premium = BT)` – validate `meta$B` and
  `meta$seed` match.

- Function `function(tri) -> list(loss = ..., premium = ...)`.

## Usage

``` r
.resolve_bootstrap_bf(
  arg,
  tri,
  B = 999L,
  seed = NULL,
  type = "parametric",
  residual = "cell",
  process = "gamma"
)
```
