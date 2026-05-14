# Build a lazy maturity detection spec

Captures
[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
arguments without running detection. Returns a closure that the consumer
(fit\_\* or
[`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md))
invokes on its own *internal* triangle. The point is **conditional /
deferred** detection – the value of \$k^\*\$ depends on which cells the
caller decides to expose:

- In
  [`fit_lr()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_lr.md)
  /
  [`fit_loss()`](https://seokhoonj.github.io/lossratio/ko/reference/fit_loss.md),
  the spec is invoked on the *full* triangle the user passed in.

- In
  [`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md),
  **the spec is invoked on the masked triangle of each holdout fold**,
  *never* on the full triangle. Held-out diagonals are removed before
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
  sees the data, so the detected \$k^\*\$ depends only on cells the
  masked fit can also see. This is the leakage-safe contract of
  `maturity_spec()`.

Contrast with
[`maturity_at()`](https://seokhoonj.github.io/lossratio/ko/reference/maturity_at.md),
which produces an eager `"Maturity"` object whose value is fixed at
construction time (independent of the fold's masked data).

Use `maturity_spec()` when you want \$k^\*\$ to be **re-detected per
fold** so backtest honestly answers "given the data available at this
fold, what would I have picked?" Use
[`maturity_at()`](https://seokhoonj.github.io/lossratio/ko/reference/maturity_at.md)
when you want a fixed value tested across folds.

## Usage

``` r
maturity_spec(...)
```

## Arguments

- ...:

  kwargs passed verbatim to
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md)
  when the spec is invoked (e.g. `target`, `groups`, `min_run`,
  `max_cv`, `max_rse`, `min_valid_ratio`, `min_n_valid`).

## Value

A function of one argument (a `"Triangle"`) returning a `"Maturity"`
object. The caller decides which triangle to pass (full vs. masked);
inside
[`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)
this is always the masked training triangle.

## See also

[`detect_maturity()`](https://seokhoonj.github.io/lossratio/ko/reference/detect_maturity.md),
[`maturity_at()`](https://seokhoonj.github.io/lossratio/ko/reference/maturity_at.md),
[`backtest()`](https://seokhoonj.github.io/lossratio/ko/reference/backtest.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Capture detection arguments, defer execution until fit time.
spec <- maturity_spec(min_run = 2, max_cv = 0.04)

# In fit_lr(): closure is invoked on the user's `tri`.
fit <- fit_lr(tri, maturity = maturity_spec(min_run = 2))

# In backtest(): closure is invoked on the *masked* triangle of
# each holdout fold, so detected k* never peeks at held-out cells.
bt <- backtest(tri, holdout = 6L,
               maturity = maturity_spec(min_run = 2, max_cv = 0.04))
} # }
```
