# harness-03.R — F3（財富層）的預算、執行上限與入口（V03）
#
# 交界契約（REQ-A-7）：本檔與 test-03_F3.R 只呼叫 helper-harness.R 的具名函式——
#   harness_data()／harness_dir()／harness_out_root()／harness_table()／
#   harness_seed()／expect_rate_equal()／expect_profile()。
# 樣本、暫存與輸出根一律由 helper 提供；本檔與測試檔都不含 read.*（read.csv／
# readLines…）、不含 set.seed、不含 tempdir／dir.create（A-25）。
#
# 本檔是 F3 的模型：把 T04（seam `programs/R/02_wealth.R`）的判定表翻成可證偽的
# 純函式，再由 test-03_F3.R 對「已發佈的表」與「入口行為」逐一斷言：
#
#   f3_cells(frame)   四格 n／格內退學率／share／phi 的獨立重算。母體界線
#                     （target ∈ Graduate／Dropout）與編碼（欠繳 = 學費未繳清 = 1、
#                     欠債 = 1）寫死在此，不由被測程式提供。
#   f3_phi(a,b,c,d)   2×2 的 phi 閉式。**不呼叫 programs/R/lib/stats.R**——那是被測
#                     對象的一部分；測試端的 oracle 必須獨立於受檢實作。
#   f3_run(out_root, clean_path)
#                     在暫存輸出根上執行 02_wealth.R，回傳結束碼、輸出與表路徑。
#                     注入只有兩個環境變數：RTOOLKIT_OUT_ROOT（寫入位置）與
#                     RTOOLKIT_CLEAN_PATH（退化 fixture 的清洗副本，02_wealth.R
#                     檔首宣告的入口）。工作目錄借 withr::with_dir() 移回專案根
#                     （02_wealth.R 以相對路徑 source 00_setup.R），離開即還原。
#   f3_sha256(path)   表指紋。專案沒有 digest／openssl，故走外部 shasum／sha256sum；
#                     兩者皆缺即以 refuse:input-missing 停止——「算不出 sha256 就
#                     說不變」是把檢查變成恆真。
#   f3_write_frame()  把變異後的資料框寫成清洗資料集形狀（逗號分隔、欄名與數值不動），
#                     供 f3_run() 的 clean_path 與 f3_cells() 的退化 fixture 使用。
#
# 樣本、種子與收縮：本流程無隨機來源（f3_budget() 的 seed／shrink 記 n/a）。退化
# fixture 的候選空間是「四格 × 兩欄編碼」的有限列舉，收縮為枚舉而非隨機最小化，
# 所以沒有可記的最短序列，只有一枚舉次數。

## 1. 常數（釘值與容差）-----------------------------------------------------

# 表名與入口（相對專案根；專案根由 AMS2640.Rproj 解析，與 00_setup.R 同一個根）
F3_TABLE <- "wealth_four_cell"
F3_PROGRAM_REL <- file.path("programs", "R", "02_wealth.R")
F3_PROJECT_MARKER <- "AMS2640.Rproj"

# 表的欄名（T04 的 Owned 面；缺一即無法判讀）
F3_COLUMNS <- c("population", "cell", "n", "dropout_rate", "share", "phi")

# 固定列序與其報告標籤（修訂 A-22：95.13／93.08／51.87／29.32 一一對應）
F3_ROW_ORDER <- c("w_both", "w_only_unpaid", "w_only_debt", "w_neither")
F3_ROW_LABELS <- c("兩者俱有", "僅欠繳", "僅欠債", "皆無")

# 四格的定義：欠繳 × 欠債 的完整分割（欠繳為入口，兩者同時成立者屬第一列）
F3_CELL_DEF <- data.frame(
  cell   = F3_ROW_ORDER,
  label  = F3_ROW_LABELS,
  unpaid = c(TRUE, TRUE, FALSE, FALSE),
  debtor = c(TRUE, FALSE, TRUE, FALSE),
  stringsAsFactors = FALSE
)

# 清洗資料集的欄名（T02 只把結果欄改名為 target，其餘沿用問卷用語）
F3_RESULT_COL <- "target"
F3_UNPAID_COL <- "Tuition fees up to date"
F3_DEBTOR_COL <- "Debtor"
F3_ANALYSIS_RESULTS <- c("Graduate", "Dropout")
F3_DROPOUT <- "Dropout"

# 分析母體：母體界線的釘值。測試同時以 population_ledger.csv 的 analysis 列對帳，
# 故這裡的數字不是唯一來源（A-21）。
F3_ANALYSIS_N <- 3630L

