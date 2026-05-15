# Loss ratio SE: `lr_se = SE(L/P)`

LR-specific internal helper. Two variants:

- `"fixed"` (default):

  Premium treated as fixed (non-random). \\\mathrm{SE}(L/P) =
  \mathrm{SE}(L) / P\\. Strictly a degenerate case of the delta method
  with `Var(P) = 0` and `Cov(L,P) = 0`.

- `"delta"`:

  First-order Taylor (delta method) including prem uncertainty and
  loss-prem correlation `rho`: \\\mathrm{Var}(L/P) \approx
  (\mathrm{SE}(L)/P)^2 + (L \cdot \mathrm{SE}(P) / P^2)^2 - 2 \rho L
  \mathrm{SE}(L) \mathrm{SE}(P) / P^3\\. The variance is clipped at zero
  before the square root (high `rho` can drive the linearised estimate
  negative).

Not exported; called only by
[`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md).
The `"fixed"` branch encodes the actuarial assumption that earned prem
is known (not estimated), so this helper is *not* a generic ratio-SE
utility.

## Usage

``` r
.compute_lr_se(
  loss,
  premium,
  loss_se,
  prem_se = NULL,
  method = c("fixed", "delta"),
  rho = 0.95
)
```

## Arguments

- loss:

  Ultimate loss vector (`L`).

- premium:

  Ultimate prem vector (`E`).

- loss_se:

  `SE(L)`.

- prem_se:

  `SE(P)`. Unused for `"fixed"`; may be `NULL`.

- method:

  One of `"fixed"` (default) or `"delta"`.

- rho:

  Loss-prem correlation in `(-1, 1)`. Used only for `"delta"`. Default
  `0.95`.

## Value

A numeric vector the same length as `loss`.
