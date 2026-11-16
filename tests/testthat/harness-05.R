# harness-05.R — F5 能力層 的預算、執行上限與入口（V05，verification A）
#
# 交界契約（REQ-A-7、A-1、A-25）：
#   * 樣本、種子、暫存與輸出根一律取自 `helper-harness.R`：本檔只呼叫 harness_data()、
#     harness_seed()、harness_dir()、harness_out_root()、harness_table()、
#     expect_rate_equal()、expect_profile()。
#   * 本檔不自行讀表（已發佈的表一律 harness_table()）、不設種子（一律 harness_seed()）、
#     不自建暫存目錄（一律 harness_dir()／harness_out_root()），故 REQ-A-7 對 tests/ 的
#     三類禁令（自行讀表、自設種子、自建暫存）在本檔的命中數為 0。
#   * 本檔只決定預算、執行上限與入口；判定表的斷言在 `test-05_F5.R`，反例與
#     trace 在 `pins/05_F5.md`。
#
# 分節：
#   1. 預算與上限            2. 釘值（Properties 逐條落成常數）
#   3. 性質函式（回傳違反清單）4. 退化 fixture 與注入（只在暫存副本上做）
#   5. 執行入口
#
# 性質函式的契約：每個 `h05_violations_*()` 回一個**字元向量**；空向量＝該性質成立，
# 非空＝逐條寫出「實得 vs 釘值」。回字元而非直接斷言，是為了讓同一支性質能被
# mutant（`h05_mutant_*()`）再跑一次，用「mutant 必須非空」證明該性質會判紅。

## 1. 預算與上限 -----------------------------------------------------------

H05_FLOW <- "F5 能力層"
H05_SAMPLE <- "能力母體全列（harness_data(\"ability\")，2828 列；無抽樣）"
H05_SAMPLE_ROWS <- 2828L
H05_GROUPS <- 4L
H05_CELLS <- 20L
# 收縮：本流程無隨機來源，收縮與種子皆記 n/a；上界照契約寫定（V05 Budget）。
H05_SHRINK_MAX_ITER <- 200L
H05_SHRINK_MAX_SEC <- 30
H05_SHRINK_NOTE <- "n/a（無隨機來源，無可收縮的輸入）"
H05_SEED_NOTE <- "本流程不消耗亂數，種子記 n/a"
# 上限：整個流程 120 秒；單一注入執行再收 60 秒，避免一個掛住的生產腳本拖垮整個測試。
H05_FLOW_LIMIT_SEC <- 120
H05_CHILD_LIMIT_SEC <- 60
H05_RETRIES <- 0L

## 2. 釘值 ----------------------------------------------------------------

# 分位表：母體、四組人數、畢業人數（＝畢業率 × 707 的整數解）、四位有效數字。
H05_POPULATION <- "ability"
H05_QUARTILES <- paste0("q", seq_len(H05_GROUPS))
H05_QUARTILE_N <- c(707L, 707L, 707L, 707L)
H05_GRADUATES <- c(366L, 544L, 593L, 631L)
H05_RATES_4SF <- c(0.5177, 0.7694, 0.8388, 0.8925)
# 四位有效數字的比較容差：末位的半個單位。
H05_SIG_TOL <- 5e-5
# 首尾差（百分點，四位有效數字）：由四個率直接推得，非獨立錨值。
H05_SPREAD_PP_4SF <- 37.48

# 分位數切點法的反事實（證明切法被釘住）：同一批人、同一欄，改用
# quantile() 的四分位切點分組所得的人數。與本表的 707×4 不符。
H05_QUANTILE_CUT_N <- c(707L, 739L, 680L, 702L)

