# Build a lazy regime detection spec

Captures
[`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
arguments without running detection. Returns a closure that the consumer
(fit\_\* or
[`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md))
invokes on its own *internal* triangle. The point is **conditional /
deferred** detection – the change points depend on which cells the
caller decides to expose:

- In
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
  /
  [`fit_loss()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_loss.md)
  /
  [`fit_premium()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_premium.md),
  the spec is invoked on the *full* triangle the user passed in.

- In
  [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md),
  **the spec is invoked on the masked triangle of each holdout fold**,
  *never* on the full triangle. Held-out diagonals are removed before
  [`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  sees the data, so the detected change points depend only on cells the
  masked fit can also see. This is the leakage-safe contract of
  `regime_spec()`.

Contrast with
[`regime_at()`](https://seokhoonj.github.io/lossratio/ko/reference/regime_at.md),
which produces an eager `"Regime"` object whose change points are fixed
at construction time (independent of the fold's masked data).

Use `regime_spec()` when you want change points to be **re-detected per
fold** so backtest honestly answers "given the data available at this
fold, what regime structure would I have picked?" Use
[`regime_at()`](https://seokhoonj.github.io/lossratio/ko/reference/regime_at.md)
when you want a fixed regime tested across folds.

## Usage

``` r
regime_spec(...)
```

## Arguments

- ...:

  kwargs passed verbatim to
  [`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md)
  when the spec is invoked (e.g. `target`, `by`, `min_run`, `method`).

## Value

A function of one argument (a `"Triangle"`) returning a `"Regime"`
object. The caller decides which triangle to pass (full vs. masked);
inside
[`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
this is always the masked training triangle.

## See also

[`detect_regime()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_regime.md),
[`regime_at()`](https://seokhoonj.github.io/lossratio/ko/reference/regime_at.md),
[`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Capture detection arguments, defer execution until fit time.
spec <- regime_spec(target = "loss_ata")

# In fit_lr(): closure is invoked on the user's `tri`.
fit <- fit_lr(tri, loss_regime = regime_spec(target = "loss_ata"))

# In backtest(): closure is invoked on the *masked* triangle of
# each holdout fold, so detected change points never peek at
# held-out cells.
bt <- backtest(tri, holdout = 6L,
               loss_regime = regime_spec(target = "loss_ata"))
} # }
```
