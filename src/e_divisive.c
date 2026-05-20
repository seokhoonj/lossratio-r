/* =============================================================================
 * lossratio: E-Divisive change-point detection kernel
 *
 * Nonparametric multivariate change-point detection on the energy
 * statistic (Matteson & James 2014). A greedy divisive procedure:
 * within every open segment find the split maximising the scaled energy
 * distance, accept the globally largest candidate when a permutation
 * test clears `sig_level` (or, when `k >= 0`, accept the `k` largest
 * unconditionally), then recurse on the two new segments.
 *
 * The permutation test is the hot path -- `n_perm` permutations per
 * accepted break, each re-running the O(m^2) best-split search -- so the
 * whole algorithm runs in C.
 *
 * Reference:
 *   Matteson, D. S. & James, N. A. (2014). A nonparametric approach for
 *   multiple change point analysis of multivariate data. Journal of the
 *   American Statistical Association, 109(505), 334-345.
 *   (The (tau, kappa) double search is Algorithm 2.)
 *
 * R <-> C contract
 * ----------------
 * Input  X_sxp        : n x d REALSXP matrix, column-major; rows are the
 *                       ordered observations to be tested.
 *        k_sxp        : INTSXP scalar; number of change points to force,
 *                       or -1 for significance-driven detection.
 *        sig_level_sxp: REALSXP scalar permutation-test threshold.
 *        min_size_sxp : INTSXP scalar; minimum size of either side of a
 *                       split (must be >= 2).
 *        R_sxp        : INTSXP scalar; permutations per significance test.
 *        alpha_sxp    : REALSXP scalar distance exponent (1 = Euclidean).
 * Output : a named list of two vectors --
 *        breakpoints  : INTSXP, sorted 1-indexed regime-start rows.
 *        p_values     : REALSXP, permutation p-value per break
 *                       (NA for forced breaks under k >= 0).
 *
 * RNG: GetRNGstate() / PutRNGstate() bracket the run; permutations draw
 *      via unif_rand(), so R's set.seed() controls reproducibility.
 *
 * Native routine registration lives in src/init.c; the public signature
 * is declared in src/lossratio.h. R-side counterpart is `.e_divisive()`
 * in R/regime.R, called by `.regime_changes()`.
 * =============================================================================
 */
#include "lossratio.h"
#include <math.h>   /* sqrt, pow */


/* ed_best_split
 *
 *   Best energy-statistic split within an index array.
 *
 *   `idx[0..m-1]` holds D-row indices forming the segment in test order
 *   (contiguous for the observed test, permuted under the null). `D` is
 *   the full n x n distance matrix (row-major: D[i*n + j]). `S` is a
 *   caller-owned scratch buffer of capacity >= (n+1)*(n+1), used here as
 *   an (m+1) x (m+1) prefix-sum table with stride (m+1):
 *
 *     S[(a+1)*(m+1) + (b+1)] = sum of D_seg[0..a][0..b]
 *
 *   where D_seg[a][b] = D[idx[a] * n + idx[b]]. Every left / cross /
 *   right block sum is then four corner lookups.
 *
 *   The candidate statistic at split `tau` (left-side count) is the max
 *   over right-window sizes `kappa` of the scaled energy distance
 *   between left = idx[0..tau-1] and right = idx[tau..kappa-1].
 *
 *   Writes the best statistic to *out_q and the left count to *out_tau
 *   (or -inf / -1 when no valid split exists).
 */
static void ed_best_split(const double *D, int n, const int *idx, int m,
                          int min_size, double *S,
                          double *out_q, int *out_tau) {
  if (m < 2 * min_size) {
    *out_q = R_NegInf;
    *out_tau = -1;
    return;
  }

  int w = m + 1;

  /* zero the top row and left column of the prefix-sum table */
  for (int b = 0; b <= m; b++) {
    S[b] = 0.0;
    S[b * w] = 0.0;
  }
  /* fill: S[a+1][b+1] = D_seg[a][b] + up + left - diag */
  for (int a = 0; a < m; a++) {
    size_t ia = (size_t) idx[a] * n;
    for (int b = 0; b < m; b++) {
      double d = D[ia + idx[b]];
      S[(a + 1) * w + (b + 1)] =
        d + S[a * w + (b + 1)] + S[(a + 1) * w + b] - S[a * w + b];
    }
  }

  double best_q = R_NegInf;
  int best_tau = -1;
  for (int tau = min_size; tau <= m - min_size; tau++) {
    double nx = (double) tau;
    double Stt = S[tau * w + tau];
    double within_x = Stt / (nx * (nx - 1.0));
    for (int kappa = tau + min_size; kappa <= m; kappa++) {
      double ny  = (double) (kappa - tau);
      double Stk = S[tau   * w + kappa];
      double Skk = S[kappa * w + kappa];
      double Skt = S[kappa * w + tau];
      double cross_sum = Stk - Stt;
      double within_y  = (Skk - Skt - Stk + Stt) / (ny * (ny - 1.0));
      double e_stat = (2.0 * cross_sum) / (nx * ny) - within_x - within_y;
      double q = (nx * ny) / (nx + ny) * e_stat;
      if (q > best_q) {
        best_q = q;
        best_tau = tau;
      }
    }
  }
  *out_q = best_q;
  *out_tau = best_tau;
}


