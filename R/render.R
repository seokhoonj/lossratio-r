#' Render a tabular object as a compact console table
#'
#' @description
#' `render()` prints a data frame, data table, or Triangle object as a
#' compact, fixed-width console table.
#'
#' The rendered table has four parts:
#' \itemize{
#'   \item a `shape: (rows, cols)` header;
#'   \item a box-drawn grid carrying a column-name row and a
#'     column-type row (`<int>`, `<dbl>`, `<date>`, `<chr>`, ...);
#'   \item a head / tail sample of rows -- when the object has more than
#'     `n` rows the middle is collapsed to a single ellipsis row;
#'   \item a tibble-style "`N` more variables" footer listing the
#'     columns dropped when the table is too wide for the console.
#' }
#'
#' The grid, `shape:` header, and per-column type row follow the
#' dataframe console layout of the package's Python sibling,
#' `lossratio-py`; the truncated-columns footer follows the `tibble`
#' print convention. Both are adopted so that `lossratio` previews stay
#' visually consistent with the wider R and Python tabular ecosystems.
#'
#' Columns are selected from both ends inward until they fill `width`;
#' the dropped middle columns are summarised in the footer.
#' `print.Triangle()` delegates to `render()`, so Triangle objects
#' print in this style by default.
#'
#' @param x An object to render. Methods are provided for data frames,
#'   data tables, tibbles, and Triangle objects; the default method
#'   falls back to [print()].
#' @param n Integer; the maximum number of data rows to show before
#'   head / tail sampling applies. Default `10`.
#' @param width Integer; the target console width in characters.
#'   Default `getOption("width", 100)`.
#' @param max_col_width Integer; the maximum width of a single column --
#'   longer values are truncated with an ellipsis. Default `14`.
#' @param verbose Logical; whether to print the "more variables" footer
#'   for columns dropped to fit `width`. Default `TRUE`.
#' @param ... Additional arguments passed to methods.
#'
#' @return The input object `x`, invisibly.
#'
#' @examples
#' data(experience)
#' render(head(experience, 20))
#'
#' @export
render <- function(x, ...) {
  UseMethod("render")
}

#' @rdname render
#' @export
render.default <- function(x, ...) {
  print(x)
  invisible(x)
}

#' @rdname render
#' @export
render.data.frame <- function(x, n = 10, width = getOption("width", 100),
                              max_col_width = 14, verbose = TRUE, ...) {
  cat(.render_table(x, n, width, max_col_width, verbose), "\n")
  invisible(x)
}

#' @rdname render
#' @export
render.data.table <- render.data.frame

#' @rdname render
#' @export
render.tbl_df     <- render.data.frame

#' @rdname render
#' @export
render.Triangle   <- render.data.frame

#' @rdname render
#' @method print Triangle
#' @export
print.Triangle <- function(x, ...) {
  render.Triangle(x, ...)
  invisible(x)
}

#' Build the box-drawn console table string for [render()].
#' @noRd
.render_table <- function(x, n = 10, width = getOption("width", 100),
                          max_col_width = 14, verbose = TRUE) {
  nr <- nrow(x)
  nc <- ncol(x)
  cols <- names(x)
  types <- vapply(x, .render_type, character(1))

  if (nr <= n) {
    sample_rows <- x
    row_gap <- FALSE
    head_n <- nr
  } else {
    head_n <- floor(n / 2)
    tail_n <- n - head_n
    sample_rows <- rbind(utils::head(x, head_n), utils::tail(x, tail_n))
    row_gap <- TRUE
  }

  fmt_val <- function(v) {
    if (inherits(v, "Date")) as.character(v)
    else if (inherits(v, c("POSIXct", "POSIXlt"))) format(v, "%Y-%m-%d %H:%M:%S")
    else if (is.numeric(v)) format(signif(v, 6), trim = TRUE, scientific = FALSE)
    else as.character(v)
  }

  # Format every column once -- the result feeds both the width
  # measurement and the row rendering, so fmt_val() runs once per
  # column instead of again cell-by-cell.
  formatted <- lapply(sample_rows, function(v) {
    vals <- fmt_val(v)
    vals[is.na(vals)] <- "NA"
    vals
  })

  value_width <- vapply(formatted, function(vals) max(nchar(vals)), numeric(1))

  col_width <- pmin(max_col_width, pmax(nchar(cols), nchar(types), value_width, 3))

  sel <- .select_columns(col_width, width)
  idx <- sel$idx
  left_n <- sel$left_n
  has_gap <- sel$has_gap
  idx_widths <- col_width[idx]

  trunc_str <- function(s, w) {
    s <- as.character(s)
    s[is.na(s)] <- "NA"

    vapply(s, function(one) {
      if (.render_width(one) <= w) return(one)

      chars <- strsplit(one, "", fixed = TRUE)[[1]]
      out <- ""

      for (ch in chars) {
        candidate <- paste0(out, ch, "\u2026")
        if (.render_width(candidate) > w) break
        out <- paste0(out, ch)
      }

      paste0(out, "\u2026")
    }, character(1))
  }

  pad_str <- function(s, w) {
    s <- trunc_str(s, w)
    pad <- pmax(0L, w - .render_width(s))
    paste0(s, strrep(" ", pad))
  }

  visible_widths <- idx_widths
  if (has_gap) visible_widths <- append(visible_widths, 1L, after = left_n)

  make_row <- function(values) {
    parts <- unlist(Map(pad_str, values, idx_widths), use.names = FALSE)
    if (has_gap) parts <- append(parts, "\u2026", after = left_n)
    paste0("\u2502 ", paste(parts, collapse = " \u2506 "), " \u2502")
  }

  top <- paste0("\u250c", paste(strrep("\u2500", visible_widths + 2L), collapse = "\u252c"), "\u2510")
  mid <- paste0("\u251c", paste(strrep("\u2500", visible_widths + 2L), collapse = "\u253c"), "\u2524")
  bot <- paste0("\u2514", paste(strrep("\u2500", visible_widths + 2L), collapse = "\u2534"), "\u2518")

  out <- c(
    paste0("shape: (", format(nr, big.mark = "_"), ", ", format(nc, big.mark = "_"), ")"),
    top,
    make_row(cols[idx]),
    make_row(types[idx]),
    mid
  )

  for (r in seq_len(nrow(sample_rows))) {
    if (row_gap && r == head_n + 1L) {
      out <- c(out, make_row(rep("\u2026", length(idx))))
    }

    vals <- vapply(idx, function(j) formatted[[j]][r], character(1))
    out <- c(out, make_row(vals))
  }

  out <- c(out, bot)

  if (verbose) {
    footer <- .render_footer(cols, types, idx, width = width)
    if (length(footer) > 0L) out <- c(out, footer)
  }

  paste(out, collapse = "\n")
}

