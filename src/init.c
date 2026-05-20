/* lossratio package: native routine registration
 *
 * Centralised registration of R-callable C entry points. New native
 * kernels are added by:
 *   1. Declaring the SEXP entry in src/lossratio.h.
 *   2. Implementing it in its own src/<name>.c file.
 *   3. Adding a row to CallEntries below.
 *
 * R-side references the symbols by the `C_*` name (e.g. .Call(C_bootstrap_kernel_cl_cell, ...))
 * — that mapping is established by `R_registerRoutines` + the
 * `useDynLib(lossratio, .registration = TRUE)` directive in NAMESPACE.
 */
#include "lossratio.h"
#include <R_ext/Rdynload.h>

static const R_CallMethodDef CallEntries[] = {
  /* name (.Call symbol)                function pointer                       #args */
  {"C_bootstrap_kernel_cl_cell",           (DL_FUNC) &bootstrap_kernel_cl_cell,           16},
  {"C_bootstrap_kernel_ed_cell",        (DL_FUNC) &bootstrap_kernel_ed_cell,        17},
  {"C_bootstrap_kernel_sa_cell",        (DL_FUNC) &bootstrap_kernel_sa_cell,        20},
  {"C_bootstrap_kernel_cl_link",           (DL_FUNC) &bootstrap_kernel_cl_link,           14},
  {"C_bootstrap_kernel_cl_parametric",     (DL_FUNC) &bootstrap_kernel_cl_parametric,     11},
  {"C_bootstrap_kernel_cl_param",       (DL_FUNC) &bootstrap_kernel_cl_param,       12},
  {"C_bootstrap_kernel_ed_param",       (DL_FUNC) &bootstrap_kernel_ed_param,       13},
  {"C_bootstrap_kernel_sa_param",       (DL_FUNC) &bootstrap_kernel_sa_param,       17},
  {"C_bootstrap_summary_kernel",        (DL_FUNC) &bootstrap_summary_kernel,         7},
  {"C_e_divisive",                      (DL_FUNC) &e_divisive,                       6},
  {NULL, NULL, 0}
};

void R_init_lossratio(DllInfo *dll) {
  R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
}
