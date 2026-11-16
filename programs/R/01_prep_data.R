# 01_prep_data.R — 分析母體與清洗資料集（F2）
#
# 一條指令做四件事：讀原始資料、清洗、寫三種資料格式、寫母體清冊。
# 常數一律取自 00_setup.R，本檔不寫出母體人數、年齡切點或 output/ 字面路徑（REQ-A-2）。
#
# 用法（專案根目錄）：Rscript programs/R/01_prep_data.R
# 產物：
#   data/processed/ams2640_clean.csv    清洗後文字格式（欄名保留原名，去掉欄名內的定位字元）
#   data/processed/ams2640.sas7bdat     SAS 可讀格式（欄名正規化，對應表入記錄）
#   data/processed/ams2640.xpt          SAS 備援格式（同上）
#   <OUT_ROOT>/tables/population_ledger.csv  母體清冊，九列固定
#   <OUT_ROOT>/logs/01_prep.log               缺值登記、新舊檔案時間、拒絕理由與下一步
#
# 輸入可由 RTOOLKIT_RAW_PATH 指向另一份副本（供拒絕分支的注入測試），預設為 data/raw/data.csv。

## 0. 唯讀守衛：寫入目標不得落在原始資料目錄內（在任何 dir.create 之前） ------

# 拒絕必須零副作用：refuse:readonly-target 之後，原始資料目錄的列舉要與執行前逐行相同。
# 00_setup.R 的自檢記錄自己就會 dir.create(OUT_ROOT/logs)——若 OUT_ROOT 指進 data/raw，
# 那次建立已經是「拒絕卻留下空目錄」的副作用，而且發生在任何判定之前。故本段把
# 「算路徑」與「建目錄」拆成兩段：這裡只算字串並判定，通過後才由 §1 source 00_setup.R
# 去建目錄。專案根與輸出根用的規則與 00_setup.R 第 1 節相同，兩邊算出的路徑逐字相同。