# 移動表：列序、20 格、對角線、缺第一學期成績列、邊際。
H05_FROM_LEVELS <- c("q1", "q2", "q3", "q4", "missing_sem1")
H05_TRANSITIONS <- matrix(
  c(
    396L, 195L,  88L,  21L,
    209L, 285L, 158L,  48L,
     74L, 155L, 313L, 158L,
     15L,  65L, 145L, 477L,
     13L,   7L,   3L,   3L
  ),
  nrow = length(H05_FROM_LEVELS), byrow = TRUE,
  dimnames = list(H05_FROM_LEVELS, paste0("to_q", seq_len(H05_GROUPS)))
)
H05_ROW_TOTALS <- c(700L, 700L, 700L, 702L, 26L)
H05_COL_TOTALS <- c(707L, 707L, 707L, 707L)
H05_DIAGONAL <- c(396L, 285L, 313L, 477L)
H05_MISSING_LABEL <- "missing_sem1"
H05_MISSING_N <- 26L
H05_MISSING_CELLS <- c(13L, 7L, 3L, 3L)
H05_NAMED_ROWS_N <- 2802L          # 四個 quartile 列的合計（母體 2828 減缺列 26）
H05_ABILITY_N <- 2828L             # 能力母體；亦為 20 格逐格相加的總數

# 欄名（以清洗資料集為準；分位表的欄名在 PRD §5 的 public surface 之外）
H05_SEM1_COL <- "Curricular units 1st sem (grade)"
H05_SEM2_COL <- "Curricular units 2nd sem (grade)"
H05_RESULT_COL <- "target"

# 表名與拒絕類別
H05_QUARTILE_TABLE <- "ability_quartiles"
H05_TRANSITION_TABLE <- "ability_transitions"
H05_REFUSE_CATEGORY <- "refuse:empty-denominator"

## 3. 性質函式 --------------------------------------------------------------

# 內部：把「實得 vs 釘值」寫成一行。違反清單的每一行都要能單獨讀懂。
h05_note <- function(fmt, ...) sprintf(fmt, ...)

h05_num <- function(x) suppressWarnings(as.numeric(as.character(x)))

# 3.1 分位表：形狀、母體、四組各 707、合計 2,828。
h05_violations_quartile_shape <- function(tbl) {
  out <- character()
  if (!is.data.frame(tbl)) return("分位表不是資料框")
  needed <- c("population", "quartile", "n", "graduation_rate")
  absent <- setdiff(needed, names(tbl))
  if (length(absent)) {
    return(h05_note("分位表缺欄：%s（實有：%s）", paste(absent, collapse = ", "), paste(names(tbl), collapse = ", ")))
  }
  if (nrow(tbl) != H05_GROUPS) {
    out <- c(out, h05_note("分位表為 %d 列，釘值 %d 列（q1–q4）", nrow(tbl), H05_GROUPS))
  }
  if (!identical(as.character(tbl$quartile), H05_QUARTILES)) {
    out <- c(out, h05_note("quartile 欄為 %s，釘值 %s（升冪、低分在前）",
                           paste(as.character(tbl$quartile), collapse = "/"),
                           paste(H05_QUARTILES, collapse = "/")))
  }
  if (!all(as.character(tbl$population) == H05_POPULATION)) {
    out <- c(out, h05_note("population 欄為 %s，釘值 %s",
                           paste(unique(as.character(tbl$population)), collapse = "/"), H05_POPULATION))
  }
  n <- h05_num(tbl$n)
  if (anyNA(n) || any(n != round(n))) {
    out <- c(out, "n 欄不是整數計數")
  } else if (length(n) == H05_GROUPS && !identical(as.integer(n), H05_QUARTILE_N)) {
    out <- c(out, h05_note("四組人數為 %s，釘值 %s（等量切組，非分位數切點）",
                           paste(as.integer(n), collapse = "/"), paste(H05_QUARTILE_N, collapse = "/")))
  }
  if (length(n) && !anyNA(n) && sum(n) != H05_ABILITY_N) {
    out <- c(out, h05_note("四組人數合計 %d，釘值 %d（能力母體）", as.integer(sum(n)), H05_ABILITY_N))
  }
  out
}

