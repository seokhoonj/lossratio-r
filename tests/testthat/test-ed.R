# Setup
data(experience)
exp <- experience
tri <- build_triangle(exp, group_var = coverage)
ed  <- build_link(tri, loss_var = "loss", premium_var = "premium")

test_that("build_link (ED mode) returns class 'Link' with expected columns", {
  expect_s3_class(ed, "Link")
  for (nm in c("coverage", "cohort", "ata_from", "ata_to", "ata_link",
               "loss_from", "loss_to", "loss_delta",
               "premium_from", "premium_to", "intensity")) {
    expect_true(nm %in% names(ed), info = paste("missing", nm))
  }
})

test_that("build_link (ED mode) attributes set correctly", {
  for (a in c("group_var", "cohort_var", "dev_var", "loss_var", "premium_var")) {
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

test_that("build_link warns (self-anchored) when loss_var == premium_var", {
  # Self-anchored ED is mathematically equivalent to chain ladder on
  # the same column (f_k = 1 + g_k). Allowed, but warned.
  expect_warning(
    build_link(tri, loss_var = "loss", premium_var = "loss"),
    "self-anchored"
  )
})

# fit_ed -----------------------------------------------------------------

test_that("fit_ed returns class 'EDFit' with expected components", {
  ef <- fit_ed(tri, loss_var = "loss", premium_var = "premium")
  expect_s3_class(ef, "EDFit")
  for (nm in c("factor", "selected")) {
    expect_true(nm %in% names(ef), info = paste("missing", nm))
  }
})

test_that("fit_ed method = 'basic' and 'mack' both work", {
  expect_no_error(fit_ed(tri, loss_var = "loss", premium_var = "premium", method = "basic"))
  ef_mack <- fit_ed(tri, loss_var = "loss", premium_var = "premium", method = "mack")
  expect_s3_class(ef_mack, "EDFit")
})

test_that("fit_ed sigma_method variants run", {
  for (sm in c("min_last2", "locf", "loglinear")) {
    expect_no_error(fit_ed(tri, loss_var = "loss", premium_var = "premium", sigma_method = sm))
  }
})

test_that("recent reduces selected rows count", {
  ef_full   <- fit_ed(tri, loss_var = "loss", premium_var = "premium")
  ef_recent <- fit_ed(tri, loss_var = "loss", premium_var = "premium", recent = 6)
  expect_true(nrow(ef_recent$selected) <= nrow(ef_full$selected))
})

test_that("print.EDFit doesn't error", {
  ef <- fit_ed(tri, loss_var = "loss", premium_var = "premium")
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

# regime_break -----------------------------------------------------------

test_that("fit_ed with regime_break drops pre-break cohorts", {
  data(experience)
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, group_var = "coverage",
                        cohort_var = "uy_m")
  ed <- build_link(tri, loss_var = "loss", premium_var = "premium")
  fit_full <- fit_ed(tri, loss_var = "loss", premium_var = "premium")
  fit_brk  <- fit_ed(tri, loss_var = "loss", premium_var = "premium", regime_break = "2025-07-01")
  expect_false(identical(fit_full$selected$g_selected,
                         fit_brk$selected$g_selected))
  expect_equal(fit_brk$regime_break, as.Date("2025-07-01"))
})

test_that("fit_ed with NULL regime_break is unchanged", {
  data(experience)
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, group_var = "coverage",
                        cohort_var = "uy_m")
  ed <- build_link(tri, loss_var = "loss", premium_var = "premium")
  fit_default <- fit_ed(tri, loss_var = "loss", premium_var = "premium")
  fit_null    <- fit_ed(tri, loss_var = "loss", premium_var = "premium", regime_break = NULL)
  expect_identical(fit_default$selected$g_selected,
                   fit_null$selected$g_selected)
})

test_that("fit_ed with Regime input extracts last breakpoint", {
  data(experience)
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, group_var = "coverage",
                        cohort_var = "uy_m")
  reg <- detect_regime(tri)
  ed <- build_link(tri, loss_var = "loss", premium_var = "premium")
  fit_reg <- fit_ed(tri, loss_var = "loss", premium_var = "premium", regime_break = reg)
  if (length(reg$breakpoints) > 0L) {
    expect_equal(fit_reg$regime_break, max(reg$breakpoints))
  }
})

# fit_ed $full projection -----------------------------------------------

test_that("fit_ed returns $full with projection columns", {
  data(experience)
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, group_var = "coverage",
                        cohort_var = "uy_m")
  ef <- fit_ed(tri, loss_var = "loss", premium_var = "premium")
  expect_true("full" %in% names(ef))
  expect_s3_class(ef$full, "data.table")
  for (nm in c("cohort", "dev", "loss_obs", "premium_obs",
               "loss_proj", "premium_proj", "lr_proj",
               "se_proj", "se_lr", "cv_lr", "is_observed")) {
    expect_true(nm %in% names(ef$full), info = paste("missing", nm))
  }
  # projection columns finite for at least some cells
  expect_true(any(is.finite(ef$full$loss_proj)))
  expect_true(any(is.finite(ef$full$premium_proj)))
  expect_true(any(is.finite(ef$full$lr_proj)))
})

test_that("fit_ed projection matches fit_lr method = 'ed'", {
  data(experience)
  exp <- experience[coverage == "SUR"]
  tri <- build_triangle(exp, group_var = "coverage",
                        cohort_var = "uy_m")
  ef <- fit_ed(tri, loss_var = "loss", premium_var = "premium")
  lr <- fit_lr(tri, method = "ed", loss_var = "loss", premium_var = "premium")

  # numerical equivalence cohort-by-cohort, cell-by-cell
  expect_equal(ef$full$loss_proj,    lr$full$loss_proj,     tolerance = 1e-8)
  expect_equal(ef$full$premium_proj, lr$full$premium_proj, tolerance = 1e-8)
  expect_equal(ef$full$lr_proj,       lr$full$lr_proj,       tolerance = 1e-8)
  expect_equal(ef$full$se_proj,       lr$full$se_proj,       tolerance = 1e-8)
})
