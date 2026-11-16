# 02_wealth.R — 財富層的四格與關聯強度（F3）
#
# 一條指令做四件事：讀清洗資料集、以「學費是否繳清」與「是否欠債」交叉出四格、
# 算各格退學率與 share、算兩欄的 phi 並寫表。
# 常數一律取自 00_setup.R（REQ-A-2），統計量取自 programs/R/lib/stats.R；
# 本檔不寫出母體人數、容差或 output/ 的字面路徑，也不讀輸出目錄（PRD §5），
# 母體界線只取自 ANALYSIS_N。
#
# 用法（專案根目錄）：Rscript programs/R/02_wealth.R
# 產物：
#   <OUT_ROOT>/tables/wealth_four_cell.csv  四列固定序，欄為 population、cell、n、dropout_rate、share、phi
#   <OUT_ROOT>/logs/02_wealth.log           母體、四格值、phi、欠債入口的對照行與拒絕理由
#
# 編碼：tuition_unpaid = (Tuition fees up to date == 0)、debtor = (Debtor == 1)。
# 兩欄的 0/1 讀法決定 phi 的符號，故編碼寫死在此；以繳清=1 讀同一份資料會得 −0.4349。
#
# 輸入可由 RTOOLKIT_CLEAN_PATH 指向另一份副本（供拒絕分支的注入測試），
# 預設為 data/processed/ams2640_clean.csv。

## 0. 由 00_setup.R 與 lib 取得常數與統計量 ---------------------------------

source("programs/R/00_setup.R")
source("programs/R/lib/stats.R")

## 1. 路徑與固定形狀 -------------------------------------------------------

CLEAN_PATH <- Sys.getenv("RTOOLKIT_CLEAN_PATH", unset = "")
if (!nzchar(CLEAN_PATH)) CLEAN_PATH <- file.path(PROJ_ROOT, "data", "processed", "ams2640_clean.csv")
CLEAN_PATH <- normalizePath(CLEAN_PATH, winslash = "/", mustWork = FALSE)

TABLE_PATH <- file.path(OUT_ROOT, "tables", "wealth_four_cell.csv")
LOG_PATH   <- file.path(OUT_ROOT, "logs", "02_wealth.log")

# 清洗資料集的欄名沿用原始問卷用語（T02 只把結果欄改名為 target）
RESULT_COL  <- "target"
TUITION_COL <- "Tuition fees up to date"
DEBTOR_COL  <- "Debtor"

# 結果欄中代表退學的類別；分析母體內的兩類之一（另一類為畢業）。
DROPOUT_LABEL <- "Dropout"

# 四格的固定列序與鍵值。cell 欄的鍵是下游對照表（cell_map 的 row_key）用的詞彙；
# 列序與報告家境一節的四個率一一對應（修訂 A-22）：
# 兩者俱有 95.13、僅欠繳 93.08、僅欠債 51.87、皆無 29.32。
# 欠繳為入口、欠債為輔助：兩者同時成立者屬第一列，不由欠債另立一格。
CELLS <- data.frame(
  cell   = c("w_both", "w_only_unpaid", "w_only_debt", "w_neither"),
  label  = c("兩者俱有", "僅欠繳", "僅欠債", "皆無"),
  unpaid = c(TRUE, TRUE, FALSE, FALSE),
  debtor = c(TRUE, FALSE, TRUE, FALSE),
  stringsAsFactors = FALSE
)

## 2. 小工具 ---------------------------------------------------------------

stamp <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# 專案內的檔案以相對路徑呈現，專案外（注入測試的暫存副本）才給絕對路徑
short_path <- function(path) {
  prefix <- paste0(PROJ_ROOT, "/")
  ifelse(startsWith(path, prefix), substring(path, nchar(prefix) + 1L), path)
}

# 檔案狀態；缺席時記 absent 而不是錯誤，讓「第一次產出」與「覆蓋舊產物」都留得下時間
file_state <- function(path) {
  if (!file.exists(path)) return("absent")
  info <- file.info(path)
  sprintf("%s bytes=%s", format(info$mtime, "%Y-%m-%dT%H:%M:%S%z"), format(info$size, scientific = FALSE))
}

# 先寫同目錄的暫存檔再改名，半途失敗不留半份表
atomic_write <- function(path, writer) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(pattern = paste0(".", basename(path), "-"), tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  writer(tmp)
  if (!file.rename(tmp, path)) {
    if (!file.copy(tmp, path, overwrite = TRUE)) {
      stop(sprintf("無法以原子替換寫入 %s", short_path(path)), call. = FALSE)
    }
  }
  invisible(path)
}