# 3.2 畢業率：四位有效數字、每組率恰為整數畢業人數除以該組人數、單調遞增、首尾差。
h05_violations_rates <- function(tbl) {
  out <- character()
  if (!is.data.frame(tbl) || !all(c("n", "graduation_rate") %in% names(tbl))) {
    return("分位表缺 n 或 graduation_rate 欄")
  }
  rate <- h05_num(tbl$graduation_rate)
  n <- h05_num(tbl$n)
  if (length(rate) != H05_GROUPS || length(n) != H05_GROUPS) {
    return(h05_note("畢業率向量長度 %d、n 長度 %d，皆應為 %d", length(rate), length(n), H05_GROUPS))
  }
  if (anyNA(rate) || any(!is.finite(rate))) return("graduation_rate 含缺值或非有限值")
  if (any(rate <= 0) || any(rate >= 1)) {
    out <- c(out, h05_note("畢業率須在 0 與 1 之間（實得 %s）", paste(signif(rate, 4), collapse = "/")))
  }
  differ <- abs(rate - H05_RATES_4SF)
  if (any(differ > H05_SIG_TOL)) {
    out <- c(out, h05_note("畢業率四位有效數字為 %s，釘值 %s（最大差 %.2e，容差 %.0e）",
                           paste(signif(rate, 4), collapse = "/"),
                           paste(H05_RATES_4SF, collapse = "/"),
                           max(differ), H05_SIG_TOL))
  }
  # 率必為「整數畢業人數 ÷ 該組人數」：分母固定 707 時，乘以 n 必得整數。
  graduates <- rate * n
  off <- abs(graduates - round(graduates))
  if (any(off > 1e-9)) {
    out <- c(out, h05_note("畢業率不是整數計數除以 n（%s × %s 偏離整數 %.2e）",
                           paste(signif(rate, 6), collapse = "/"), paste(n, collapse = "/"), max(off)))
  } else if (!identical(as.integer(round(graduates)), H05_GRADUATES)) {
    out <- c(out, h05_note("各組畢業人數為 %s，釘值 %s",
                           paste(as.integer(round(graduates)), collapse = "/"),
                           paste(H05_GRADUATES, collapse = "/")))
  }
  if (is.unsorted(rate, strictly = TRUE)) {
    out <- c(out, h05_note("畢業率未隨分位嚴格遞增（%s）", paste(signif(rate, 4), collapse = "/")))
  }
  spread <- 100 * (rate[H05_GROUPS] - rate[1L])
  if (abs(spread - H05_SPREAD_PP_4SF) > H05_SIG_TOL * 100) {
    out <- c(out, h05_note("首尾差 %.4f 個百分點，釘值 %.2f", spread, H05_SPREAD_PP_4SF))
  }
  out
}

# 3.3 切法被釘住：等量切組重算得 707×4；分位數切點法重算得 707/739/680/702，與本表不符。
#     兩件都要成立才算證明：表等於前者、且不等於後者。
h05_equal_split <- function(score, groups = H05_GROUPS) {
  n <- length(score)
  placement <- order(score, method = "radix")   # 穩定排序：同分依輸入列序
  width <- n %/% groups
  membership <- integer(n)
  for (g in seq_len(groups - 1L)) {
    membership[placement[((g - 1L) * width + 1L):(g * width)]] <- g
  }
  membership[placement[((groups - 1L) * width + 1L):n]] <- groups
  membership
}

h05_quantile_cut_split <- function(score, groups = H05_GROUPS) {
  breaks <- stats::quantile(score, probs = seq(0, 1, length.out = groups + 1L), type = 7, names = FALSE)
  as.integer(table(cut(score, breaks = breaks, include.lowest = TRUE)))
}

