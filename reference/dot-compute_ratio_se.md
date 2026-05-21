# Loss ratio SE: `ratio_se = SE(L/P)`

Ratio-specific internal helper. Two variants:

- `"fixed"` (default):

  Premium treated as fixed (non-random). \\\mathrm{SE}(L/P) =
  \mathrm{SE}(L) / P\\. Strictly a degenerate case of the delta method
  with `Var(P) = 0` and `Cov(L,P) = 0`.

- `"delta"`:

  First-order Taylor (delta method) including premium uncertainty and
  loss-premium correlation `rho`: \\\mathrm{Var}(L/P) \approx
  (\mathrm{SE}(L)/P)^2 + (L \cdot \mathrm{SE}(P) / P^2)^2 - 2 \rho L
  \mathrm{SE}(L) \mathrm{SE}(P) / P^3\\. The variance is clipped at zero
  before the square root (high `rho` can drive the linearised estimate
  negative).

Not exported; called only by
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md).
The `"fixed"` branch encodes the actuarial assumption that earned
premium is known (not estimated), so this helper is *not* a generic
ratio-SE utility.

## Usage

``` r
.compute_ratio_se(
  loss,
  premium,
  loss_se,
  premium_se = NULL,
  method = c("fixed", "delta"),
  rho = 0.95
)
```

## Arguments

- loss:

  Ultimate loss vector (`L`).

- premium:

  Ultimate premium vector (`E`).

- loss_se:

  `SE(L)`.

- premium_se:

  `SE(P)`. Unused for `"fixed"`; may be `NULL`.

- method:

  One of `"fixed"` (default) or `"delta"`.

- rho:

  Loss-premium correlation in `(-1, 1)`. Used only for `"delta"`.
  Default `0.95`.

## Value

A numeric vector the same length as `loss`.
