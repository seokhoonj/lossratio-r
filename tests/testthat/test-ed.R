# Setup
data(experience)
exp <- experience
tri <- as_triangle(exp, groups = "coverage", cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_premium")
ed  <- as_link(tri, loss = "loss", exposure = "premium")

test_that("as_link (ED mode) returns class 'Link' with expected columns", {
  expect_s3_class(ed, "Link")
  for (nm in c("coverage", "cohort", "ata_from", "ata_to", "ata_link",
               "loss_from", "loss_to", "loss_delta",
               "premium_from", "premium_to", "intensity")) {
    expect_true(nm %in% names(ed), info = paste("missing", nm))
  }
})

test_that("as_link (ED mode) attributes set correctly", {
  for (a in c("groups", "cohort", "dev", "loss", "premium")) {
    expect_false(is.null(attr(ed, a)), info = paste("missing attr", a))
  }
})

test_that("intensity == loss_delta / premium_from when premium_from > 0", {
  ok <- is.finite(ed$intensity) & ed$premium_from > 0
  expect_equal(ed$intensity[ok],
               ed$loss_delta[ok] / ed$premium_from[ok], tolerance = 1e-6)
})

test_that("loss_delta == loss_to - loss_from", {
  ok <- is.finite(ed$loss_delta)
  expect_equal(ed$loss_delta[ok],
               ed$loss_to[ok] - ed$loss_from[ok],
               tolerance = 1e-6)
})

test_that("as_link warns (self-anchored) when loss == premium", {
  # Self-anchored ED is mathematically equivalent to chain ladder on
  # the same column (f_k = 1 + g_k). Allowed, but warned.
  expect_warning(
    as_link(tri, loss = "loss", exposure = "loss"),
    "self-anchored"
  )
})

# fit_ed -----------------------------------------------------------------

test_that("fit_ed returns class 'EDFit' with expected components", {
  ef <- fit_ed(tri, loss = "loss", exposure = "premium")
  expect_s3_class(ef, "EDFit")
  for (nm in c("factor", "selected")) {
    expect_true(nm %in% names(ef), info = paste("missing", nm))
  }
})

test_that("fit_ed method = 'mack' works", {
  ef_mack <- fit_ed(tri, loss = "loss", exposure = "premium", method = "mack")
  expect_s3_class(ef_mack, "EDFit")
})

test_that("fit_ed sigma_method variants run", {
  for (sm in c("min_last2", "locf", "loglinear", "mack", "none")) {
    expect_no_error(suppressWarnings(
      fit_ed(tri, loss = "loss", exposure = "premium", sigma_method = sm)))
  }
})

test_that("recent reduces selected rows count", {
  ef_full   <- fit_ed(tri, loss = "loss", exposure = "premium")
  ef_recent <- fit_ed(tri, loss = "loss", exposure = "premium", recent = 6)
  expect_true(nrow(ef_recent$selected) <= nrow(ef_full$selected))
})

test_that("print.EDFit doesn't error", {
  ef <- fit_ed(tri, loss = "loss", exposure = "premium")
  expect_no_error(capture.output(print(ef)))
})

# summary.Link (ED mode) -------------------------------------------------

test_that("summary.Link (ed mode) returns EDSummary with expected columns", {
  smr <- summary(ed, alpha = 1)
  expect_s3_class(smr, "EDSummary")
  for (nm in c("ata_from", "ata_to", "mean", "median", "wt", "g")) {
    expect_true(nm %in% names(smr), info = paste("missing", nm))
  }
})

# regime -----------------------------------------------------------------

test_that("fit_ed with regime masks the bridged band", {
  data(experience)
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_premium")
  ed <- as_link(tri, loss = "loss", exposure = "premium")
  fit_full <- fit_ed(tri, loss = "loss", exposure = "premium")
  fit_brk  <- fit_ed(tri, loss = "loss", exposure = "premium",
                     regime = regime_at(change = "2025-07-01"))
  # The bridged band excludes pre-regime early-dev cells, so the pooled
  # intensity factors differ from the unfiltered fit.
  expect_false(identical(fit_full$selected$g_sel,
                         fit_brk$selected$g_sel))
  expect_s3_class(fit_brk$regime, "Regime")
})

test_that("fit_ed with NULL regime is unchanged", {
  data(experience)
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_premium")
  ed <- as_link(tri, loss = "loss", exposure = "premium")
  fit_default <- fit_ed(tri, loss = "loss", exposure = "premium")
  fit_null    <- fit_ed(tri, loss = "loss", exposure = "premium", regime = NULL)
  expect_identical(fit_default$selected$g_sel,
                   fit_null$selected$g_sel)
})

test_that("fit_ed with Regime input preserves the Regime object", {
  data(experience)
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_premium")
  reg <- detect_regime(tri)
  ed <- as_link(tri, loss = "loss", exposure = "premium")
  fit_reg <- fit_ed(tri, loss = "loss", exposure = "premium", regime = reg)
  expect_s3_class(fit_reg$regime, "Regime")
  expect_identical(fit_reg$regime$changes, reg$changes)
})

# fit_ed $full projection -----------------------------------------------

test_that("fit_ed returns $full with projection columns", {
  data(experience)
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_premium")
  ef <- fit_ed(tri, loss = "loss", exposure = "premium")
  expect_true("full" %in% names(ef))
  expect_s3_class(ef$full, "data.table")
  # Worker layer: loss projection + premium projection only.
  # Ratio composition (ratio_proj, ratio_se, ratio_cv) belongs to fit_ratio().
  for (nm in c("cohort", "dev", "loss_obs", "premium_obs",
               "loss_proj", "premium_proj",
               "loss_total_se", "is_observed")) {
    expect_true(nm %in% names(ef$full), info = paste("missing", nm))
  }
  # projection columns finite for at least some cells
  expect_true(any(is.finite(ef$full$loss_proj)))
  expect_true(any(is.finite(ef$full$premium_proj)))
})

test_that("fit_ed loss projection matches fit_ratio method = 'ed'", {
  data(experience)
  exp <- experience[coverage == "surgery"]
  tri <- as_triangle(exp, groups = "coverage",
                        cohort = "uy_m", calendar = "cy_m", loss = "incr_loss", premium = "incr_premium")
  ef <- fit_ed(tri, loss = "loss", exposure = "premium")
  lr <- fit_ratio(tri, method = "ed", bootstrap = FALSE)

  # Worker (fit_ed) produces the loss/premium projection; the ratio
  # composition (ratio_proj) is fit_ratio's concern. Compare common columns.
  expect_equal(ef$full$loss_proj,     lr$full$loss_proj,       tolerance = 1e-8)
  expect_equal(ef$full$premium_proj,  lr$full$premium_proj,    tolerance = 1e-8)
  expect_equal(ef$full$loss_total_se, lr$full$loss_total_se,   tolerance = 1e-8)
})