h05_violations_split <- function(ability, analysis, tbl) {
  out <- character()
  need <- c(H05_SEM2_COL, H05_RESULT_COL)
  absent <- setdiff(need, names(ability))
  if (length(absent)) return(h05_note("能力母體缺欄：%s", paste(absent, collapse = ", ")))
  sem2 <- ability[[H05_SEM2_COL]]
  if (nrow(ability) != H05_ABILITY_N) {
    out <- c(out, h05_note("harness_data(\"ability\") 為 %d 列，釘值 %d", nrow(ability), H05_ABILITY_N))
  }
  if (any(sem2 <= 0) || anyNA(sem2)) {
    out <- c(out, "能力母體含第二學期成績為零或缺失者（剔除後母體不該含零分）")
  }
  equal_n <- as.integer(tabulate(h05_equal_split(sem2), nbins = H05_GROUPS))
  cut_n <- h05_quantile_cut_split(sem2)
  if (!identical(equal_n, H05_QUARTILE_N)) {
    out <- c(out, h05_note("等量切組重算為 %s，釘值 %s", paste(equal_n, collapse = "/"),
                           paste(H05_QUARTILE_N, collapse = "/")))
  }
  if (!identical(as.integer(cut_n), H05_QUANTILE_CUT_N)) {
    out <- c(out, h05_note("分位數切點法重算為 %s，釘值 %s（反事實值，用於證明切法被釘住）",
                           paste(as.integer(cut_n), collapse = "/"),
                           paste(H05_QUANTILE_CUT_N, collapse = "/")))
  }
  if (identical(as.integer(cut_n), equal_n)) {
    out <- c(out, "分位數切點法與等量切組在本資料上給出相同人數：本性質失去區辨力")
  }
  if (is.data.frame(tbl) && "n" %in% names(tbl)) {
    in_table <- as.integer(h05_num(tbl$n))
    if (!identical(in_table, equal_n)) {
      out <- c(out, h05_note("表內四組人數 %s 與等量切組重算 %s 不符（表不是由等量切組產生？）",
                             paste(in_table, collapse = "/"), paste(equal_n, collapse = "/")))
    }
    if (identical(in_table, as.integer(cut_n))) {
      out <- c(out, h05_note("表內四組人數等於分位數切點法的 %s：切法被換成 quantile() 切點",
                             paste(as.integer(cut_n), collapse = "/")))
    }
  }
  # 剔除零分是有效的：含零分者以同一切法所得的首尾差與本表相差 40 個百分點以上。
  if (is.data.frame(analysis) && all(need %in% names(analysis)) && nrow(analysis) > H05_ABILITY_N) {
    all_q <- h05_equal_split(analysis[[H05_SEM2_COL]])
    all_n <- as.integer(tabulate(all_q, nbins = H05_GROUPS))
    graduated <- analysis[[H05_RESULT_COL]] == "Graduate"
    all_rate <- vapply(seq_len(H05_GROUPS), function(g) sum(graduated[all_q == g]) / all_n[g], numeric(1))
    all_spread <- 100 * (all_rate[H05_GROUPS] - all_rate[1L])
    if (abs(all_spread - H05_SPREAD_PP_4SF) < 40) {
      out <- c(out, h05_note("含零分者的首尾差 %.4f 個百分點與本表 %.2f 相差不足 40：剔除零分未被證明有效",
                             all_spread, H05_SPREAD_PP_4SF))
    }
  }
  out
}

# 內部：取 20 格的計數矩陣（列＝from_sem1，欄＝to_q1–to_q4）。
h05_cell_matrix <- function(tbl) {
  cols <- paste0("to_q", seq_len(H05_GROUPS))
  if (!all(c(H05_FROM_LEVELS) %in% as.character(tbl$from_sem1)) || !all(cols %in% names(tbl))) return(NULL)
  m <- as.matrix(tbl[match(H05_FROM_LEVELS, as.character(tbl$from_sem1)), cols, drop = FALSE])
  storage.mode(m) <- "integer"
  dimnames(m) <- list(H05_FROM_LEVELS, cols)
  m
}

