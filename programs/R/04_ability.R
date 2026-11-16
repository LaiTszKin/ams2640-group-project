# 04_ability.R — 能力分位與兩期追蹤（F5）
#
# 一張分位表與一張 5×4 移動表：
#   能力母體（分析母體 ∩ 第二學期成績 > 0）依第二學期成績**等量**切四組，
#   各組人數與畢業率寫入分位表；同一批人以第一學期的等量切組追蹤到第二學期，
#   組別移動的計數寫入寬表，缺第一學期成績者單列 missing_sem1。
#
# 切法：成績升冪、`order(..., method = "radix")`（穩定排序，同分依清洗資料集的
# 原始列序）、組寬 floor(n/4)、末組收餘。**不得用 quantile() 切點**：分位數切點法
# 在能力母體上所得的組寬與釘值不符（任務檔 T06 步驟 2、V05）。
#
# 常數一律取自 00_setup.R，呈現用 lib/stats.R 的 fmt_sig；本檔不寫出母體人數、
# 分位數或 output/ 字面路徑（REQ-A-2），也不讀輸出目錄（PRD §5）。
#
# 用法（專案根目錄）：Rscript programs/R/04_ability.R
# 產物：
#   <OUT_ROOT>/tables/ability_quartiles.csv     population、quartile、n、graduation_rate
#   <OUT_ROOT>/tables/ability_transitions.csv   寬表 5 列 × 4 欄
#   <OUT_ROOT>/logs/04_ability.log              執行記錄、切分方法、被剔除人數

## 0. 設定與共用統計量 -----------------------------------------------------

source(file.path(here::here("programs/R/00_setup.R")))
source(file.path(PROJ_ROOT, "programs/R/lib/stats.R"))

## 1. 路徑、欄名與固定形狀 -------------------------------------------------

CLEAN_PATH <- file.path(PROJ_ROOT, "data", "processed", "ams2640_clean.csv")
QUARTILE_PATH <- file.path(OUT_ROOT, "tables", "ability_quartiles.csv")
TRANSITION_PATH <- file.path(OUT_ROOT, "tables", "ability_transitions.csv")
LOG_PATH <- file.path(OUT_ROOT, "logs", "04_ability.log")

# 欄名以清洗資料集為準（01_prep_data.R 保留原名，只把結果欄改名為 target）
RESULT_COL <- "target"
SEM1_COL <- "Curricular units 1st sem (grade)"
SEM2_COL <- "Curricular units 2nd sem (grade)"
REQUIRED_COLS <- c(RESULT_COL, SEM1_COL, SEM2_COL)

# 畢業＝結果欄的 Graduate；結果欄的三個類別由 01_prep_data.R 驗過
GRADUATE <- "Graduate"

# 表內的母體具名值（清冊與其他表同用 full／analysis／ability，PRD §3）
POPULATION <- "ability"
MISSING_LABEL <- "missing_sem1"
QUARTILE_LEVELS <- paste0("q", seq_len(N_QUARTILES))
FROM_LEVELS <- c(QUARTILE_LEVELS, MISSING_LABEL)

## 2. 小工具 ---------------------------------------------------------------