# 逐格釘值（修訂 A-10／A-22）：四位有效數字後相等
F3_PIN_N <- c(226L, 260L, 187L, 2957L)
F3_PIN_DROPOUT_RATE <- c(0.9513, 0.9308, 0.5187, 0.2932)

# phi 的釘值與容差：編碼 欠繳=1、欠債=1 時為 +0.4349（四位有效數字，容差 1e-3）。
# 編碼反轉（繳清=1）得 −0.4349——符號是編碼的產物，不是資料的性質。
F3_PIN_PHI <- 0.4349
F3_PHI_TOL <- 1e-3
F3_SIG_DIGITS <- 4L

# 單格對調（A-10 駁回的「任一格對調即變號」）：a↔b 得 0.4928，不是 −0.4349。
# 留在模型裡當「這條斷言不是恆真」的反面錨。
F3_PIN_PHI_SINGLE_SWAP <- 0.4927638

# share 相加為 1 的容差（A-10：四位有效數字呈現所致）
F3_SHARE_TOL <- 1e-4

# 性質比對的絕對容差：模型與表都以未格式化 double 存值（A-19），故同值時差為 0；
# 1e-12 只吸收浮點運算次序（例如先除後加與先加後除）。
F3_VALUE_TOL <- 1e-12

# 單流程執行上限（V03 的 Budget）
F3_FLOW_SECONDS <- 120

## 2. 預算 ----------------------------------------------------------------

# 種子與收縮：流程無隨機來源，兩者記 n/a；退化 fixture 以有限枚舉取代收縮。
f3_budget <- function() {
  list(
    rows = nrow(harness_data("analysis")),
    sample = "全列（無抽樣）",
    seed = "n/a（無隨機來源；harness_seed() 未被呼叫）",
    shrink = "n/a（fixture 為有限枚舉，非隨機最小化）",
    flow_seconds = F3_FLOW_SECONDS,
    retries = 0L
  )
}

## 3. 呈現與比較 ----------------------------------------------------------

# 四位有效數字（與 lib 的 fmt_sig 同形，但本檔不 source 生產檔案）
f3_sig <- function(x, digits = F3_SIG_DIGITS) {
  template <- paste0("%#.", as.integer(digits), "g")
  vapply(as.numeric(x), function(value) {
    if (is.na(value)) NA_character_ else sprintf(template, value)
  }, character(1))
}

# 逐值「四位有效數字後相等」
f3_sig_equal <- function(actual, expected, digits = F3_SIG_DIGITS) {
  identical(f3_sig(actual, digits), f3_sig(expected, digits))
}

## 4. 路徑與執行 ----------------------------------------------------------

# 專案根：與 00_setup.R 同一個標記檔（here() 由 AMS2640.Rproj 決定根）。
# 只用來指名入口程式，不用來讀表——表一律經 harness_table()（A-36）。
f3_project_root <- function() {
  root <- tryCatch(here::here(), error = function(e) NA_character_)
  if (is.na(root) || !file.exists(file.path(root, F3_PROJECT_MARKER))) {
    stop(
      "refuse:input-missing\n- here() 未解析到含 ", F3_PROJECT_MARKER,
      " 的專案根（實得 ", root, "）：無法指名入口程式 ", F3_PROGRAM_REL, "。",
      call. = FALSE
    )
  }
  normalizePath(root, winslash = "/", mustWork = TRUE)
}

f3_program_path <- function() file.path(f3_project_root(), F3_PROGRAM_REL)

f3_rscript <- function() {
  exe <- file.path(R.home("bin"), "Rscript")
  if (!file.exists(exe)) exe <- unname(Sys.which("Rscript"))
  if (!nzchar(exe)) {
    stop("refuse:input-missing\n- 找不到 Rscript：無法執行 ", F3_PROGRAM_REL, "。", call. = FALSE)
  }
  exe
}

f3_table_path <- function(out_root) file.path(out_root, "tables", paste0(F3_TABLE, ".csv"))

f3_log_path <- function(out_root) file.path(out_root, "logs", "02_wealth.log")

