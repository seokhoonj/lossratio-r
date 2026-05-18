# Setup -- full pipeline objects for plot dispatch tests
data(experience)
exp  <- experience
tri  <- as_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure")
cal  <- as_calendar(tri)
ata  <- as_link(tri, loss = "loss")
af   <- fit_ata(tri, loss = "loss")
ed   <- as_link(tri, loss = "loss", exposure = "exposure")
ef   <- fit_ed(tri, loss = "loss", exposure = "exposure")
cl_m <- fit_cl(tri, loss = "loss", method = "mack")
lr   <- fit_ratio(tri, method = "sa", bootstrap = FALSE)
sub  <- as_triangle(exp[coverage == "surgery"], groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", exposure = "incr_exposure")
reg  <- detect_regime(sub, window = 12, method = "e_divisive")

is_plot <- function(x) inherits(x, "ggplot") || inherits(x, "gtable")

# plot.<class> -----------------------------------------------------------

test_that("plot.Triangle dispatches", {
  expect_true(is_plot(suppressWarnings(plot(tri))))
  expect_true(is_plot(suppressWarnings(plot(tri, metric = "loss"))))
  expect_true(is_plot(suppressWarnings(plot(tri, summary = TRUE))))
})

test_that("plot.Calendar dispatches", {
  expect_true(is_plot(suppressWarnings(plot(cal))))
  expect_true(is_plot(suppressWarnings(plot(cal, metric = "loss"))))
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

test_that("plot.RatioFit dispatches across metrics and cell_types", {
  for (m in c("ratio", "loss", "exposure")) {
    for (ct in c("cumulative", "incremental")) {
      p <- suppressWarnings(plot(lr, metric = m, cell_type = ct,
                                 per_group = FALSE))
      expect_true(is_plot(p),
                  info = sprintf("metric = %s, cell_type = %s", m, ct))
    }
  }
})

test_that("plot.RatioFit per_group = TRUE returns list of ggplots", {
  res <- suppressWarnings(
    plot(lr, per_group = TRUE, ask = FALSE)
  )
  expect_type(res, "list")
  expect_true(all(vapply(res, inherits, logical(1L), "ggplot")))
  # one entry per group value
  expect_equal(length(res),
               length(unique(lr$full[[lr$groups[[1L]]]])))
})

test_that("plot.RatioFit per_group = FALSE returns single ggplot", {
  p <- suppressWarnings(plot(lr, per_group = FALSE))
  expect_true(is_plot(p))
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
  for (r in c("proj", "full", "data")) {
    p <- suppressWarnings(plot_triangle(cl_m, region = r))
    expect_true(is_plot(p), info = paste("region =", r))
  }
})

test_that("plot_triangle.RatioFit dispatches", {
  expect_true(is_plot(suppressWarnings(plot_triangle(lr, region = "proj"))))
  expect_true(is_plot(suppressWarnings(plot_triangle(lr, region = "full"))))
  expect_true(is_plot(suppressWarnings(plot_triangle(lr, region = "data"))))
})

test_that("plot_triangle.RatioFit view = 'usage' dispatches", {
  expect_true(is_plot(suppressWarnings(plot_triangle(lr, view = "usage"))))
})

test_that("plot_triangle.CLFit view = 'usage' dispatches", {
  expect_true(is_plot(suppressWarnings(plot_triangle(cl_m, view = "usage"))))
})
