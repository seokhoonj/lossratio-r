# Pick the divisor that produces the shortest formatted median label

Internal helper used when `amount_divisor = "auto"`. Considers the
SI/financial prefix set `{1, 1e3, 1e6, 1e9, 1e12}` (no unit / thousand /
million / billion / trillion) and picks the divisor that minimises
`nchar(sprintf("%.1f", median / divisor))`. Candidates whose median
label rounds exactly to `"0.0"` are disqualified (precision loss). On
ties, the *smallest* divisor wins so the most significant digit survives
(e.g. `"6.7"` over `"0.7"`). Falls back to `1` when the data have no
finite positive values.

The candidate set deliberately uses powers of 1000 (no `1e7` / `1e8`):
the rule's "tie-break on smallest divisor" already keeps the label
between `1.0` and `999.X`, so a finer grid would not change compactness.
The trade-off accepts that the tails of a wide distribution may round to
the same label – the heatmap colour fill carries the precise value; the
in-cell label is only a numeric hint.

Examples: median 6.6e7 -\> divisor `1e6`, label `"66.6"` (4 chars;
`/1e9` would give `"0.1"`, but rounds away signal so `1e6` wins by the
smallest-divisor tie-break). median 5e5 -\> divisor `1e3`, label
`"500.0"` (5 chars). median 5e9 -\> divisor `1e9`, label `"5.0"` (3
chars).

## Usage

``` r
.auto_divisor(values)
```

## Arguments

- values:

  Numeric vector of cell values to be labelled.

## Value

A single numeric divisor.
