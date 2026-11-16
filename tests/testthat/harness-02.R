# harness-02.R — F2（母體）的預算、執行上限與入口（V02）
#
# 交界契約（REQ-A-7）：本檔與 test-02_F2.R 只呼叫 helper-harness.R 的具名函式——
#   harness_data()／harness_dir()／harness_out_root()／harness_table()／
#   harness_seed()／expect_rate_equal()／expect_profile()。
# 樣本、種子、暫存與輸出根一律由 helper 提供；本檔與測試檔都不含 read.*（read.csv／
# readLines…）、不含 set.seed、不含 tempdir／dir.create（A-25）。任何檔案指紋一律走
# 外部 shasum／sha256sum，讀回 SAS 兩式一律走 haven（`read_sas`／`read_xpt`，不是
# `read.*` 家族的字面呼叫）。
#
# 本檔是 F2 的模型：把 T02（seam `programs/R/01_prep_data.R`）的判定表翻成可證偽的
# 入口與純函式，再由 test-02_F2.R 對「已發佈的清冊」、「清洗資料集重算的母體界線」、
# 「SAS 兩式的讀回」與「三個拒絕分支」逐一斷言：
#
#   f2_pins()            清冊的九列釘值（population, metric, n, value），逐列固定。
#   f2_ledger()          harness_table("population_ledger") 加欄名檢查；表缺欄即拒絕。
#   f2_populations()     由 harness_data("full") 獨立重算九個指標與能力母體的交集，
#                        不讀清冊、不 source 生產檔案——它是清冊的 oracle。
#   f2_sas(which)        以 haven 讀回 data/processed 的 .sas7bdat 或 .xpt。
#   f2_sha256(path)      檔案指紋（sha256）。算不出即拒絕，不讓「不變」變成恆真。
#   f2_raw_fixture(mutator)
#                        原始資料形狀的暫存副本；注入一律寫在 harness_dir() 的副本上，
#                        不碰 data/raw。回傳副本路徑。
#   f2_run(raw_path, out_root, allow_absent_out_root = FALSE)
#                        F2 的入口：在呼叫者給的暫存輸出根上執行 01_prep_data.R。
#                        注入只有兩個環境變數——RTOOLKIT_RAW_PATH（輸入副本）與
#                        RTOOLKIT_OUT_ROOT（寫入位置），兩者都是 01_prep_data.R 檔首
#                        宣告的入口。工作目錄借 withr::with_dir() 移回專案根（01 以相對
#                        路徑 source 00_setup.R），離開即還原。
#                        allow_absent_out_root = TRUE 時允許輸出路徑尚不存在（原樣注入，
#                        不由測試端建立或解連結）：供「輸出根是 raw 下未建立的子目錄」與
#                        「輸出根經符號連結指進 raw」兩條注入使用。
#   f2_processed_shas()  data/processed 三個產物的指紋，用來證明拒絕分支沒有動到它們。
#   f2_budget()          本流程的預算（樣本、種子、收縮、上限、重試）。
#
# 樣本與種子：全列（4,424／3,630／2,828），無抽樣；F2 無隨機來源，種子與收縮記 n/a。

## 1. 常數（釘值與入口）-----------------------------------------------------

# 清冊與入口（相對專案根；專案根由 AMS2640.Rproj 解析，與 00_setup.R 同一個根）
F2_TABLE <- "population_ledger"
F2_PROGRAM_REL <- file.path("programs", "R", "01_prep_data.R")
F2_PROJECT_MARKER <- "AMS2640.Rproj"
# 已發佈清冊的所在（相對專案根）。只用於**指紋**——讀表一律經 harness_table()（A-36）。
F2_TABLES_REL <- file.path("output", "tables")

# 原始資料與其校驗值（T02 的 Untouched；REQ-F-F2-2）
F2_RAW_REL <- file.path("data", "raw", "data.csv")
F2_RAW_SHA256 <- "3ef126de5cefff26eb11fbb4237f1a1401cb64b488e2f1d598c23cedeb4c45ae"

# 清洗資料集與 SAS 兩式（T02 的 Owned 面）
F2_PROCESSED_REL <- c(
  clean = file.path("data", "processed", "ams2640_clean.csv"),
  sas = file.path("data", "processed", "ams2640.sas7bdat"),
  xpt = file.path("data", "processed", "ams2640.xpt")
)

# 原始資料的形狀：36 個變數加結果欄（§3「建立母體」的前置）
F2_EXPECTED_COLS <- 37L
F2_RESULT_COL <- "target"
F2_RAW_RESULT_COL <- "Target"
F2_RESULTS <- c("Graduate", "Dropout", "Enrolled")
F2_ANALYSIS_RESULTS <- c("Graduate", "Dropout")
F2_ABILITY_SCORE_COL <- "Curricular units 2nd sem (grade)"
F2_ENROLLED_COLS <- c(
  "Curricular units 1st sem (enrolled)",
  "Curricular units 2nd sem (enrolled)"
)

