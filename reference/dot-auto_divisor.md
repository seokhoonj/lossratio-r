# Pick the divisor that produces the shortest formatted median label

Internal helper used when `amount_divisor = "auto"`. Considers the
SI/financial prefix set `{1, 1e3, 1e6, 1e9, 1e12}` (no unit / thousand /
million / billion / trillion) and picks the largest divisor such that
`median / divisor` still rounds (at `%.1f`) to a non-zero label. Below
the `0.05` threshold the label would format as `"0.0"` and precision is
wiped out, so those divisors are disqualified. Falls back to `1` when
the data have no finite positive values.

The "largest divisor that still rounds non-zero" rule favours labels in
the `0.X` range (3 chars) over `X.X` / `XX.X` / `XXX.X` (3-5 chars).
This keeps in-cell heatmap text compact; the colour fill carries the
precise value.

Examples (median -\> divisor, label): `5e2` -\> `1e3`, `"0.5"` `5e7` -\>
`1e9`, `"0.1"` (since `5e7 / 1e9 = 0.05 >= 0.05`) `5e10` -\> `1e12`,
`"0.1"` `5e12` -\> `1e12`, `"5.0"` (capped at the largest candidate)

The numeric `>= 0.05` test is deliberate: Windows R's
`sprintf("%.1f", 0.05)` rounds to `"0.0"` while Linux / macOS round to
`"0.1"`. Comparing numerically (with a tiny `1e-10` slack) produces a
deterministic, platform-independent choice.

## Usage

``` r
.auto_divisor(values)
```

## Arguments

- values:

  Numeric vector of cell values to be labelled.

## Value

A single numeric divisor.
