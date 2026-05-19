/* lossratio package: public C API
 *
 * Declarations of native routines exposed to R via .Call (registered in
 * src/init.c). File-local helpers stay private to their implementation
 * file and are NOT declared here.
 */
#ifndef LOSSRATIO_H
#define LOSSRATIO_H

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

/* ----- Bootstrap kernels (src/bootstrap.c) -------------------------------
 *
 * Stage-1 + Stage-2 data perturbation: residual resample (or parametric
 * f-draw) + per-replicate f* refit (residual modes only) + forward
 * projection + process-noise draw, all on a paired [n_coh, n_dev, B]
 * cumulative array (mean) + a paired sampled array. Each kernel
 * returns a named list with two REALSXP 3D arrays:
 *
 *   list(cum_mean    = <real[n_coh, n_dev, B]>,    // Stage 1 only
 *        cum_sampled = <real[n_coh, n_dev, B]>)    // Stage 1 + Stage 2
 *
 * cum_mean and cum_sampled are identical on the upper triangle (observed
 * region — Stage 1 perturbation already absorbs noise via the residual /
 * parametric draw). They differ on the lower triangle (projected
 * region): cum_mean[i, j, b] is the mean projection under draw b;
 * cum_sampled[i, j, b] = cum_mean[i, j, b] + epsilon, where epsilon is
 * one process-noise draw from ProcessDist(0, sigma^2(mean^alpha)) with
 * sigma^2 chosen per paradigm (phi for cell ODP, sigma2_k for Mack
 * link / parametric).
 *
 * Three residual / type modes, one kernel each:
 *   - bootstrap_kernel_cl_cell     : residual = "cell"   (England-Verrall ODP)
 *   - bootstrap_kernel_cl_link     : residual = "link"   (Mack / Pinheiro)
 *   - bootstrap_kernel_cl_parametric  : type     = "parametric" (Mack closed form)
 *
 * Process distribution: encoded as integer code in `process_code_sxp`:
 *   1 = gamma     (positivity-preserving, ODP-compatible)
 *   2 = od_pois   (over-dispersed Poisson — gamma parameterised by phi)
 *   3 = normal    (Mack default for residual = "link" / parametric)
 *
 * See the file header of src/bootstrap.c for the R <-> C contract
 * (array layout, index conventions, RNG state handling, pool CSR layout).
 */
SEXP bootstrap_kernel_cl_cell(
    SEXP B_sxp,
    SEXP mu_active_sxp,
    SEXP sqrt_active_sxp,
    SEXP active_lin_sxp,
    SEXP cell_pool_idx_sxp,
    SEXP pool_residuals_sxp,
    SEXP pool_starts_sxp,
    SEXP last_obs_idx_sxp,
    SEXP link_to_idx_sxp,
    SEXP k_idx_by_j_sxp,
    SEXP f_hat_vec_sxp,
    SEXP phi_sxp,             /* scalar dispersion phi (cell mode) */
    SEXP alpha_sxp,           /* variance exponent */
    SEXP process_code_sxp,    /* 1 gamma / 2 od_pois / 3 normal */
    SEXP n_coh_sxp,
    SEXP n_dev_sxp);

/* ED-paradigm cell kernel (Phase 1: fixed exposure).
 *
 * Mirrors bootstrap_kernel_cl_cell but uses the additive exposure-driven
 * recursion `Delta loss = g_k * exposure_{from} + noise` instead of the
 * multiplicative chain ladder. Stage 1 phases (a)-(c) are identical
 * because mu_active and sqrt_active are pre-computed in R; phases (d)-(f)
 * call ED-specific helpers (bootstrap_refit_gstar /
 * bootstrap_fwd_proj_ed_and_clip / bootstrap_fwd_sim_ed_cell).
 *
 * `g_hat_vec[k]` is the original per-link intensity anchor
 * (sum(loss_delta) / sum(exposure_from) over observed link cells);
 * `exposure_proj` is the [n_coh, n_dev] projected exposure (CL-projected
 * once in R on the exposure column) which stays fixed across all B
 * replicates in Phase 1. Phase 2/3 will release this assumption by
 * jointly bootstrapping the exposure column.
 *
 * Returns the same list(cum_mean, cum_sampled) named pair as the CL
 * cell kernel so downstream summary / pseudo_triangles code is unchanged.
 */
SEXP bootstrap_kernel_ed_cell(
    SEXP B_sxp,
    SEXP mu_active_sxp,
    SEXP sqrt_active_sxp,
    SEXP active_lin_sxp,
    SEXP cell_pool_idx_sxp,
    SEXP pool_residuals_sxp,
    SEXP pool_starts_sxp,
    SEXP last_obs_idx_sxp,
    SEXP link_to_idx_sxp,
    SEXP k_idx_by_j_sxp,
    SEXP g_hat_vec_sxp,
    SEXP exposure_proj_sxp,
    SEXP phi_sxp,             /* scalar dispersion phi (cell mode) */
    SEXP alpha_sxp,           /* variance exponent */
    SEXP process_code_sxp,    /* 1 gamma / 2 od_pois / 3 normal */
    SEXP n_coh_sxp,
    SEXP n_dev_sxp);

