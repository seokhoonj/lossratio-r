# Resolve a regime input to a Regime object (or NULL)

Internal 4-type dispatcher used by
[`fit_ratio()`](https://seokhoonj.github.io/lossratio/reference/fit_ratio.md),
[`fit_loss()`](https://seokhoonj.github.io/lossratio/reference/fit_loss.md),
[`fit_premium()`](https://seokhoonj.github.io/lossratio/reference/fit_premium.md),
and
[`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
to normalize the `regime` input (or split-axis variants such as
`loss_regime`) into a single representation: either `NULL` (no filter)
or a `"Regime"` object.

The four accepted input types are:

- `NULL`:

  Returns `NULL` – no filter is applied.

- `"Regime"` object:

  Returned as-is.

- `"auto"`:

  Runs
  [`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
  on `masked_tri` if supplied, otherwise on `tri`, with
  `loss = "ratio"`. The `masked_tri` fallback is the leakage-safe path
  used by
  [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  – fit functions pass only `tri`, while
  [`backtest()`](https://seokhoonj.github.io/lossratio/reference/backtest.md)
  passes both so detection sees only the masked (training) data.

- `function(tri) -> Regime`:

  Closure invoked with `masked_tri` (if non-NULL) or `tri`. Its return
  value must inherit `"Regime"`; an error is raised otherwise.

## Usage

``` r
.resolve_regime(arg, tri, masked_tri = NULL)
```

## Arguments

- arg:

  The regime-change input (NULL / Regime / `"auto"` / function).

- tri:

  A `"Triangle"` object – used as the detection input when `masked_tri`
  is `NULL`.

- masked_tri:

  Optional masked `"Triangle"` (e.g. backtest's training-only triangle).
  When supplied, `"auto"` and function inputs operate on this triangle
  instead of `tri`.

## Value

`NULL` or a `"Regime"` object.
