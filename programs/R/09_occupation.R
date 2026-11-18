# 09_occupation.R — 父母職業階級、財務標記與畢業率（F12，2026-11-18 新增）
#
# 一條指令做三件事：把 UCI 697 的職業碼（1–10、90、99 及其 101–195 細分類）併成
# 七個實質階級與三個非職業碼；逐組算畢業率、與其餘人比的精確檢定（BH 校正）；
# 再逐組算三個財務標記的比率（欠繳、獎學金、欠債），供「收入背景 → 財務標記 →
# 畢業」這條鏈的兩端各有一個可引用的數。
#
# 與 02–08 的關係：本檔是報告「財務背景的兩段鏈條」一節的唯一數值來源。職業在
# 這條鏈上位於上游（收入的粗糙代理），故本檔**不**以欠繳為分組條件，也不把
# 欠繳放進分組的模型；把中介變項調掉之後再宣稱上游「無效」，是把要看的路徑
# 自己切斷（AMENDMENTS A-50）。
#
# 用法（專案根目錄）：Rscript programs/R/09_occupation.R
# 產物：
#   <OUT_ROOT>/tables/occupation_by_parent.csv      母／父 × 十組，畢業率與檢定
#   <OUT_ROOT>/tables/occupation_financial.csv      母／父 × 十組，三個財務標記的比率
#   <OUT_ROOT>/tables/occupation_tests.csv          整體關聯（χ²、Cramér V、η）
#   <OUT_ROOT>/logs/09_occupation.log               母體、碼表、各組數值與拒絕理由
#
# 輸入可由 RTOOLKIT_CLEAN_PATH 指向另一份副本（供注入測試），預設為
# data/processed/ams2640_clean.csv。

## 0. 由 00_setup.R 與 lib 取得常數與統計量 ---------------------------------

source("programs/R/00_setup.R")
source("programs/R/lib/stats.R")

## 1. 路徑與固定形狀 -------------------------------------------------------

CLEAN_PATH <- Sys.getenv("RTOOLKIT_CLEAN_PATH", unset = "")
if (!nzchar(CLEAN_PATH)) CLEAN_PATH <- file.path(PROJ_ROOT, "data", "processed", "ams2640_clean.csv")
CLEAN_PATH <- normalizePath(CLEAN_PATH, winslash = "/", mustWork = FALSE)

TABLE_GROUP_PATH <- file.path(OUT_ROOT, "tables", "occupation_by_parent.csv")
TABLE_FIN_PATH   <- file.path(OUT_ROOT, "tables", "occupation_financial.csv")
TABLE_TEST_PATH  <- file.path(OUT_ROOT, "tables", "occupation_tests.csv")
TABLE_MARKER_PATH <- file.path(OUT_ROOT, "tables", "financial_markers.csv")
TABLE_CROSS_PATH <- file.path(OUT_ROOT, "tables", "financial_cross.csv")
LOG_PATH         <- file.path(OUT_ROOT, "logs", "09_occupation.log")

RESULT_COL    <- "target"
MOTHER_COL    <- "Mother's occupation"
FATHER_COL    <- "Father's occupation"
TUITION_COL   <- "Tuition fees up to date"
DEBTOR_COL    <- "Debtor"
SCHOLAR_COL   <- "Scholarship holder"
GRADUATE_LABEL <- "Graduate"

# 官方碼 → 大類。字典（UCI 697）的 1–10、90、99 為大類；101–195 為細分類，
# 依字典所載職業內容歸回其所屬大類，逐項寫出而不以位數推算——154（保安）、
# 161／163（農）、181–183（機械）的首位數字都不是它們的大類，推算會錯。
OCC_LABELS <- c(
  "0" = "in_school", "1" = "exec_dir", "2" = "professional", "3" = "assoc_tech",
  "4" = "admin", "5" = "service_sales", "6" = "agri", "7" = "craft",
  "8" = "machine", "9" = "unskilled", "10" = "armed",
  "90" = "other_situation", "99" = "blank"
)
OCC_SUB <- c(
  "101" = "armed", "102" = "armed", "103" = "armed",
  "112" = "exec_dir", "114" = "exec_dir",
  "121" = "professional", "122" = "professional", "123" = "professional",
  "124" = "professional", "125" = "professional",
  "131" = "assoc_tech", "132" = "assoc_tech", "134" = "assoc_tech", "135" = "assoc_tech",
  "141" = "admin", "143" = "admin", "144" = "admin",
  "151" = "service_sales", "152" = "service_sales", "153" = "service_sales",
  "154" = "service_sales",
  "161" = "agri", "163" = "agri",
  "171" = "craft", "172" = "craft", "173" = "craft", "174" = "craft", "175" = "craft",
  "181" = "machine", "182" = "machine", "183" = "machine",
  "191" = "unskilled", "192" = "unskilled", "193" = "unskilled",
  "194" = "unskilled", "195" = "unskilled"
)

