# Draw a PCA scatter of cohort development trajectories

A lean PCA biplot specialised for
[`detect_regime()`](https://seokhoonj.github.io/lossratio-r/reference/detect_regime.md)
output: every numeric column of `data` is treated as a trajectory
feature, the `regime` column colours the score cloud, and loading arrows
show how each development period contributes to the first two principal
components.

Scores on `PC1` / `PC2` are divided by `sdev * sqrt(n)` raised to
`scale` (biplot-style scaling); loading vectors are rescaled to fit
inside the score range.

## Usage

``` r
.regime_pca_plot(
  data,
  show_arrow = TRUE,
  show_label = TRUE,
  show_ellipse = TRUE,
  show_mean = TRUE,
  show_median = TRUE,
  alpha = 0.3,
  palette = "Set1",
  scale = 1,
  title = NULL,
  subtitle = NULL,
  caption = NULL,
  theme = "view",
  ...
)
```

## Arguments

- data:

  A `data.frame` of numeric trajectory columns plus one categorical
  `regime` column.

- show_arrow, show_label:

  Draw loading arrows / variable names.

- show_ellipse:

  Draw per-regime normal-theory 90% ellipses.

- show_mean, show_median:

  Draw per-regime mean (open circle) and median (cross) score points.

- alpha:

  Point transparency.

- palette:

  Discrete Brewer palette for the `regime` colour.

- scale:

  Biplot scaling exponent; `0` disables score scaling.

- title, subtitle, caption:

  Passed to
  [`ggplot2::labs()`](https://ggplot2.tidyverse.org/reference/labs.html).

- theme:

  Theme key forwarded to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio-r/reference/dot-switch_theme.md).

- ...:

  Forwarded to
  [`.switch_theme()`](https://seokhoonj.github.io/lossratio-r/reference/dot-switch_theme.md).

## Value

A `ggplot` object.
