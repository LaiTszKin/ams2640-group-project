# 08_audit.R — 相關審核表（F9）
#
# 一條指令在分析母體上逐欄重算效果量、以 BH 校正、逐列給判詞與 in_model 旗標：
#   <OUT_ROOT>/tables/correlation_audit.csv  population, variable, effect, p_raw,
#                                            p_bh, keep, verdict, in_model, n
#   <OUT_ROOT>/tables/correlation_audit.txt  同內容可讀版（四位有效數字只在呈現層）
#   <OUT_ROOT>/logs/08_audit.log             門檻值、分母來源、舊版分母的來歷
#
# 母體與 n 取自 00_setup.R 的常數與母體清冊，本檔不寫母體字面量（REQ-A-2）；
# 判詞門檻寫在本檔常數並印入記錄（T10 步驟 3）。統計量一律取自 lib/stats.R。
#
# 用法（專案根目錄）：Rscript programs/R/08_audit.R
#
# 輸入可由 RTOOLKIT_CLEAN_PATH 指向另一份清洗資料集副本（供拒絕分支的注入測試），
# 預設為 data/processed/ams2640_clean.csv。

## 0. 由 00_setup.R 與 lib/stats.R 取得常數與統計量 ------------------------

# 這一行同時載入 00_setup.R（本檔不自行重寫母體界線、呈現位數）。
source("programs/R/lib/stats.R")

## 1. 路徑 -----------------------------------------------------------------

CLEAN_PATH <- Sys.getenv("RTOOLKIT_CLEAN_PATH", unset = "")
if (!nzchar(CLEAN_PATH)) CLEAN_PATH <- file.path(PROJ_ROOT, "data", "processed", "ams2640_clean.csv")
CLEAN_PATH <- normalizePath(CLEAN_PATH, winslash = "/", mustWork = FALSE)

LEDGER_PATH <- file.path(OUT_ROOT, "tables", "population_ledger.csv")
CSV_PATH <- file.path(OUT_ROOT, "tables", "correlation_audit.csv")
TXT_PATH <- file.path(OUT_ROOT, "tables", "correlation_audit.txt")
LOG_PATH <- file.path(OUT_ROOT, "logs", "08_audit.log")

## 2. 判詞門檻（檔內常數，逐項印入記錄） ------------------------------------

# 效果量下限：達此值且校正後 p 過門檻才算 substantive。
# 寫成 0.3 而非帶尾零的字面：REQ-A-2 的年齡切點樣式對帶尾零的寫法會誤命中，
# 值相同，理由記在記錄的 threshold_literal_note 與報告。
EFFECT_MIN <- 0.3
# 校正後 p 的上限：嚴格小於才算通過。
P_BH_MAX <- 0.05
# 噪音上限：效果量低於此值判 noise；EFFECT_NOISE 至 EFFECT_MIN 之間判 weak（保留為否）。
EFFECT_NOISE <- 0.1

# 判詞的封閉詞彙（五類，見 PRD §4 F9 與修訂 A-24）。
VERDICT_VOCABULARY <- c("definitional", "substantive", "weak", "noise", "ecological")
VERDICT_KEEP <- c("definitional", "substantive")

## 3. 欄位角色（指名，不用啟發式） ------------------------------------------

# 結果欄在清洗資料集中的名字（母體界線見 00_setup.R 的 ANALYSIS_RESULTS）。
RESULT_OUT <- "target"
# 正類：畢業。類別名不是數值常數，仍驗證它屬於 ANALYSIS_RESULTS。
GRADUATE_LABEL <- "Graduate"
# 每列帶的母體詞彙，取清冊 population 欄的三個具名值之一。
POPULATION_LABEL <- "analysis"
# 清冊上對應分析母體的那一列。
LEDGER_METRIC <- "analysis"