# 執行 02_wealth.R。注入只有兩個環境變數，寫入位置一律是呼叫者給的暫存根；
# 專案的 output/ 不經手。結束碼 0 = happy path，非 0 = 拒絕分支（訊息在 output 內）。
f3_run <- function(out_root, clean_path = NULL) {
  if (!is.character(out_root) || length(out_root) != 1L || !nzchar(out_root) || !dir.exists(out_root)) {
    stop("f3_run：out_root 須為既有的輸出根（由 harness_out_root() 取得）。", call. = FALSE)
  }
  env <- paste0("RTOOLKIT_OUT_ROOT=", shQuote(normalizePath(out_root, winslash = "/", mustWork = TRUE)))
  if (!is.null(clean_path)) {
    if (!file.exists(clean_path)) {
      stop("f3_run：clean_path 不存在：", clean_path, call. = FALSE)
    }
    env <- c(env, paste0("RTOOLKIT_CLEAN_PATH=", shQuote(normalizePath(clean_path, winslash = "/", mustWork = TRUE))))
  }
  args <- shQuote(f3_program_path())
  started <- Sys.time()
  # 02_wealth.R 以相對路徑 source 00_setup.R，故子行程的工作目錄須為專案根。
  # with_dir() 以 force() 取值，故第二個引數必須是「呼叫」而非包成函式。
  # 拒絕分支的結束碼非零是預期結果（下面以 status 斷言），故抑制 system2 的
  # 「已有狀態 1」警告；非零本身仍由 status 帶出，不被吞掉。
  output <- withr::with_dir(
    f3_project_root(),
    suppressWarnings(system2(f3_rscript(), args, env = env, stdout = TRUE, stderr = TRUE))
  )
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  list(
    status = as.integer(status),
    output = as.character(output),
    out_root = out_root,
    table = f3_table_path(out_root),
    log = f3_log_path(out_root),
    elapsed = elapsed
  )
}

# 表指紋：sha256。專案無 digest／openssl，故以外部工具計算；兩者皆缺即拒絕。
f3_sha256 <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  found <- Sys.which(c("shasum", "sha256sum"))
  found <- found[nzchar(found)]
  if (!length(found)) {
    stop(
      "refuse:input-missing\n- 找不到 shasum／sha256sum：無法計算 ", path,
      " 的 sha256，拒絕在無法比對的情況下宣稱表未變。",
      call. = FALSE
    )
  }
  tool <- found[[1]]
  args <- if (grepl("sha256sum$", tool)) shQuote(path) else c("-a", "256", shQuote(path))
  out <- system2(tool, args, stdout = TRUE, stderr = TRUE)
  if (!length(out) || !grepl("^[0-9a-f]{64}([[:space:]]|$)", out[[1]])) {
    stop(
      "refuse:input-missing\n- ", basename(tool), " 未回可解析的 sha256（", paste(out, collapse = " "), "）。",
      call. = FALSE
    )
  }
  sub("[[:space:]].*$", "", out[[1]])
}

