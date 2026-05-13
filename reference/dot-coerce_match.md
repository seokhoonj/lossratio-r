# Coerce a name token back to the type of a vector for comparison.

Used internally by print.Regime / summary.Regime: group values are
stored as names (character) on `$n_regimes`, `$trajectory`, etc., but
the actual column type in `$labels[[grp]]` / `$changes[[grp]]` may be
factor, character, or even Date. This converts the character name back
to a scalar of the column's type for `==` filtering.

## Usage

``` r
.coerce_match(name, vec)
```