# 3.4 移動表：5 列 × 4 欄共 20 格、列序、放寬表為 7 欄、逐格釘值。
h05_violations_transition_cells <- function(tbl) {
  out <- character()
  if (!is.data.frame(tbl)) return("移動表不是資料框")
  needed <- c("population", "from_sem1", paste0("to_q", seq_len(H05_GROUPS)), "n")
  absent <- setdiff(needed, names(tbl))
  if (length(absent)) {
    return(h05_note("移動表缺欄：%s（實有：%s）", paste(absent, collapse = ", "), paste(names(tbl), collapse = ", ")))
  }
  if (ncol(tbl) != length(needed)) {
    out <- c(out, h05_note("移動表為 %d 欄，釘值 %d 欄（population、from_sem1、四個計數欄、n）",
                           ncol(tbl), length(needed)))
  }
  if (nrow(tbl) != length(H05_FROM_LEVELS)) {
    out <- c(out, h05_note("移動表為 %d 列，釘值 %d 列（q1–q4 與 %s）",
                           nrow(tbl), length(H05_FROM_LEVELS), H05_MISSING_LABEL))
  }
  if (!identical(as.character(tbl$from_sem1), H05_FROM_LEVELS)) {
    out <- c(out, h05_note("from_sem1 列序為 %s，釘值 %s（缺第一學期成績列固定在最後）",
                           paste(as.character(tbl$from_sem1), collapse = "/"),
                           paste(H05_FROM_LEVELS, collapse = "/")))
  }
  if (!all(as.character(tbl$population) == H05_POPULATION)) {
    out <- c(out, h05_note("population 欄為 %s，釘值 %s",
                           paste(unique(as.character(tbl$population)), collapse = "/"), H05_POPULATION))
  }
  m <- h05_cell_matrix(tbl)
  if (is.null(m)) return(c(out, "取不到 20 格的計數矩陣（列名或 to_q 欄不符）"))
  if (length(m) != H05_CELLS) {
    out <- c(out, h05_note("計數格為 %d 格，釘值 %d 格（%d 列 × %d 欄）",
                           length(m), H05_CELLS, length(H05_FROM_LEVELS), H05_GROUPS))
  }
  if (anyNA(m)) {
    out <- c(out, "計數格含缺值")
    return(out)
  }
  if (any(m < 0)) out <- c(out, "計數格出現負值")
  differ <- which(m != H05_TRANSITIONS, arr.ind = TRUE)
  if (nrow(differ)) {
    detail <- vapply(seq_len(nrow(differ)), function(i) {
      h05_note("%s→%s 為 %d，釘值 %d",
               rownames(m)[differ[i, 1L]], colnames(m)[differ[i, 2L]],
               m[differ[i, 1L], differ[i, 2L]], H05_TRANSITIONS[differ[i, 1L], differ[i, 2L]])
    }, character(1))
    out <- c(out, h05_note("%d 格與釘值不符", nrow(differ)), detail)
  }
  out
}

# 3.5 對角線與缺第一學期成績列。
h05_violations_diagonal_and_missing <- function(tbl) {
  out <- character()
  m <- tryCatch(h05_cell_matrix(tbl), error = function(e) NULL)
  if (is.null(m)) return("取不到 20 格的計數矩陣，無法檢查對角線與缺列")
  diag_value <- vapply(seq_len(H05_GROUPS), function(g) m[g, g], integer(1))
  if (!identical(as.integer(diag_value), H05_DIAGONAL)) {
    out <- c(out, h05_note("對角線為 %s，釘值 %s（同一人在兩期留在同組）",
                           paste(diag_value, collapse = "/"), paste(H05_DIAGONAL, collapse = "/")))
  }
  missing_row <- m[H05_MISSING_LABEL, ]
  if (!identical(as.integer(missing_row), H05_MISSING_CELLS)) {
    out <- c(out, h05_note("%s 列的四格為 %s，釘值 %s",
                           H05_MISSING_LABEL, paste(missing_row, collapse = "/"),
                           paste(H05_MISSING_CELLS, collapse = "/")))
  }
  if (sum(missing_row) != H05_MISSING_N) {
    out <- c(out, h05_note("%s 列合計 %d，釘值 %d", H05_MISSING_LABEL, sum(missing_row), H05_MISSING_N))
  }
  out
}

