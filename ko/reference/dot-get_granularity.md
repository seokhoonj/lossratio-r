# Granularity of a cohort or development variable

Like
[`.get_period_type()`](https://seokhoonj.github.io/lossratio/ko/reference/dot-get_period_type.md)
but also recognises the integer development-period columns (`dev_m` /
`dev_q` / `dev_h` / `dev_y`). Used by
[`as_triangle()`](https://seokhoonj.github.io/lossratio/ko/reference/as_triangle.md)
to verify that `cohort` and `dev` share the same granularity. Not used
for date formatting (these dev columns are integers, not Date).

## Usage

``` r
.get_granularity(var)
```
