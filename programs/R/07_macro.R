# 07_macro.R — 宏觀三欄的值域與角色（F8）
#
# 一條指令做三件事：以 (Unemployment rate, Inflation rate, GDP) 三元組建立十個年度
# 區塊、逐 (variable, year) 計數、寫逐值表並把三欄標為控制變數。
# 常數一律取自 00_setup.R，本檔不寫出母體人數、呈現位數或 output/ 字面路徑（REQ-A-2）。
#
# 用法（專案根目錄）：Rscript programs/R/07_macro.R
# 產物：
#   <OUT_ROOT>/tables/macro_values.csv  30 列：population、variable、value、year、
#                                       year_inferred、n、role
#   <OUT_ROOT>/logs/07_macro.log        十個三元組與其人數、各欄不同值數量、拒絕理由
#
# 年份的來源（A-17）：資料無年份欄，且列序不含年份資訊——相鄰列的宏觀值隨機交替，
# 故不得以列序推定。改以三元組為鍵：十個互異的三元組各對應一個年度，對應表見下節
# YEAR_BY_TRIPLET，鍵為三元組、值為年度；year_inferred = TRUE 記的就是這件事。
# 同一數值可跨年（Inflation rate 的 1.4 在 2010 與 2017），故列鍵是 (variable, year)
# 而不是 (variable, value)：全表 30 列而非 29。
#
# 拒絕：某欄不同值多於人數的十分之一時 refuse:input-schema，記錄寫明實測值後停止，
# 表不被覆寫；三元組不在對應表內時同類拒絕（年份無從推定，不得靜默留空）。

## 0. 由 00_setup.R 取得常數 -------------------------------------------------

source(file.path(here::here("programs", "R", "00_setup.R")))

## 1. 路徑與形狀 -----------------------------------------------------------

# 清洗資料集由 T02 產出（data/processed，不是輸出目錄）：分析腳本只讀它，不讀 output/。
CLEAN_PATH <- file.path(PROJ_ROOT, "data", "processed", "ams2640_clean.csv")
TABLE_PATH <- file.path(OUT_ROOT, "tables", "macro_values.csv")
LOG_PATH <- file.path(OUT_ROOT, "logs", "07_macro.log")

# 三欄的欄名即清洗資料集的欄名；表的 variable 欄沿用原名，使下游對得回資料集。
MACRO_VARS <- c("Unemployment rate", "Inflation rate", "GDP")

# 年度區塊數與每列固定欄位（契約界定的七欄與其順序）
EXPECTED_YEARS <- 10L
TABLE_COLS <- c("population", "variable", "value", "year", "year_inferred", "n", "role")

# 固定標記：三欄一律屬分析母體，角色一律為控制變數（PRD D6、Q37）。
POPULATION_LABEL <- "analysis"
ROLE_LABEL <- "control"

## 2. 三元組 → 年度 的對應表 -----------------------------------------------

# 鍵為完整三元組（三欄合起來唯一），值為該區塊的年度。這張表是本檔唯一的年份來源：
# 不以列序推定、不以單欄值的名次推定（年 unemployment 先升後降，單欄排序復原不了
# 時間順序）。三元組的序列與葡萄牙 2008–2017 的年度宏觀值一致（失業率在 2013 見頂
# 16.2 後回落，GDP 在 2012 觸底 -4.06 後回升），故年度標籤以 2008 起連續十年，
# 並全部標 year_inferred = TRUE：這是推定，不是資料欄位。
YEAR_BY_TRIPLET <- data.frame(
  unemployment = c(7.6, 9.4, 10.8, 12.7, 15.5, 16.2, 13.9, 12.4, 11.1, 8.9),
  inflation    = c(2.6, -0.8, 1.4, 3.7, 2.8, 0.3, -0.3, 0.5, 0.6, 1.4),
  gdp          = c(0.32, -3.12, 1.74, -1.70, -4.06, -0.92, 0.79, 1.79, 2.02, 3.51),
  year         = 2008:2017,
  stringsAsFactors = FALSE
)

# 三元組的鍵：兩位的字串，讓 1.4 與 1.40 不會被當成兩個鍵，也免去浮點相等的判定。
triplet_key <- function(unemployment, inflation, gdp) {
  paste(sprintf("%.2f", unemployment), sprintf("%.2f", inflation), sprintf("%.2f", gdp), sep = "|")
}

