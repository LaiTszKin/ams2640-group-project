# 06_language.R — 語言文化的小樣本材料（F7）
#
# 一張表回答局限一節需要的四件事：各語言圈有多少人（含在讀）、其中多少可比較
# （僅畢業與退學）、退學率與其威爾遜區間、以及驗出觀察到的差距所需的每組人數。
# 本地只作對照、不佔列；對照組是西語圈，不是最大組——最大組是葡語圈，與本地
# 同語，不作跨語比較（tasks/T08 步驟 4、修訂 A-18）。
#
# 常數一律取自 00_setup.R，統計量取自 lib/stats.R（REQ-A-2、REQ-A-3；本檔不寫出
# 母體人數、信賴水準或 output/ 下的字面路徑）。
#
# 用法（專案根目錄）：Rscript programs/R/06_language.R
# 產物：
#   <OUT_ROOT>/tables/language_groups.csv  population 逐列填 full；本地不佔列
#   <OUT_ROOT>/logs/06_language.log        逐值國籍對應、三圈人數、對照與檢定力
#
# 國籍代碼→語言圈（依 UCI data dictionary 的國名，逐值寫入記錄）：
#   葡語圈：21 安哥拉、22 佛得角、24 幾內亞比紹、25 莫桑比克、26 聖多美、41 巴西
#   西語圈：6 西班牙、101 墨西哥、108 古巴、109 哥倫比亞
#   其餘非本地國籍：歸其他
#
# 退學率的兩個分母不可混用：n_members 含在讀（Enrolled），n 只含畢業與退學
# （ANALYSIS_RESULTS）；在讀者的結果未定，不入率的分母（PRD D2、F7 邊界）。

## 0. 由 00_setup.R 與 lib/stats.R 取得常數與統計量 -------------------------

source("programs/R/00_setup.R")
# stats.R 自行 source 00_setup.R；重複 source 為無操作
source("programs/R/lib/stats.R")

## 1. 路徑與判準 -----------------------------------------------------------

CLEAN_PATH <- file.path(PROJ_ROOT, "data", "processed", "ams2640_clean.csv")
TABLE_PATH <- file.path(OUT_ROOT, "tables", "language_groups.csv")
LOG_PATH <- file.path(OUT_ROOT, "logs", "06_language.log")

# 本地國籍代碼：只在對照組出現，不入表
LOCAL_CODE <- 1L

# 表的列序：三個語言圈依葡語、西語、其他的固定次序寫出，重跑逐位元組相同
GROUP_ORDER <- c("Portuguese", "Spanish", "Other")

# 對照組：西語圈。葡語圈與本地同語，不作跨語比較（tasks/T08 步驟 4）
COMPARISON_GROUP <- "Spanish"

# 小樣本門檻：某圈的可比較人數低於此值時該圈只出計數，率與區間留空
# （PRD F7 拒絕路徑；n 為零另記 refuse:empty-denominator，不中止）
MIN_GROUP_N <- 10L

# 檢定力：雙尾 α = 0.05、power = 0.8（tasks/T08 步驟 5）。兩者不屬母體界線、
# 年齡切點、分位數或兩端容差，00_setup.R 未持有，故在本檔具名，不寫成散落的數字
POWER_ALPHA <- 0.05
POWER_TARGET <- 0.8

# 國籍代碼 → 語言圈；未列於此表的非本地代碼一律歸 Other
NATIONALITY_GROUP <- c(
  `21` = "Portuguese",  # 安哥拉
  `22` = "Portuguese",  # 佛得角
  `24` = "Portuguese",  # 幾內亞比紹
  `25` = "Portuguese",  # 莫桑比克
  `26` = "Portuguese",  # 聖多美
  `41` = "Portuguese",  # 巴西
  `6` = "Spanish",      # 西班牙
  `101` = "Spanish",    # 墨西哥
  `108` = "Spanish",    # 古巴
  `109` = "Spanish"     # 哥倫比亞
)

# 記錄用的國名；本地與未列名的代碼另以字面說明，避免把猜測寫成對應
NATIONALITY_NAME <- c(
  `1` = "Portuguese (local)", `6` = "Spanish", `21` = "Angolan",
  `22` = "Cape Verdean", `24` = "Guinean", `25` = "Mozambican",
  `26` = "Santomean", `41` = "Brazilian", `101` = "Mexican",
  `108` = "Cuban", `109` = "Colombian"
)