# 記錄一律追加一段；同一段內的列序固定，時間戳只在段首
log_block <- function(lines) {
  dir.create(dirname(LOG_PATH), recursive = TRUE, showWarnings = FALSE)
  block <- c(sprintf("== 02_wealth %s ==", stamp()), lines, "")
  atomic_write(LOG_PATH, function(path) {
    previous <- if (file.exists(LOG_PATH)) readLines(LOG_PATH, warn = FALSE) else character()
    writeLines(c(previous, block), path, useBytes = TRUE)
  })
}

# 拒絕：先把理由與下一步寫進記錄，再以非零結束碼停止；既有表不動（F3 的拒絕路徑）
refuse <- function(class, reason, next_step) {
  log_block(c(
    sprintf("input: %s", short_path(CLEAN_PATH)),
    sprintf("status: refuse:%s", class),
    sprintf("reason: %s", reason),
    sprintf("table_untouched: %s（before=%s）", short_path(TABLE_PATH), file_state(TABLE_PATH)),
    sprintf("next_step: %s", next_step)
  ))
  stop(
    sprintf("refuse:%s\n- %s\n- 下一步：%s", class, reason, next_step),
    call. = FALSE
  )
}

## 3. 讀清洗資料集 ---------------------------------------------------------

if (!file.exists(CLEAN_PATH)) {
  refuse("input-schema", sprintf("找不到清洗資料集 %s", short_path(CLEAN_PATH)),
         "先執行 programs/R/01_prep_data.R 產生清洗資料集後重跑。")
}

clean <- tryCatch(
  utils::read.csv(CLEAN_PATH, check.names = FALSE, stringsAsFactors = FALSE),
  error = function(e) e
)
if (inherits(clean, "error")) {
  refuse("input-schema", sprintf("清洗資料集無法解析：%s", conditionMessage(clean)),
         "重跑 programs/R/01_prep_data.R 後再試。")
}

required_cols <- c(TUITION_COL, DEBTOR_COL, RESULT_COL)
absent_cols <- setdiff(required_cols, names(clean))
if (length(absent_cols)) {
  refuse("input-schema", sprintf("缺少欄位：%s", paste(absent_cols, collapse = ", ")),
         "確認清洗資料集是 programs/R/01_prep_data.R 的產物後重跑。")
}

## 4. 分析母體與兩欄編碼 ---------------------------------------------------

result <- as.character(clean[[RESULT_COL]])
in_analysis <- result %in% ANALYSIS_RESULTS
analysis_n <- sum(in_analysis)

# 母體界線由 00_setup.R 釘住；數目不同即代表這份輸入已不是研究界定的那一群
if (analysis_n != ANALYSIS_N) {
  refuse("input-schema",
         sprintf("分析母體實算 %d 人，與 00_setup.R 的 %d 不符", analysis_n, ANALYSIS_N),
         "換回契約界定的清洗資料集後重跑；本次未寫出任何表。")
}

# 欠繳 = 學費未繳清（原欄 1 為繳清），欠債 = 原欄為 1；兩者皆須無缺值才進四格
tuition <- clean[[TUITION_COL]][in_analysis]
debtor_code <- clean[[DEBTOR_COL]][in_analysis]
if (anyNA(tuition) || anyNA(debtor_code)) {
  refuse("input-schema",
         sprintf("兩欄在分析母體內有缺值：%s=%d 個、%s=%d 個",
                 TUITION_COL, sum(is.na(tuition)), DEBTOR_COL, sum(is.na(debtor_code))),
         "補齊這兩欄後重跑；本次未寫出任何表。")
}

unpaid <- tuition == 0
debtor <- debtor_code == 1
dropout <- result[in_analysis] == DROPOUT_LABEL

## 5. 四格計數 -------------------------------------------------------------

n_cell <- integer(nrow(CELLS))
dropout_cell <- integer(nrow(CELLS))
for (i in seq_len(nrow(CELLS))) {
  in_cell <- unpaid == CELLS$unpaid[i] & debtor == CELLS$debtor[i]
  n_cell[i] <- sum(in_cell)
  dropout_cell[i] <- sum(in_cell & dropout)
}

# 任一格為空即退學率無分母；寫明空格位置後停止，既有表不覆寫（F3 的拒絕路徑）
empty <- which(n_cell == 0L)
if (length(empty)) {
  refuse("empty-denominator",
         sprintf("空格位置：%s（該格人數為 0，退學率無分母）",
                 paste(sprintf("%s（%s）", CELLS$cell[empty], CELLS$label[empty]), collapse = "、")),
         "檢查這兩欄的編碼與分析母體界線後重跑；既有 wealth_four_cell.csv 未覆寫。")
}

# 四格是欠繳 × 欠債的完整分割，故合計須等於分析母體
if (sum(n_cell) != ANALYSIS_N) {
  refuse("input-schema",
         sprintf("四格 n 合計 %d，與分析母體 %d 不符：四格未覆蓋全部母體", sum(n_cell), ANALYSIS_N),
         "檢查編碼與母體界線後重跑；既有表未覆寫。")
}