# 把變異後的資料框寫成清洗資料集的形狀（逗號分隔、欄名與數值不動），
# 供 RTOOLKIT_CLEAN_PATH 注入。寫入位置由呼叫者以 harness_dir() 提供。
f3_write_frame <- function(frame, path) {
  if (!is.data.frame(frame)) stop("f3_write_frame：frame 須為資料框。", call. = FALSE)
  utils::write.csv(frame, path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

## 5. 模型：四格、率、share 與 phi -----------------------------------------

# phi_2x2 的閉式：(ad − bc) / sqrt((a+b)(c+d)(a+c)(b+d))。
# 邊際為零即只有一個類別，回 refuse:single-class（與 lib 的類別同名，但實作獨立）。
# 四格先轉 double：整數乘積在四位數母體上會溢位（A-32），模型不得重犯。
f3_phi <- function(a, b, c, d) {
  cells <- c(a, b, c, d)
  if (!is.numeric(cells) || length(cells) != 4L) {
    stop("f3_phi：a、b、c、d 須為四個數值。", call. = FALSE)
  }
  if (anyNA(cells) || any(cells < 0)) {
    stop("f3_phi：四格須為非負且無缺值。", call. = FALSE)
  }
  a <- as.numeric(a); b <- as.numeric(b); c <- as.numeric(c); d <- as.numeric(d)
  rows <- c(a + b, c + d)
  cols <- c(a + c, b + d)
  if (rows[1] == 0 || rows[2] == 0 || cols[1] == 0 || cols[2] == 0) {
    return("refuse:single-class")
  }
  (a * d - b * c) / sqrt(rows[1] * rows[2] * cols[1] * cols[2])
}

# 四格的遮罩：回傳長度 4 的 list，元素為在「已篩到分析母體」的資料框上的 logical。
f3_cell_masks <- function(frame) {
  absent <- setdiff(c(F3_RESULT_COL, F3_UNPAID_COL, F3_DEBTOR_COL), names(frame))
  if (length(absent)) {
    stop(
      "refuse:input-missing\n- 資料框缺欄位：", paste(absent, collapse = ", "),
      "；母體界線與編碼以這三欄為準。",
      call. = FALSE
    )
  }
  unpaid <- frame[[F3_UNPAID_COL]] == 0
  debtor <- frame[[F3_DEBTOR_COL]] == 1
  dropout <- as.character(frame[[F3_RESULT_COL]]) == F3_DROPOUT
  lapply(seq_len(nrow(F3_CELL_DEF)), function(i) {
    unpaid == F3_CELL_DEF$unpaid[i] & debtor == F3_CELL_DEF$debtor[i] & !is.na(unpaid) & !is.na(debtor)
  })
}

# 模型：以分析母體重算四格。任一格為空即 refuse:empty-denominator 並寫明位置
# （四格是完整分割，故「合計等於母體」不是額外條件而是同時成立）。
f3_cells <- function(frame) {
  if (!is.data.frame(frame)) stop("f3_cells：frame 須為資料框。", call. = FALSE)
  in_analysis <- as.character(frame[[F3_RESULT_COL]]) %in% F3_ANALYSIS_RESULTS
  if (!any(in_analysis)) {
    stop("refuse:input-missing\n- 分析母體為 0 列：結果欄不在 ", paste(F3_ANALYSIS_RESULTS, collapse = "／"), " 之內。", call. = FALSE)
  }
  population <- frame[in_analysis, , drop = FALSE]

  absent <- setdiff(c(F3_UNPAID_COL, F3_DEBTOR_COL), names(population))
  if (length(absent)) {
    stop("refuse:input-missing\n- 分析母體缺欄位：", paste(absent, collapse = ", "), call. = FALSE)
  }
  if (anyNA(population[[F3_UNPAID_COL]]) || anyNA(population[[F3_DEBTOR_COL]])) {
    stop(
      "refuse:input-missing\n- 兩欄在分析母體內有缺值：",
      F3_UNPAID_COL, "=", sum(is.na(population[[F3_UNPAID_COL]])), "、",
      F3_DEBTOR_COL, "=", sum(is.na(population[[F3_DEBTOR_COL]])), call. = FALSE
    )
  }

  masks <- f3_cell_masks(population)
  dropout <- as.character(population[[F3_RESULT_COL]]) == F3_DROPOUT
  n_cell <- vapply(masks, sum, numeric(1))
  dropout_cell <- vapply(masks, function(m) sum(m & dropout), numeric(1))

  empty <- which(n_cell == 0)
  if (length(empty)) {
    stop(
      sprintf(
        "refuse:empty-denominator\n- 空格位置：%s（該格人數為 0，退學率無分母）",
        paste(sprintf("%s（%s）", F3_CELL_DEF$cell[empty], F3_CELL_DEF$label[empty]), collapse = "、")
      ),
      call. = FALSE
    )
  }

  analysis_n <- sum(n_cell)
  phi <- f3_phi(n_cell[1], n_cell[2], n_cell[3], n_cell[4])
  if (!is.numeric(phi)) {
    stop("refuse:single-class\n- phi 無定義：四格中有一整列或一整欄為空。", call. = FALSE)
  }

  data.frame(
    population = rep("analysis", nrow(F3_CELL_DEF)),
    cell = F3_CELL_DEF$cell,
    n = as.numeric(n_cell),
    dropout_n = as.numeric(dropout_cell),
    dropout_rate = dropout_cell / n_cell,
    share = n_cell / analysis_n,
    phi = rep(phi, nrow(F3_CELL_DEF)),
    stringsAsFactors = FALSE
  )
}

## 6. 已發佈的表與母體清冊 ------------------------------------------------

# 已發佈的四格表（固定讀 PROJ_ROOT/output/tables，A-36）。欄名缺一即拒絕。
f3_table <- function() {
  tbl <- harness_table(F3_TABLE, required = F3_COLUMNS)
  if (!identical(as.character(tbl$cell), F3_ROW_ORDER)) {
    stop(
      sprintf(
        "表 %s.csv 的列序為 %s，契約為 %s（A-22：與報告的 95.13／93.08／51.87／29.32 一一對應）。",
        F3_TABLE, paste(tbl$cell, collapse = ", "), paste(F3_ROW_ORDER, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  tbl
}

# 母體清冊的 analysis 列：n 合計的另一個來源（A-21／REQ-F-F2-1）
f3_ledger_n <- function(population = "analysis") {
  ledger <- harness_table("population_ledger")
  absent <- setdiff(c("population", "metric", "n"), names(ledger))
  if (length(absent)) {
    stop("refuse:input-missing\n- population_ledger.csv 缺欄名：", paste(absent, collapse = ", "), call. = FALSE)
  }
  rows <- ledger[as.character(ledger$population) == population & as.character(ledger$metric) == population, , drop = FALSE]
  if (nrow(rows) != 1L) {
    stop("refuse:input-missing\n- 母體清冊的 ", population, " 列有 ", nrow(rows), " 筆，應為 1 筆。", call. = FALSE)
  }
  as.numeric(rows$n)
}