# 大類 → 報告用的組。十組固定序：七個實質階級由高到低，再三個非職業碼。
GROUP_OF <- c(
  exec_dir = "high_prof", professional = "high_prof",
  assoc_tech = "mid_white", admin = "mid_white",
  service_sales = "service", agri = "agri", craft = "craft",
  machine = "machine", unskilled = "unskilled",
  armed = "armed", in_school = "in_school",
  other_situation = "other", blank = "blank"
)
GROUPS <- c("high_prof", "mid_white", "service", "agri", "craft", "machine",
            "unskilled", "armed", "in_school", "other", "blank")
GROUP_LABEL <- c(
  high_prof = "高層與專業", mid_white = "中層技術與行政", service = "服務銷售與保安",
  agri = "農漁林", craft = "工業建築技工", machine = "機械操作與裝配",
  unskilled = "非技術", armed = "武裝部隊", in_school = "0 在學",
  other = "90 其他狀況", blank = "99 空白"
)
IS_OCCUPATION <- c(
  high_prof = TRUE, mid_white = TRUE, service = TRUE, agri = TRUE, craft = TRUE,
  machine = TRUE, unskilled = TRUE, armed = TRUE,
  in_school = FALSE, other = FALSE, blank = FALSE
)

PARENTS <- data.frame(
  parent = c("mother", "father"),
  column = c(MOTHER_COL, FATHER_COL),
  stringsAsFactors = FALSE
)

## 2. 小工具 ---------------------------------------------------------------

stamp <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

short_path <- function(path) {
  prefix <- paste0(PROJ_ROOT, "/")
  ifelse(startsWith(path, prefix), substring(path, nchar(prefix) + 1L), path)
}

file_state <- function(path) {
  if (!file.exists(path)) return("absent")
  info <- file.info(path)
  sprintf("%s bytes=%s", format(info$mtime, "%Y-%m-%dT%H:%M:%S%z"), format(info$size, scientific = FALSE))
}

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

log_block <- function(lines) {
  dir.create(dirname(LOG_PATH), recursive = TRUE, showWarnings = FALSE)
  block <- c(sprintf("== 09_occupation %s ==", stamp()), lines, "")
  atomic_write(LOG_PATH, function(path) {
    previous <- if (file.exists(LOG_PATH)) readLines(LOG_PATH, warn = FALSE) else character()
    writeLines(c(previous, block), path, useBytes = TRUE)
  })
}

refuse <- function(class, reason, next_step) {
  log_block(c(
    sprintf("input: %s", short_path(CLEAN_PATH)),
    sprintf("status: refuse:%s", class),
    sprintf("reason: %s", reason),
    sprintf("next_step: %s", next_step)
  ))
  stop(sprintf("refuse:%s\n- %s\n- 下一步：%s", class, reason, next_step), call. = FALSE)
}