# 3.6 邊際：四個 quartile 列合計 2,802；四個欄各 707；20 格合計 2,828（每人恰計一次）。
h05_violations_margins <- function(quart, trans) {
  out <- character()
  m <- tryCatch(h05_cell_matrix(trans), error = function(e) NULL)
  if (is.null(m)) return("取不到 20 格的計數矩陣，無法檢查邊際")
  named <- m[seq_len(H05_GROUPS), , drop = FALSE]
  row_totals <- as.integer(rowSums(named))
  if (!identical(row_totals, H05_ROW_TOTALS[seq_len(H05_GROUPS)])) {
    out <- c(out, h05_note("四個 quartile 列合計為 %s，釘值 %s",
                           paste(row_totals, collapse = "/"),
                           paste(H05_ROW_TOTALS[seq_len(H05_GROUPS)], collapse = "/")))
  }
  if (sum(row_totals) != H05_NAMED_ROWS_N) {
    out <- c(out, h05_note("四個 quartile 列合計相加 %d，釘值 %d（母體 %d 減缺列 %d）",
                           sum(row_totals), H05_NAMED_ROWS_N, H05_ABILITY_N, H05_MISSING_N))
  }
  col_totals <- as.integer(colSums(m))
  if (!identical(col_totals, H05_COL_TOTALS)) {
    out <- c(out, h05_note("四個欄的邊際為 %s，釘值 %s（等於第二學期四組人數）",
                           paste(col_totals, collapse = "/"), paste(H05_COL_TOTALS, collapse = "/")))
  }
  if (sum(m) != H05_ABILITY_N) {
    out <- c(out, h05_note("20 格合計 %d，釘值 %d（每人恰計一次）", sum(m), H05_ABILITY_N))
  }
  if (is.data.frame(trans) && "n" %in% names(trans)) {
    n_col <- as.integer(h05_num(trans$n)[match(H05_FROM_LEVELS, as.character(trans$from_sem1))])
    if (!identical(n_col, as.integer(rowSums(m)))) {
      out <- c(out, h05_note("n 欄為 %s，與四個計數欄的列合計 %s 不符",
                             paste(n_col, collapse = "/"), paste(as.integer(rowSums(m)), collapse = "/")))
    }
  }
  if (is.data.frame(quart) && "n" %in% names(quart)) {
    q_n <- as.integer(h05_num(quart$n))
    if (!identical(col_totals, q_n)) {
      out <- c(out, h05_note("移動表欄合計 %s 與分位表四組人數 %s 不符",
                             paste(col_totals, collapse = "/"), paste(q_n, collapse = "/")))
    }
  }
  out
}

## 4. 退化 fixture 與注入（只在暫存副本上做） --------------------------------

# 4.1 清洗資料集形狀的 fixture：資料來自 harness_data()，寫到 harness_dir()。
#     mutate 收到完整母體（4424 列），回傳變異後的資料框；欄名與順序不動。
h05_clean_fixture <- function(dir, mutate, population = "full") {
  frame <- harness_data(population)
  mutated <- mutate(frame)
  if (!is.data.frame(mutated)) stop("mutate 必須回傳資料框", call. = FALSE)
  if (!identical(names(mutated), names(frame))) stop("mutate 不得改動欄名（fixture 需保持清洗資料集的形狀）", call. = FALSE)
  path <- file.path(dir, "f5_fixture_clean.csv")
  readr::write_csv(mutated, path)
  path
}

# 4.2 注入：把 04_ability.R 複製到暫存目錄，只改 CLEAN_PATH 這一行。
#     生產檔不動；注入前的 seam 必須如預期出現一次，否則停手（契約 drift）。
h05_injected_script <- function(dir, clean_path) {
  source_path <- file.path(h05_project_root(), "programs", "R", "04_ability.R")
  if (!file.exists(source_path)) stop("找不到 programs/R/04_ability.R：F5 的 seam 不在預期位置", call. = FALSE)
  lines <- readLines(source_path, warn = FALSE)
  seam <- grep("^CLEAN_PATH <- ", lines)
  if (length(seam) != 1L) {
    stop(sprintf("programs/R/04_ability.R 的 CLEAN_PATH 宣告有 %d 處（預期 1 處）：注入點已漂移，請回報主代理",
                 length(seam)), call. = FALSE)
  }
  lines[seam] <- sprintf("CLEAN_PATH <- %s", deparse(clean_path))
  path <- file.path(dir, "04_ability_injected.R")
  writeLines(lines, path, useBytes = TRUE)
  path
}

