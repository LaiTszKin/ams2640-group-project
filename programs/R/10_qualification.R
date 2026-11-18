# 10_qualification.R — 父母學歷（文化資本的操作量）與畢業率（F13，2026-11-18 新增）
#
# 一條指令做四件事：把 UCI 697 的教育程度碼併成五個實質級與一個未填碼；逐級算畢業率
# 與三個財務標記；在實質級上做整體檢定與逐級精確檢定（BH）；把學歷的解釋力拆成
# 「與財務標記重疊」與「不重疊」兩部分。
#
# 兩個先寫下的判斷（A-51）：
#   ① 學歷在此專案屬社會背景一層，量的是制度化文化資本；財務標記是競爭解釋，也是
#      學歷的下游（學歷 → 收入 → 資助與繳費），故**不得**以調整財務標記後的係數
#      宣稱學歷無效；報告引用的是未調整的總效應，調整後的部分只標為 direct。
#   ② 入學年齡與學歷高度交纏（V = 0.3919／0.3254），且可能是學歷的下游（延遲入學、
#      重讀、先工作再讀）。它不是混雜因子，故本檔**不**按年齡分層、不把年齡放進模型；
#      交纏本身寫成限制。
#
# 用法（專案根目錄）：Rscript programs/R/10_qualification.R
# 產物：
#   <OUT_ROOT>/tables/qualification_by_parent.csv   母／父 × 六級，畢業率與檢定
#   <OUT_ROOT>/tables/qualification_financial.csv   母／父 × 六級，三個財務標記比率
#   <OUT_ROOT>/tables/qualification_tests.csv       整體關聯（χ²、Cramér V、η）
#   <OUT_ROOT>/tables/qualification_models.csv      解釋力與兩兩重疊的分解
#   <OUT_ROOT>/tables/highest_parent_education.csv  最高一方的學歷分級
#   <OUT_ROOT>/logs/10_qualification.log            母體、碼表、各級數值與拒絕理由
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

TABLE_LEVEL_PATH  <- file.path(OUT_ROOT, "tables", "qualification_by_parent.csv")
TABLE_FIN_PATH    <- file.path(OUT_ROOT, "tables", "qualification_financial.csv")
TABLE_TEST_PATH   <- file.path(OUT_ROOT, "tables", "qualification_tests.csv")
TABLE_MODEL_PATH  <- file.path(OUT_ROOT, "tables", "qualification_models.csv")
TABLE_HIGHEST_PATH <- file.path(OUT_ROOT, "tables", "highest_parent_education.csv")
TABLE_GRAD_PATH    <- file.path(OUT_ROOT, "tables", "qualification_gradient.csv")
TABLE_ENT_PATH     <- file.path(OUT_ROOT, "tables", "qualification_entanglement.csv")
LOG_PATH          <- file.path(OUT_ROOT, "logs", "10_qualification.log")

RESULT_COL  <- "target"
MOTHER_COL  <- "Mother's qualification"
FATHER_COL  <- "Father's qualification"
TUITION_COL <- "Tuition fees up to date"
DEBTOR_COL  <- "Debtor"
SCHOLAR_COL <- "Scholarship holder"
GRADUATE_LABEL <- "Graduate"

# 官方碼 → 級。字典（UCI 697）逐項寫出，不以位數或次數推算。
#   高等教育：2 學士、3 學位、4 碩士、5 博士、6 曾就讀高等教育、40 學位(1st cycle)、
#             41 專門高等研究、43 碩士(2nd cycle)、44 博士(3rd cycle)
#   技術高等教育：39 技術專門化、42 專業高等技術課程（ISCED 短周期，非學位）
#   中等教育完成：1 十二年级、13 補充高中二年、18 商業通識、20 補充高中、
#                 22 技術專業、25 補充高中未完成、27 通識高中第二周期、31 行政商業、
#                 33 補充會計行政
#   中學以下：9 十二年级未完成、10 十一年级未完成、11 七年级(舊制)、12 其他十一年级、
#             14 十年级、19 基礎教育第三階段、26 七年级、29 九年级未完成、30 八年级、
#             38 基礎教育第二階段
#   小學或以下：35 不能讀寫、36 能讀寫但未滿四年、37 基礎教育第一階段
QUAL_MAP <- c(
  "2" = "higher", "3" = "higher", "4" = "higher", "5" = "higher", "6" = "higher",
  "40" = "higher", "41" = "higher", "43" = "higher", "44" = "higher",
  "39" = "post_sec", "42" = "post_sec",
  "1" = "secondary", "13" = "secondary", "18" = "secondary", "20" = "secondary",
  "22" = "secondary", "25" = "secondary", "27" = "secondary", "31" = "secondary",
  "33" = "secondary",
  "9" = "lower_sec", "10" = "lower_sec", "11" = "lower_sec", "12" = "lower_sec",
  "14" = "lower_sec", "19" = "lower_sec", "26" = "lower_sec", "29" = "lower_sec",
  "30" = "lower_sec", "38" = "lower_sec",
  "35" = "primary_or_less", "36" = "primary_or_less", "37" = "primary_or_less",
  "34" = "unknown"
)

