# Get the period type string for a period variable name

Internal helper that maps a period variable name (e.g. `"uy_m"`,
`"cy_q"`) to the corresponding type string accepted by
[`.format_period()`](https://seokhoonj.github.io/lossratio-r/reference/dot-format_period.md).

Falls back to a `grain` hint (M/Q/H/Y) when the variable name is not one
of the package-standard forms. This keeps plot formatting robust to
user-supplied raw column names like `"uym"`, `"elap_m"`, or
`"underwriting_month"`.

Returns `NA_character_` when neither path resolves a type. Callers can
use that to fall back to
[`as.character()`](https://rdrr.io/r/base/character.html) formatting.

## Usage

``` r
.get_period_type(var, grain = NULL)
```

## Arguments

- var:

  A single character string naming a period variable.

- grain:

  Optional grain code from `attr(tri, "grain")` – one of `"M"`, `"Q"`,
  `"H"`, `"Y"`. Used when `var` is not recognised.

## Value

One of `"month"`, `"quarter"`, `"half"`, `"year"`, or `NA_character_`.
