# 03_age.R — F4 社會背景：年齡帶與婚配分層
#
# 一張五帶概況表、一張兩個關鍵檢定表、一張逐帶婚配分層表。帶的定義為左閉右開
# [a, b)：第一帶 <AGE_BREAKS[1]、中間各帶 [a, b)、最後一帶 [AGE_BREAKS[end], ∞)。
# 以 findInterval() 切帶而不是 cut 的預設右閉（right = TRUE）：後者會把邊界值
# 歸到下一帶的左端，切出來的帶與契約釘值不符（修訂 A-11）。
#
# 婚配映射：已婚＝婚姻狀況 2；單身＝其餘（1、3、4、5、6）。此讀法寫入記錄，
# 釘值只在此讀法下重現；改成「單身＝1」會得到另一組 p（修訂 A-11）。
#
# 逐帶三分支、互斥且依序判定：
#   ① 帶內已婚或單身人數為零 → refuse:empty-denominator，整支停止，三張表皆不產生
#   ② 四格中任一格人數低於 SMALL_CELL_MIN → 入表，p 值留空、status 為 insufficient_n
#   ③ 其餘各做一次雙尾精確檢定
# 小帶不拒絕（A-11）；拒絕只在零分母。
#
# 用法（專案根目錄或子目錄皆可）：
#   Rscript programs/R/03_age.R
# 產物：
#   <OUT_ROOT>/tables/age_bands.csv
#   <OUT_ROOT>/tables/age_tests.csv
#   <OUT_ROOT>/tables/marriage_strata.csv
#   <OUT_ROOT>/logs/03_age.log

## 0. 由 00_setup.R 取常數 ---------------------------------------------------

source(file.path(here::here("programs/R/00_setup.R")))
source(file.path(here::here("programs/R/lib/stats.R")))

## 1. 路徑與小工具 ---------------------------------------------------------

CLEAN_PATH <- file.path(PROJ_ROOT, "data", "processed", "ams2640_clean.csv")
TABLE_DIR <- file.path(OUT_ROOT, "tables")
LOG_PATH <- file.path(OUT_ROOT, "logs", "03_age.log")

BANDS_PATH <- file.path(TABLE_DIR, "age_bands.csv")
TESTS_PATH <- file.path(TABLE_DIR, "age_tests.csv")
MARRIAGE_PATH <- file.path(TABLE_DIR, "marriage_strata.csv")

# 母體標籤：三張表的 population 欄逐列填同一個值（PRD §3：每列自帶母體）。
POPULATION <- "analysis"

# 小格門檻（契約的「任一格人數低於三十」）：計數的整數下界，不是年齡切點；
# 寫成 30L 使 REQ-A-2 的年齡切點掃描不會誤讀成切點。
SMALL_CELL_MIN <- 30L

# 分析用的四個欄名（清洗資料集保留原始欄名，只有結果欄改名 target）。
COL_AGE <- "Age at enrollment"
COL_MARITAL <- "Marital status"
COL_TUITION <- "Tuition fees up to date"
COL_RESULT <- "target"

# 婚配映射：已婚固定為此值，單身取其餘全部類別。
MARRIED_VALUE <- 2L
SINGLE_VALUES <- c(1L, 3L, 4L, 5L, 6L)

# 欠繳＝學費未繳清（學費是否繳清 = 0）；編碼與 T04 相同（A-10）。
UNPAID_VALUE <- 0L

# 結果欄的退學值取自 00_setup.R 的分析母體類別。
DROPOUT_VALUE <- ANALYSIS_RESULTS[ANALYSIS_RESULTS == "Dropout"]

stamp <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# 專案內的檔案以相對路徑呈現
short_path <- function(path) {
  prefix <- paste0(PROJ_ROOT, "/")
  ifelse(startsWith(path, prefix), substring(path, nchar(prefix) + 1L), path)
}

# 先寫同目錄暫存檔再改名，半途失敗不留半份表
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

# 記錄一律追加一段；時間戳只在段首
log_block <- function(lines) {
  dir.create(dirname(LOG_PATH), recursive = TRUE, showWarnings = FALSE)
  block <- c(sprintf("== 03_age %s ==", stamp()), lines, "")
  atomic_write(LOG_PATH, function(path) {
    previous <- if (file.exists(LOG_PATH)) readLines(LOG_PATH, warn = FALSE) else character()
    writeLines(c(previous, block), path, useBytes = TRUE)
  })
}