LEVELS <- c("higher", "post_sec", "secondary", "lower_sec", "primary_or_less", "unknown")
# 未填碼（34）不是教育程度，是資料收集的紀錄，故不進整體檢定
SUBSTANTIVE <- c("higher", "post_sec", "secondary", "lower_sec", "primary_or_less")
LEVEL_LABEL <- c(
  higher = "高等教育", post_sec = "技術高等教育", secondary = "中等教育完成",
  lower_sec = "中學以下（5–11 年）", primary_or_less = "小學或以下", unknown = "34 未填"
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
  block <- c(sprintf("== 10_qualification %s ==", stamp()), lines, "")
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

decode_qualification <- function(code) unname(QUAL_MAP[as.character(code)])

# McFadden 偽 R²：與 05_models.R 同一算式，供兩兩重疊的分解使用
mcfadden <- function(fit) {
  y <- fit$y
  1 - as.numeric(stats::logLik(fit)) / sum(stats::dbinom(y, 1, mean(y), log = TRUE))
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

## 4. 分析母體與解碼 -------------------------------------------------------

result <- as.character(clean[[RESULT_COL]])
in_analysis <- result %in% ANALYSIS_RESULTS
analysis_n <- sum(in_analysis)
if (analysis_n != ANALYSIS_N) {
  refuse("input-schema",
         sprintf("分析母體實算 %d 人，與 00_setup.R 的 %d 不符", analysis_n, ANALYSIS_N),
         "換回契約界定的清洗資料集後重跑；本次未寫出任何表。")
}

dat <- data.frame(
  graduate = as.integer(result[in_analysis] == GRADUATE_LABEL),
  unpaid   = as.integer(clean[[TUITION_COL]][in_analysis] == 0),
  debtor   = as.integer(clean[[DEBTOR_COL]][in_analysis] == 1),
  scholar  = as.integer(clean[[SCHOLAR_COL]][in_analysis] == 1),
  age      = clean[["Age at enrollment"]][in_analysis],
  course   = clean[["Course"]][in_analysis],
  stringsAsFactors = FALSE
)

for (i in seq_len(nrow(PARENTS))) {
  code <- clean[[PARENTS$column[i]]][in_analysis]
  if (anyNA(code)) {
    refuse("input-schema", sprintf("%s 在分析母體內有 %d 個缺值", PARENTS$column[i], sum(is.na(code))),
           "補齊該欄後重跑；本次未寫出任何表。")
  }
  lev <- decode_qualification(code)
  unknown <- unique(as.character(code)[is.na(lev)])
  if (length(unknown)) {
    refuse("input-schema",
           sprintf("%s 出現字典未定義的碼：%s（不得猜測歸級）", PARENTS$column[i],
                   paste(sort(unknown), collapse = ", ")),
           "把新碼補進 QUAL_MAP 並在記錄寫明依據後重跑；本次未寫出任何表。")
  }
  dat[[PARENTS$parent[i]]] <- lev
}

for (p in PARENTS$parent) {
  miss <- setdiff(LEVELS, unique(dat[[p]]))
  if (length(miss)) {
    refuse("empty-denominator",
           sprintf("%s 有級別無人：%s（該級比率無分母）", p, paste(miss, collapse = ", ")),
           "檢查母體界線與碼表後重跑；本次未寫出任何表。")
  }
}

## 5. 逐級：畢業率、對照其餘的檢定、三個財務標記 ---------------------------

rows_level <- list()
rows_fin <- list()
for (i in seq_len(nrow(PARENTS))) {
  p <- PARENTS$parent[i]
  lev <- dat[[p]]
  for (lv in LEVELS) {
    idx <- lev == lv
    n <- sum(idx)
    k <- sum(dat$graduate[idx])
    rest_n <- analysis_n - n
    rest_k <- sum(dat$graduate) - k
    ft <- fisher_2x2(k, n - k, rest_k, rest_n - rest_k)
    if (identical(ft, "refuse:empty-denominator")) {
      refuse("empty-denominator", sprintf("%s / %s 的 2×2 有一整列或一整欄為空", p, lv),
             "檢查該級是否覆蓋全體後重跑；本次未寫出任何表。")
    }
    ci <- prop_ci(k, n, PROP_CI_LEVEL)
    rows_level[[length(rows_level) + 1L]] <- data.frame(
      population = "analysis", parent = p, level = lv, level_label = unname(LEVEL_LABEL[lv]),
      n = n, graduate_n = k, grad_rate = k / n, ci_lo = ci$lower, ci_hi = ci$upper,
      odds_ratio = ft$odds_ratio, p_fisher = ft$p_value,
      is_substantive = lv %in% SUBSTANTIVE,
      stringsAsFactors = FALSE
    )
    rows_fin[[length(rows_fin) + 1L]] <- data.frame(
      population = "analysis", parent = p, level = lv, n = n,
      unpaid_rate = mean(dat$unpaid[idx]),
      scholarship_rate = mean(dat$scholar[idx]),
      debtor_rate = mean(dat$debtor[idx]),
      stringsAsFactors = FALSE
    )
  }
}
by_parent <- do.call(rbind, rows_level)
by_parent$p_bh <- NA_real_
for (p in PARENTS$parent) {
  sel <- by_parent$parent == p
  # BH 在此因素的所有級別上做（含未填碼，故偏保守）
  by_parent$p_bh[sel] <- stats::p.adjust(by_parent$p_fisher[sel], method = "BH")
}
by_parent <- by_parent[order(match(by_parent$parent, PARENTS$parent),
                             match(by_parent$level, LEVELS)), ]
financial <- do.call(rbind, rows_fin)
financial <- financial[order(match(financial$parent, PARENTS$parent),
                             match(financial$level, LEVELS)), ]

## 6. 整體關聯（實質級）-----------------------------------------------------

rows_test <- list()
for (i in seq_len(nrow(PARENTS))) {
  p <- PARENTS$parent[i]
  sel <- dat[[p]] %in% SUBSTANTIVE
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

## 7. 解釋力與分解 --------------------------------------------------------

dat$m_q <- factor(dat$mother, levels = LEVELS)
dat$f_q <- factor(dat$father, levels = LEVELS)
dat$course_f <- factor(dat$course)

m_qual <- stats::glm(graduate ~ m_q + f_q, family = stats::binomial, data = dat)
m_fin  <- stats::glm(graduate ~ unpaid + scholar + debtor, family = stats::binomial, data = dat)
m_both <- stats::glm(graduate ~ unpaid + scholar + debtor + m_q + f_q,
                     family = stats::binomial, data = dat)
m_cour <- stats::glm(graduate ~ course_f, family = stats::binomial, data = dat)
m_cour_qual <- stats::glm(graduate ~ course_f + m_q + f_q, family = stats::binomial, data = dat)

r_qual <- mcfadden(m_qual)
r_fin  <- mcfadden(m_fin)
r_both <- mcfadden(m_both)
r_cour <- mcfadden(m_cour)
r_cour_qual <- mcfadden(m_cour_qual)

# 重疊 = 兩者各自解釋力之和減去並置後的解釋力；不是調整，是分解
shared <- r_qual + r_fin - r_both

lrt_p <- function(small, big) as.numeric(anova(small, big, test = "LRT")$`Pr(>Chi)`[2])

models <- data.frame(
  population = "analysis",
  model = c("qualification", "financial_three", "qualification_plus_financial",
            "course", "course_plus_qualification"),
  r2 = c(r_qual, r_fin, r_both, r_cour, r_cour_qual),
  delta_r2 = c(NA_real_, NA_real_, r_both - r_fin, NA_real_, r_cour_qual - r_cour),
  lrt_p = c(NA_real_, NA_real_, lrt_p(m_fin, m_both), NA_real_, lrt_p(m_cour, m_cour_qual)),
  note = c(
    "學歷（母 + 父）單獨；此為總效應",
    "繳費、獎學金、欠債三標記",
    "ΔR² 為財務三標記之上再加學歷；此為不經財務標記的部分（direct）",
    "課程",
    "ΔR² 為課程之上再加學歷"
  ),
  stringsAsFactors = FALSE
)
shared_row <- data.frame(
  population = "analysis", model = "overlap_qualification_financial",
  r2 = shared, delta_r2 = NA_real_, lrt_p = NA_real_,
  note = sprintf("學歷與財務三標記共同解釋的部分；占學歷總效應 %s", fmt_sig(shared / r_qual)),
  stringsAsFactors = FALSE
)
models <- rbind(models, shared_row)

## 8. 最高一方的學歷 ------------------------------------------------------

ord <- c(higher = 1L, post_sec = 2L, secondary = 3L, lower_sec = 4L,
         primary_or_less = 5L, unknown = 6L)
highest_code <- pmin(ord[dat$mother], ord[dat$father])
highest <- LEVELS[highest_code]
rows_high <- list()
for (lv in LEVELS) {
  idx <- highest == lv
  k <- sum(dat$graduate[idx])
  ci <- prop_ci(k, sum(idx), PROP_CI_LEVEL)
  rows_high[[length(rows_high) + 1L]] <- data.frame(
    population = "analysis", level = lv, level_label = unname(LEVEL_LABEL[lv]),
    n = sum(idx), graduate_n = k, grad_rate = k / sum(idx),
    ci_lo = ci$lower, ci_hi = ci$upper,
    scholarship_rate = mean(dat$scholar[idx]),
    stringsAsFactors = FALSE
  )
}
highest_tbl <- do.call(rbind, rows_high)

## 8b. 梯度與交纏 ---------------------------------------------------------

# 梯度：級別作次序變數（只取五個實質級，由高到低 1–5）。單調版本的否證靠這一列。
grad_rows <- list()
for (p in PARENTS$parent) {
  keep <- dat[[p]] %in% SUBSTANTIVE
  o <- match(dat[[p]][keep], SUBSTANTIVE)
  y <- dat$graduate[keep]
  ct <- suppressWarnings(stats::cor.test(o, y, method = "spearman"))
  grad_rows[[length(grad_rows) + 1L]] <- data.frame(
    population = "analysis", parent = p, n = sum(keep),
    spearman_rho = unname(ct$estimate), p_value = ct$p.value,
    stringsAsFactors = FALSE
  )
}
gradient <- do.call(rbind, grad_rows)

# 交纏：學歷 × 是否 25 歲後入學。此數只寫成限制，不進模型（A-51）
ent_rows <- list()
for (p in PARENTS$parent) {
  tab <- table(dat[[p]], dat$age >= 25)
  ct <- suppressWarnings(stats::chisq.test(tab))
  ent_rows[[length(ent_rows) + 1L]] <- data.frame(
    population = "analysis", parent = p, partner = "age_25_plus",
    n = sum(tab), chi2 = as.numeric(ct$statistic), df = as.integer(ct$parameter),
    p_value = as.numeric(ct$p.value),
    cramer_v = sqrt(as.numeric(ct$statistic) / sum(tab)),
    stringsAsFactors = FALSE
  )
}
entangle <- do.call(rbind, ent_rows)

## 9. 寫表 ----------------------------------------------------------------

paths <- c(TABLE_LEVEL_PATH, TABLE_FIN_PATH, TABLE_TEST_PATH, TABLE_MODEL_PATH,
           TABLE_HIGHEST_PATH, TABLE_GRAD_PATH, TABLE_ENT_PATH)
states_before <- vapply(paths, file_state, character(1))
atomic_write(TABLE_LEVEL_PATH, function(path) readr::write_csv(by_parent, path))
atomic_write(TABLE_FIN_PATH, function(path) readr::write_csv(financial, path))
atomic_write(TABLE_TEST_PATH, function(path) readr::write_csv(tests, path))
atomic_write(TABLE_MODEL_PATH, function(path) readr::write_csv(models, path))
atomic_write(TABLE_HIGHEST_PATH, function(path) readr::write_csv(highest_tbl, path))
atomic_write(TABLE_GRAD_PATH, function(path) readr::write_csv(gradient, path))
atomic_write(TABLE_ENT_PATH, function(path) readr::write_csv(entangle, path))

## 10. 記錄 ---------------------------------------------------------------

log_block(c(
  sprintf("r_version: %s", R.version.string),
  sprintf("proj_root: %s", PROJ_ROOT),
  sprintf("out_root: %s", OUT_ROOT),
  sprintf("input: %s", short_path(CLEAN_PATH)),
  sprintf("population: analysis %d（取自 00_setup.R 的 ANALYSIS_N）", analysis_n),
  sprintf("levels: %s；未填碼 34 不進整體檢定", paste(sprintf("%s(%s)", LEVELS, LEVEL_LABEL[LEVELS]), collapse = " / ")),
  sprintf("entanglement_note: 入學年齡與學歷 V = (見 A-51)，本檔不分層、不調整年齡"),
  vapply(PARENTS$parent, function(p) {
    s <- by_parent[by_parent$parent == p, ]
    sprintf("grad_rate[%s]: %s", p,
            paste(sprintf("%s %s (%d)", s$level, fmt_sig(s$grad_rate), s$n), collapse = " | "))
  }, character(1)),
  vapply(PARENTS$parent, function(p) {
    s <- financial[financial$parent == p, ]
    sprintf("scholarship_rate[%s]: %s", p,
            paste(sprintf("%s %s", s$level, fmt_sig(s$scholarship_rate)), collapse = " | "))
  }, character(1)),
  vapply(seq_len(nrow(tests)), function(i) {
    r <- tests[i, ]
    sprintf("test[%s x %s]: chi2=%s df=%d p=%s V=%s eta=%s n=%d exp_below_5=%d",
            r$parent, r$outcome, fmt_sig(r$chi2), r$df, fmt_sig(r$p_value),
            fmt_sig(r$cramer_v), fmt_sig(r$eta), r$n, r$exp_below_5)
  }, character(1)),
  vapply(seq_len(nrow(models)), function(i) {
    sprintf("model[%s]: r2=%s delta_r2=%s lrt_p=%s", models$model[i],
            fmt_sig(models$r2[i]), fmt_sig(models$delta_r2[i]), fmt_sig(models$lrt_p[i]))
  }, character(1)),
  sprintf("product: %s rows=%d before=%s after=%s", short_path(TABLE_LEVEL_PATH),
          nrow(by_parent), states_before[[1]], file_state(TABLE_LEVEL_PATH)),
  sprintf("product: %s rows=%d before=%s after=%s", short_path(TABLE_FIN_PATH),
          nrow(financial), states_before[[2]], file_state(TABLE_FIN_PATH)),
  sprintf("product: %s rows=%d before=%s after=%s", short_path(TABLE_TEST_PATH),
          nrow(tests), states_before[[3]], file_state(TABLE_TEST_PATH)),
  sprintf("product: %s rows=%d before=%s after=%s", short_path(TABLE_MODEL_PATH),
          nrow(models), states_before[[4]], file_state(TABLE_MODEL_PATH)),
  sprintf("product: %s rows=%d before=%s after=%s", short_path(TABLE_HIGHEST_PATH),
          nrow(highest_tbl), states_before[[5]], file_state(TABLE_HIGHEST_PATH)),
  sprintf("product: %s rows=%d before=%s after=%s", short_path(TABLE_GRAD_PATH),
          nrow(gradient), states_before[[6]], file_state(TABLE_GRAD_PATH)),
  sprintf("product: %s rows=%d before=%s after=%s", short_path(TABLE_ENT_PATH),
          nrow(entangle), states_before[[7]], file_state(TABLE_ENT_PATH)),
  vapply(seq_len(nrow(gradient)), function(i) {
    sprintf("gradient[%s]: rho=%s p=%s n=%d（級別作次序變數；單調版本）",
            gradient$parent[i], fmt_sig(gradient$spearman_rho[i]),
            fmt_sig(gradient$p_value[i]), gradient$n[i])
  }, character(1)),
  vapply(seq_len(nrow(entangle)), function(i) {
    sprintf("entanglement[%s x %s]: chi2=%s df=%d p=%s V=%s（只列為限制，不進模型）",
            entangle$parent[i], entangle$partner[i], fmt_sig(entangle$chi2[i]),
            entangle$df[i], fmt_sig(entangle$p_value[i]), fmt_sig(entangle$cramer_v[i]))
  }, character(1)),
  "status: ok",
  "next_step: 報告「社會背景之一：文化資本」一節引用 qualification_by_parent.csv、qualification_models.csv 與 highest_parent_education.csv；整體檢定引 qualification_tests.csv"
))

cat(sprintf("10_qualification: 分析母體 %d 人\n", analysis_n))
for (p in PARENTS$parent) {
  s <- by_parent[by_parent$parent == p, ]
  cat(sprintf("10_qualification: %s 畢業率 %s\n", p,
              paste(sprintf("%s=%s", s$level, fmt_sig(s$grad_rate)), collapse = " / ")))
}
cat(sprintf("10_qualification: χ²（學歷 × 畢業）p：母 %s、父 %s\n",
            fmt_sig(tests$p_value[tests$parent == "mother" & tests$outcome == "graduate"]),
            fmt_sig(tests$p_value[tests$parent == "father" & tests$outcome == "graduate"])))
cat(sprintf("10_qualification: R² 學歷 %s、財務 %s、兩者 %s、重疊 %s\n",
            fmt_sig(r_qual), fmt_sig(r_fin), fmt_sig(r_both), fmt_sig(shared)))
cat(sprintf("10_qualification: 表 %s 等七張\n", short_path(TABLE_LEVEL_PATH)))