# 4.3 執行注入後的腳本：在獨立環境中 source，回傳結果類別與訊息。
#     時間上限由 setTimeLimit 收緊；重試次數固定 0（H05_RETRIES）。
h05_run_ability <- function(script, out_root) {
  started <- Sys.time()
  setTimeLimit(elapsed = H05_CHILD_LIMIT_SEC, transient = TRUE)
  on.exit(setTimeLimit(elapsed = Inf, transient = TRUE), add = TRUE)
  env <- new.env(parent = globalenv())
  outcome <- "ok"
  message_text <- ""
  error <- tryCatch({
    sys.source(script, envir = env)
    NULL
  }, error = function(e) e)
  if (!is.null(error)) {
    message_text <- conditionMessage(error)
    outcome <- if (grepl(H05_REFUSE_CATEGORY, message_text, fixed = TRUE)) "refuse" else "error"
  }
  list(
    outcome = outcome,
    message = message_text,
    elapsed = as.numeric(difftime(Sys.time(), started, units = "secs")),
    retries = H05_RETRIES,
    out_root = out_root
  )
}

# 4.4 sha256：優先 shasum -a 256（macOS），其次 sha256sum（Linux）；兩者皆無則回 NA。
h05_sha256 <- function(paths) {
  tool <- Sys.which(c("shasum", "sha256sum"))
  tool <- tool[nzchar(tool)]
  if (!length(tool)) return(stats::setNames(rep(NA_character_, length(paths)), paths))
  args <- if (grepl("sha256sum$", tool[[1]])) shQuote(paths) else c("-a", "256", shQuote(paths))
  out <- suppressWarnings(system2(tool[[1]], args, stdout = TRUE, stderr = FALSE))
  hex <- sub("^([0-9a-fA-F]{64})\\b.*$", "\\1", out)
  if (length(hex) != length(paths)) return(stats::setNames(rep(NA_character_, length(paths)), paths))
  stats::setNames(hex, paths)
}

# 4.5 已發佈兩張表的路徑與指紋；路徑由測試台解析（A-36 的分家），本檔不自組。
h05_published_paths <- function() {
  if (!exists(".harness_table_path", mode = "function")) {
    stop("harness-05.R 需要先載入 helper-harness.R（.harness_table_path() 由它提供）", call. = FALSE)
  }
  c(
    quartiles = .harness_table_path(H05_QUARTILE_TABLE),
    transitions = .harness_table_path(H05_TRANSITION_TABLE)
  )
}

# 4.6 暫存輸出根：由測試台建根（RTOOLKIT_OUT_ROOT 指到它），先把已發佈的兩張表
#     複製進去，之後任何寫入都只會落在這份副本上。
h05_seeded_out_root <- function() {
  root <- harness_out_root()
  published <- h05_published_paths()
  file.copy(published, file.path(root, "tables"), overwrite = TRUE)
  list(
    root = root,
    tables = file.path(root, "tables", basename(published))
  )
}

# 4.7 mutant：把一份正確的表改壞一格，用來證明對應的性質會判紅。
#     spec: n1/n2/n3/n4（分位表人數）、rate1（第一組畢業率）、
#           cell（矩陣位置，c(row, col)）、cell_value、drop_missing、shift_margin。
h05_mutant_quartiles <- function(tbl, n = NULL, rate = NULL) {
  out <- tbl
  if (!is.null(n)) out$n <- as.integer(n)
  if (!is.null(rate)) out$graduation_rate <- as.numeric(rate)
  out
}

