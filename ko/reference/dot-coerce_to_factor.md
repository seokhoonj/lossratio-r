# Coerce a vector to a factor with sorted levels

Existing factors pass through unchanged; character / numeric / Date
vectors become factors with ascending levels, so cells draw on a regular
integer grid.

## Usage

``` r
.coerce_to_factor(x)
```