#' Pick columns from both ends inward until they fill the console width.
#' @noRd
.select_columns <- function(col_width, width) {
  n <- length(col_width)
  if (n == 0L) {
    return(list(idx = integer(), left_n = 0L, has_gap = FALSE))
  }

  sep_width <- 3L
  gap_width <- 5L

  left <- integer()
  right <- integer()
  used <- 1L + gap_width

  l <- 1L
  r <- n
  turn_left <- TRUE

  while (l <= r) {
    if (turn_left) {
      add <- col_width[l] + sep_width
      if (used + add >= width) break
      left <- c(left, l)
      used <- used + add
      l <- l + 1L
    } else {
      add <- col_width[r] + sep_width
      if (used + add >= width) break
      right <- c(r, right)
      used <- used + add
      r <- r - 1L
    }

    turn_left <- !turn_left
  }

  idx <- c(left, right)
  has_gap <- length(idx) < n

  if (!has_gap) idx <- seq_len(n)

  list(idx = idx, left_n = length(left), has_gap = has_gap)
}

#' Format the "N more variables" footer for columns dropped to fit width.
#'
#' Mimics the `tibble` print convention: when a table is too wide, the
#' dropped columns are listed as "N more variables: name <type>, ...",
#' wrapping at the console width.
#' @noRd
.render_footer <- function(cols, types, idx, width = getOption("width", 100)) {
  hidden_idx <- setdiff(seq_along(cols), idx)
  if (length(hidden_idx) == 0L) return(character())

  hidden <- paste0(cols[hidden_idx], " ", types[hidden_idx])

  prefix <- paste0(length(hidden_idx), " more variables: ")
  indent <- paste(rep(" ", .render_width(prefix)), collapse = "")

  lines <- character()
  current <- prefix

  for (i in seq_along(hidden)) {
    item <- hidden[i]
    piece <- if (identical(current, prefix)) item else paste0(", ", item)

    if (.render_width(current) + .render_width(piece) > width) {
      lines <- c(lines, paste0(current, ","))
      current <- paste0(indent, item)
    } else {
      current <- paste0(current, piece)
    }
  }

  c(lines, current)
}

#' Short type tag (`<int>`, `<dbl>`, `<date>`, ...) for a column.
#' @noRd
.render_type <- function(x) {

  type <- if (inherits(x, "Date")) {
    "date"
  } else if (inherits(x, c("POSIXct", "POSIXlt"))) {
    "dttm"
  } else if (inherits(x, "difftime")) {
    "drtn"
  } else if (is.ordered(x)) {
    "ord"
  } else if (is.factor(x)) {
    "fct"
  } else if (is.integer(x)) {
    "int"
  } else if (is.double(x)) {
    "dbl"
  } else if (is.numeric(x)) {
    "num"
  } else if (is.character(x)) {
    "chr"
  } else if (is.logical(x)) {
    "lgl"
  } else if (is.list(x)) {
    "list"
  } else {
    class(x)[1]
  }

  paste0("<", type, ">")
}

#' Display width of a string, accounting for wide / zero-width glyphs.
#' @noRd
.render_width <- function(x) {
  cli::ansi_nchar(
    as.character(x),
    type = "width"
  )
}