# 拒絕：先把理由與下一步寫進記錄，再以非零結束碼停止；三張表皆不寫
refuse <- function(class, reason, next_step) {
  log_block(c(
    sprintf("input: %s", short_path(CLEAN_PATH)),
    sprintf("status: refuse:%s", class),
    sprintf("reason: %s", reason),
    sprintf("next_step: %s", next_step)
  ))
  stop(
    sprintf("refuse:%s\n- %s\n- 下一步：%s", class, reason, next_step),
    call. = FALSE
  )
}

## 2. 帶的定義（全部由 AGE_BREAKS 導出） -----------------------------------

# 帶界：第一帶下界為 -Inf；標籤依切點自動組出，不在本檔寫入任何年齡數字。
BAND_LOWER <- c(-Inf, AGE_BREAKS)
BAND_UPPER <- c(AGE_BREAKS, Inf)
N_BANDS <- length(BAND_LOWER)

BAND_LABELS <- c(
  sprintf("<%s", AGE_BREAKS[1L]),
  vapply(
    seq_len(length(AGE_BREAKS) - 1L),
    function(i) sprintf("%s-%s", AGE_BREAKS[i], AGE_BREAKS[i + 1L] - 1L),
    character(1)
  ),
  sprintf("%s+", AGE_BREAKS[length(AGE_BREAKS)])
)

# 檢定帶：以第二個切點為下界的那一帶，與最後一帶。
TEST_BAND <- which(BAND_LOWER == AGE_BREAKS[2L])
TOP_BAND <- N_BANDS

## 3. 讀清洗資料集並界定分析母體 -------------------------------------------

if (!file.exists(CLEAN_PATH)) {
  refuse("input-schema", sprintf("找不到清洗資料集 %s", short_path(CLEAN_PATH)),
         "先執行 programs/R/01_prep_data.R 產出清洗資料集後重跑。")
}

clean <- tryCatch(
  utils::read.csv(CLEAN_PATH, encoding = "UTF-8-BOM", check.names = FALSE, stringsAsFactors = FALSE),
  error = function(e) e
)
if (inherits(clean, "error")) {
  refuse("input-schema", sprintf("清洗資料集無法解析：%s", conditionMessage(clean)),
         "重新執行 programs/R/01_prep_data.R 後重跑。")
}

required <- c(COL_AGE, COL_MARITAL, COL_TUITION, COL_RESULT)
missing_cols <- setdiff(required, names(clean))
if (length(missing_cols)) {
  refuse("input-schema", sprintf("清洗資料集缺欄位：%s", paste(missing_cols, collapse = ", ")),
         "換回 T02 產出的清洗資料集後重跑。")
}

data <- clean[clean[[COL_RESULT]] %in% ANALYSIS_RESULTS, , drop = FALSE]
if (nrow(data) != ANALYSIS_N) {
  refuse("input-schema",
         sprintf("分析母體實算 %d 列，契約為 %d", nrow(data), ANALYSIS_N),
         "換回 T02 產出的清洗資料集後重跑；三張表皆未寫出。")
}

observed_marital <- sort(unique(data[[COL_MARITAL]]))
observed_tuition <- sort(unique(data[[COL_TUITION]]))
if (!all(observed_marital %in% c(SINGLE_VALUES, MARRIED_VALUE))) {
  refuse("input-schema",
         sprintf("婚姻狀況出現未登記的類別：%s", paste(observed_marital, collapse = ", ")),
         "確認婚配映射後重跑；三張表皆未寫出。")
}
if (!all(observed_tuition %in% c(UNPAID_VALUE, 1L))) {
  refuse("input-schema",
         sprintf("學費繳清欄出現未登記的值：%s", paste(observed_tuition, collapse = ", ")),
         "確認欠繳編碼後重跑；三張表皆未寫出。")
}