stamp <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# 專案內的檔案以相對路徑呈現（記錄可讀；不寫死任何絕對路徑）
short_path <- function(path) {
  prefix <- paste0(PROJ_ROOT, "/")
  ifelse(startsWith(path, prefix), substring(path, nchar(prefix) + 1L), path)
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

# 記錄一律追加一段；時間戳只在段首，段內列序固定
log_block <- function(lines) {
  dir.create(dirname(LOG_PATH), recursive = TRUE, showWarnings = FALSE)
  block <- c(sprintf("== 04_ability %s ==", stamp()), lines, "")
  atomic_write(LOG_PATH, function(path) {
    previous <- if (file.exists(LOG_PATH)) readLines(LOG_PATH, warn = FALSE) else character()
    writeLines(c(previous, block), path, useBytes = TRUE)
  })
}

# 拒絕：先寫理由與下一步，再以非零結束碼停止；既有表不動（不覆寫）
refuse <- function(reason, next_step) {
  log_block(c(
    sprintf("input: %s", short_path(CLEAN_PATH)),
    "status: refuse:empty-denominator",
    sprintf("reason: %s", reason),
    sprintf("next_step: %s", next_step),
    "products_untouched: ability_quartiles.csv、ability_transitions.csv"
  ))
  stop(
    sprintf("refuse:empty-denominator\n- %s\n- 下一步：%s", reason, next_step),
    call. = FALSE
  )
}

## 3. 等量切組 -------------------------------------------------------------

# equal_split(score, groups)：等量切 groups 組，回傳與 score 同長度的組號（1..groups）。
#
# 排序為升冪的 radix 穩定排序：同分者保持 score 的原始次序（此處即清洗資料集的
# 原始列序），故切分結果不依賴 R 的排序實作細節。組寬取 floor(n / groups)，
# 餘數全部收進末組；不取任何分位數切點。
equal_split <- function(score, groups) {
  n <- length(score)
  placement <- order(score, method = "radix")
  width <- n %/% groups
  membership <- integer(n)
  for (g in seq_len(groups - 1L)) {
    membership[placement[((g - 1L) * width + 1L):(g * width)]] <- g
  }
  membership[placement[((groups - 1L) * width + 1L):n]] <- groups
  membership
}

## 4. 讀清洗資料集 ---------------------------------------------------------

if (!file.exists(CLEAN_PATH)) {
  stop(
    sprintf("找不到清洗資料集 %s；先執行 Rscript programs/R/01_prep_data.R。", short_path(CLEAN_PATH)),
    call. = FALSE
  )
}

clean <- utils::read.csv(CLEAN_PATH, check.names = FALSE, stringsAsFactors = FALSE)
missing_cols <- setdiff(REQUIRED_COLS, names(clean))
if (length(missing_cols)) {
  stop(
    sprintf("清洗資料集缺欄：%s", paste(missing_cols, collapse = " | ")),
    call. = FALSE
  )
}

## 5. 能力母體 -------------------------------------------------------------

result <- as.character(clean[[RESULT_COL]])
sem1_grade <- clean[[SEM1_COL]]
sem2_grade <- clean[[SEM2_COL]]

in_analysis <- result %in% ANALYSIS_RESULTS
# 第二學期成績嚴格大於門檻才算「有成績」；零分是「無成績」，不是低能力（PRD D4）
has_sem2 <- sem2_grade > ABILITY_MIN_SCORE

analysis_n <- sum(in_analysis)
ability_index <- which(in_analysis & has_sem2)
ability_n <- length(ability_index)
# 被剔除人數：分析母體中第二學期成績為零者（本在能力母體之外）
excluded_n <- analysis_n - ability_n
excluded_dropout_n <- sum(in_analysis & !has_sem2 & result == "Dropout")

if (ability_n < N_QUARTILES) {
  refuse(
    sprintf(
      "剔除零成績後母體為 %d 人，不足以等量切成 %d 組（分析母體 %d 人、其中第二學期零分 %d 人）",
      ability_n, N_QUARTILES, analysis_n, excluded_n
    ),
    "確認清洗資料集是契約界定的那一份（第二學期成績欄有值且大於門檻）後重跑。"
  )
}

## 6. 第二學期等量切四組與畢業率 -------------------------------------------

sem2_ability <- sem2_grade[ability_index]
quartile2 <- equal_split(sem2_ability, N_QUARTILES)
graduate <- result[ability_index] == GRADUATE
# 清洗資料集的原始列序即同分時的次序，記錄下來供比對
row_order <- ability_index

quartile_n <- tabulate(quartile2, nbins = N_QUARTILES)
quartile_graduates <- vapply(
  seq_len(N_QUARTILES),
  function(g) sum(graduate[quartile2 == g]),
  integer(1)
)
quartile_rate <- quartile_graduates / quartile_n

quartiles <- data.frame(
  population = POPULATION,
  quartile = QUARTILE_LEVELS,
  n = as.integer(quartile_n),
  graduation_rate = as.numeric(quartile_rate),
  stringsAsFactors = FALSE
)

# 內部不變量：四組人數相加即能力母體（等量切法下每組同寬或為末組的餘數）
if (sum(quartiles$n) != ability_n) {
  stop(
    sprintf("分位表人數合計 %d 與能力母體 %d 不符", sum(quartiles$n), ability_n),
    call. = FALSE
  )
}

## 7. 第一學期等量切四組與移動表 -------------------------------------------

# 第一學期只在「有第一學期成績」的人上切；缺成績者單列 missing_sem1
has_sem1 <- sem1_grade[ability_index] > ABILITY_MIN_SCORE
sem1_n <- sum(has_sem1)
sem1_missing_n <- ability_n - sem1_n

quartile1 <- integer(ability_n)
if (sem1_n >= N_QUARTILES) {
  quartile1[has_sem1] <- equal_split(sem1_grade[ability_index][has_sem1], N_QUARTILES)
} else if (sem1_n > 0L) {
  # 有第一學期成績者不足四組時，等量切法無法定義；以同一拒絕類別停止
  refuse(
    sprintf("有第一學期成績者僅 %d 人，不足以等量切成 %d 組", sem1_n, N_QUARTILES),
    "確認第一學期成績欄後重跑。"
  )
}

from <- ifelse(has_sem1, paste0("q", quartile1), MISSING_LABEL)

# 寬表：列為第一學期的組（q1–q4 與 missing_sem1），欄為第二學期的四組
transitions <- data.frame(
  population = POPULATION,
  from_sem1 = FROM_LEVELS,
  stringsAsFactors = FALSE
)
for (g in seq_len(N_QUARTILES)) {
  transitions[[paste0("to_q", g)]] <- as.integer(vapply(
    FROM_LEVELS,
    function(level) sum(from == level & quartile2 == g),
    integer(1)
  ))
}
transitions$n <- as.integer(rowSums(transitions[paste0("to_q", seq_len(N_QUARTILES))]))

# 內部不變量：列合計回到能力母體，欄合計即第二學期的四組人數
if (sum(transitions$n) != ability_n) {
  stop(
    sprintf("移動表列合計 %d 與能力母體 %d 不符", sum(transitions$n), ability_n),
    call. = FALSE
  )
}
column_totals <- vapply(paste0("to_q", seq_len(N_QUARTILES)), function(col) sum(transitions[[col]]), integer(1))
if (!identical(as.integer(column_totals), as.integer(quartile_n))) {
  stop(
    sprintf("移動表欄合計（%s）與第二學期四組人數（%s）不符",
            paste(column_totals, collapse = "/"), paste(quartile_n, collapse = "/")),
    call. = FALSE
  )
}

## 8. 寫表 -----------------------------------------------------------------

atomic_write(QUARTILE_PATH, function(path) readr::write_csv(quartiles, path))
atomic_write(TRANSITION_PATH, function(path) readr::write_csv(transitions, path))

## 9. 記錄 -----------------------------------------------------------------

log_block(c(
  sprintf("r_version: %s", R.version.string),
  sprintf("proj_root: %s", PROJ_ROOT),
  sprintf("out_root: %s", OUT_ROOT),
  sprintf("input: %s", short_path(CLEAN_PATH)),
  sprintf("input_rows: %d", nrow(clean)),
  sprintf("population: %s %d（分析母體 %d ∩ %s > %s）",
          POPULATION, ability_n, analysis_n, SEM2_COL, format(ABILITY_MIN_SCORE)),
  sprintf("excluded_zero_sem2: %d（分析母體中第二學期成績為零；其中退學 %d）",
          excluded_n, excluded_dropout_n),
  sprintf("excluded_share_of_analysis: %s", fmt_sig(excluded_n / analysis_n)),
  "split_method: 等量切組（equal_split）— 成績升冪、order(method = \"radix\") 穩定排序、",
  "  同分依清洗資料集原始列序、組寬 floor(n / groups)、餘數全收末組",
  sprintf("quartile_groups: %d（N_QUARTILES）", N_QUARTILES),
  "quantile_cutpoints: 不使用 quantile() 切點（分位數切點法與釘值不符，見任務檔 T06 步驟 2 與 V05）",
  sprintf("sem2_quartile_n: %s", paste(quartile_n, collapse = "/")),
  sprintf("sem2_quartile_graduates: %s", paste(quartile_graduates, collapse = "/")),
  sprintf("sem2_quartile_graduation_rate: %s（呈現值；表存未格式化 double）",
          paste(fmt_sig(quartile_rate), collapse = "/")),
  sprintf("sem2_quartile_rate_range: %s 至 %s（首尾差 %s 個百分點）",
          fmt_sig(min(quartile_rate)), fmt_sig(max(quartile_rate)),
          fmt_sig(100 * (max(quartile_rate) - min(quartile_rate)))),
  sprintf("sem1_quartile_basis: %d 人（能力母體中有第一學期成績者）", sem1_n),
  sprintf("sem1_quartile_n: %s（組寬 floor(n / %d)，末組收餘）",
          paste(tabulate(quartile1[has_sem1], nbins = N_QUARTILES), collapse = "/"), N_QUARTILES),
  sprintf("sem1_missing: %d 人（第一學期成績為 %s，單列 %s）",
          sem1_missing_n, format(ABILITY_MIN_SCORE), MISSING_LABEL),
  sprintf("from_levels: %s", paste(FROM_LEVELS, collapse = ", ")),
  sprintf("transition_shape: 5 列 × 4 個計數欄共 20 格（加 population、from_sem1、n 為 %d 欄）", ncol(transitions)),
  sprintf("transition_row_totals: %s（合計 %d）",
          paste(sprintf("%s=%d", transitions$from_sem1, transitions$n), collapse = ", "),
          sum(transitions$n)),
  sprintf("transition_col_totals: %s（每欄等於第二學期該組人數）",
          paste(sprintf("to_q%d=%d", seq_len(N_QUARTILES), column_totals), collapse = ", ")),
  sprintf("tie_order: 同分依清洗資料集原始列序；能力母體所在列索引為 %d 至 %d", min(row_order), max(row_order)),
  "value_scale: graduation_rate 為 0 至 1 的比率（非百分比）",
  "table_precision: 表存未格式化 double 與整數計數（D9），四位有效數字只在記錄與呈現層",
  sprintf("product: %s rows=%d", short_path(QUARTILE_PATH), nrow(quartiles)),
  sprintf("product: %s rows=%d", short_path(TRANSITION_PATH), nrow(transitions)),
  "status: ok",
  "next_step: 05_models.R 讀 ability_quartiles.csv 的分組，02_wealth.R 起可讀清洗資料集"
))

cat(sprintf("04_ability: 能力母體 %d（分析母體 %d，剔除第二學期零分 %d）\n",
            ability_n, analysis_n, excluded_n))
cat(sprintf("04_ability: 第二學期四組 %s；畢業率 %s\n",
            paste(quartile_n, collapse = "/"), paste(fmt_sig(quartile_rate), collapse = "/")))
cat(sprintf("04_ability: 移動表 %d 列 × %d 個計數欄（寬表 %d 欄）；列合計 %s；欄合計 %s\n",
            nrow(transitions), N_QUARTILES, ncol(transitions),
            paste(transitions$n, collapse = "/"), paste(column_totals, collapse = "/")))
cat(sprintf("04_ability: 表 %s、%s\n", short_path(QUARTILE_PATH), short_path(TRANSITION_PATH)))