## 2. 小工具 ---------------------------------------------------------------

stamp <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# 專案內的檔案以相對路徑呈現，專案外（注入測試的暫存根）才給絕對路徑
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

# 記錄一律追加一段；段內列序固定，時間戳只在段首
log_block <- function(lines) {
  dir.create(dirname(LOG_PATH), recursive = TRUE, showWarnings = FALSE)
  block <- c(sprintf("== 06_language %s ==", stamp()), lines, "")
  atomic_write(LOG_PATH, function(path) {
    previous <- if (file.exists(LOG_PATH)) readLines(LOG_PATH, warn = FALSE) else character()
    writeLines(c(previous, block), path, useBytes = TRUE)
  })
}

# 拒絕：先把理由與下一步寫進記錄，再以非零結束碼停止；不寫半份表
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

## 3. 讀清洗資料集 ---------------------------------------------------------

if (!file.exists(CLEAN_PATH)) {
  refuse("input-schema",
         sprintf("找不到清洗資料集 %s", short_path(CLEAN_PATH)),
         "先跑 programs/R/01_prep_data.R 產生清洗資料集後重跑。")
}

clean <- tryCatch(
  readr::read_csv(CLEAN_PATH, show_col_types = FALSE),
  error = function(e) e
)
if (inherits(clean, "error")) {
  refuse("input-schema",
         sprintf("清洗資料集無法解析：%s", conditionMessage(clean)),
         "確認檔案為 UTF-8 CSV、第一列為欄名後重跑。")
}

REQUIRED_COLS <- c("Nacionality", "target")
missing_cols <- setdiff(REQUIRED_COLS, names(clean))
if (length(missing_cols)) {
  refuse("input-schema",
         sprintf("清洗資料集缺欄：%s；現有欄名共 %d 個", paste(missing_cols, collapse = ", "), ncol(clean)),
         "以 01_prep_data.R 重建清洗資料集後重跑；本次未寫出任何表。")
}

KNOWN_RESULTS <- c(ANALYSIS_RESULTS, "Enrolled")
unknown_results <- setdiff(unique(as.character(clean$target)), KNOWN_RESULTS)
if (length(unknown_results)) {
  refuse("input-schema",
         sprintf("結果欄出現未登記的類別：%s", paste(unknown_results, collapse = ", ")),
         "確認清洗資料集來自 01_prep_data.R 的母體流程後重跑；本次未寫出任何表。")
}

## 4. 分圈 ---------------------------------------------------------------

n_rows <- nrow(clean)
code <- as.integer(clean$Nacionality)
target <- as.character(clean$target)

is_local <- !is.na(code) & code == LOCAL_CODE
# 未列名的非本地代碼歸其他；本地留在 NA，不進任何一圈
group <- unname(NATIONALITY_GROUP[as.character(code)])
group[is.na(group) & !is.na(code) & !is_local] <- "Other"
group[is_local] <- NA_character_

comparable <- target %in% ANALYSIS_RESULTS
in_circle <- !is.na(group)

unmapped <- setdiff(sort(unique(code[in_circle & group == "Other"])), as.integer(names(NATIONALITY_GROUP)))

## 5. 對照組（本地） -------------------------------------------------------

local_dropout <- sum(is_local & target == "Dropout")
local_n <- sum(is_local & comparable)
local_rate <- if (local_n > 0) local_dropout / local_n else NA_real_

## 6. 逐圈計算 -----------------------------------------------------------

# 檢定力：兩獨立比例、雙尾 α、指定 power，以觀察到的兩個比例與未合併變異數計算
required_per_group <- function(p1, p2, alpha = POWER_ALPHA, power = POWER_TARGET) {
  if (!is.finite(p1) || !is.finite(p2)) return(NA_real_)
  delta <- abs(p1 - p2)
  if (delta == 0) return(NA_real_)
  z_alpha <- stats::qnorm(1 - alpha / 2)
  z_power <- stats::qnorm(power)
  (z_alpha + z_power)^2 * (p1 * (1 - p1) + p2 * (1 - p2)) / delta^2
}

rows <- vector("list", length(GROUP_ORDER))
log_rows <- character()
refusals <- character()

