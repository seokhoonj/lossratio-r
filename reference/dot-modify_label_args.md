# Merge user-supplied `label_args` with the standard ggshort label defaults

Mirrors `ggshort:::.modify_label_args()` so heatmap callers can supply a
partial list (e.g. `list(size = 2.5)`) and let the remaining slots fall
back to the standard ggshort label appearance.

## Usage

``` r
.modify_label_args(label_args)
```