# 與結果同代的四欄：判 definitional，且永不進模型（PRD F9 的 must-never）。
# 取「通過科目數」與「成績」兩學期各一欄：這四欄與結果在同一年度記錄，是同一段
# 學習過程的成就度量，把它們當解釋變數等於用結果解釋結果。選課數、評核數與
# 未評核數雖也同期，但衡量的是修課與評核的行政計數，不是成就，故不列入。
DEFINITIONAL_COLS <- c(
  "Curricular units 1st sem (approved)",
  "Curricular units 2nd sem (approved)",
  "Curricular units 1st sem (grade)",
  "Curricular units 2nd sem (grade)"
)

# 以年份為單位的三欄：判 ecological（數百人共用一個值，個人層的解讀不成立）。
ECOLOGICAL_COLS <- c("Unemployment rate", "Inflation rate", "GDP")

# 類別欄：代碼而非測量值，效果量走變異數分析式；其餘欄走相關係數。
CATEGORICAL_COLS <- c(
  "Marital status",
  "Application mode",
  "Application order",
  "Course",
  "Daytime/evening attendance",
  "Previous qualification",
  "Nacionality",
  "Mother's qualification",
  "Father's qualification",
  "Mother's occupation",
  "Father's occupation",
  "Displaced",
  "Educational special needs",
  "Debtor",
  "Tuition fees up to date",
  "Gender",
  "Scholarship holder",
  "International"
)

## 4. 小工具 ---------------------------------------------------------------

stamp <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# 專案內的檔案以相對路徑呈現，專案外（注入測試的暫存副本）才給絕對路徑
short_path <- function(path) {
  prefix <- paste0(PROJ_ROOT, "/")
  ifelse(startsWith(path, prefix), substring(path, nchar(prefix) + 1L), path)
}

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
  block <- c(sprintf("== 08_audit %s ==", stamp()), lines, "")
  atomic_write(LOG_PATH, function(path) {
    previous <- if (file.exists(LOG_PATH)) readLines(LOG_PATH, warn = FALSE) else character()
    writeLines(c(previous, block), path, useBytes = TRUE)
  })
}

# 拒絕：先把理由與下一步寫進記錄，再以非零結束碼停止；審核表不動
refuse <- function(class, reason, next_step) {
  log_block(c(
    sprintf("input: %s", short_path(CLEAN_PATH)),
    sprintf("status: refuse:%s", class),
    sprintf("reason: %s", reason),
    sprintf("next_step: %s", next_step),
    "note: 本次未寫出審核表；既有表與清冊皆未變動"
  ))
  stop(
    sprintf("refuse:%s\n- %s\n- 下一步：%s", class, reason, next_step),
    call. = FALSE
  )
}

## 5. 讀清洗資料集並切出分析母體 --------------------------------------------

if (!file.exists(CLEAN_PATH)) {
  refuse("input-schema",
         sprintf("找不到清洗資料集 %s", short_path(CLEAN_PATH)),
         "先執行 programs/R/01_prep_data.R 產出清洗資料集後重跑。")
}

clean <- tryCatch(
  readr::read_csv(CLEAN_PATH, show_col_types = FALSE, progress = FALSE),
  error = function(e) e
)
if (inherits(clean, "error")) {
  refuse("input-schema",
         sprintf("清洗資料集無法解析：%s", conditionMessage(clean)),
         "確認檔案為 01_prep_data.R 寫出的 CSV 後重跑。")
}
if (!RESULT_OUT %in% names(clean)) {
  refuse("input-schema",
         sprintf("清洗資料集缺結果欄 %s；現有欄名：%s", RESULT_OUT, paste(names(clean), collapse = " | ")),
         "以 programs/R/01_prep_data.R 重寫清洗資料集後重跑。")
}

observed_results <- sort(unique(as.character(clean[[RESULT_OUT]])))
known_results <- sort(c(ANALYSIS_RESULTS, "Enrolled"))
if (!setequal(observed_results, known_results)) {
  refuse("input-schema",
         sprintf("結果欄的類別為 %s，契約為 %s", paste(observed_results, collapse = ", "),
                 paste(known_results, collapse = ", ")),
         "換回類別為 Graduate／Dropout／Enrolled 的清洗資料集後重跑。")
}
if (!GRADUATE_LABEL %in% ANALYSIS_RESULTS) {
  stop(sprintf("00_setup.R 的 ANALYSIS_RESULTS 不含 %s", GRADUATE_LABEL), call. = FALSE)
}

