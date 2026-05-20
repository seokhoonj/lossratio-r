# Draw a cohort x development cell grid (heatmap or table)

A general `ggplot2` cell-grid builder: the `x` and `y` columns are
coerced to factors and placed on a regular integer grid of unit tiles,
with optional in-cell text labels. One builder covers both the
continuous heatmap and the threshold-coloured table – the only
difference is how the fill is mapped, selected by `fill_scale`:

- `"gradient"`:

  `fill` is numeric and mapped continuously
  ([`ggplot2::scale_fill_gradient2()`](https://ggplot2.tidyverse.org/reference/scale_gradient.html)
  when `fill_args$midpoint` is set, otherwise
  [`ggplot2::scale_fill_gradient()`](https://ggplot2.tidyverse.org/reference/scale_gradient.html)).

- `"threshold"`:

  `fill` is numeric and compared to `fill_args$threshold` with the
  `fill_args$when` operator; cells are coloured `high` / `low` / `na`
  and drawn with
  [`ggplot2::scale_fill_identity()`](https://ggplot2.tidyverse.org/reference/scale_identity.html).

- `"none"`:

  no fill.

Columns are referenced by name (plain strings) – no non-standard
evaluation. The result is a `ggplot` object the caller can extend.

## Usage

``` r
.cell_grid(
  data,
  x,
  y,
  label = NULL,
  fill = NULL,
  fill_scale = c("none", "gradient", "threshold"),
  fill_args = list(),
  label_args = list(),
  border = c("tile", "panel", "none"),
  border_color = "black",
  border_width = 0.3
)
```

## Arguments

- data:

  A `data.frame` / `data.table`.

- x, y:

  Column-name strings mapped to the grid axes.

- label:

  Optional column-name string drawn as in-cell text.

- fill:

  Optional column-name string (numeric) driving cell fill.

- fill_scale:

  One of `"gradient"`, `"threshold"`, `"none"`.

- fill_args:

  Named list of fill options. Gradient keys: `low`, `mid`, `high`,
  `midpoint`, `na`, `guide`. Threshold keys: `threshold`, `when` (`">"`,
  `">="`, `"<"`, `"<="`), `high`, `low`, `na`.

- label_args:

  Named list passed to the label `geom_text()`.

- border:

  One of `"tile"` (per-cell border), `"panel"` (grid lines on cell
  edges), or `"none"`.

- border_color, border_width:

  Border colour and line width.

## Value

A `ggplot` object.
