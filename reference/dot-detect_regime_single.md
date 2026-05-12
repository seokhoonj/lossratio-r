# Single-group regime detection

Core single-group routine used by
[`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md).
Takes a pre-filtered data.table `d` (single group) and returns a list
with the per-group Regime fields. Multi-group dispatch lives in
[`detect_regime()`](https://seokhoonj.github.io/lossratio/reference/detect_regime.md)
itself.

## Usage

``` r
.detect_regime_single(
  d,
  target,
  window,
  method,
  n_regimes,
  sig_level,
  min_size,
  coh,
  dev
)
```