## 6. 各格退學率、share 與 phi ---------------------------------------------

# 分母的兩層：dropout_rate 以該格人數為分母，share 以分析母體為分母（修訂 A-10）
dropout_rate <- dropout_cell / n_cell
share <- n_cell / analysis_n

# 同一 2×2：列為欠繳（1/0）、欄為欠債（1/0），故 a = 兩者俱有、b = 僅欠繳、
# c = 僅欠債、d = 皆無。phi 對稱於行列互換，符號只由編碼決定。
#
# 四格以 double 傳入：phi_2x2 的乘積（邊際和的乘積，此處約 2.0e10）在整數型別上會
# 溢位成 NA，而 NA 仍是 numeric，呼叫端無從以型別分辨。空格的位置已由上一節判過，
# 故這裡的 NA 只可能是溢位，一併當作無定義處理。
phi <- phi_2x2(as.numeric(n_cell[1]), as.numeric(n_cell[2]),
               as.numeric(n_cell[3]), as.numeric(n_cell[4]))
if (!is.numeric(phi) || is.na(phi)) {
  refuse("single-class",
         sprintf("phi 無定義：%s（四格中有一整列或一整欄為空，或邊際和的乘積溢位）", format(phi)),
         "檢查這兩欄是否只剩一個類別後重跑；既有表未覆寫。")
}

## 7. 寫四格表 -------------------------------------------------------------

# population 逐列填分析母體；不另寫首列註記，數值存未格式化的 double（D9）
four_cell <- data.frame(
  population = rep("analysis", nrow(CELLS)),
  cell = CELLS$cell,
  n = n_cell,
  dropout_rate = dropout_rate,
  share = share,
  phi = rep(phi, nrow(CELLS)),
  stringsAsFactors = FALSE
)

table_before <- file_state(TABLE_PATH)
atomic_write(TABLE_PATH, function(path) readr::write_csv(four_cell, path))

## 8. 記錄 ----------------------------------------------------------------

# 以欠債作入口的對照：只留在記錄一行，不入表（F3 的 Boundaries）
debtor_n <- sum(debtor)
debtor_dropout_n <- sum(debtor & dropout)

log_block(c(
  sprintf("r_version: %s", R.version.string),
  sprintf("proj_root: %s", PROJ_ROOT),
  sprintf("out_root: %s", OUT_ROOT),
  sprintf("input: %s", short_path(CLEAN_PATH)),
  sprintf("input_rows: %d", nrow(clean)),
  sprintf("population: analysis %d（取自 00_setup.R 的 ANALYSIS_N；四格 n 合計等於它）", analysis_n),
  sprintf("coding: tuition_unpaid = (%s == 0)；debtor = (%s == 1)", TUITION_COL, DEBTOR_COL),
  sprintf("row_order: %s（%s）", paste(CELLS$cell, collapse = ", "), paste(CELLS$label, collapse = "、")),
  sprintf("cell: %s（%s）n=%d dropout=%d dropout_rate=%s share=%s",
          CELLS$cell, CELLS$label, n_cell, dropout_cell, fmt_sig(dropout_rate), fmt_sig(share)),
  sprintf("n_sum: %d", sum(n_cell)),
  sprintf("share_sum: %s", fmt_sig(sum(share))),
  sprintf("phi: %s（2×2 列序 欠繳 1/0、欄序 欠債 1/0；表內存未格式化 double %.10f）",
          fmt_sig(phi), phi),
  sprintf("cross_check: 以欠債為入口 debtors=%d dropout=%d dropout_rate=%s（僅此一行，不入表）",
          debtor_n, debtor_dropout_n, fmt_sig(debtor_dropout_n / debtor_n)),
  sprintf("product: %s rows=%d before=%s after=%s",
          short_path(TABLE_PATH), nrow(four_cell), table_before, file_state(TABLE_PATH)),
  "status: ok",
  "next_step: 家境一節可引用此表；對照表（cell_map）以 cell 欄的鍵 w_both、w_only_unpaid、w_only_debt、w_neither 對應"
))

cat(sprintf("02_wealth: 分析母體 %d 人，四格 n = %s\n", analysis_n, paste(n_cell, collapse = " / ")))
cat(sprintf("02_wealth: dropout_rate = %s\n", paste(fmt_sig(dropout_rate), collapse = " / ")))
cat(sprintf("02_wealth: share = %s（合計 %s）\n", paste(fmt_sig(share), collapse = " / "), fmt_sig(sum(share))))
cat(sprintf("02_wealth: phi = %s\n", fmt_sig(phi)))
cat(sprintf("02_wealth: 表 %s（%d 列）\n", short_path(TABLE_PATH), nrow(four_cell)))
