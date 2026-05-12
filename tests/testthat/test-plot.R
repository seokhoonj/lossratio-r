# Setup — full pipeline objects for plot dispatch tests
data(experience)
exp  <- experience
tri  <- build_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
cal  <- build_calendar(exp, groups = "coverage", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
ata  <- build_link(tri, target = "loss")
af   <- fit_ata(tri, target = "loss")
ed   <- build_link(tri, target = "loss", exposure = "premium")
ef   <- fit_ed(tri, target = "loss", exposure = "premium")
cl_m <- fit_cl(tri, target = "loss", method = "mack")
lr   <- fit_lr(tri, method = "sa")
sub  <- build_triangle(exp[coverage == "SUR"], groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "loss_incr", premium = "premium_incr")
reg  <- detect_regime(sub, K = 12, method = "e_divisive")

is_plot <- function(x) inherits(x, "ggplot") || inherits(x, "gtable")

# plot.<class> -----------------------------------------------------------

test_that("plot.Triangle dispatches", {
  expect_true(is_plot(suppressWarnings(plot(tri))))
  expect_true(is_plot(suppressWarnings(plot(tri, metric = "loss"))))
  expect_true(is_plot(suppressWarnings(plot(tri, summary = TRUE))))
})

test_that("plot.Calendar dispatches", {
  expect_true(is_plot(suppressWarnings(plot(cal))))
  expect_true(is_plot(suppressWarnings(plot(cal, x_by = "dev"))))
})

test_that("plot.Link (ata mode) dispatches across types", {
  for (tp in c("cv", "rse", "summary", "box", "point")) {
    p <- suppressWarnings(plot(ata, type = tp))
    expect_true(is_plot(p), info = paste("type =", tp))
  }
})

test_that("plot.ATAFit dispatches", {
  expect_true(is_plot(suppressWarnings(plot(af))))
})

test_that("plot.Link (ed mode) dispatches across types", {
  for (tp in c("summary", "box", "point")) {
    p <- suppressWarnings(plot(ed, type = tp))
    expect_true(is_plot(p), info = paste("type =", tp))
  }
})

test_that("plot.EDFit dispatches", {
  expect_true(is_plot(suppressWarnings(plot(ef))))
})

test_that("plot.CLFit dispatches (mack, both types)", {
  expect_true(is_plot(suppressWarnings(plot(cl_m, type = "projection"))))
  expect_true(is_plot(suppressWarnings(plot(cl_m, type = "reserve"))))
})

test_that("plot.LRFit dispatches across types", {
  expect_true(is_plot(suppressWarnings(plot(lr, type = "lr"))))
  expect_true(is_plot(suppressWarnings(plot(lr, type = "loss"))))
})

test_that("plot.Regime dispatches", {
  expect_true(is_plot(suppressWarnings(plot(reg))))
})

# plot_triangle.<class> --------------------------------------------------

test_that("plot_triangle.Triangle dispatches", {
  expect_true(is_plot(suppressWarnings(plot_triangle(tri))))
  expect_true(is_plot(suppressWarnings(plot_triangle(tri, label_style = "detail"))))
})

test_that("plot_triangle.Link (ata mode) dispatches", {
  expect_true(is_plot(suppressWarnings(plot_triangle(ata))))
  expect_true(is_plot(suppressWarnings(plot_triangle(ata, show_maturity = TRUE))))
})

test_that("plot_triangle.ATAFit dispatches", {
  expect_true(is_plot(suppressWarnings(plot_triangle(af))))
})

test_that("plot_triangle.Link (ed mode) dispatches", {
  expect_true(is_plot(suppressWarnings(plot_triangle(ed))))
})

test_that("plot_triangle.EDFit dispatches", {
  expect_true(is_plot(suppressWarnings(plot_triangle(ef))))
})

test_that("plot_triangle.CLFit dispatches across region variants", {
  for (r in c("pred", "full", "data")) {
    p <- suppressWarnings(plot_triangle(cl_m, region = r))
    expect_true(is_plot(p), info = paste("region =", r))
  }
})

test_that("plot_triangle.LRFit dispatches", {
  expect_true(is_plot(suppressWarnings(plot_triangle(lr, region = "pred"))))
  expect_true(is_plot(suppressWarnings(plot_triangle(lr, region = "full"))))
  expect_true(is_plot(suppressWarnings(plot_triangle(lr, region = "data"))))
})

test_that("plot_triangle.LRFit view = 'usage' dispatches", {
  expect_true(is_plot(suppressWarnings(plot_triangle(lr, view = "usage"))))
})

test_that("plot_triangle.CLFit view = 'usage' dispatches", {
  expect_true(is_plot(suppressWarnings(plot_triangle(cl_m, view = "usage"))))
})
