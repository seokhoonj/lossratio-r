# Resolve a maturity input to a Maturity object (or NULL)

Internal 4-type dispatcher used by
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md),
[`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md),
and
[`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
to normalize the `maturity` input into a single representation: either
`NULL` (no maturity override) or a `"Maturity"` object.

The four accepted input types are:

- `NULL`:

  Returns `NULL` – caller falls back to its default maturity behavior.

- `"Maturity"` object:

  Returned as-is.

- `"auto"`:

  Runs
  [`detect_maturity()`](https://seokhoonj.github.io/lossratio/reference/detect_maturity.md)
  on `masked_tri` if supplied, otherwise on `tri`. The `masked_tri`
  fallback is the leakage-safe path used by
  [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  – fit functions pass only `tri`, while
  [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  passes both so detection sees only the masked (training) data.

- `function(tri) -> Maturity`:

  Closure invoked with `masked_tri` (if non-NULL) or `tri`. Its return
  value must inherit `"Maturity"`; an error is raised otherwise.

## Usage

``` r
.resolve_maturity(arg, tri, masked_tri = NULL)
```

## Arguments

- arg:

  The maturity input (NULL / Maturity / `"auto"` / function).

- tri:

  A `"Triangle"` object – used as the detection input when `masked_tri`
  is `NULL`.

- masked_tri:

  Optional masked `"Triangle"` (e.g. backtest's training-only triangle).
  When supplied, `"auto"` and function inputs operate on this triangle
  instead of `tri`.

## Value

`NULL` or a `"Maturity"` object.
