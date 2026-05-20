# Derive a non-native regime detection metric

Computes diagnostic / experimental detection metrics that are not stored
directly on the Triangle:

- `loss_ata`:

  Loss age-to-age factor – `loss[k+1] / loss[k]` per (group, cohort).
  Captures *multiplicative* development speed.

- `exposure_ata`:

  Exposure age-to-age factor – same form on exposure. Captures exposure
  *recognition speed*.

- `loss_ed`:

  Loss intensity (ED model's \$g_k\$) –
  `(loss[k] - loss[k-1]) / exposure[k-1]` per (group, cohort).
  *Additive*, exposure-anchored.

The first dev row per cohort is NA (no predecessor). Downstream
`.detect_regime_single` handles NA-tolerant aggregation.

## Usage

``` r
.derive_regime_target(d, loss, groups = character(0))
```
