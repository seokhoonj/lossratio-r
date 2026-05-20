# Merge user-supplied `label_args` with the standard label defaults

A cell label is a `geom_text()` layer; this fills any slot the caller
did not supply (`family`, `size`, `angle`, `hjust`, `vjust`, `color`) so
callers can pass a partial list such as `list(size = 2.5)`.

## Usage

``` r
.modify_label_args(label_args)
```
