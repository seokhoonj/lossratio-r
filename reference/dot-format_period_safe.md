# Safely format a period vector for plot axis labels

Internal helper that formats a period vector using
[`.format_period()`](https://seokhoonj.github.io/lossratio/reference/dot-format_period.md)
when the variable name is a recognised period variable, or falls back to
[`base::as.character()`](https://rdrr.io/r/base/character.html)
otherwise.

Used in axis label functions inside plot helpers to avoid errors when
the development variable is a plain integer rather than a date-like
period.

## Usage

``` r
.format_period_safe(x, var, grain = NULL)
```

## Arguments

- x:

  A vector to format.

- var:

  A single character string naming the variable (e.g. `"uy_m"`,
  `"dev_m"`).

- grain:

  Optional grain code (`"M"`/`"Q"`/`"H"`/`"Y"`). Used when `var` is not
  a package-standard period name (see
  [`.get_period_type()`](https://seokhoonj.github.io/lossratio/reference/dot-get_period_type.md)).

## Value

A character vector of formatted labels.
