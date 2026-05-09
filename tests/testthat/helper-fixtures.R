# Shared test fixtures (auto-sourced by testthat)
#
# These helpers centralise the common construction of `Experience`,
# `Triangle`, and the full fit set used across multiple test files.
# Tests that only need a single object should call the focused helper
# (`make_tri`, `make_sub_tri`); tests that exercise the whole pipeline
# can pull a `make_fit_set()` list.

make_exp <- function() {
  data(experience, package = "lossratio", envir = environment())
  as_experience(experience)
}

make_tri <- function(group_var = "cv_nm", ...) {
  build_triangle(make_exp(), group_var = !!group_var, ...)
}

make_sub_tri <- function(cv = "SUR") {
  exp <- make_exp()
  build_triangle(exp[cv_nm == cv], group_var = "cv_nm")
}

make_link_set <- function() {
  tri <- make_tri()
  ata <- build_link(tri, loss_var = "loss")
  ed  <- build_link(tri, loss_var = "loss", premium_var = "premium")
  list(
    exp     = make_exp(),
    tri     = tri,
    ata     = ata,
    ata_fit = fit_ata(tri, loss_var = "loss"),
    ata_sm  = summary(ata),
    ed      = ed,
    ed_fit  = fit_ed(tri, loss_var = "loss", premium_var = "premium"),
    ed_sm   = summary(ed),
    cl      = fit_cl(tri, loss_var = "loss", method = "mack"),
    lr      = fit_lr(tri, method = "sa"),
    cal     = build_calendar(make_exp(), group_var = "cv_nm"),
    tot     = build_total(make_exp(), group_var = "cv_nm")
  )
}

# Backwards-compatible alias for any helper that still calls make_fit_set().
make_fit_set <- make_link_set

is_plot <- function(x) inherits(x, "ggplot") || inherits(x, "gg") ||
                       inherits(x, "gtable")