YEAR_BY_TRIPLET$key <- triplet_key(
  YEAR_BY_TRIPLET$unemployment, YEAR_BY_TRIPLET$inflation, YEAR_BY_TRIPLET$gdp
)
if (anyDuplicated(YEAR_BY_TRIPLET$key) || anyDuplicated(YEAR_BY_TRIPLET$year)) {
  stop("07_macro：年度對應表的三元組或年度有重複，年份無從唯一推定", call. = FALSE)
}
if (nrow(YEAR_BY_TRIPLET) != EXPECTED_YEARS) {
  stop(sprintf("07_macro：年度對應表有 %d 列，契約要求 %d 個年度", nrow(YEAR_BY_TRIPLET), EXPECTED_YEARS),
       call. = FALSE)
}

## 3. 小工具 ---------------------------------------------------------------

stamp <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# 專案內的檔案以相對路徑呈現；專案外（注入測試的暫存副本）才給絕對路徑
short_path <- function(path) {
  prefix <- paste0(PROJ_ROOT, "/")
  ifelse(startsWith(path, prefix), substring(path, nchar(prefix) + 1L), path)
}

file_state <- function(path) {
  if (!file.exists(path)) return("absent")
  info <- file.info(path)
  sprintf("%s bytes=%s", format(info$mtime, "%Y-%m-%dT%H:%M:%S%z"),
          format(info$size, scientific = FALSE))
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
  block <- c(sprintf("== 07_macro %s ==", stamp()), lines, "")
  atomic_write(LOG_PATH, function(path) {
    previous <- if (file.exists(LOG_PATH)) readLines(LOG_PATH, warn = FALSE) else character()
    writeLines(c(previous, block), path, useBytes = TRUE)
  })
}

# 拒絕：先把理由與下一步寫進記錄，再以非零結束碼停止；表不動
refuse <- function(reason, next_step) {
  log_block(c(
    sprintf("r_version: %s", R.version.string),
    sprintf("input: %s", short_path(CLEAN_PATH)),
    "status: refuse:input-schema",
    sprintf("reason: %s", reason),
    sprintf("next_step: %s", next_step)
  ))
  stop(
    sprintf("refuse:input-schema\n- %s\n- 下一步：%s", reason, next_step),
    call. = FALSE
  )
}

## 4. 讀清洗資料集與分析母體 -----------------------------------------------

if (!file.exists(CLEAN_PATH)) {
  refuse(sprintf("找不到清洗資料集 %s（由 T02 產出）", short_path(CLEAN_PATH)),
         "先跑 programs/R/01_prep_data.R 產出清洗資料集後重跑；本次未寫出任何表。")
}

clean <- tryCatch(
  readr::read_csv(CLEAN_PATH, show_col_types = FALSE, progress = FALSE),
  error = function(e) e
)
if (inherits(clean, "error")) {
  refuse(sprintf("清洗資料集無法解析：%s", conditionMessage(clean)),
         "重跑 programs/R/01_prep_data.R 後再試；本次未寫出任何表。")
}

missing_cols <- setdiff(c(MACRO_VARS, "target"), names(clean))
if (length(missing_cols)) {
  refuse(sprintf("清洗資料集缺欄：%s", paste(missing_cols, collapse = ", ")),
         "確認輸入是 T02 產出的清洗資料集後重跑；本次未寫出任何表。")
}
non_numeric <- MACRO_VARS[!vapply(clean[MACRO_VARS], is.numeric, logical(1))]
if (length(non_numeric)) {
  refuse(sprintf("宏觀欄不是數值欄：%s", paste(non_numeric, collapse = ", ")),
         "檢查清洗資料集這幾欄的內容後重跑；本次未寫出任何表。")
}

# 母體界線取自 00_setup.R：結果欄限 Graduate／Dropout（在讀者不進分析母體，PRD D2）
analysis <- clean[as.character(clean$target) %in% ANALYSIS_RESULTS, , drop = FALSE]
analysis_n <- nrow(analysis)
if (analysis_n == 0L) {
  refuse("分析母體為 0 列，無法標為宏觀",
         "確認結果欄的類別值後重跑；本次未寫出任何表。")
}
if (analysis_n != ANALYSIS_N) {
  refuse(sprintf("分析母體為 %d 列，00_setup.R 釘值為 %d；這份輸入已不是研究界定的那一群",
                 analysis_n, ANALYSIS_N),
         "換回契約界定的那一份清洗資料集後重跑；本次未寫出任何表。")
}

## 5. 值域檢查：某欄不同值多於人數的十分之一即拒絕 -------------------------