# 清冊九列（A-21／A-3）：population 取三個具名值，n 為該列母體總數，value 為指標值。
# 列序固定，逐列比對；數字與 data/raw/data.csv 的實算一致（本檔的 f2_populations()
# 會從清洗資料集獨立重算一次，兩者不是同一個來源）。
F2_PINS <- data.frame(
  population = c(
    "full", "full", "full", "full",
    "analysis", "analysis", "analysis", "analysis",
    "ability"
  ),
  metric = c(
    "total", "graduate", "dropout", "enrolled",
    "analysis", "no_registration_rows", "zero_score_sem2", "zero_score_sem2_dropout",
    "ability"
  ),
  n = c(4424L, 4424L, 4424L, 4424L, 3630L, 3630L, 3630L, 3630L, 2828L),
  value = c(4424L, 2209L, 1421L, 794L, 3630L, 180L, 802L, 727L, 2828L),
  stringsAsFactors = FALSE
)

# 母體界線的釘值（與 00_setup.R 的 ANALYSIS_N／ABILITY_N／RETIRED_ANALYSIS_N 同義；
# 測試端不 source 生產設定檔，故在此以資料欄位重新表達）
F2_ANALYSIS_N <- 3630L
F2_ABILITY_N <- 2828L
F2_TOTAL_N <- 4424L
F2_ENROLLED_N <- 794L
# 全樣本上「第二學期成績 > 0」的人數，與能力母體相差的 726 人全為在讀者（T02 步驟 3）
F2_SCORED_FULL_N <- 3554L
F2_SCORED_ANALYSIS_GAP <- 726L

# 單流程執行上限（V02 的 Budget）
F2_FLOW_SECONDS <- 120

## 2. 預算 ----------------------------------------------------------------

# 樣本為三個母體的全列、無抽樣；F2 無隨機來源，seed 與 shrink 記 n/a（V02 Budget）。
# 退化 fixture 是「少一欄／第四類／一個缺值」的具名構造，不是隨機最小化，故收縮步數為 0。
f2_budget <- function() {
  list(
    rows = c(full = nrow(harness_data("full")), analysis = nrow(harness_data("analysis")),
             ability = nrow(harness_data("ability"))),
    sample = "全列（無抽樣）",
    seed = "n/a（無隨機來源；harness_seed() 未被呼叫）",
    shrink = "n/a（fixture 為具名構造，收縮步數 0）",
    shrink_upper = "200 次 / 30 秒（本流程未用）",
    flow_seconds = F2_FLOW_SECONDS,
    retries = 0L
  )
}

## 3. 路徑 ----------------------------------------------------------------

# 專案根：與 00_setup.R 同一個標記檔（here() 由 AMS2640.Rproj 決定根）。
# 只用來指名入口程式與資料產物，不用來讀表——清冊一律經 harness_table()（A-36）。
f2_project_root <- function() {
  root <- tryCatch(here::here(), error = function(e) NA_character_)
  if (is.na(root) || !file.exists(file.path(root, F2_PROJECT_MARKER))) {
    stop(
      "refuse:input-missing\n- here() 未解析到含 ", F2_PROJECT_MARKER,
      " 的專案根（實得 ", root, "）：無法指名入口程式 ", F2_PROGRAM_REL, "。",
      call. = FALSE
    )
  }
  normalizePath(root, winslash = "/", mustWork = TRUE)
}

f2_program_path <- function() file.path(f2_project_root(), F2_PROGRAM_REL)

f2_raw_path <- function() file.path(f2_project_root(), F2_RAW_REL)

# 清冊的檔案路徑：拒絕分支的後置條件是「清冊未被改寫」，那是檔案的性質、不是資料框的
# 性質，故這裡指名檔案算 sha256；讀表本身仍一律經 harness_table()（A-36）。
f2_published_ledger_path <- function() {
  file.path(f2_project_root(), F2_TABLES_REL, paste0(F2_TABLE, ".csv"))
}

f2_processed_path <- function(which = c("clean", "sas", "xpt")) {
  which <- match.arg(which)
  file.path(f2_project_root(), F2_PROCESSED_REL[[which]])
}

f2_rscript <- function() {
  exe <- file.path(R.home("bin"), "Rscript")
  if (!file.exists(exe)) exe <- unname(Sys.which("Rscript"))
  if (!nzchar(exe)) {
    stop("refuse:input-missing\n- 找不到 Rscript：無法執行 ", F2_PROGRAM_REL, "。", call. = FALSE)
  }
  exe
}