# 碼 → 大類；未知碼回 NA，由呼叫端拒絕（不猜、不併入「其他」）
decode_occupation <- function(code) {
  key <- as.character(code)
  out <- unname(OCC_LABELS[key])
  hit <- unname(OCC_SUB[key])
  out[!is.na(hit)] <- hit[!is.na(hit)]
  out
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

required_cols <- c(MOTHER_COL, FATHER_COL, TUITION_COL, DEBTOR_COL, SCHOLAR_COL, RESULT_COL)
absent_cols <- setdiff(required_cols, names(clean))
if (length(absent_cols)) {
  refuse("input-schema", sprintf("缺少欄位：%s", paste(absent_cols, collapse = ", ")),
         "確認清洗資料集是 programs/R/01_prep_data.R 的產物後重跑。")
}

## 4. 分析母體與編碼 -------------------------------------------------------

result <- as.character(clean[[RESULT_COL]])
in_analysis <- result %in% ANALYSIS_RESULTS
analysis_n <- sum(in_analysis)

if (analysis_n != ANALYSIS_N) {
  refuse("input-schema",
         sprintf("分析母體實算 %d 人，與 00_setup.R 的 %d 不符", analysis_n, ANALYSIS_N),
         "換回契約界定的清洗資料集後重跑；本次未寫出任何表。")
}

dat <- data.frame(
  graduate  = as.integer(result[in_analysis] == GRADUATE_LABEL),
  unpaid    = as.integer(clean[[TUITION_COL]][in_analysis] == 0),
  debtor    = as.integer(clean[[DEBTOR_COL]][in_analysis] == 1),
  scholar   = as.integer(clean[[SCHOLAR_COL]][in_analysis] == 1),
  stringsAsFactors = FALSE
)

for (i in seq_len(nrow(PARENTS))) {
  code <- clean[[PARENTS$column[i]]][in_analysis]
  if (anyNA(code)) {
    refuse("input-schema", sprintf("%s 在分析母體內有 %d 個缺值", PARENTS$column[i], sum(is.na(code))),
           "補齊該欄後重跑；本次未寫出任何表。")
  }
  big <- decode_occupation(code)
  unknown <- unique(as.character(code)[is.na(big)])
  if (length(unknown)) {
    refuse("input-schema",
           sprintf("%s 出現字典未定義的碼：%s（不得猜測歸類）", PARENTS$column[i],
                   paste(sort(unknown), collapse = ", ")),
           "把新碼補進 OCC_LABELS／OCC_SUB 並在記錄寫明依據後重跑；本次未寫出任何表。")
  }
  dat[[PARENTS$parent[i]]] <- unname(GROUP_OF[big])
}

for (p in PARENTS$parent) {
  miss <- setdiff(GROUPS, unique(dat[[p]]))
  if (length(miss)) {
    refuse("empty-denominator",
           sprintf("%s 有組別無人：%s（該組比率無分母）", p, paste(miss, collapse = ", ")),
           "檢查母體界線與碼表後重跑；本次未寫出任何表。")
  }
}

## 5. 逐組：畢業率、對照其餘的檢定、三個財務標記 ---------------------------

rows_group <- list()
rows_fin <- list()

for (i in seq_len(nrow(PARENTS))) {
  p <- PARENTS$parent[i]
  g <- dat[[p]]
  for (lv in GROUPS) {
    idx <- g == lv
    n <- sum(idx)
    k <- sum(dat$graduate[idx])
    rest_n <- analysis_n - n
    rest_k <- sum(dat$graduate) - k
    ft <- fisher_2x2(k, n - k, rest_k, rest_n - rest_k)
    if (identical(ft, "refuse:empty-denominator")) {
      refuse("empty-denominator", sprintf("%s / %s 的 2×2 有一整列或一整欄為空", p, lv),
             "檢查該組是否覆蓋全體後重跑；本次未寫出任何表。")
    }
    ci <- prop_ci(k, n, PROP_CI_LEVEL)
    rows_group[[length(rows_group) + 1L]] <- data.frame(
      population = "analysis", parent = p, group = lv, group_label = unname(GROUP_LABEL[lv]),
      n = n, graduate_n = k, grad_rate = k / n,
      ci_lo = ci$lower, ci_hi = ci$upper,
      odds_ratio = ft$odds_ratio, p_fisher = ft$p_value,
      is_occupation = unname(IS_OCCUPATION[lv]),
      stringsAsFactors = FALSE
    )
    rows_fin[[length(rows_fin) + 1L]] <- data.frame(
      population = "analysis", parent = p, group = lv, n = n,
      unpaid_rate = mean(dat$unpaid[idx]),
      scholarship_rate = mean(dat$scholar[idx]),
      debtor_rate = mean(dat$debtor[idx]),
      stringsAsFactors = FALSE
    )
  }
}

by_parent <- do.call(rbind, rows_group)
by_parent$p_bh <- NA_real_
for (p in PARENTS$parent) {
  sel <- by_parent$parent == p
  by_parent$p_bh[sel] <- stats::p.adjust(by_parent$p_fisher[sel], method = "BH")
}
by_parent <- by_parent[order(match(by_parent$parent, PARENTS$parent),
                             match(by_parent$group, GROUPS)), ]
financial <- do.call(rbind, rows_fin)
financial <- financial[order(match(financial$parent, PARENTS$parent),
                             match(financial$group, GROUPS)), ]

## 6. 整體關聯：χ²、Cramér V、η ---------------------------------------------

# 實質階級的整體檢定只用七個職業組：非職業碼不是職業，把它們放進同一個 χ² 會讓
# 「在學／其他／空白」的低畢業率冒充職業效應；武裝部隊另立一組但mother 一側只有 2 人，
# 期望次數低於 5，故亦不進整體檢定（仍留在逐組表內）。
OCC_GROUPS <- c("high_prof", "mid_white", "service", "agri", "craft", "machine", "unskilled")

rows_test <- list()
for (i in seq_len(nrow(PARENTS))) {
  p <- PARENTS$parent[i]
  sel <- dat[[p]] %in% OCC_GROUPS
  for (outcome in c("graduate", "unpaid", "scholar", "debtor")) {
    tab <- table(dat[[p]][sel], dat[[outcome]][sel])
    ct <- suppressWarnings(stats::chisq.test(tab))
    n <- sum(tab)
    k <- nrow(tab)
    rows_test[[length(rows_test) + 1L]] <- data.frame(
      population = "analysis", parent = p, outcome = outcome,
      n = n, levels = k, chi2 = as.numeric(ct$statistic), df = as.integer(ct$parameter),
      p_value = as.numeric(ct$p.value),
      cramer_v = sqrt(as.numeric(ct$statistic) / (n * (k - 1L))),
      eta = sqrt(as.numeric(ct$statistic) / n),
      exp_below_5 = sum(ct$expected < 5),
      stringsAsFactors = FALSE
    )
  }
}
tests <- do.call(rbind, rows_test)

## 7. 財務標記 → 畢業：單欄與交叉 -------------------------------------------

# 三個標記各自對畢業，以及「欠繳 × 獎學金」四格——鏈條的下游一段。放在本檔是因為
# 報告同一節要同時引用上游（職業 → 標記）與下游（標記 → 畢業）；下游若只存在於
# 02_wealth 的四格表（欠繳 × 欠債）裡，獎學金那一段就沒有可引用的產物。
rows_marker <- list()
for (m in c("unpaid", "scholar", "debtor")) {
  for (v in c(1L, 0L)) {
    idx <- dat[[m]] == v
    k <- sum(dat$graduate[idx])
    ci <- prop_ci(k, sum(idx), PROP_CI_LEVEL)
    rows_marker[[length(rows_marker) + 1L]] <- data.frame(
      population = "analysis", marker = m, value = v, n = sum(idx), graduate_n = k,
      grad_rate = k / sum(idx), ci_lo = ci$lower, ci_hi = ci$upper,
      stringsAsFactors = FALSE
    )
  }
}
markers <- do.call(rbind, rows_marker)

rows_cross <- list()
for (u in c(0L, 1L)) for (s in c(0L, 1L)) {
  idx <- dat$unpaid == u & dat$scholar == s
  k <- sum(dat$graduate[idx])
  ci <- prop_ci(k, sum(idx), PROP_CI_LEVEL)
  rows_cross[[length(rows_cross) + 1L]] <- data.frame(
    population = "analysis", unpaid = u, scholarship = s, n = sum(idx), graduate_n = k,
    grad_rate = k / sum(idx), ci_lo = ci$lower, ci_hi = ci$upper,
    stringsAsFactors = FALSE
  )
}
cross <- do.call(rbind, rows_cross)

## 8. 寫表 ----------------------------------------------------------------

states_before <- vapply(c(TABLE_GROUP_PATH, TABLE_FIN_PATH, TABLE_TEST_PATH,
                          TABLE_MARKER_PATH, TABLE_CROSS_PATH), file_state, character(1))
atomic_write(TABLE_GROUP_PATH, function(path) readr::write_csv(by_parent, path))
atomic_write(TABLE_FIN_PATH, function(path) readr::write_csv(financial, path))
atomic_write(TABLE_TEST_PATH, function(path) readr::write_csv(tests, path))
atomic_write(TABLE_MARKER_PATH, function(path) readr::write_csv(markers, path))
atomic_write(TABLE_CROSS_PATH, function(path) readr::write_csv(cross, path))

## 9. 記錄 ----------------------------------------------------------------

fmt_line <- function(df, cols) {
  apply(df, 1, function(r) paste(sprintf("%s=%s", cols, r[cols]), collapse = " "))
}

log_block(c(
  sprintf("r_version: %s", R.version.string),
  sprintf("proj_root: %s", PROJ_ROOT),
  sprintf("out_root: %s", OUT_ROOT),
  sprintf("input: %s", short_path(CLEAN_PATH)),
  sprintf("population: analysis %d（取自 00_setup.R 的 ANALYSIS_N）", analysis_n),
  sprintf("groups: %s", paste(sprintf("%s(%s)", GROUPS, GROUP_LABEL[GROUPS]), collapse = " / ")),
  sprintf("occupation_groups_used_in_chi2: %s（非職業碼 0／90／99 不進整體檢定）",
          paste(OCC_GROUPS, collapse = ", ")),
  sprintf("codes_seen: mother %d 種、father %d 種；全部對應到字典",
          length(unique(clean[[MOTHER_COL]][in_analysis])),
          length(unique(clean[[FATHER_COL]][in_analysis]))),
  vapply(PARENTS$parent, function(p) {
    s <- by_parent[by_parent$parent == p, ]
    sprintf("grad_rate[%s]: %s", p, paste(sprintf("%s %s (%d)", s$group, fmt_sig(s$grad_rate), s$n), collapse = " | "))
  }, character(1)),
  vapply(PARENTS$parent, function(p) {
    s <- financial[financial$parent == p, ]
    sprintf("scholarship_rate[%s]: %s", p, paste(sprintf("%s %s", s$group, fmt_sig(s$scholarship_rate)), collapse = " | "))
  }, character(1)),
  vapply(PARENTS$parent, function(p) {
    s <- financial[financial$parent == p, ]
    sprintf("unpaid_rate[%s]: %s", p, paste(sprintf("%s %s", s$group, fmt_sig(s$unpaid_rate)), collapse = " | "))
  }, character(1)),
  vapply(seq_len(nrow(tests)), function(i) {
    r <- tests[i, ]
    sprintf("test[%s x %s]: chi2=%s df=%d p=%s V=%s eta=%s n=%d",
            r$parent, r$outcome, fmt_sig(r$chi2), r$df, fmt_sig(r$p_value),
            fmt_sig(r$cramer_v), fmt_sig(r$eta), r$n)
  }, character(1)),
  sprintf("product: %s rows=%d before=%s after=%s", short_path(TABLE_GROUP_PATH),
          nrow(by_parent), states_before[[1]], file_state(TABLE_GROUP_PATH)),
  sprintf("product: %s rows=%d before=%s after=%s", short_path(TABLE_FIN_PATH),
          nrow(financial), states_before[[2]], file_state(TABLE_FIN_PATH)),
  sprintf("product: %s rows=%d before=%s after=%s", short_path(TABLE_TEST_PATH),
          nrow(tests), states_before[[3]], file_state(TABLE_TEST_PATH)),
  sprintf("product: %s rows=%d before=%s after=%s", short_path(TABLE_MARKER_PATH),
          nrow(markers), states_before[[4]], file_state(TABLE_MARKER_PATH)),
  sprintf("product: %s rows=%d before=%s after=%s", short_path(TABLE_CROSS_PATH),
          nrow(cross), states_before[[5]], file_state(TABLE_CROSS_PATH)),
  vapply(seq_len(nrow(markers)), function(i) {
    r <- markers[i, ]
    sprintf("marker[%s=%d]: n=%d grad_rate=%s ci=[%s, %s]", r$marker, r$value, r$n,
            fmt_sig(r$grad_rate), fmt_sig(r$ci_lo), fmt_sig(r$ci_hi))
  }, character(1)),
  vapply(seq_len(nrow(cross)), function(i) {
    r <- cross[i, ]
    sprintf("cross[unpaid=%d scholarship=%d]: n=%d grad_rate=%s ci=[%s, %s]", r$unpaid, r$scholarship,
            r$n, fmt_sig(r$grad_rate), fmt_sig(r$ci_lo), fmt_sig(r$ci_hi))
  }, character(1)),
  "status: ok",
  "next_step: 報告「財務背景的兩段鏈條」一節引用 occupation_by_parent.csv 與 occupation_financial.csv；整體檢定引 occupation_tests.csv"
))

cat(sprintf("09_occupation: 分析母體 %d 人\n", analysis_n))
for (p in PARENTS$parent) {
  s <- by_parent[by_parent$parent == p, ]
  cat(sprintf("09_occupation: %s 畢業率 %s\n", p,
              paste(sprintf("%s=%s", s$group, fmt_sig(s$grad_rate)), collapse = " / ")))
}
cat(sprintf("09_occupation: χ²（母親 × 畢業）p = %s；父親 p = %s\n",
            fmt_sig(tests$p_value[tests$parent == "mother" & tests$outcome == "graduate"]),
            fmt_sig(tests$p_value[tests$parent == "father" & tests$outcome == "graduate"])))
cat(sprintf("09_occupation: 表 %s / %s / %s\n",
            short_path(TABLE_GROUP_PATH), short_path(TABLE_FIN_PATH), short_path(TABLE_TEST_PATH)))