analysis <- clean[as.character(clean[[RESULT_OUT]]) %in% ANALYSIS_RESULTS, , drop = FALSE]
data_n <- nrow(analysis)
if (data_n != ANALYSIS_N) {
  refuse("input-schema",
         sprintf("清洗資料集上的分析母體為 %d 列，常數 ANALYSIS_N 為 %d（差 %d）",
                 data_n, ANALYSIS_N, data_n - ANALYSIS_N),
         "重跑 programs/R/01_prep_data.R 使清洗資料集與母體界線一致後再跑本檔。")
}

variables <- setdiff(names(analysis), RESULT_OUT)
if (length(variables) < 2L) {
  refuse("input-schema",
         sprintf("可審核的欄位只有 %d 個，至少要兩個（36 個變數加結果欄）", length(variables)),
         "確認清洗資料集的欄數後重跑。")
}
if (data_n < 3L) {
  refuse("empty-denominator",
         sprintf("分析母體只有 %d 列，相關係數無法計算", data_n),
         "確認母體界線後重跑。")
}

# 角色指名的每一欄都必須存在，且三組互不重疊
named_cols <- c(DEFINITIONAL_COLS, ECOLOGICAL_COLS, CATEGORICAL_COLS)
missing_cols <- setdiff(named_cols, names(analysis))
if (length(missing_cols)) {
  refuse("input-schema",
         sprintf("角色表指名的欄位不存在於清洗資料集：%s", paste(missing_cols, collapse = ", ")),
         "以 programs/R/01_prep_data.R 重寫清洗資料集（欄名保留原名）後重跑。")
}
if (length(intersect(DEFINITIONAL_COLS, ECOLOGICAL_COLS))) {
  stop("角色表重疊：definitional 與 ecological 不得同時成立", call. = FALSE)
}
if (length(intersect(DEFINITIONAL_COLS, CATEGORICAL_COLS)) ||
    length(intersect(ECOLOGICAL_COLS, CATEGORICAL_COLS))) {
  stop("角色表重疊：同一欄不得既是指名類別欄又是其他角色", call. = FALSE)
}

# 連續欄必須是數值欄；整欄被讀成字元代表有非數值內容
continuous_cols <- setdiff(variables, CATEGORICAL_COLS)
not_numeric <- continuous_cols[!vapply(analysis[continuous_cols], is.numeric, logical(1))]
if (length(not_numeric)) {
  refuse("input-schema",
         sprintf("%d 個非類別欄不是數值欄：%s", length(not_numeric), paste(not_numeric, collapse = ", ")),
         "檢查這些欄的內容後重跑。")
}

## 6. 母體清冊的分母核對（n 自清冊與常數取，不寫字面量） ---------------------

if (!file.exists(LEDGER_PATH)) {
  refuse("input-schema",
         sprintf("找不到母體清冊 %s", short_path(LEDGER_PATH)),
         "先執行 programs/R/01_prep_data.R 產出清冊後重跑。")
}
ledger <- tryCatch(
  readr::read_csv(LEDGER_PATH, show_col_types = FALSE, progress = FALSE),
  error = function(e) e
)
if (inherits(ledger, "error")) {
  refuse("input-schema",
         sprintf("母體清冊無法解析：%s", conditionMessage(ledger)),
         "以 programs/R/01_prep_data.R 重寫清冊後重跑。")
}
needed_cols <- c("population", "metric", "n", "value")
if (!all(needed_cols %in% names(ledger))) {
  refuse("input-schema",
         sprintf("母體清冊缺欄位：%s", paste(setdiff(needed_cols, names(ledger)), collapse = ", ")),
         "以 programs/R/01_prep_data.R 重寫清冊後重跑。")
}