if (anyNA(data[[COL_AGE]]) || anyNA(data[[COL_MARITAL]]) || anyNA(data[[COL_TUITION]])) {
  refuse("input-schema", "年齡、婚姻狀況或學費繳清欄含缺值",
         "重新執行 programs/R/01_prep_data.R 並確認 MISSING_PROFILE 為零後重跑。")
}

## 4. 分類向量 -------------------------------------------------------------

age <- as.numeric(data[[COL_AGE]])
band_index <- findInterval(age, AGE_BREAKS) + 1L     # 左閉右開；age 小於首切點得 1

dropout <- data[[COL_RESULT]] == DROPOUT_VALUE
unpaid <- data[[COL_TUITION]] == UNPAID_VALUE
married <- data[[COL_MARITAL]] == MARRIED_VALUE
single <- data[[COL_MARITAL]] %in% SINGLE_VALUES

if (any(band_index < 1L) || any(band_index > N_BANDS)) {
  refuse("input-schema", "年齡切帶落在界外", "確認 AGE_BREAKS 與年齡欄後重跑。")
}

## 5. 五帶概況 -------------------------------------------------------------

bands <- do.call(rbind, lapply(seq_len(N_BANDS), function(b) {
  sel <- band_index == b
  n_b <- sum(sel)
  data.frame(
    population = POPULATION,
    band = BAND_LABELS[b],
    n = as.integer(n_b),
    share = n_b / nrow(data),
    dropout_rate = if (n_b) mean(dropout[sel]) else NA_real_,
    unpaid_rate = if (n_b) mean(unpaid[sel]) else NA_real_,
    stringsAsFactors = FALSE
  )
}))

## 6. 兩個關鍵檢定（退學率、欠繳率；兩帶：第二個切點起的一帶 vs 最後一帶） --

test_rows <- list()
for (metric in c("dropout", "unpaid")) {
  event <- if (identical(metric, "dropout")) dropout else unpaid
  sel_a <- band_index == TEST_BAND
  sel_b <- band_index == TOP_BAND
  cells <- c(
    sum(event & sel_a), sum(!event & sel_a),
    sum(event & sel_b), sum(!event & sel_b)
  )
  result <- fisher_2x2(cells[1L], cells[2L], cells[3L], cells[4L])
  if (!is.list(result)) {
    # 邊際和為零：與婚配零分母同一類別，整支停止
    refuse("empty-denominator",
           sprintf("%s 的兩帶邊際和為零（格數 %s）", paste0(metric, "_rate"),
                   paste(cells, collapse = ", ")),
           "檢查該帶是否有觀測後重跑；三張表皆未寫出。")
  }
  test_rows[[metric]] <- data.frame(
    population = POPULATION,
    test = paste0(metric, "_rate"),
    group_a = BAND_LABELS[TEST_BAND],
    n_a = as.integer(sum(sel_a)),
    group_b = BAND_LABELS[TOP_BAND],
    n_b = as.integer(sum(sel_b)),
    odds_ratio = result$odds_ratio,
    p_value = result$p_value,
    tail = "two.sided",
    status = "ok",
    stringsAsFactors = FALSE
  )
}
tests <- do.call(rbind, test_rows)

## 7. 逐帶婚配分層（三分支，先全數判定再寫表） ------------------------------

strata <- do.call(rbind, lapply(seq_len(N_BANDS), function(b) {
  sel <- band_index == b
  m <- sel & married
  s <- sel & single
  married_n <- sum(m)
  single_n <- sum(s)

  # ① 零格：整支停止（此處先回報，由呼叫端在寫表前統一停止）
  if (married_n == 0L || single_n == 0L) {
    refuse("empty-denominator",
           sprintf("帶 %s 的已婚 %d 人、單身 %d 人，其中一組為零",
                   BAND_LABELS[b], married_n, single_n),
           "檢查婚姻狀況欄的編碼後重跑；三張表皆未寫出。")
  }

  cells <- c(sum(m & dropout), sum(m & !dropout), sum(s & dropout), sum(s & !dropout))

  # ② 任一格低於門檻：入表、p 留空、標 insufficient_n
  if (any(cells < SMALL_CELL_MIN)) {
    return(data.frame(
      population = POPULATION,
      band = BAND_LABELS[b],
      married_n = as.integer(married_n),
      married_rate = mean(dropout[m]),
      single_n = as.integer(single_n),
      single_rate = mean(dropout[s]),
      n = as.integer(sum(sel)),
      p_value = NA_real_,
      status = "insufficient_n",
      stringsAsFactors = FALSE
    ))
  }

  # ③ 其餘：雙尾精確檢定
  result <- fisher_2x2(cells[1L], cells[2L], cells[3L], cells[4L])
  if (!is.list(result)) {
    refuse("empty-denominator",
           sprintf("帶 %s 的婚配四格邊際和為零（格數 %s）",
                   BAND_LABELS[b], paste(cells, collapse = ", ")),
           "檢查婚姻狀況欄的編碼後重跑；三張表皆未寫出。")
  }
  data.frame(
    population = POPULATION,
    band = BAND_LABELS[b],
    married_n = as.integer(married_n),
    married_rate = mean(dropout[m]),
    single_n = as.integer(single_n),
    single_rate = mean(dropout[s]),
    n = as.integer(sum(sel)),
    p_value = result$p_value,
    status = "ok",
    stringsAsFactors = FALSE
  )
}))

