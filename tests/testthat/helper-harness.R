# helper-harness.R — 測試端唯一的共用設施（REQ-A-7）
#
# 交界契約：`harness-0N.R` 與 `test-*.R` 只可呼叫下列函式。測試檔不得自行讀檔
# （`read.csv`／`read_csv`）、不得自設種子（`set.seed`）、不得自建暫存目錄
# （`tempdir`／`dir.create`）；樣本、種子、暫存與輸出根一律由此檔提供。
#
#   harness_data(population, mutator = NULL)
#       population 取 `full`／`analysis`／`ability`，回該母體的全量資料框（不抽樣）。
#       給 `mutator` 時把變異後的資料寫入 `harness_dir()` 並回該路徑（退化 fixture）。
#       變異檔採原始資料的形狀（分號分隔、結果欄寫回 `Target`、其餘欄名與數值不動），
#       故可直接以 `RTOOLKIT_RAW_PATH` 餵給 `01_prep_data.R` 走完整條管線；該檔的母體
#       人數仍會受 `00_setup.R` 的釘值檢查，做退化 fixture 時須保持 3,630／2,828 不變。
#   harness_seed()
#       以 `HARNESS_SEED` 就位亂數種子後回傳種子值。
#   harness_dir()
#       每次呼叫回一個新的獨立暫存目錄；session 結束時整棵暫存根一併清除。
#   harness_out_root()
#       以 `tempfile()` 建一個空的輸出根（`tables/`、`logs/` 兩個空子目錄）並回傳路徑；
#       **不自動清除**，由呼叫者刪除；根位於系統暫存目錄，不隨 session 的 tempdir 消失。
#       **本函式只決定被測程式碼的寫入位置**：把 `RTOOLKIT_OUT_ROOT` 指到這個空根，使
#       `programs/R/` 的產出全落在暫存、不碰專案的 `output/`。它**不改變本檔讀表的位置**。
#   harness_table(name, required = c("population", "n"))
#       集中讀 **`PROJ_ROOT/output/tables/`** 的一張**已發佈**的表（`name` 可帶或不帶
#       `.csv`）並檢查欄名。此處一律以專案根解析，**不看 `RTOOLKIT_OUT_ROOT`**（A-36）：
#       取根的 `V14` 與讀表的 `V09`／`V10` 因此可在同一個 session 內並存——先呼叫
#       `harness_out_root()` 再呼叫 `harness_table()` 仍得專案的表。
#   harness_self_check()
#       A-36 的回歸自我檢查：在暫存根放一張同名的 1 列誘餌表，先 `harness_out_root()`
#       再 `harness_table("population_ledger")`，要求讀到的是 `PROJ_ROOT/output/tables`
#       的已發佈表（不是誘餌）、且該目錄在檢查期間未被改動；結束後還原環境變數、刪掉
#       自己的根。`tests/testthat.R` 每次執行前呼叫它。
#   expect_rate_equal(actual, expected, tolerance = HARNESS_RATE_TOL)
#       比率比較；容差為相對差（PRD D10）。
#   expect_profile(tbl, populations = HARNESS_POPULATIONS)
#       表須自帶母體與 n（PRD §3 不變量）。
#
# 本檔不在載入時觸碰 testthat：以 `source()` 在 testthat 之外載入亦可用，斷言函式
# 只在被呼叫時才解析 `testthat::`。資料來源為 `data/processed/ams2640_clean.csv`
# （T02 的產物），欄名以該檔為準，本檔不改寫、不改名、不抽樣。

## 1. 常數 -----------------------------------------------------------------

# 固定種子：V01–V11 的預算一律引用此值（A-2）。
HARNESS_SEED <- 20261117L

# 比率比較的相對容差，與兩端容差同源（PRD D10：計數零差、比率相對差 1e-9）。
HARNESS_RATE_TOL <- 1e-9

# 三個具名母體（PRD §2）。
HARNESS_POPULATIONS <- c("full", "analysis", "ability")