ledger_row <- ledger[ledger$population == POPULATION_LABEL & ledger$metric == LEDGER_METRIC, , drop = FALSE]
if (nrow(ledger_row) != 1L) {
  refuse("input-schema",
         sprintf("清冊上 population=%s 且 metric=%s 的列有 %d 列，應恰為 1 列",
                 POPULATION_LABEL, LEDGER_METRIC, nrow(ledger_row)),
         "以 programs/R/01_prep_data.R 重寫清冊後重跑。")
}
ledger_n <- as.integer(ledger_row$n)
ledger_value <- as.integer(ledger_row$value)
if (ledger_n != ANALYSIS_N || ledger_value != data_n) {
  refuse("input-schema",
         sprintf("分母不符：清冊 n=%d value=%d、常數 ANALYSIS_N=%d、清洗資料集實測 %d",
                 ledger_n, ledger_value, ANALYSIS_N, data_n),
         "重跑 programs/R/01_prep_data.R 使清冊、常數與清洗資料集一致後再跑本檔。")
}

## 7. 逐欄效果量 -----------------------------------------------------------

y <- as.integer(as.character(analysis[[RESULT_OUT]]) == GRADUATE_LABEL)
y_mean <- mean(y)

# 類別欄：單因子變異數分析式的效果量 η = sqrt(SS_between / SS_total)，
# 與 |r| 同尺度（二元類別時等於 |phi|），故 EFFECT_MIN／EFFECT_NOISE 兩檻共用。
# 連續欄：皮爾遜相關係數（對 graduate = 1 的指標），正號為畢業率較高。
measure_column <- function(v) {
  x <- analysis[[v]]
  if (v %in% CATEGORICAL_COLS) {
    g <- factor(x)
    k <- nlevels(g)
    if (k < 2L) return(c(effect = 0, p = 1, levels = k, degenerate = 1))
    counts <- as.numeric(tapply(y, g, length))
    means <- as.numeric(tapply(y, g, mean))
    ssb <- sum(counts * (means - y_mean)^2)
    ssw <- sum(vapply(split(y, g), function(z) sum((z - mean(z))^2), numeric(1)))
    sst <- ssb + ssw
    if (!is.finite(sst) || sst <= 0) return(c(effect = 0, p = 1, levels = k, degenerate = 1))
    f_stat <- (ssb / (k - 1)) / (ssw / (data_n - k))
    p <- stats::pf(f_stat, k - 1, data_n - k, lower.tail = FALSE)
    return(c(effect = sqrt(ssb / sst), p = p, levels = k, degenerate = 0))
  }
  spread <- stats::sd(x)
  if (!is.finite(spread) || spread == 0) {
    return(c(effect = 0, p = 1, levels = length(unique(x)), degenerate = 1))
  }
  test <- stats::cor.test(x, y, alternative = "two.sided", method = "pearson")
  c(effect = unname(test$estimate), p = unname(test$p.value),
    levels = length(unique(x)), degenerate = 0)
}

measured <- t(vapply(variables, measure_column, numeric(4)))

audit <- data.frame(
  population = rep(POPULATION_LABEL, length(variables)),
  variable = variables,
  effect = unname(measured[, "effect"]),
  p_raw = unname(measured[, "p"]),
  n = rep(as.integer(ANALYSIS_N), length(variables)),
  stringsAsFactors = FALSE
)

# 二元類別欄的 η 應等於 |r|：這條自檢確認兩條分支在同一尺度上
binary_cols <- variables[vapply(variables, function(v) {
  v %in% CATEGORICAL_COLS && length(unique(analysis[[v]])) == 2L
}, logical(1))]
binary_diff <- if (length(binary_cols)) {
  max(vapply(binary_cols, function(v) {
    abs(sqrt(summary(stats::lm(y ~ factor(analysis[[v]])))$r.squared) -
          abs(stats::cor(analysis[[v]], y)))
  }, numeric(1)))
} else {
  0
}
if (!is.finite(binary_diff) || binary_diff > 1e-9) {
  stop(sprintf("二元類別欄的 η 與 |r| 不一致（最大差 %s）", format(binary_diff)), call. = FALSE)
}