SEXP e_divisive(SEXP X_sxp, SEXP k_sxp, SEXP sig_level_sxp,
                SEXP min_size_sxp, SEXP R_sxp, SEXP alpha_sxp) {

  int n = Rf_nrows(X_sxp);
  int d = Rf_ncols(X_sxp);
  const double *X = REAL(X_sxp);
  int    k         = Rf_asInteger(k_sxp);          /* -1 => significance */
  double sig_level = Rf_asReal(sig_level_sxp);
  int    min_size  = Rf_asInteger(min_size_sxp);
  int    n_perm    = Rf_asInteger(R_sxp);
  double alpha     = Rf_asReal(alpha_sxp);

  if (min_size < 2)
    Rf_error("`min_size` must be >= 2.");

  /* pairwise Euclidean distance matrix D (n x n, row-major) */
  double *D = (double *) R_alloc((size_t) n * n, sizeof(double));
  for (int i = 0; i < n; i++) {
    D[(size_t) i * n + i] = 0.0;
    for (int j = i + 1; j < n; j++) {
      double ss = 0.0;
      for (int l = 0; l < d; l++) {
        double diff = X[i + (size_t) l * n] - X[j + (size_t) l * n];
        ss += diff * diff;
      }
      double dist = sqrt(ss);
      if (alpha != 1.0) dist = pow(dist, alpha);
      D[(size_t) i * n + j] = dist;
      D[(size_t) j * n + i] = dist;
    }
  }

  /* scratch buffers (auto-freed at .Call return) */
  double *S    = (double *) R_alloc((size_t) (n + 1) * (n + 1), sizeof(double));
  int    *idx  = (int *)    R_alloc((size_t) n, sizeof(int));
  int    *perm = (int *)    R_alloc((size_t) n, sizeof(int));

  /* open segments: parallel arrays, 0-indexed inclusive [s, e] */
  int *seg_s  = (int *)    R_alloc((size_t) n, sizeof(int));
  int *seg_e  = (int *)    R_alloc((size_t) n, sizeof(int));
  int  n_seg  = 1;
  seg_s[0] = 0;
  seg_e[0] = n - 1;

  int    *breaks = (int *)    R_alloc((size_t) n, sizeof(int));
  double *pvals  = (double *) R_alloc((size_t) n, sizeof(double));
  int     n_break = 0;

  GetRNGstate();

  for (;;) {
    if (k >= 0 && n_break >= k) break;

    /* best candidate split across all open segments */
    double best_q  = R_NegInf;
    int    best_si = -1, best_brk = -1;
    for (int si = 0; si < n_seg; si++) {
      int s = seg_s[si], e = seg_e[si], m = e - s + 1;
      for (int t = 0; t < m; t++) idx[t] = s + t;
      double q;
      int tau;
      ed_best_split(D, n, idx, m, min_size, S, &q, &tau);
      if (tau >= 0 && q > best_q) {
        best_q   = q;
        best_si  = si;
        best_brk = s + tau;
      }
    }
    if (best_si < 0 || !R_FINITE(best_q)) break;

    int s = seg_s[best_si], e = seg_e[best_si], m = e - s + 1;
    double p_value;

    if (k < 0) {
      /* permutation test on the picked segment only */
      for (int t = 0; t < m; t++) perm[t] = s + t;
      int count = 0;
      for (int r = 0; r < n_perm; r++) {
        /* Fisher-Yates shuffle */
        for (int t = m - 1; t > 0; t--) {
          int u = (int) (unif_rand() * (t + 1));
          if (u > t) u = t;
          int tmp = perm[t];
          perm[t] = perm[u];
          perm[u] = tmp;
        }
        double q_perm;
        int tau_perm;
        ed_best_split(D, n, perm, m, min_size, S, &q_perm, &tau_perm);
        if (q_perm >= best_q) count++;
      }
      p_value = (double) (count + 1) / (double) (n_perm + 1);
      if (p_value >= sig_level) break;
    } else {
      p_value = NA_REAL;
    }

    /* accept the break and split the segment in place */
    breaks[n_break] = best_brk;
    pvals[n_break]  = p_value;
    n_break++;
    seg_e[best_si]  = best_brk - 1;   /* left keeps the slot */
    seg_s[n_seg]    = best_brk;       /* right is appended   */
    seg_e[n_seg]    = e;
    n_seg++;
  }

  PutRNGstate();

  /* insertion sort breaks ascending, carrying p-values (n_break tiny) */
  for (int i = 1; i < n_break; i++) {
    int    bk = breaks[i];
    double pv = pvals[i];
    int j = i - 1;
    while (j >= 0 && breaks[j] > bk) {
      breaks[j + 1] = breaks[j];
      pvals[j + 1]  = pvals[j];
      j--;
    }
    breaks[j + 1] = bk;
    pvals[j + 1]  = pv;
  }

  SEXP bp = PROTECT(Rf_allocVector(INTSXP,  n_break));
  SEXP pv = PROTECT(Rf_allocVector(REALSXP, n_break));
  int    *bp_ptr = INTEGER(bp);
  double *pv_ptr = REAL(pv);
  for (int i = 0; i < n_break; i++) {
    bp_ptr[i] = breaks[i] + 1;   /* 0-indexed -> 1-indexed */
    pv_ptr[i] = pvals[i];
  }

  SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
  SET_VECTOR_ELT(out, 0, bp);
  SET_VECTOR_ELT(out, 1, pv);
  SEXP nm = PROTECT(Rf_allocVector(STRSXP, 2));
  SET_STRING_ELT(nm, 0, Rf_mkChar("breakpoints"));
  SET_STRING_ELT(nm, 1, Rf_mkChar("p_values"));
  Rf_setAttrib(out, R_NamesSymbol, nm);

  UNPROTECT(4);
  return out;
}