for (i in seq_along(GROUP_ORDER)) {
  g <- GROUP_ORDER[i]
  member <- in_circle & !is.na(group) & group == g

  n_members <- sum(member)
  n_group <- sum(member & comparable)
  k_dropout <- sum(member & target == "Dropout")

  rate <- NA_real_
  ci_low <- NA_real_
  ci_high <- NA_real_
  p_vs_local <- NA_real_
  n_required <- NA_real_
  raw_required <- NA_real_
  note <- "ok"

  if (n_group == 0L) {
    # refuse:empty-denominator：該圈列 n=0 並在記錄寫明，不中止
    note <- "refuse:empty-denominator"
    refusals <- c(refusals, sprintf("- %s：可比較人數為 0（n_members=%d），該列只出計數", g, n_members))
  } else if (n_group < MIN_GROUP_N) {
    # 小樣本：入表、率與區間留空
    note <- "insufficient_n"
    refusals <- c(refusals, sprintf("- %s：n=%d < %d，率與區間留空（insufficient_n）", g, n_group, MIN_GROUP_N))
  } else {
    interval <- prop_ci(k_dropout, n_group)
    if (identical(interval, "refuse:empty-denominator")) {
      note <- "refuse:empty-denominator"
      refusals <- c(refusals, sprintf("- %s：prop_ci 回 refuse:empty-denominator，率與區間留空", g))
    } else {
      rate <- interval$estimate
      ci_low <- interval$lower
      ci_high <- interval$upper
    }
  }

  # 對照檢定只在西語圈做；葡語圈與本地同語，p 留空（tasks/T08 步驟 4）
  if (identical(g, COMPARISON_GROUP) && n_group > 0L && local_n > 0L) {
    test <- fisher_2x2(k_dropout, n_group - k_dropout, local_dropout, local_n - local_dropout)
    if (identical(test, "refuse:empty-denominator")) {
      refusals <- c(refusals, sprintf("- %s：與本地比對的邊際和為零，p 留空", g))
    } else {
      p_vs_local <- test$p_value
      raw_required <- required_per_group(rate, local_rate)
      # 人數取整（向上），未取整的值寫入記錄供核算
      if (is.finite(raw_required)) n_required <- as.integer(ceiling(raw_required))
    }
  }

  rows[[i]] <- data.frame(
    population = "full",
    group = g,
    n_members = as.integer(n_members),
    n = as.integer(n_group),
    dropout_rate = rate,
    ci_low = ci_low,
    ci_high = ci_high,
    p_vs_local = p_vs_local,
    required_per_group = n_required,
    stringsAsFactors = FALSE
  )

  log_rows <- c(log_rows, sprintf(
    "- %-10s n_members=%d n=%d dropout=%d dropout_rate=%s ci=[%s, %s] p_vs_local=%s required_per_group=%s status=%s",
    g, n_members, n_group, k_dropout,
    if (is.na(rate)) "NA" else sprintf("%.10f", rate),
    if (is.na(ci_low)) "NA" else sprintf("%.10f", ci_low),
    if (is.na(ci_high)) "NA" else sprintf("%.10f", ci_high),
    if (is.na(p_vs_local)) "NA" else sprintf("%.10f", p_vs_local),
    if (is.na(n_required)) "NA" else sprintf("%d（未取整 %.6f）", n_required, raw_required),
    note
  ))
}

table_out <- do.call(rbind, rows)

## 7. 不變量檢查 ---------------------------------------------------------

non_local_members <- sum(in_circle)
circle_sum <- sum(table_out$n_members)
if (circle_sum != non_local_members) {
  refuse("input-schema",
         sprintf("三圈 n_members 合計 %d 與非本地人數 %d 不符（有列未歸圈）", circle_sum, non_local_members),
         "檢查國籍代碼的對應與缺值後重跑；本次未寫出表。")
}
comparable_total <- sum(table_out$n)
if (comparable_total > non_local_members) {
  refuse("input-schema",
         sprintf("可比較人數 %d 大於非本地人數 %d", comparable_total, non_local_members),
         "檢查結果欄的類別與 ANALYSIS_RESULTS 後重跑；本次未寫出表。")
}

## 8. 寫表與記錄 ---------------------------------------------------------

table_before <- file_state(TABLE_PATH)
atomic_write(TABLE_PATH, function(path) readr::write_csv(table_out, path, na = ""))