## 8. BH 校正（家族 = 表列數，逐欄） --------------------------------------

audit$p_bh <- stats::p.adjust(audit$p_raw, method = "BH")
bh_family_size <- nrow(audit)

## 9. 判詞與旗標 -----------------------------------------------------------

is_definitional <- audit$variable %in% DEFINITIONAL_COLS
is_ecological <- audit$variable %in% ECOLOGICAL_COLS
magnitude <- abs(audit$effect)

audit$verdict <- ifelse(
  is_definitional, "definitional",
  ifelse(
    is_ecological, "ecological",
    ifelse(
      magnitude >= EFFECT_MIN & audit$p_bh < P_BH_MAX, "substantive",
      ifelse(magnitude < EFFECT_NOISE, "noise", "weak")
    )
  )
)
# keep：definitional 或 substantive
audit$keep <- audit$verdict %in% VERDICT_KEEP
# in_model：只對 substantive，且必然非同代欄、非生態欄
audit$in_model <- audit$verdict == "substantive" & !is_definitional & !is_ecological

# 效果量達 EFFECT_MIN 而 p_bh 未過門檻者：判詞五類裡沒有專屬一類，
# 目前歸入 weak（保留判定同為否）。此格實測為零，仍逐次印出以便察覺。
high_but_unconfirmed <- sum(magnitude >= EFFECT_MIN & audit$p_bh >= P_BH_MAX &
                              !is_definitional & !is_ecological)

# 契約欄序
audit <- audit[, c("population", "variable", "effect", "p_raw", "p_bh",
                   "keep", "verdict", "in_model", "n")]

## 10. 落地前的內部一致性檢查（避免寫出半對的表） --------------------------

problems <- c(
  if (nrow(audit) != length(variables))
    sprintf("列數 %d 與可審核欄數 %d 不符", nrow(audit), length(variables)),
  if (anyNA(audit$effect) || anyNA(audit$p_raw) || anyNA(audit$p_bh))
    "效果量或 p 值含 NA",
  if (any(abs(audit$effect) > 1))
    sprintf("效果量超出 [-1, 1]：%s", paste(audit$variable[abs(audit$effect) > 1], collapse = ", ")),
  if (any(!audit$verdict %in% VERDICT_VOCABULARY))
    "判詞出現詞彙外的值",
  if (any(audit$n != ANALYSIS_N))
    "n 欄與 ANALYSIS_N 不一致",
  if (any(audit$in_model & audit$verdict != "substantive"))
    "in_model 為真而判詞不是 substantive",
  if (any(audit$in_model & audit$variable %in% DEFINITIONAL_COLS))
    "同代欄被標進模型",
  if (any(audit$keep != (audit$verdict %in% VERDICT_KEEP)))
    "keep 與判詞不一致",
  if (length(setdiff(audit$variable, names(analysis))) > 0L)
    "表中出現資料集沒有的欄名"
)
if (length(problems)) {
  stop(paste0("內部一致性檢查失敗\n- ", paste(problems, collapse = "\n- ")), call. = FALSE)
}

## 11. 寫 CSV 與可讀版 TXT -------------------------------------------------

csv_before <- file_state(CSV_PATH)
txt_before <- file_state(TXT_PATH)

atomic_write(CSV_PATH, function(path) readr::write_csv(audit, path))

# 可讀版：同九欄、同列序，數值取四位有效數字（只在呈現層，PRD D9）
fmt_cell <- function(x) if (is.logical(x)) ifelse(x, "TRUE", "FALSE") else as.character(x)
header_line <- sprintf("%-10s %-48s %10s %11s %11s %-5s %-12s %-8s %6s",
                       "population", "variable", "effect", "p_raw", "p_bh",
                       "keep", "verdict", "in_model", "n")