# 路徑的實體解析：先解開符號連結，且對「尚不存在」的目標同樣成立。
# normalizePath(mustWork = FALSE) 對不存在的路徑原樣返回輸入、不解連結；輸出目標通常
# 尚未存在（第一次產出），而原始資料目錄的另一種拼法若是連結（macOS 的 /var →
# /private/var），字串比較就會漏判（A-44 S1）。故解析到**最接近的既有祖先**：把該祖先
# 解析成實體路徑後，再接回尚未存在的尾部；目標本身已存在時整條解析（連尾端的連結一併解開）。
resolve_path <- function(path) {
  p <- sub("/+$", "", as.character(path))
  if (!nzchar(p)) return("/")                       # 輸入是根目錄本身
  if (file.exists(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  tail <- character()
  cur <- p
  repeat {
    parent <- dirname(cur)
    if (identical(parent, cur)) break                # 已上溯到根仍不存在
    tail <- c(basename(cur), tail)
    cur <- parent
    if (file.exists(cur)) {
      ancestor <- normalizePath(cur, winslash = "/", mustWork = TRUE)
      return(do.call(file.path, c(list(ancestor), tail)))
    }
  }
  normalizePath(p, winslash = "/", mustWork = FALSE)  # 連祖先都不存在：退回原樣
}

# 寫入前的「目標不在原始資料目錄內」判定（REQ-F-F2-2 的 refuse:readonly-target）。
# 兩邊都先解到實體路徑再比，故「輸出根以符號連結指進原始資料目錄」與「以實體路徑直指」
# 得到同一個判定；前綴帶分隔字元，data/raw2 因此不會被 data/raw 誤判。
is_inside <- function(path, dir) {
  p <- resolve_path(path)
  d <- resolve_path(dir)
  if (identical(d, "/")) return(TRUE)                # 原始資料在根目錄：其下全算在內
  identical(p, d) || startsWith(p, paste0(d, "/"))
}

# 專案內的檔案以相對路徑呈現，專案外（注入測試的暫存副本）才給絕對路徑。
# 根由呼叫端給：本段跑在 00_setup.R 之前，PROJ_ROOT 尚未存在（預設值屆時才取值）。
short_path <- function(path, root = PROJ_ROOT) {
  prefix <- paste0(root, "/")
  ifelse(startsWith(path, prefix), substring(path, nchar(prefix) + 1L), path)
}

# 目錄列舉（排序後的字串）：只讀，用作「拒絕前後逐行相同」的自檢基準
dir_listing <- function(dir) {
  if (!dir.exists(dir)) return(character())
  sort(list.files(dir, all.files = TRUE, no.. = TRUE))
}

# 五個寫入目標的路徑字串（不建立目錄）。§0 的守衛與 §2 的實際寫入共用同一份拼法，
# 兩處不會各自漂移。
prep_paths <- function(proj_root, out_root) {
  processed_dir <- file.path(proj_root, "data", "processed")
  list(
    processed_dir = processed_dir,
    clean = file.path(processed_dir, "ams2640_clean.csv"),
    sas = file.path(processed_dir, "ams2640.sas7bdat"),
    xpt = file.path(processed_dir, "ams2640.xpt"),
    ledger = file.path(out_root, "tables", "population_ledger.csv"),
    log = file.path(out_root, "logs", "01_prep.log")
  )
}
WRITE_TARGET_KEYS <- c("clean", "sas", "xpt", "ledger", "log")

# 拒絕本體：任一寫入目標落在原始資料目錄內即停止。除判定外只多做一件自檢——把拒絕
# 當下的列舉與執行前的列舉相比，有新增項就是缺陷（拒絕本應零副作用），在輸出中明示。
# 記錄本身也落在同一個目錄，故這裡不寫記錄，只把拒絕內容印到 stderr。
refuse_readonly <- function(paths, raw_dir, root, listing_before) {
  targets <- unname(unlist(paths[WRITE_TARGET_KEYS], use.names = FALSE))
  violating <- targets[vapply(targets, is_inside, logical(1), dir = raw_dir)]
  if (!length(violating)) return(invisible(NULL))
  added <- setdiff(dir_listing(raw_dir), listing_before)
  if (length(added)) {
    cat(sprintf(
      "01_prep_data: 缺陷——拒絕路徑在 %s 新增了 %s（拒絕應零副作用，A-44 S1 的殘餘）\n",
      short_path(raw_dir, root), paste(added, collapse = ", ")
    ), file = stderr())
  }
  stop(
    sprintf(
      "refuse:readonly-target\n- 寫入目標落在原始資料目錄 %s 內：%s\n- 下一步：把 RTOOLKIT_OUT_ROOT 指回專案的 output/（或任何不在 data/raw 下的目錄）後重跑；原始資料未變動。",
      short_path(raw_dir, root), paste(short_path(violating, root), collapse = ", ")
    ),
    call. = FALSE
  )
}

# 守衛的執行：只算路徑、取列舉、判定。此後專案內才會出現第一個目錄（§1 的自檢記錄）。
raw_listing_before <- local({
  root <- here::here()
  out_root <- Sys.getenv("RTOOLKIT_OUT_ROOT", unset = "")
  if (!nzchar(out_root)) out_root <- file.path(root, "output")
  raw_path <- Sys.getenv("RTOOLKIT_RAW_PATH", unset = "")
  if (!nzchar(raw_path)) raw_path <- file.path(root, "data", "raw", "data.csv")
  raw_path <- normalizePath(raw_path, winslash = "/", mustWork = FALSE)

  raw_dir <- dirname(raw_path)
  listing <- dir_listing(raw_dir)                    # 執行前的列舉（自檢基準）
  refuse_readonly(prep_paths(root, out_root), raw_dir, root, listing)
  listing
})

## 1. 由 00_setup.R 取得常數 -------------------------------------------------

# 唯讀守衛（§0）已在任何目錄被建立之前通過，此後才輪到 00_setup.R 的自檢記錄寫入。
source("programs/R/00_setup.R")

## 2. 路徑與固定形狀 -------------------------------------------------------

RAW_PATH <- Sys.getenv("RTOOLKIT_RAW_PATH", unset = "")
if (!nzchar(RAW_PATH)) RAW_PATH <- file.path(PROJ_ROOT, "data", "raw", "data.csv")
RAW_PATH <- normalizePath(RAW_PATH, winslash = "/", mustWork = FALSE)
RAW_DIR <- dirname(RAW_PATH)

PROCESSED_DIR <- file.path(PROJ_ROOT, "data", "processed")
PATHS <- prep_paths(PROJ_ROOT, OUT_ROOT)             # 與 §0 同一份拼法
CLEAN_PATH <- PATHS$clean
SAS_PATH <- PATHS$sas
XPT_PATH <- PATHS$xpt
LEDGER_PATH <- PATHS$ledger
LOG_PATH <- PATHS$log

# 寫入前複核（REQ-F-F2-2）：§0 的判定用的是「與 00_setup.R 同規則自行算出的根」，
# 這裡再用 00_setup.R 匯出的 PROJ_ROOT／OUT_ROOT 判一次。正常情形不會觸發；留著是
# 為了兩處的根一旦分岔就當場拒絕，而不是寫進原始資料目錄。
refuse_readonly(PATHS, RAW_DIR, PROJ_ROOT, raw_listing_before)

# 原始資料的形狀：36 個變數加結果欄。欄數不符即 refuse:input-schema（REQ-F-F2-3）。
EXPECTED_COLS <- 37L

# 結果欄：原名 Target，寫出時改名為 target（清洗資料集與兩種 SAS 格式同名）。
RESULT_COL <- "Target"
RESULT_OUT <- "target"

# 三個既知類別；00_setup.R 只匯出入分析母體的兩個，第三個是剩下的 Enrolled。
KNOWN_RESULTS <- c(ANALYSIS_RESULTS, "Enrolled")

# SAS 欄名：≤32 字元且僅 [A-Za-z0-9_]。原欄名含空格、括號、斜線，其中十個超過 32 字元，
# 兩種 SAS 格式實測皆寫不出，故先正規化。命名沿用既有交付檔的 SAS 端詞彙
# （cu1_*／cu2_* 一類），使既有 SAS 程式與新檔對得上；原名 → 新名逐項寫入記錄。
SAS_NAME_MAP <- c(
  "Marital status" = "marital_status",
  "Application mode" = "app_mode",
  "Application order" = "app_order",
  "Course" = "course",
  "Daytime/evening attendance" = "attendance",
  "Previous qualification" = "prev_qual",
  "Previous qualification (grade)" = "prev_qual_grade",
  "Nacionality" = "nationality",
  "Mother's qualification" = "mother_qual",
  "Father's qualification" = "father_qual",
  "Mother's occupation" = "mother_occ",
  "Father's occupation" = "father_occ",
  "Admission grade" = "admission_grade",
  "Displaced" = "displaced",
  "Educational special needs" = "spec_needs",
  "Debtor" = "debtor",
  "Tuition fees up to date" = "tuition_uptodate",
  "Gender" = "gender",
  "Scholarship holder" = "scholarship",
  "Age at enrollment" = "age_enrol",
  "International" = "international",
  "Curricular units 1st sem (credited)" = "cu1_credited",
  "Curricular units 1st sem (enrolled)" = "cu1_enrolled",
  "Curricular units 1st sem (evaluations)" = "cu1_evals",
  "Curricular units 1st sem (approved)" = "cu1_approved",
  "Curricular units 1st sem (grade)" = "cu1_grade",
  "Curricular units 1st sem (without evaluations)" = "cu1_noevals",
  "Curricular units 2nd sem (credited)" = "cu2_credited",
  "Curricular units 2nd sem (enrolled)" = "cu2_enrolled",
  "Curricular units 2nd sem (evaluations)" = "cu2_evals",
  "Curricular units 2nd sem (approved)" = "cu2_approved",
  "Curricular units 2nd sem (grade)" = "cu2_grade",
  "Curricular units 2nd sem (without evaluations)" = "cu2_noevals",
  "Unemployment rate" = "unemployment",
  "Inflation rate" = "inflation",
  "GDP" = "gdp"
)
# 結果欄在清洗資料集已改名為 target，SAS 端沿用同名（對應表以清洗資料集的欄名為鍵）
SAS_NAME_MAP[RESULT_OUT] <- RESULT_OUT

## 3. 小工具 ---------------------------------------------------------------

stamp <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# 檔案狀態；缺席時記 absent 而不是錯誤，讓「第一次產出」與「覆蓋舊產物」都留得下時間
file_state <- function(path) {
  if (!file.exists(path)) return("absent")
  info <- file.info(path)
  sprintf("%s bytes=%s", format(info$mtime, "%Y-%m-%dT%H:%M:%S%z"), format(info$size, scientific = FALSE))
}

file_mtime <- function(path) if (file.exists(path)) format(file.info(path)$mtime, "%Y-%m-%dT%H:%M:%S%z") else "absent"

# 先寫同目錄的暫存檔再改名，半途失敗不留半份資料集
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
  block <- c(sprintf("== 01_prep_data %s ==", stamp()), lines, "")
  atomic_write(LOG_PATH, function(path) {
    previous <- if (file.exists(LOG_PATH)) readLines(LOG_PATH, warn = FALSE) else character()
    writeLines(c(previous, block), path, useBytes = TRUE)
  })
}

# 拒絕：先把理由與下一步寫進記錄，再以非零結束碼停止；母體清冊不動（REQ-F-F2-3）
refuse <- function(class, reason, next_step) {
  log_block(c(
    sprintf("input: %s", short_path(RAW_PATH)),
    sprintf("status: refuse:%s", class),
    sprintf("reason: %s", reason),
    sprintf("next_step: %s", next_step)
  ))
  stop(
    sprintf("refuse:%s\n- %s\n- 下一步：%s", class, reason, next_step),
    call. = FALSE
  )
}

# 母體清冊的形狀：population 取三個具名值之一，n 為該列母體總數，value 為指標的值
ledger_row <- function(population, metric, n, value) {
  data.frame(population = population, metric = metric, n = as.integer(n), value = as.integer(value),
             stringsAsFactors = FALSE)
}

## 4. 讀原始資料 -----------------------------------------------------------

if (!file.exists(RAW_PATH)) {
  refuse("input-schema", sprintf("找不到原始資料 %s", short_path(RAW_PATH)),
         "確認檔案路徑（必要時設 RTOOLKIT_RAW_PATH）後重跑。")
}

raw_before <- file_state(RAW_PATH)

raw <- tryCatch(
  utils::read.csv(RAW_PATH, sep = ";", encoding = "UTF-8-BOM", check.names = FALSE,
                  stringsAsFactors = FALSE),
  error = function(e) e
)
if (inherits(raw, "error")) {
  refuse("input-schema", sprintf("原始資料無法解析：%s", conditionMessage(raw)),
         "確認分隔符為分號、編碼為 UTF-8、第一列為欄名後重跑。")
}

## 5. 欄數與類別檢查（REQ-F-F2-3） -----------------------------------------

if (ncol(raw) != EXPECTED_COLS) {
  refuse("input-schema",
         sprintf("欄數為 %d，契約要求 %d（36 個變數加結果欄）", ncol(raw), EXPECTED_COLS),
         sprintf("換回契約界定的那一份原始資料後重跑；本次未寫出任何產品，母體清冊未更新。"))
}

# 欄名清洗：去掉定位字元與首尾空白（第五欄原名結尾帶一個定位字元），收斂連續空白
names(raw) <- gsub(" {2,}", " ", trimws(gsub("\t", " ", names(raw))))
if (anyDuplicated(names(raw))) {
  refuse("input-schema",
         sprintf("清洗後欄名重複：%s", paste(unique(names(raw)[duplicated(names(raw))]), collapse = ", ")),
         "檢查原始檔的欄名後重跑。")
}
if (!RESULT_COL %in% names(raw)) {
  refuse("input-schema",
         sprintf("找不到結果欄 %s；現有欄名：%s", RESULT_COL, paste(names(raw), collapse = " | ")),
         "確認結果欄的欄名後重跑。")
}

observed_results <- sort(unique(as.character(raw[[RESULT_COL]])))
if (!setequal(observed_results, sort(KNOWN_RESULTS))) {
  extra <- setdiff(observed_results, KNOWN_RESULTS)
  absent <- setdiff(KNOWN_RESULTS, observed_results)
  refuse("input-schema",
         sprintf("結果欄含未知類別（多出：%s；缺少：%s）；實測為 %s，契約為 %s",
                 if (length(extra)) paste(extra, collapse = ", ") else "無",
                 if (length(absent)) paste(absent, collapse = ", ") else "無",
                 paste(observed_results, collapse = ", "),
                 paste(sort(KNOWN_RESULTS), collapse = ", ")),
         "換回類別為 Graduate／Dropout／Enrolled 的原始資料後重跑；母體清冊未更新。")
}

# 其餘 36 欄須為數值：整欄被讀成字元即代表有非數值內容，寫進 SAS 會靜默變成缺值
others <- setdiff(names(raw), RESULT_COL)
non_numeric <- others[!vapply(raw[others], is.numeric, logical(1))]
if (length(non_numeric)) {
  refuse("input-schema",
         sprintf("%d 個非結果欄不是數值欄：%s", length(non_numeric), paste(non_numeric, collapse = ", ")),
         "檢查這些欄的內容（非數值文字或千分位逗號）後重跑。")
}

## 6. 缺值登記（refuse:missing-profile） -----------------------------------

# 「未登記修讀」= 兩學期 enrolled 皆 0 的列：那是 0，不是缺值，故不計入缺值總數
enrolled_cols <- c("Curricular units 1st sem (enrolled)", "Curricular units 2nd sem (enrolled)")
no_registration <- raw[[enrolled_cols[1]]] == 0 & raw[[enrolled_cols[2]]] == 0
missing_by_col <- vapply(raw[!no_registration, ], function(x) sum(is.na(x)), integer(1))
missing_cells <- sum(missing_by_col)

if (missing_cells > MISSING_PROFILE) {
  detail <- missing_by_col[missing_by_col > 0]
  refuse("missing-profile",
         sprintf("缺值儲存格 %d 個，超出上限 %d（不含未登記修讀的 %d 列）：%s",
                 missing_cells, MISSING_PROFILE, sum(no_registration),
                 paste(sprintf("%s=%d", names(detail), detail), collapse = ", ")),
         "補齊這些欄的值後重跑，或由主代理調整 00_setup.R 的 MISSING_PROFILE；本次未寫出任何產品。")
}

## 7. 母體界線 -------------------------------------------------------------

# 舊產物的時間先取，寫完再取一次；記錄同時留新舊兩邊，覆蓋舊檔時看得出換了什麼
clean_before <- file_state(CLEAN_PATH)
sas_before <- file_state(SAS_PATH)
xpt_before <- file_state(XPT_PATH)
ledger_before <- file_state(LEDGER_PATH)

result <- as.character(raw[[RESULT_COL]])
sem2_grade <- raw[["Curricular units 2nd sem (grade)"]]

in_analysis <- result %in% ANALYSIS_RESULTS
# 第二學期成績嚴格大於門檻才算「有成績」；零分是「無成績」，不是低能力（PRD D4）
has_score <- sem2_grade > ABILITY_MIN_SCORE

total_n <- nrow(raw)
graduate_n <- sum(result == "Graduate")
dropout_n <- sum(result == "Dropout")
enrolled_n <- sum(result == "Enrolled")
analysis_n <- sum(in_analysis)
ability_n <- sum(in_analysis & has_score)
no_registration_n <- sum(no_registration)
zero_sem2_n <- sum(in_analysis & !has_score)
# 第二學期零分且結果為退學者：這一組不進能力母體
zero_sem2_dropout_n <- sum(in_analysis & !has_score & result == "Dropout")
score_full_n <- sum(has_score)

# 母體界線須與 00_setup.R 的釘值一致；不一致代表這份輸入已不是研究界定的那一群
checks <- c(
  total = total_n == RETIRED_ANALYSIS_N,
  analysis = analysis_n == ANALYSIS_N,
  ability = ability_n == ABILITY_N,
  partition = graduate_n + dropout_n + enrolled_n == total_n,
  retired = graduate_n + dropout_n + enrolled_n == RETIRED_ANALYSIS_N
)
if (!all(checks)) {
  refuse("input-schema",
         sprintf("實算母體與 00_setup.R 不符：total=%d（%d）、analysis=%d（%d）、ability=%d（%d）",
                 total_n, RETIRED_ANALYSIS_N, analysis_n, ANALYSIS_N, ability_n, ABILITY_N),
         "換回契約界定的那一份原始資料後重跑；母體清冊未更新。")
}

## 8. 寫三種資料格式 -------------------------------------------------------

# 結果欄改名為 target；其餘欄名保留原名（清洗資料集是下游分析腳本的欄名來源）
clean <- raw
names(clean)[names(clean) == RESULT_COL] <- RESULT_OUT

# SAS 兩式的欄名正規化：先取對應表的目標名，再驗證 SAS 的命名限制
unknown <- setdiff(names(clean), names(SAS_NAME_MAP))
if (length(unknown)) {
  refuse("input-schema",
         sprintf("欄名對應表缺 %d 個欄位：%s", length(unknown), paste(unknown, collapse = " | ")),
         "補上 SAS 欄名對應後重跑。")
}
sas <- clean
names(sas) <- unname(SAS_NAME_MAP[names(clean)])
invalid <- names(sas)[!grepl("^[A-Za-z][A-Za-z0-9_]{0,31}$", names(sas))]
if (length(invalid)) {
  refuse("input-schema",
         sprintf("正規化後仍有不合格的 SAS 欄名：%s", paste(invalid, collapse = ", ")),
         "修正對應表後重跑。")
}
# factor 先轉字元：haven 寫 SAS 時 factor 會落成數值碼
sas[] <- lapply(sas, function(x) if (is.factor(x)) as.character(x) else x)

atomic_write(CLEAN_PATH, function(path) readr::write_csv(clean, path, na = ""))
# write_sas 在 haven 2.5.2 已標 deprecated，但仍是 .sas7bdat 的唯一寫入路徑
atomic_write(SAS_PATH, function(path) suppressWarnings(haven::write_sas(sas, path)))
atomic_write(XPT_PATH, function(path) haven::write_xpt(sas, path, version = 8, name = "ams2640"))

## 9. 母體清冊（九列固定） -------------------------------------------------

ledger <- rbind(
  ledger_row("full", "total", RETIRED_ANALYSIS_N, total_n),
  ledger_row("full", "graduate", RETIRED_ANALYSIS_N, graduate_n),
  ledger_row("full", "dropout", RETIRED_ANALYSIS_N, dropout_n),
  ledger_row("full", "enrolled", RETIRED_ANALYSIS_N, enrolled_n),
  ledger_row("analysis", "analysis", ANALYSIS_N, analysis_n),
  ledger_row("analysis", "no_registration_rows", ANALYSIS_N, no_registration_n),
  ledger_row("analysis", "zero_score_sem2", ANALYSIS_N, zero_sem2_n),
  ledger_row("analysis", "zero_score_sem2_dropout", ANALYSIS_N, zero_sem2_dropout_n),
  ledger_row("ability", "ability", ABILITY_N, ability_n)
)
if (nrow(ledger) != 9L) stop("母體清冊列數不為 9", call. = FALSE)

atomic_write(LEDGER_PATH, function(path) readr::write_csv(ledger, path))

## 10. 記錄 ----------------------------------------------------------------

log_block(c(
  sprintf("r_version: %s", R.version.string),
  sprintf("proj_root: %s", PROJ_ROOT),
  sprintf("out_root: %s", OUT_ROOT),
  sprintf("input: %s", short_path(RAW_PATH)),
  sprintf("input_state_before: %s", raw_before),
  sprintf("input_rows: %d", total_n),
  sprintf("input_cols: %d", ncol(raw)),
  sprintf("result_categories: %s", paste(observed_results, collapse = ", ")),
  sprintf("result_categories_expected: %s", paste(sort(KNOWN_RESULTS), collapse = ", ")),
  sprintf("missing_cells: %d", missing_cells),
  sprintf("missing_cells_limit: %d", MISSING_PROFILE),
  sprintf("missing_columns_registered: %s",
          if (any(missing_by_col > 0)) {
            paste(sprintf("%s=%d", names(missing_by_col)[missing_by_col > 0],
                          missing_by_col[missing_by_col > 0]), collapse = ", ")
          } else {
            sprintf("none（%d 欄皆無缺值）", length(missing_by_col))
          }),
  sprintf("missing_cells_excluded_rows: %d", no_registration_n),
  sprintf("no_registration_rule: Curricular units 1st sem (enrolled) = 0 且 2nd sem (enrolled) = 0"),
  sprintf("population: full total %d", total_n),
  sprintf("population: full graduate %d", graduate_n),
  sprintf("population: full dropout %d", dropout_n),
  sprintf("population: full enrolled %d", enrolled_n),
  sprintf("population: analysis analysis %d", analysis_n),
  sprintf("population: analysis no_registration_rows %d（全樣本上兩學期 enrolled 皆 0；其中 %d 列在分析母體內）",
          no_registration_n, sum(no_registration & in_analysis)),
  sprintf("population: analysis zero_score_sem2 %d", zero_sem2_n),
  sprintf("population: analysis zero_score_sem2_dropout %d", zero_sem2_dropout_n),
  sprintf("population: ability ability %d", ability_n),
  sprintf("ability_rule: 分析母體 ∩ Curricular units 2nd sem (grade) > %s", format(ABILITY_MIN_SCORE)),
  sprintf("ability_basis_full_sample: %d（差額 %d 全為在讀者）", score_full_n, score_full_n - ability_n),
  sprintf("population_checks: %s", if (all(checks)) "ok" else "mismatch"),
  sprintf("product: %s before=%s after=%s", short_path(CLEAN_PATH), clean_before, file_state(CLEAN_PATH)),
  sprintf("product: %s before=%s after=%s", short_path(SAS_PATH), sas_before, file_state(SAS_PATH)),
  sprintf("product: %s before=%s after=%s", short_path(XPT_PATH), xpt_before, file_state(XPT_PATH)),
  sprintf("ledger: %s rows=%d before=%s after=%s", short_path(LEDGER_PATH), nrow(ledger),
          ledger_before, file_state(LEDGER_PATH)),
  sprintf("sas_writer: haven::write_sas（haven %s，已標 deprecated 但為 .sas7bdat 唯一寫入路徑）；haven::write_xpt version=8",
          format(utils::packageVersion("haven"))),
  "sas_binary_note: 兩種 SAS 格式的檔頭含建立時間，逐位元組不隨重跑固定；可重現的是內容（列數、欄名與逐值）",
  sprintf("input_state_after: %s（只讀；本次未寫入原始資料）", file_state(RAW_PATH)),
  "column_name_map (清洗資料集 -> SAS):",
  sprintf("- %s -> %s", names(SAS_NAME_MAP), unname(SAS_NAME_MAP)),
  "status: ok",
  "next_step: programs/R/02_wealth.R 起可讀 data/processed/ams2640_clean.csv，母體自 population_ledger.csv 取"
))

cat(sprintf("01_prep_data: %d 列 x %d 欄 -> %s\n", total_n, ncol(clean), short_path(CLEAN_PATH)))
cat(sprintf("01_prep_data: 三種格式已寫出：%s\n",
            paste(short_path(c(CLEAN_PATH, SAS_PATH, XPT_PATH)), collapse = "、")))
cat(sprintf("01_prep_data: 母體 full=%d analysis=%d ability=%d\n", total_n, analysis_n, ability_n))
cat(sprintf("01_prep_data: 清冊 %s（%d 列）\n", short_path(LEDGER_PATH), nrow(ledger)))