# 母體界線：結果欄的兩個類別入分析母體；能力母體另要求第二學期成績嚴格大於門檻。
# 值與 00_setup.R 的 ANALYSIS_RESULTS／ABILITY_MIN_SCORE 同義，測試端不 source 生產
# 設定檔（那會在 source 時載入版本環境並寫記錄），故在此以資料欄位重新表達界線。
HARNESS_RESULT_COL <- "target"
HARNESS_RAW_RESULT_COL <- "Target"
HARNESS_RESULTS <- c("Graduate", "Dropout")
HARNESS_ABILITY_SCORE_COL <- "Curricular units 2nd sem (grade)"
HARNESS_ABILITY_MIN_SCORE <- 0

# 樣本與暫存的形狀
HARNESS_CLEAN_REL_PATH <- file.path("data", "processed", "ams2640_clean.csv")
# 已發佈的表的所在（相對專案根）。讀表一律由此解析，不經 RTOOLKIT_OUT_ROOT（A-36）。
HARNESS_TABLES_REL_PATH <- file.path("output", "tables")
HARNESS_PROJECT_MARKER <- "AMS2640.Rproj"

## 2. 內部狀態 -------------------------------------------------------------

.harness_state <- new.env(parent = emptyenv())
.harness_state$project_root <- NULL
.harness_state$session_root <- NULL
.harness_state$data <- NULL
.harness_state$dirs <- character()

# 專案根：自工作目錄向上找 AMS2640.Rproj。testthat 在 tests/testthat 下執行，
# 自專案根執行時則一步命中；兩者都得到同一個根。
.harness_project_root <- function() {
  cached <- .harness_state$project_root
  if (!is.null(cached) && dir.exists(cached)) return(cached)
  dir <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  repeat {
    if (file.exists(file.path(dir, HARNESS_PROJECT_MARKER))) break
    parent <- dirname(dir)
    if (identical(parent, dir)) {
      stop(
        "找不到專案根目錄：自 ", normalizePath(getwd(), winslash = "/", mustWork = FALSE),
        " 向上無 ", HARNESS_PROJECT_MARKER, "。請在專案或其子目錄下執行測試。",
        call. = FALSE
      )
    }
    dir <- parent
  }
  .harness_state$project_root <- dir
  dir
}

# 訊息內的專案內路徑以相對形式呈現；專案外（暫存根）給絕對路徑。
.harness_short <- function(path) {
  root <- .harness_state$project_root
  if (is.null(root)) return(path)
  prefix <- paste0(root, "/")
  ifelse(startsWith(path, prefix), substring(path, nchar(prefix) + 1L), path)
}

.harness_clean_path <- function() file.path(.harness_project_root(), HARNESS_CLEAN_REL_PATH)

.harness_file_stamp <- function(path) {
  info <- file.info(path)
  sprintf("%s|%s", format(info$mtime, "%Y-%m-%dT%H:%M:%OS6"), format(info$size))
}

# 清洗資料集：讀一次、按檔案時間戳記快取。缺席即 refuse:input-missing，
# 訊息寫明缺哪個檔、應先執行哪個任務（T14 的 Refusal）。
.harness_read_clean <- function() {
  path <- .harness_clean_path()
  if (!file.exists(path)) {
    stop(
      "refuse:input-missing\n- 缺清洗資料集 ", .harness_short(path),
      "：請先執行 T02（programs/R/01_prep_data.R）產生它，再跑測試。",
      call. = FALSE
    )
  }
  stamp <- .harness_file_stamp(path)
  cached <- .harness_state$data
  if (!is.null(cached) && identical(cached$stamp, stamp)) return(cached$frame)

  frame <- utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
  absent <- setdiff(c(HARNESS_RESULT_COL, HARNESS_ABILITY_SCORE_COL), names(frame))
  if (length(absent)) {
    stop(
      "refuse:input-missing\n- 清洗資料集 ", .harness_short(path), " 缺欄位：",
      paste(absent, collapse = ", "),
      "；母體界線以這兩欄為準，請先以 T02 重產清洗資料集。",
      call. = FALSE
    )
  }
  if (!nrow(frame)) {
    stop("refuse:input-missing\n- 清洗資料集 ", .harness_short(path), " 為 0 列，無樣本可取。", call. = FALSE)
  }
  .harness_state$data <- list(stamp = stamp, frame = frame)
  frame
}