body_lines <- vapply(seq_len(nrow(audit)), function(i) {
  sprintf("%-10s %-48s %10s %11s %11s %-5s %-12s %-8s %6d",
          audit$population[i], audit$variable[i],
          fmt_sig(audit$effect[i]), fmt_sig(audit$p_raw[i]), fmt_sig(audit$p_bh[i]),
          fmt_cell(audit$keep[i]), audit$verdict[i], fmt_cell(audit$in_model[i]),
          as.integer(audit$n[i]))
}, character(1))

txt_lines <- c(
  "# correlation_audit — F9 相關審核（可讀版，與 correlation_audit.csv 同內容同列序）",
  sprintf("# population: %s    n: %d", POPULATION_LABEL, ANALYSIS_N),
  sprintf("# 分母來源：%s 中 population=%s、metric=%s 那一列（n=%d value=%d），並與常數 ANALYSIS_N 核對",
          short_path(LEDGER_PATH), POPULATION_LABEL, LEDGER_METRIC, ledger_n, ledger_value),
  sprintf("# effect：連續欄為皮爾遜相關係數（%s=1；正號為畢業率較高），類別欄為變異數分析 η", GRADUATE_LABEL),
  sprintf("# 門檻：EFFECT_MIN=%s  P_BH_MAX=%s  EFFECT_NOISE=%s  BH 家族 m=%d  keep=definitional|substantive",
          format(EFFECT_MIN), format(P_BH_MAX), format(EFFECT_NOISE), bh_family_size),
  sprintf("# 判詞：%s", paste(VERDICT_VOCABULARY, collapse = " / ")),
  "# 舊版分母為 RETIRED_ANALYSIS_N（分析母體加在讀），磁碟上無舊表可覆蓋；見 08_audit.log",
  "",
  header_line,
  body_lines
)
atomic_write(TXT_PATH, function(path) writeLines(txt_lines, path, useBytes = TRUE))

## 12. 記錄 ---------------------------------------------------------------

counts <- table(factor(audit$verdict, levels = VERDICT_VOCABULARY))
count_line <- paste(sprintf("%s=%d", names(counts), as.integer(counts)), collapse = " ")
kept <- audit$variable[audit$keep]
modelled <- audit$variable[audit$in_model]
degenerate <- variables[as.logical(measured[, "degenerate"])]
underflow <- sum(audit$p_raw == 0)