## 4. 指紋 ----------------------------------------------------------------

# sha256：專案無 digest／openssl，故以外部工具計算；兩者皆缺即拒絕。
f2_sha256 <- function(path) {
  if (!file.exists(path)) {
    stop("refuse:input-missing\n- 檔案不存在，無法計算 sha256：", path, call. = FALSE)
  }
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  found <- Sys.which(c("shasum", "sha256sum"))
  found <- found[nzchar(found)]
  if (!length(found)) {
    stop(
      "refuse:input-missing\n- 找不到 shasum／sha256sum：無法計算 ", path,
      " 的 sha256，拒絕在無法比對的情況下宣稱檔案未變。",
      call. = FALSE
    )
  }
  tool <- found[[1]]
  args <- if (grepl("sha256sum$", tool)) shQuote(path) else c("-a", "256", shQuote(path))
  out <- suppressWarnings(system2(tool, args, stdout = TRUE, stderr = TRUE))
  if (!length(out) || !grepl("^[0-9a-f]{64}([[:space:]]|$)", out[[1]])) {
    stop(
      "refuse:input-missing\n- ", basename(tool), " 未回可解析的 sha256（",
      paste(out, collapse = " "), "）。", call. = FALSE
    )
  }
  sub("[[:space:]].*$", "", out[[1]])
}

# data/processed 的三個產物：拒絕分支必須讓它們逐位元組不變（不在原始資料目錄，
# 但一次走到底的執行會覆寫它們，故把指紋當成「沒有越線」的證據）。
f2_processed_shas <- function() {
  vapply(c("clean", "sas", "xpt"), function(k) f2_sha256(f2_processed_path(k)), character(1))
}

## 5. 清冊與母體界線（oracle）---------------------------------------------

# 已發佈的清冊：固定讀 PROJ_ROOT/output/tables（A-36）。欄名缺一即拒絕。
f2_ledger <- function() {
  harness_table(F2_TABLE, required = c("population", "metric", "n", "value"))
}

# 由清洗資料集獨立重算九個指標。界線以欄位重新表達，不讀清冊、不 source 生產檔案：
#   analysis = target ∈ {Graduate, Dropout}
#   ability  = analysis ∩ Curricular units 2nd sem (grade) > 0
#   no_registration_rows = 兩學期 enrolled 皆 0（那是 0，不是缺值）
f2_populations <- function(frame = harness_data("full")) {
  needed <- c(F2_RESULT_COL, F2_ABILITY_SCORE_COL, F2_ENROLLED_COLS)
  absent <- setdiff(needed, names(frame))
  if (length(absent)) {
    stop(
      "refuse:input-missing\n- 清洗資料集缺欄位：", paste(absent, collapse = ", "),
      "；母體界線以這些欄為準。", call. = FALSE
    )
  }
  result <- as.character(frame[[F2_RESULT_COL]])
  scored <- frame[[F2_ABILITY_SCORE_COL]] > 0
  scored[is.na(scored)] <- FALSE
  in_analysis <- result %in% F2_ANALYSIS_RESULTS
  no_registration <- frame[[F2_ENROLLED_COLS[1]]] == 0 & frame[[F2_ENROLLED_COLS[2]]] == 0

  data.frame(
    population = c(
      "full", "full", "full", "full",
      "analysis", "analysis", "analysis", "analysis",
      "ability"
    ),
    metric = F2_PINS$metric,
    value = c(
      nrow(frame),
      sum(result == "Graduate"),
      sum(result == "Dropout"),
      sum(result == "Enrolled"),
      sum(in_analysis),
      sum(no_registration),
      sum(in_analysis & !scored),
      sum(in_analysis & !scored & result == "Dropout"),
      sum(in_analysis & scored)
    ),
    stringsAsFactors = FALSE
  )
}

# 能力母體的交集事實：全樣本上 3,554 人有第二學期成績，交集後 2,828 人，
# 差額 726 人「全為在讀者」——這一條不是算術恆真，是可以被資料推翻的。
f2_ability_basis <- function(frame = harness_data("full")) {
  result <- as.character(frame[[F2_RESULT_COL]])
  scored <- frame[[F2_ABILITY_SCORE_COL]] > 0
  scored[is.na(scored)] <- FALSE
  in_analysis <- result %in% F2_ANALYSIS_RESULTS
  outside <- scored & !in_analysis
  list(
    scored_full = sum(scored),
    ability = sum(scored & in_analysis),
    gap = sum(scored) - sum(scored & in_analysis),
    outside_results = unique(result[outside]),
    outside_n = sum(outside)
  )
}

