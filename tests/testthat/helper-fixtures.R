# Shared test fixtures (auto-sourced by testthat)
#
# These helpers centralise the common construction of `Triangle` and the
# full fit set used across multiple test files. Tests that only need a
# single object should call the focused helper (`make_tri`,
# `make_sub_tri`); tests that exercise the whole pipeline can pull a
# `make_fit_set()` list.

make_exp <- function() {
  data(experience, package = "lossratio", envir = environment())
  experience
}

make_tri <- function(group = "coverage", ...) {
  as_triangle(make_exp(), groups = group,
                 cohort = "uy_m", calendar = "cy_m",
                 loss = "incr_loss", prem = "incr_prem", ...)
}

make_sub_tri <- function(cv = "surgery") {
  exp <- make_exp()
  as_triangle(exp[coverage == cv], groups = "coverage",
                 cohort = "uy_m", calendar = "cy_m",
                 loss = "incr_loss", prem = "incr_prem")
}

make_link_set <- function() {
  tri <- make_tri()
  ata <- as_link(tri, target = "loss")
  ed  <- as_link(tri, target = "loss", exposure = "prem")
  list(
    exp     = make_exp(),
    tri     = tri,
    ata     = ata,
    ata_fit = fit_ata(tri, target = "loss"),
    ata_sm  = summary(ata),
    ed      = ed,
    ed_fit  = fit_ed(tri, target = "loss", exposure = "prem"),
    ed_sm   = summary(ed),
    cl      = fit_cl(tri, target = "loss", method = "mack"),
    lr      = fit_lr(tri, method = "sa", bootstrap = FALSE),
    cal     = as_calendar(tri),
    tot     = as_total(tri)
  )
}

# Backwards-compatible alias for any helper that still calls make_fit_set().
make_fit_set <- make_link_set

is_plot <- function(x) inherits(x, "ggplot") || inherits(x, "gg") ||
                       inherits(x, "gtable")