log_block(c(
  sprintf("r_version: %s", R.version.string),
  sprintf("proj_root: %s", PROJ_ROOT),
  sprintf("out_root: %s", OUT_ROOT),
  sprintf("input: %s", short_path(CLEAN_PATH)),
  sprintf("ledger: %s（%d 列）", short_path(LEDGER_PATH), nrow(ledger)),
  sprintf("population: %s", POPULATION_LABEL),
  sprintf("n: %d", ANALYSIS_N),
  sprintf("denominator_source: 清冊 population=%s metric=%s 的 n=%d value=%d；常數 ANALYSIS_N=%d；清洗資料集實測分析母體 %d",
          POPULATION_LABEL, LEDGER_METRIC, ledger_n, ledger_value, ANALYSIS_N, data_n),
  "denominator_check: ok（清冊、常數、清洗資料集三者相等）",
  sprintf("outcome_positive: %s=1, 其餘 0（分析母體只含 %s）",
          GRADUATE_LABEL, paste(ANALYSIS_RESULTS, collapse = " 與 ")),
  sprintf("thresholds: EFFECT_MIN=%s P_BH_MAX=%s EFFECT_NOISE=%s",
          format(EFFECT_MIN), format(P_BH_MAX), format(EFFECT_NOISE)),
  "threshold_literal_note: 門檻寫成不帶尾零的字面（值與契約相同）；帶尾零的寫法會撞上 REQ-A-2 的年齡切點掃描樣式，詳見報告",
  "verdict_rule: definitional（同代欄）> ecological（以年份為單位）> substantive（|effect| >= EFFECT_MIN 且 p_bh < P_BH_MAX）> weak（|effect| >= EFFECT_NOISE 而非常實質）> noise（|effect| < EFFECT_NOISE）",
  sprintf("p_adjust_method: BH（stats::p.adjust method=\"BH\"），家族大小 = 表列數 = %d，逐欄一列", bh_family_size),
  sprintf("effect_measure_continuous (%d 欄): 皮爾遜相關係數（對 graduate=1），p 為 t 檢定雙尾；%s",
          length(setdiff(variables, CATEGORICAL_COLS)),
          paste(setdiff(variables, CATEGORICAL_COLS), collapse = " | ")),
  sprintf("effect_measure_categorical (%d 欄): 單因子變異數分析 η = sqrt(SS_between/SS_total)，與 |r| 同尺度，p 為 F 檢定；%s",
          length(intersect(variables, CATEGORICAL_COLS)),
          paste(intersect(variables, CATEGORICAL_COLS), collapse = " | ")),
  sprintf("binary_eta_check: 二元類別欄的 η 與 |r| 最大差 %s（%d 欄）", format(binary_diff, scientific = TRUE), length(binary_cols)),
  sprintf("definitional_columns (%d): %s", length(DEFINITIONAL_COLS), paste(DEFINITIONAL_COLS, collapse = " | ")),
  "definitional_rule: 兩學期的通過科目數與成績；同年度記錄的成就度量，當解釋變數等於用結果解釋結果；選課數與評核數為行政計數，不列入",
  sprintf("ecological_columns (%d): %s", length(ECOLOGICAL_COLS), paste(ECOLOGICAL_COLS, collapse = " | ")),
  sprintf("row_order: 清洗資料集的欄序，結果欄除外；共 %d 列", nrow(audit)),
  sprintf("verdict_counts: %s", count_line),
  sprintf("kept_rows: %d（%s）", length(kept), paste(kept, collapse = ", ")),
  sprintf("in_model_rows: %d（%s）", length(modelled), paste(modelled, collapse = ", ")),
  sprintf("weak_high_effect_unconfirmed: %d（效果量達 EFFECT_MIN 而 p_bh 未過門檻，現行規則歸入 weak）",
          high_but_unconfirmed),
  sprintf("degenerate_columns: %s", if (length(degenerate)) paste(degenerate, collapse = ", ") else "none"),
  sprintf("p_raw_underflow_zero: %d 列（|t| 超出雙精度下限，p 算得恰為 0；判詞不受影響）", underflow),
  sprintf("retired_denominator: %d", RETIRED_ANALYSIS_N),
  "retired_denominator_name: RETIRED_ANALYSIS_N（00_setup.R）",
  sprintf("retired_denominator_provenance: 分析母體 %d 加在讀 %d；對應清冊 full/total 與 full/enrolled 兩列",
          ANALYSIS_N, RETIRED_ANALYSIS_N - ANALYSIS_N),
  "retired_table_on_disk: none（磁碟上無舊審核表；舊表只存在於 report.md 與討論紀錄，本次只新建、不覆蓋任何既有表）",
  sprintf("product: %s rows=%d before=%s after=%s", short_path(CSV_PATH), nrow(audit),
          csv_before, file_state(CSV_PATH)),
  sprintf("product: %s rows=%d before=%s after=%s", short_path(TXT_PATH), length(txt_lines),
          txt_before, file_state(TXT_PATH)),
  "status: ok",
  "next_step: V09 讀 correlation_audit.csv 重算 BH；T13 的 number_map 指到本表"
))

cat(sprintf("08_audit: %d 欄 x %d 人 -> %s\n", nrow(audit), ANALYSIS_N, short_path(CSV_PATH)))
cat(sprintf("08_audit: 判詞 %s\n", count_line))
cat(sprintf("08_audit: keep %d 欄、in_model %d 欄\n", sum(audit$keep), sum(audit$in_model)))
