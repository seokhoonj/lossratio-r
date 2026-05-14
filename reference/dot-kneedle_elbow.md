# Kneedle elbow heuristic for a decreasing curve.

Implements the Kneedle algorithm (Satopaa et al., 2011) restricted to
the *decreasing convex* shape we expect for change_count vs window:
normalise both axes to `[0, 1]`, find the index with maximum distance
from the diagonal `y = 1 - x`, return the corresponding `window`.

## Usage

``` r
.kneedle_elbow(window, change_count)
```

## Details

Returns `NA_integer_` when the curve is flat (no variation) or has fewer
than 3 points.