## 8. 寫三張表 -------------------------------------------------------------

atomic_write(BANDS_PATH, function(path) readr::write_csv(bands, path, na = ""))
atomic_write(TESTS_PATH, function(path) readr::write_csv(tests, path, na = ""))
atomic_write(MARRIAGE_PATH, function(path) readr::write_csv(strata, path, na = ""))

## 9. 記錄 ----------------------------------------------------------------

log_block(c(
  sprintf("r_version: %s", R.version.string),
  sprintf("proj_root: %s", PROJ_ROOT),
  sprintf("out_root: %s", OUT_ROOT),
  sprintf("input: %s", short_path(CLEAN_PATH)),
  sprintf("population: %s n=%d", POPULATION, nrow(data)),
  sprintf("band_rule: left_closed_right_open"),
  sprintf("age_breaks: %s", paste(AGE_BREAKS, collapse = ",")),
  sprintf("age_range: %s", paste(range(age), collapse = "-")),
  sprintf("bands: %s", paste(sprintf("%s=%d", BAND_LABELS, bands$n), collapse = ", ")),
  sprintf("dropout_value: %s", DROPOUT_VALUE),
  sprintf("unpaid_rule: %s = %d", COL_TUITION, UNPAID_VALUE),
  sprintf("marital_values_observed: %s", paste(observed_marital, collapse = ",")),
  sprintf("marriage_map: married = %d; single = %s", MARRIED_VALUE, paste(SINGLE_VALUES, collapse = ",")),
  sprintf("married_total: %d", sum(married)),
  sprintf("single_total: %d", sum(single)),
  sprintf("small_cell_min: %d", SMALL_CELL_MIN),
  sprintf("test_bands: %s vs %s", BAND_LABELS[TEST_BAND], BAND_LABELS[TOP_BAND]),
  vapply(seq_len(nrow(tests)), function(i) {
    sprintf("test: %s %s n=%d vs %s n=%d odds_ratio=%s p=%s tail=%s status=%s",
            tests$test[i], tests$group_a[i], tests$n_a[i], tests$group_b[i], tests$n_b[i],
            format(tests$odds_ratio[i], digits = 10), format(tests$p_value[i], digits = 10),
            tests$tail[i], tests$status[i])
  }, character(1)),
  vapply(seq_len(nrow(strata)), function(i) {
    sprintf("strata: %s married=%d rate=%s single=%d rate=%s n=%d p=%s status=%s",
            strata$band[i], strata$married_n[i], format(strata$married_rate[i], digits = 10),
            strata$single_n[i], format(strata$single_rate[i], digits = 10), strata$n[i],
            if (is.na(strata$p_value[i])) "NA" else format(strata$p_value[i], digits = 10),
            strata$status[i])
  }, character(1)),
  sprintf("output: %s", short_path(BANDS_PATH)),
  sprintf("output: %s", short_path(TESTS_PATH)),
  sprintf("output: %s", short_path(MARRIAGE_PATH)),
  "status: ok"
))

cat(sprintf("03_age：分析母體 %d、五帶 %s，三張表已寫出\n",
            nrow(data), paste(bands$n, collapse = "/")))