# 原始資料形狀的寫出：分號分隔、結果欄寫回 `Target`，使變異檔可直接以
# RTOOLKIT_RAW_PATH 餵給 01_prep_data.R（退化 fixture 的用途）。欄名與數值不改。
.harness_write_raw_shape <- function(frame, path) {
  out <- frame
  if (HARNESS_RESULT_COL %in% names(out)) {
    names(out)[names(out) == HARNESS_RESULT_COL] <- HARNESS_RAW_RESULT_COL
  }
  utils::write.table(
    out, path,
    sep = ";", row.names = FALSE, col.names = TRUE,
    na = "", qmethod = "double", fileEncoding = "UTF-8"
  )
  path
}

# 讀表的位置與 00_setup.R 的「寫入」解析順序**分開**（A-36）。已發佈的表固定在
# <PROJ_ROOT>/output/tables：那是 T01–T13 的產物所在，也是 V09／V10 要比對的對象。
# RTOOLKIT_OUT_ROOT 說的是「被測程式碼把結果寫到哪」，屬 harness_out_root() 的職責；
# 兩件事共用同一個變數，會使「先取根、後讀表」的 session 一張表都讀不到。
.harness_tables_dir <- function() file.path(.harness_project_root(), HARNESS_TABLES_REL_PATH)

.harness_table_path <- function(name) {
  if (!is.character(name) || length(name) != 1L || !nzchar(name)) {
    stop("harness_table() 需一個表名（可帶或不帶 .csv）。", call. = FALSE)
  }
  file <- if (grepl("[.]csv$", name)) name else paste0(name, ".csv")
  file.path(.harness_tables_dir(), file)
}

# 目錄指紋：檔名、大小與 mtime。自我檢查用它證明 output/tables 沒被寫入。
.harness_dir_stamp <- function(dir) {
  files <- sort(list.files(dir, all.files = FALSE, no.. = TRUE))
  if (!length(files)) return(character())
  info <- file.info(file.path(dir, files))
  sprintf("%s|%s|%s", files, format(info$size), format(info$mtime, "%Y-%m-%dT%H:%M:%OS6"))
}

# 暫存根：一個 session 一個，位於 R 的 tempdir 內；session 結束時整棵刪除。
.harness_session_root <- function() {
  root <- .harness_state$session_root
  if (!is.null(root) && dir.exists(root)) return(root)
  root <- tempfile(pattern = "harness-session-")
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(root)) stop("無法建立暫存根：", root, call. = FALSE)
  .harness_state$session_root <- root
  reg.finalizer(.harness_state, function(state) {
    if (!is.null(state$session_root)) unlink(state$session_root, recursive = TRUE, force = TRUE)
  }, onexit = TRUE)
  root
}

## 3. 五個具名函式 ---------------------------------------------------------

harness_data <- function(population, mutator = NULL) {
  population <- match.arg(population, HARNESS_POPULATIONS)
  frame <- .harness_read_clean()
  in_analysis <- frame[[HARNESS_RESULT_COL]] %in% HARNESS_RESULTS
  rows <- switch(
    population,
    full = rep(TRUE, nrow(frame)),
    analysis = in_analysis,
    ability = in_analysis & frame[[HARNESS_ABILITY_SCORE_COL]] > HARNESS_ABILITY_MIN_SCORE
  )
  sample <- frame[rows, , drop = FALSE]
  rownames(sample) <- NULL
  if (!nrow(sample)) {
    stop(
      "refuse:input-missing\n- 母體 ", population, " 為 0 列：清洗資料集的界線與契約不符（",
      .harness_short(.harness_clean_path()), "）；請先以 T02 重產清洗資料集。",
      call. = FALSE
    )
  }
  if (is.null(mutator)) return(sample)

  if (!is.function(mutator)) {
    stop("mutator 必須是函式（輸入資料框、回傳變異後的資料框）；實得 ", class(mutator)[1], "。", call. = FALSE)
  }
  mutated <- mutator(sample)
  if (!is.data.frame(mutated)) {
    stop("mutator 必須回傳資料框；實得 ", class(mutated)[1], "。", call. = FALSE)
  }
  path <- file.path(harness_dir(), sprintf("%s_mutated.csv", population))
  .harness_write_raw_shape(mutated, path)
  path
}

harness_seed <- function() {
  set.seed(HARNESS_SEED)
  HARNESS_SEED
}