/* SA-paradigm cell kernel (Phase 1: fixed exposure, two-pool concat).
 *
 * Composes the ED + CL cell kernels via a per-cohort stage transition at
 * `mat_k_vec[i]` (1-indexed from-dev at which CL begins). Stage 1 phases
 * (a)-(c) are identical to the CL / ED siblings because `mu_active` and
 * `sqrt_active` are pre-computed in R using the paradigm appropriate for
 * each cell. Phases (d)-(f) refit BOTH f_star (CL) AND g_star (ED) per
 * replicate, then project + Stage-2-noise with per-cohort stage dispatch.
 *
 * `pool_residuals` is the concatenation of the ED Pearson pool and the CL
 * Pearson pool; `cell_pool_idx[a]` points each active cell to the bucket
 * of its paradigm. Per-cell Stage-2 dispersion uses `phi_ed` (ED stage)
 * or `phi_cl` (CL stage) scalars. See src/bootstrap_sa.c for the math.
 *
 * Returns the same list(cum_mean, cum_sampled) named pair as the CL / ED
 * cell kernels.
 */
SEXP bootstrap_kernel_sa_cell(
    SEXP B_sxp,
    SEXP mu_active_sxp,
    SEXP sqrt_active_sxp,
    SEXP active_lin_sxp,
    SEXP cell_pool_idx_sxp,
    SEXP pool_residuals_sxp,
    SEXP pool_starts_sxp,
    SEXP last_obs_idx_sxp,
    SEXP link_to_idx_sxp,
    SEXP k_idx_by_j_sxp,
    SEXP f_hat_vec_sxp,
    SEXP g_hat_vec_sxp,
    SEXP exposure_proj_sxp,
    SEXP mat_k_vec_sxp,      /* per-cohort 1-indexed CL-start; NA / INT_MAX = all-ED */
    SEXP phi_ed_sxp,         /* scalar ED Stage-2 dispersion */
    SEXP phi_cl_sxp,         /* scalar CL Stage-2 dispersion */
    SEXP alpha_sxp,          /* variance exponent */
    SEXP process_code_sxp,   /* 1 gamma / 2 od_pois / 3 normal */
    SEXP n_coh_sxp,
    SEXP n_dev_sxp);

SEXP bootstrap_kernel_cl_link(
    SEXP B_sxp,
    SEXP mat_obs_sxp,
    SEXP last_obs_idx_sxp,
    SEXP link_to_idx_sxp,
    SEXP k_idx_by_j_sxp,
    SEXP f_hat_vec_sxp,
    SEXP sigma2_vec_sxp,
    SEXP link_pool_idx_sxp,
    SEXP pool_residuals_sxp,
    SEXP pool_starts_sxp,
    SEXP alpha_sxp,           /* variance exponent */
    SEXP process_code_sxp,    /* 1 gamma / 2 od_pois / 3 normal */
    SEXP n_coh_sxp,
    SEXP n_dev_sxp);

SEXP bootstrap_kernel_cl_parametric(
    SEXP B_sxp,
    SEXP mat_obs_sxp,
    SEXP last_obs_idx_sxp,
    SEXP k_idx_by_j_sxp,
    SEXP f_hat_vec_sxp,
    SEXP f_var_vec_sxp,
    SEXP sigma2_vec_sxp,      /* Mack sigma^2 for Stage 2 noise */
    SEXP alpha_sxp,
    SEXP process_code_sxp,
    SEXP n_coh_sxp,
    SEXP n_dev_sxp);

/* Pythagorean SE decomposition over the two [n_coh, n_dev, B] cumulative
 * arrays — replaces the R-level data.table group-wise aggregation in
 * .boot_summary_from_arrays(). Returns a
 * named list of five flat length n_coh × n_dev REALSXPs: mean_proj,
 * param_se, proc_se, total_se, total_cv. When `quantile_ci_sxp` is
 * TRUE, the returned list additionally carries `ci_lo` and `ci_hi`
 * empirical percentile bounds (Davison-Hinkley type=1 ordinal: rank
 * `ceil(p * n_finite)` 1-indexed; NA_real_ when fewer than 2 finite
 * values per cell). `probs_sxp` carries the probabilities (typically
 * c(0.025, 0.975); length-2 in practice, parameterised for future
 * extension). See src/bootstrap.c for the full contract. */
SEXP bootstrap_summary_kernel(
    SEXP cum_mean_sxp,
    SEXP cum_sampled_sxp,
    SEXP n_coh_sxp,
    SEXP n_dev_sxp,
    SEXP n_groups_sxp,
    SEXP quantile_ci_sxp,
    SEXP probs_sxp);

#endif /* LOSSRATIO_H */