# 三欄各只有九至十個值，每個值由數百人共用；不同值多於 n/10 即代表這欄不是年度層級的
# 宏觀變數（PRD F8 的 refusal path，類別 refuse:input-schema）。這一條先於年度對應，
# 因為它判的是「這欄還算不算宏觀變數」，而對應表只判「已知的宏觀值屬於哪一年」。
distinct_by_var <- vapply(MACRO_VARS, function(v) length(unique(analysis[[v]])), integer(1))
distinct_limit <- analysis_n / 10
over_limit <- MACRO_VARS[distinct_by_var > distinct_limit]
if (length(over_limit)) {
  refuse(
    sprintf("%s 不同值多於人數的十分之一（實測 %s，上限 %s，人數 %d）",
            paste(over_limit, collapse = "、"),
            paste(distinct_by_var[over_limit], collapse = "、"),
            format(distinct_limit, trim = TRUE), analysis_n),
    "確認這幾欄是年度層級的宏觀變數而非個人層欄位；門檻與量法見 PRD F8，勿改 07_macro.R 的判定；本次未寫出任何表。"
  )
}

## 6. 年度區塊：三元組 → 年度 ---------------------------------------------

# 十個互異的三元組；每個由數百人共用（PRD F8 的 boundary behaviour）
block_key <- triplet_key(analysis[[MACRO_VARS[1]]], analysis[[MACRO_VARS[2]]],
                         analysis[[MACRO_VARS[3]]])
observed_keys <- sort(unique(block_key))
unmapped <- setdiff(observed_keys, YEAR_BY_TRIPLET$key)
if (length(unmapped)) {
  refuse(sprintf("%d 個三元組不在年度對應表內：%s", length(unmapped),
                 paste(utils::head(unmapped, 5L), collapse = "; ")),
         "年度只能由三元組推定（A-17）；確認清洗資料集的宏觀欄未被改寫，或在 07_macro.R 的 YEAR_BY_TRIPLET 補上對應後重跑；本次未寫出任何表。")
}

block_n <- as.integer(table(factor(block_key, levels = YEAR_BY_TRIPLET$key)))
names(block_n) <- YEAR_BY_TRIPLET$key
block_n <- block_n[!is.na(block_n)]
if (sum(block_n) != analysis_n) {
  stop(sprintf("07_macro：年度區塊人數合計 %d 與分析母體 %d 不符", sum(block_n), analysis_n),
       call. = FALSE)
}
if (length(block_n) != EXPECTED_YEARS) {
  refuse(sprintf("三元組共 %d 組，契約要求 %d 個年度", length(block_n), EXPECTED_YEARS),
         "確認清洗資料集的宏觀三欄完整後重跑；本次未寫出任何表。")
}

## 7. 逐 (variable, year) 計數 --------------------------------------------

# 列鍵是 (variable, year)：同一數值可跨年（inflation 的 1.4 在兩個年度各一列），
# 所以列數是 3 × 10 = 30，而不是各欄不同值數之和 29。
rows <- vector("list", length(MACRO_VARS))
for (i in seq_along(MACRO_VARS)) {
  variable <- MACRO_VARS[i]
  rows[[i]] <- data.frame(
    population = rep(POPULATION_LABEL, EXPECTED_YEARS),
    variable = rep(variable, EXPECTED_YEARS),
    value = YEAR_BY_TRIPLET[[c("unemployment", "inflation", "gdp")[i]]],
    year = YEAR_BY_TRIPLET$year,
    year_inferred = rep(TRUE, EXPECTED_YEARS),
    n = block_n[YEAR_BY_TRIPLET$key],
    role = rep(ROLE_LABEL, EXPECTED_YEARS),
    stringsAsFactors = FALSE
  )
}
macro_values <- do.call(rbind, rows)
names(macro_values) <- TABLE_COLS
macro_values$year <- as.integer(macro_values$year)
macro_values$n <- as.integer(macro_values$n)
rownames(macro_values) <- NULL

if (nrow(macro_values) != length(MACRO_VARS) * EXPECTED_YEARS) {
  stop(sprintf("07_macro：表長 %d 列，契約要求 %d 列", nrow(macro_values),
               length(MACRO_VARS) * EXPECTED_YEARS), call. = FALSE)
}
# 列鍵唯一（(variable, year) 不得重複），且每欄的人數合計等於分析母體
if (anyDuplicated(paste(macro_values$variable, macro_values$year))) {
  stop("07_macro：(variable, year) 的列鍵有重複", call. = FALSE)
}
n_by_var <- vapply(MACRO_VARS, function(v) sum(macro_values$n[macro_values$variable == v]), integer(1))
if (any(n_by_var != analysis_n)) {
  stop(sprintf("07_macro：逐欄人數合計與分析母體不符（%s）",
               paste(sprintf("%s=%d", names(n_by_var), n_by_var), collapse = ", ")), call. = FALSE)
}
if (!all(macro_values$population == POPULATION_LABEL) ||
    !all(macro_values$role == ROLE_LABEL) ||
    !all(macro_values$year_inferred)) {
  stop("07_macro：population、role 或 year_inferred 未依契約寫成固定值", call. = FALSE)
}