# 逐值國籍對應：每一個出現在資料裡的代碼一列（含本地與歸其他的代碼）
observed_codes <- sort(unique(code[!is.na(code)]))
map_lines <- vapply(observed_codes, function(cd) {
  members <- sum(code == cd & !is.na(code))
  in_group <- group[code == cd & !is.na(code)]
  label <- if (as.character(cd) %in% names(NATIONALITY_NAME)) {
    unname(NATIONALITY_NAME[as.character(cd)])
  } else {
    "unlisted"
  }
  placed <- if (cd == LOCAL_CODE) "local (control)" else in_group[1]
  sprintf("- %3d %-28s members=%3d -> %s", cd, label, members, placed)
}, character(1))

log_block(c(
  sprintf("r_version: %s", R.version.string),
  sprintf("input: %s", short_path(CLEAN_PATH)),
  sprintf("input_rows: %d", n_rows),
  sprintf("out_root: %s", OUT_ROOT),
  sprintf("non_local_members: %d", non_local_members),
  sprintf("comparable_total: %d（畢業與退學；含在讀的非本地人數為 %d）",
          comparable_total, non_local_members - comparable_total),
  sprintf("circle_members: Portuguese=%d Spanish=%d Other=%d",
          table_out$n_members[1], table_out$n_members[2], table_out$n_members[3]),
  sprintf("circle_n: Portuguese=%d Spanish=%d Other=%d",
          table_out$n[1], table_out$n[2], table_out$n[3]),
  "nationality_map (國籍代碼 -> 語言圈；依 UCI data dictionary 的國名):",
  map_lines,
  sprintf("portuguese_codes: %s", paste(sort(as.integer(names(NATIONALITY_GROUP)[NATIONALITY_GROUP == "Portuguese"])), collapse = ", ")),
  sprintf("spanish_codes: %s", paste(sort(as.integer(names(NATIONALITY_GROUP)[NATIONALITY_GROUP == "Spanish"])), collapse = ", ")),
  sprintf("other_codes: %s", if (length(unmapped)) paste(unmapped, collapse = ", ") else "none"),
  sprintf("local_control: code=%d n_members=%d n=%d dropout=%d dropout_rate=%s（本地不佔列）",
          LOCAL_CODE, sum(is_local), local_n, local_dropout,
          if (is.na(local_rate)) "NA" else sprintf("%.10f", local_rate)),
  sprintf("comparison: %s vs local（最大組為葡語圈，與本地同語，不作跨語比較）", COMPARISON_GROUP),
  sprintf("p_vs_local_rule: 只在 %s 列填值；其餘圈留空", COMPARISON_GROUP),
  "test: fisher_2x2 雙尾精確檢定（lib/stats.R）",
  sprintf("ci: prop_ci 威爾遜分數區間，level = %s", format(PROP_CI_LEVEL)),
  sprintf("small_sample_rule: n < %d 者入表、dropout_rate 與區間留空（insufficient_n）", MIN_GROUP_N),
  sprintf("power: alpha=%s two-sided, power=%s, 兩獨立比例未合併變異數；required_per_group 取整向上",
          format(POWER_ALPHA), format(POWER_TARGET)),
  if (length(refusals)) c("refusals:", refusals) else "refusals: none",
  "rows:",
  log_rows,
  sprintf("table: %s rows=%d cols=%d before=%s after=%s",
          short_path(TABLE_PATH), nrow(table_out), ncol(table_out), table_before, file_state(TABLE_PATH)),
  "status: ok",
  "note: 本表只出局限材料；不以分組差異下結論（PRD D7、Q31 已撤回）"
))

cat(sprintf("06_language: 非本地 %d 人（葡語 %d、西語 %d、其他 %d），可比較 %d 人\n",
            non_local_members, table_out$n_members[1], table_out$n_members[2],
            table_out$n_members[3], comparable_total))
cat(sprintf("06_language: 西語圈 n=%d、退學率 %s、p=%s、每組需 %s 人\n",
            table_out$n[2],
            fmt_sig(table_out$dropout_rate[2]),
            fmt_sig(table_out$p_vs_local[2]),
            if (is.na(table_out$required_per_group[2])) "NA" else format(table_out$required_per_group[2])))
cat(sprintf("06_language: 表 %s（%d 列）\n", short_path(TABLE_PATH), nrow(table_out)))