## 6. SAS 兩式讀回 --------------------------------------------------------

# 以 haven 讀回 T02 寫出的兩種格式；不使用 read.* 家族的呼叫（REQ-A-7）。
f2_sas <- function(which = c("sas", "xpt")) {
  which <- match.arg(which)
  path <- f2_processed_path(which)
  if (!file.exists(path)) {
    stop("refuse:input-missing\n- 缺 SAS 格式：", path, "；請先執行 T02。", call. = FALSE)
  }
  if (identical(which, "sas")) haven::read_sas(path) else haven::read_xpt(path)
}

## 7. 退化 fixture 與入口 -------------------------------------------------

# 原始資料形狀的暫存副本：harness_data() 的 mutator 已把變異寫成
# 「分號分隔、結果欄寫回 Target、其餘欄名與數值不動」，可直接餵給 01_prep_data.R。
f2_raw_fixture <- function(mutator = NULL) {
  if (is.null(mutator)) mutator <- function(frame) frame
  harness_data("full", mutator)
}

# F2 的入口：在 out_root 上執行 01_prep_data.R。
#   raw_path  輸入（原始資料形狀的副本；呼叫者以 f2_raw_fixture() 取得）
#   out_root  寫入位置（清冊與記錄落在 out_root/tables、out_root/logs）
#   allow_absent_out_root
#             預設 FALSE：out_root 須已存在（harness_out_root()／harness_dir() 提供）。
#             設 TRUE 時允許一個**尚不存在**的輸出根——這是「拒絕仍有副作用」那兩條注入
#             （raw 下未建立的子目錄、經符號連結指進 raw 的路徑）的形狀。此處刻意**不**
#             代為建立或解析它：建立就是被測的副作用本身；把連結解開則是測試端替生產端
#             做了判定，第二條注入會退化成第一條。
# 回傳結束碼與合流的輸出。結束碼 0 = happy path，非 0 = 拒絕分支（訊息在 output 內）。
f2_run <- function(raw_path, out_root, allow_absent_out_root = FALSE) {
  if (!is.character(raw_path) || length(raw_path) != 1L || !file.exists(raw_path)) {
    stop("f2_run：raw_path 須為既有的檔案（以 f2_raw_fixture() 取得）。", call. = FALSE)
  }
  if (!is.character(out_root) || length(out_root) != 1L) {
    stop("f2_run：out_root 須為單一字串路徑。", call. = FALSE)
  }
  if (!allow_absent_out_root && !dir.exists(out_root)) {
    stop("f2_run：out_root 須為既有的輸出根（以 harness_out_root() 或 harness_dir() 取得）。",
         call. = FALSE)
  }
  # 兩條路徑都先正規化：01_prep_data.R 的「目標是否落在原始資料目錄內」判定用的是
  # normalizePath() 之後的字串，注入的字面拼法若與之不同（macOS 的 /var → /private/var），
  # 判定會落空。測試端不得靠拼法取得綠燈。
  # 尚不存在的輸出根原樣注入（normalizePath(mustWork = FALSE) 對它本就原樣返回）：
  # 要求呼叫者給絕對路徑，其餘的解析（含符號連結）由 01 的 §0 自己做。
  out_root_env <- if (dir.exists(out_root)) {
    normalizePath(out_root, winslash = "/", mustWork = TRUE)
  } else {
    out_root
  }
  env <- c(
    paste0("RTOOLKIT_OUT_ROOT=", shQuote(out_root_env)),
    paste0("RTOOLKIT_RAW_PATH=", shQuote(normalizePath(raw_path, winslash = "/", mustWork = TRUE)))
  )
  started <- Sys.time()
  # withr::with_dir(new, code) 以 force(code) 求值一個**表達式**（不是回呼函式）：
  # 傳入 function() {...} 會拿到函式物件本身，子行程根本沒跑。
  output <- withr::with_dir(f2_project_root(), {
    suppressWarnings(system2(f2_rscript(), shQuote(f2_program_path()),
                             env = env, stdout = TRUE, stderr = TRUE))
  })
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  list(
    status = as.integer(status),
    output = as.character(output),
    raw_path = raw_path,
    out_root = out_root,
    table = file.path(out_root, "tables", paste0(F2_TABLE, ".csv")),
    log = file.path(out_root, "logs", "01_prep.log"),
    elapsed = as.numeric(difftime(Sys.time(), started, units = "secs"))
  )
}

# 拒絕訊息的單一判定點：Rscript 把 stop() 的訊息寫到 stderr，system2 合流後為字元向量。
f2_refused <- function(result, class) {
  any(grepl(paste0("refuse:", class), result$output, fixed = TRUE))
}