harness_dir <- function() {
  path <- tempfile(pattern = "dir-", tmpdir = .harness_session_root())
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(path)) stop("無法建立暫存目錄：", path, call. = FALSE)
  .harness_state$dirs <- c(.harness_state$dirs, path)
  path
}

harness_out_root <- function() {
  # 根的基底取系統暫存目錄（TMPDIR），不用 R session 的 tempdir：session 結束時 R 會刪掉
  # tempdir，根若在其中就等於被自動清除，與「由呼叫者負責刪除」相抵。TMPDIR 未設時退回
  # tempfile() 的預設，行為仍為「本檔不刪」。
  base <- Sys.getenv("TMPDIR", unset = "")
  root <- if (nzchar(base) && dir.exists(base)) {
    tempfile(pattern = "harness-out-", tmpdir = base)
  } else {
    tempfile(pattern = "harness-out-")
  }
  dir.create(file.path(root, "tables"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(root, "logs"), recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(root)) stop("無法建立輸出根：", root, call. = FALSE)
  # 只影響**被測程式碼**的寫入位置：programs/R/ 以 RTOOLKIT_OUT_ROOT 為輸出基底，指到
  # 這裡就使測試不寫入專案的 output/（T14 Boundaries）。讀表路徑不受此影響——
  # harness_table() 固定讀 PROJ_ROOT/output/tables，兩者不同源（A-36）。
  Sys.setenv(RTOOLKIT_OUT_ROOT = root)
  root
}

harness_table <- function(name, required = c("population", "n")) {
  # 已發佈的表一律自 PROJ_ROOT/output/tables 讀取；即使本 session 已呼叫過
  # harness_out_root()（RTOOLKIT_OUT_ROOT 指向暫存根），這裡也不看那個變數（A-36）。
  path <- .harness_table_path(name)
  file <- basename(path)
  if (!file.exists(path)) {
    stop(
      "refuse:input-missing\n- 缺表 ", .harness_short(path),
      "：請先執行產生該表的分析任務（或 T13 的 programs/R/run_all.R 一次產生全部表）。",
      call. = FALSE
    )
  }
  tbl <- utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
  absent <- setdiff(required, names(tbl))
  if (length(absent)) {
    stop(sprintf(
      "表 %s 缺欄名 %s（實有：%s）；每張表須自帶母體與 n（PRD §3 不變量）。",
      file, paste(absent, collapse = ", "), paste(names(tbl), collapse = ", ")
    ), call. = FALSE)
  }
  tbl
}

## 4. 自我檢查：取根與讀表不得共用同一個變數（A-36） ----------------------

# 這一支是針對 A-36 的回歸檢查，形狀就是缺陷本身：在這一次呼叫的暫存根放一張**同名
# 1 列誘餌表**，然後先 `harness_out_root()`、後 `harness_table("population_ledger")`，
# 並要求結果與「取根之前同一個呼叫」完全相同。
#   - 讀到誘餌（1 列）→ harness_table() 仍跟著 RTOOLKIT_OUT_ROOT 走，判紅；
#   - 讀到專案已發佈的表（與取根前同維度）→ 兩者已分家，判綠；
#   - 檢查期間 `output/tables/` 的指紋改變 → 有人寫了專案的輸出，判紅。
# 起點先把環境變數清空，故本檢查在任何 session（含已被其他輸出根污染的）與任何次數
# 下都可重複呼叫；結束時還原原值、刪掉自己的根。不以 testthat 實作（本檔須能單獨 source）。
harness_self_check <- function() {
  name <- "population_ledger"
  prior <- Sys.getenv("RTOOLKIT_OUT_ROOT", unset = "")
  tables <- .harness_tables_dir()
  before_stamp <- .harness_dir_stamp(tables)

  # 先掛清理再動環境變數：中途中斷（例如真的缺表）時仍還原呼叫者的原值。
  root <- NULL
  on.exit({
    if (nzchar(prior)) Sys.setenv(RTOOLKIT_OUT_ROOT = prior) else Sys.unsetenv("RTOOLKIT_OUT_ROOT")
    if (!is.null(root)) unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  Sys.unsetenv("RTOOLKIT_OUT_ROOT")
  baseline <- harness_table(name)

  root <- harness_out_root()

  if (!identical(Sys.getenv("RTOOLKIT_OUT_ROOT", unset = ""), root)) {
    stop(
      "harness 自我檢查失敗：harness_out_root() 未把 RTOOLKIT_OUT_ROOT 指到新根 ", root,
      "，被測程式碼仍會寫入專案的 output/。", call. = FALSE
    )
  }

  # 誘餌：與真表同名、只 1 列。若 harness_table() 仍依 RTOOLKIT_OUT_ROOT 解析，就讀到它。
  decoy <- file.path(root, "tables", paste0(name, ".csv"))
  writeLines(c("population,metric,n,value", "full,decoy,1,1"), decoy)

  path <- .harness_table_path(name)
  published <- file.path(tables, paste0(name, ".csv"))
  if (!identical(path, published)) {
    stop(
      "harness 自我檢查失敗：harness_table() 解析到 ", path, "，應為 ", published,
      "（讀表不得受 RTOOLKIT_OUT_ROOT 影響）。", call. = FALSE
    )
  }

  after <- harness_table(name)
  if (!identical(dim(after), dim(baseline)) || !nrow(after)) {
    stop(
      "harness 自我檢查失敗：先 harness_out_root() 之後，harness_table(\"", name,
      "\") 回 ", nrow(after), " 列，而取根之前同一個呼叫回 ", nrow(baseline),
      " 列——讀到的不是已發佈的表（暫存根的同名誘餌表有 1 列）。",
      call. = FALSE
    )
  }

  after_stamp <- .harness_dir_stamp(tables)
  if (!identical(before_stamp, after_stamp)) {
    written <- setdiff(after_stamp, before_stamp)
    stop(
      "harness 自我檢查失敗：檢查期間 ", .harness_short(tables),
      " 被改動（", paste(written, collapse = "、"), "）；取根不應寫入專案的輸出。",
      call. = FALSE
    )
  }

  invisible(list(root = root, table = published, rows = nrow(after), decoy = decoy))
}

## 5. 斷言輔助 -------------------------------------------------------------

# 比率比較：長度相同、逐值在相對容差內。預期值為 0 時以絕對差比較（相對差無定義）。
expect_rate_equal <- function(actual, expected, tolerance = HARNESS_RATE_TOL) {
  act <- as.numeric(actual)
  exp <- as.numeric(expected)
  testthat::expect_equal(length(act), length(exp), label = "比率向量的長度")
  comparable <- is.finite(exp) & exp != 0
  testthat::expect_equal(act[comparable], exp[comparable], tolerance = tolerance, label = "比率（相對差）")
  testthat::expect_equal(act[!comparable], exp[!comparable], tolerance = 0, label = "比率（預期值為 0，絕對差）")
  invisible(act)
}

# 表須自帶母體與 n：欄位齊備、無缺值、population 取三個具名值之一、n 為非負整數。
expect_profile <- function(tbl, populations = HARNESS_POPULATIONS) {
  testthat::expect_true(is.data.frame(tbl), label = "表為資料框")
  if (!is.data.frame(tbl)) return(invisible(FALSE))
  needed <- c("population", "n")
  if (!all(needed %in% names(tbl))) {
    testthat::expect_true(
      FALSE,
      label = sprintf("表含 population 與 n（實有：%s）", paste(names(tbl), collapse = ", "))
    )
    return(invisible(FALSE))
  }
  testthat::expect_false(anyNA(tbl$population), label = "population 無缺值")
  n_values <- suppressWarnings(as.numeric(as.character(tbl$n)))
  if (anyNA(n_values)) {
    testthat::expect_false(TRUE, label = "n 無缺值且可轉為數值")
    return(invisible(FALSE))
  }
  testthat::expect_true(
    all(as.character(tbl$population) %in% populations),
    label = sprintf(
      "population 取 %s（實得：%s）",
      paste(populations, collapse = "／"),
      paste(unique(as.character(tbl$population)), collapse = ", ")
    )
  )
  testthat::expect_true(all(n_values >= 0), label = "n 非負")
  testthat::expect_true(all(n_values == round(n_values)), label = "n 為整數")
  invisible(TRUE)
}