# 同一數值跨年的情形逐項列出，供記錄與讀者核對（inflation 的 1.4 應有兩列）
cross_year_values <- local({
  out <- character()
  for (v in MACRO_VARS) {
    sub <- macro_values[macro_values$variable == v, , drop = FALSE]
    dup <- unique(sub$value[duplicated(sub$value)])
    if (length(dup)) {
      for (value in dup) {
        hit <- sub[sub$value == value, , drop = FALSE]
        out <- c(out, sprintf("%s=%s 跨 %s（%s；n 合計 %d）", v, format(value, trim = TRUE),
                              paste(hit$year, collapse = "、"),
                              paste(sprintf("n=%d", hit$n), collapse = "、"), sum(hit$n)))
      }
    }
  }
  out
})

## 8. 寫表與記錄 -----------------------------------------------------------

table_before <- file_state(TABLE_PATH)

atomic_write(TABLE_PATH, function(path) readr::write_csv(macro_values, path))

log_block(c(
  sprintf("r_version: %s", R.version.string),
  sprintf("proj_root: %s", PROJ_ROOT),
  sprintf("out_root: %s", OUT_ROOT),
  sprintf("input: %s", short_path(CLEAN_PATH)),
  sprintf("input_rows: %d", nrow(clean)),
  sprintf("analysis_rows: %d", analysis_n),
  sprintf("analysis_population_expected: %d", ANALYSIS_N),
  sprintf("population: %s", POPULATION_LABEL),
  sprintf("role: %s", ROLE_LABEL),
  sprintf("year_inferred: TRUE（資料無年份欄，列序不含年份資訊；年度由三元組對應推定，A-17）"),
  sprintf("year_rule: 以 (Unemployment rate, Inflation rate, GDP) 三元組為鍵，十個互異三元組各對應一個年度 %d–%d；不以列序推定",
          min(YEAR_BY_TRIPLET$year), max(YEAR_BY_TRIPLET$year)),
  sprintf("distinct_values: %s", paste(sprintf("%s=%d", MACRO_VARS, distinct_by_var), collapse = ", ")),
  sprintf("distinct_limit: %s（人數 %d 的十分之一；某欄多於此值即 refuse:input-schema）",
          format(distinct_limit, trim = TRUE), analysis_n),
  sprintf("distinct_check: %s", if (length(over_limit)) "refuse" else "ok"),
  sprintf("blocks: %d 個年度區塊，人數合計 %d", length(block_n), sum(block_n)),
  "triplets (year, 三元組, n):",
  vapply(seq_len(nrow(YEAR_BY_TRIPLET)), function(i) {
    sprintf("- triplet: year=%d unemployment=%s inflation=%s gdp=%s n=%d",
            YEAR_BY_TRIPLET$year[i],
            format(YEAR_BY_TRIPLET$unemployment[i], trim = TRUE),
            format(YEAR_BY_TRIPLET$inflation[i], trim = TRUE),
            format(YEAR_BY_TRIPLET$gdp[i], trim = TRUE),
            block_n[[YEAR_BY_TRIPLET$key[i]]])
  }, character(1)),
  sprintf("rows: %d（%d 欄 × %d 年度）", nrow(macro_values), length(MACRO_VARS), EXPECTED_YEARS),
  sprintf("n_by_variable: %s", paste(sprintf("%s=%d", MACRO_VARS, n_by_var), collapse = ", ")),
  if (length(cross_year_values)) c("cross_year_values:", paste0("- ", cross_year_values)) else
    "cross_year_values: none",
  sprintf("product: %s before=%s after=%s", short_path(TABLE_PATH), table_before,
          file_state(TABLE_PATH)),
  "status: ok",
  "next_step: 07 之後由模型與審核表引用此表；三欄以控制變數身分進入，不作主效應（PRD D6、Q37）"
))

cat(sprintf("07_macro: %d 列（%d 欄 x %d 年度）-> %s\n", nrow(macro_values),
            length(MACRO_VARS), EXPECTED_YEARS, short_path(TABLE_PATH)))
cat(sprintf("07_macro: 不同值數量 %s（上限 %s）\n",
            paste(sprintf("%s=%d", MACRO_VARS, distinct_by_var), collapse = "、"),
            format(distinct_limit, trim = TRUE)))
cat(sprintf("07_macro: 年度區塊 %d 個，人數 %s\n", length(block_n),
            paste(sprintf("%d=%d", YEAR_BY_TRIPLET$year, block_n[YEAR_BY_TRIPLET$key]), collapse = " ")))
cat(sprintf("07_macro: 三欄皆 role=%s、population=%s；year_inferred 全為 TRUE\n",
            ROLE_LABEL, POPULATION_LABEL))