h05_mutant_transitions <- function(tbl, cell = NULL, cell_value = NULL, drop_missing = FALSE,
                                   shift_margin = FALSE) {
  out <- tbl
  cols <- paste0("to_q", seq_len(H05_GROUPS))
  if (!is.null(cell)) {
    row <- match(H05_FROM_LEVELS[cell[1L]], as.character(out$from_sem1))
    out[row, cols[cell[2L]]] <- as.integer(cell_value)
    out$n <- as.integer(rowSums(out[cols]))
  }
  if (shift_margin) {
    # 一格 +1、同列另一格 −1：20 格合計不變，只有欄邊際壞掉。
    up_row <- match("q4", as.character(out$from_sem1))
    out[up_row, cols[4L]] <- as.integer(out[up_row, cols[4L]]) + 1L
    out[up_row, cols[1L]] <- as.integer(out[up_row, cols[1L]]) - 1L
    out$n <- as.integer(rowSums(out[cols]))
  }
  if (drop_missing) out <- out[as.character(out$from_sem1) != H05_MISSING_LABEL, , drop = FALSE]
  out
}

## 5. 執行入口 ---------------------------------------------------------------

h05_project_root <- function() {
  if (exists(".harness_project_root", mode = "function")) return(.harness_project_root())
  getwd()
}

# 本檔所在目錄：直接 Rscript 執行時由 --file= 決定，被 source() 時由 ofile 決定。
h05_this_dir <- function() {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg)) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[[1L]]), winslash = "/", mustWork = FALSE)))
  }
  frames <- sys.frames()
  for (i in rev(seq_along(frames))) {
    ofile <- frames[[i]]$ofile
    if (!is.null(ofile) && grepl("harness-05[.]R$", ofile)) {
      return(dirname(normalizePath(ofile, winslash = "/", mustWork = FALSE)))
    }
  }
  getwd()
}

h05_script_mode <- function() {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  length(file_arg) == 1L && identical(basename(sub("^--file=", "", file_arg[[1L]])), "harness-05.R")
}

# 入口：載入測試台 → 印預算 → 跑本流程的測試檔 → 檢查總耗時不超過 120 秒。
h05_entry <- function(reporter = "summary") {
  dir <- h05_this_dir()
  if (!exists("harness_table", mode = "function")) {
    source(file.path(dir, "helper-harness.R"))
  }
  seed <- harness_seed()
  cat(sprintf(
    "harness-05: flow=%s\n  sample=%s\n  seed=%d（%s）\n  shrink=%s（上界 %d 次／%d 秒）\n  limit=%d 秒；retries=%d\n",
    H05_FLOW, H05_SAMPLE, seed, H05_SEED_NOTE, H05_SHRINK_NOTE,
    H05_SHRINK_MAX_ITER, H05_SHRINK_MAX_SEC, H05_FLOW_LIMIT_SEC, H05_RETRIES
  ))
  started <- Sys.time()
  results <- testthat::test_file(file.path(dir, "test-05_F5.R"), reporter = reporter)
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  assertions <- sum(vapply(results, function(r) length(r$results), integer(1)))
  cat(sprintf("harness-05: %s 秒（上限 %d 秒）；斷言 %d 條\n", sprintf("%.2f", elapsed),
              H05_FLOW_LIMIT_SEC, assertions))
  if (elapsed > H05_FLOW_LIMIT_SEC) {
    stop(sprintf("F5 測試超過單流程上限：%.2f 秒 > %d 秒", elapsed, H05_FLOW_LIMIT_SEC), call. = FALSE)
  }
  # 有紅即以非零結束：入口被 CI 或主代理直接呼叫時，不能讓 exit 0 冒充全綠。
  frame <- as.data.frame(results)
  red <- if (nrow(frame)) sum(frame$failed) + sum(as.integer(frame$error)) else 0L
  if (red > 0L) {
    cat(sprintf("harness-05: %d 條斷言判紅\n", red))
    if (h05_script_mode()) quit(save = "no", status = 1L) else stop("F5 有斷言判紅", call. = FALSE)
  }
  invisible(results)
}

# 自動入口：僅在「以 Rscript 直接執行本檔」且不是由本檔自己的入口再入時觸發。
# 入口會 source 測試檔，測試檔又會 source 本檔——沒有這個守衛就會遞迴。
if (h05_script_mode() && !isTRUE(getOption("harness05.entry.running"))) {
  options(harness05.entry.running = TRUE)
  on.exit(options(harness05.entry.running = NULL), add = TRUE)
  h05_entry()
}
