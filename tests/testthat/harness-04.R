# harness-04.R — F4（社會背景：年齡帶與婚配）的預算、執行上限與入口
#
# 交界契約：`test-04_F4.R` 只呼叫本檔的 `h04_*` 與 `helper-harness.R` 的具名函式。
# 樣本、暫存與輸出根一律取自 `helper-harness.R`（REQ-A-7）：本檔不設工作目錄、
# 不自設種子、不自行讀取資料檔——被測資料只經 `harness_data()` 取得，已發佈的表
# 只經 `harness_table()` 取得。本檔只讀一種非資料檔：`programs/R/03_age.R` 的原始碼
# （注入 fixture 用），那是被測程式本身，不是樣本。
#
# 入口有兩個：
#   h04_run(script, ...)          在**本行程**內 source 一支 03_age.R（或其暫存副本），
#                                 回傳執行結果、腳本產生的三張表之 sha256、以及腳本
#                                 在自身環境留下的資料框（`bands`／`tests`／`strata`）。
#                                 輸出根由 `harness_out_root()` 提供（A-36：只決定被測
#                                 程式的寫入位置，不改 `harness_table()` 的讀取位置）。
#   h04_script(...)／h04_fixture() 造退化 fixture：把 03_age.R 的副本寫進 `harness_dir()`，
#                                 只改 CLEAN_PATH 一行（注入資料）或 single 一行（負向控制）。
#                                 生產檔案、`output/`、`programs/` 皆不動。
#
# 預算（V04 契約）：樣本 3,630 全列、無抽樣；種子與收縮記 n/a——本流程沒有隨機來源
# （`fisher.test` 為確定性計算，同一輸入必得同一 p），故不抽樣、不收縮、不重試；
# 單流程上限 120 秒，以 `setTimeLimit()` 實際套在每次 source 上。

## 1. 預算 -----------------------------------------------------------------

H04_BUDGET <- list(
  rows = 3630L,       # 分析母體全列；fixture 亦自母體推導，不抽樣
  seed = NA_integer_, # n/a：無隨機來源（helper-harness.R 的種子本流程不使用）
  shrink_max = 200L,  # n/a：無隨機來源可收縮
  shrink_sec = 30,    # n/a
  timeout_sec = 120,  # 單流程上限
  retries = 0L
)

## 2. 釘值與欄名 -----------------------------------------------------------

# 本流程擁有的三張表；重建檢查以此為全集。
H04_TABLES <- c("age_bands", "age_tests", "marriage_strata")

# 清洗資料集的四個欄名與兩個類別值（與 03_age.R、00_setup.R 同義，測試端自行表達）。
H04_COL_AGE <- "Age at enrollment"
H04_COL_MARITAL <- "Marital status"
H04_COL_TUITION <- "Tuition fees up to date"
H04_COL_RESULT <- "target"
H04_DROPOUT <- "Dropout"

# 左閉右開 [a, b) 的切點（A-11）：<20、20-24、25-29、30-39、40+。
H04_AGE_BREAKS <- c(20, 25, 30, 40)

# 婚配映射（A-11）：已婚 = 2；單身 = 其餘（1、3、4、5、6）。釘值只在此讀法下重現。
H04_MARRIED_VALUE <- 2L
H04_SINGLE_VALUES <- c(1L, 3L, 4L, 5L, 6L)

# 欠繳 = 學費未繳清（學費是否繳清 = 0），編碼與 T04 相同（A-10）。
H04_UNPAID_VALUE <- 0

# 小格門檻：四格中任一格低於此值即入表並標 insufficient_n（A-11 的三分支之②）。
H04_SMALL_CELL_MIN <- 30L

# 呈現精度：四位有效數字只在斷言層使用（A-19：表存未格式化 double）。
H04_SIG_DIGITS <- 4L

# 契約釘住的錨值。比率與 p 值一律以「四位有效數字後相等」比較；計數以整數相等比較。
H04_PIN <- list(
  bands = c("<20", "20-24", "25-29", "30-39", "40+"),
  n = c(1621L, 1033L, 355L, 403L, 218L),
  analysis_n = 3630L,
  # 五帶概況（age_bands.csv）：25-29 與 40+ 兩帶的兩個率
  dropout_25_29 = 0.6930,
  dropout_40p = 0.5826,
  unpaid_25_29 = 0.2789,
  unpaid_40p = 0.2523,
  # 兩個關鍵檢定（age_tests.csv）：25-29 對 40+，雙尾
  test_band_a = "25-29",
  test_band_b = "40+",
  p_dropout = 0.008781,
  p_unpaid = 0.4987,
  odds_ratio_dropout = 1.617,
  odds_ratio_unpaid = 1.146,
  # 兩個檢定的 2×2（帶內人數 × 兩率導出）：退學 246/109 對 127/91、欠繳 99/256 對 55/163
  cells_dropout_test = c(246L, 109L, 127L, 91L),
  cells_unpaid_test = c(99L, 256L, 55L, 163L),
  # 婚配分層（marriage_strata.csv）：兩帶的四格與 p
  cells_30_39 = c(87L, 66L, 171L, 79L),   # 已婚退學／已婚畢業／單身退學／單身畢業
  cells_40p = c(61L, 54L, 66L, 37L),
  married_30_39 = 153L,
  single_30_39 = 250L,
  p_30_39 = 0.02455,
  married_40p = 115L,
  single_40p = 103L,
  p_40p = 0.1301,
  # 三分支之②：三帶入表且 p 留空
  insufficient = c("<20", "20-24", "25-29"),
  # 負向控制（單身 = 1，A-11）：30-39 的 p 變 0.0024；40+ 出現 20 人的格故轉
  # insufficient_n，其未經門檻的雙尾 Fisher p 為 0.05706（契約寫 0.0571 為三位有效數字）。
  p_30_39_single1 = 0.0024,
  p_40p_single1 = 0.05706
)

## 3. 路徑與雜湊 -----------------------------------------------------------

# 專案根：與生產端同一個解析方式（here 由 AMS2640.Rproj 決定），並檢查標記檔。
h04_project_root <- function() {
  root <- here::here()
  if (!file.exists(file.path(root, "AMS2640.Rproj"))) {
    stop(sprintf("找不到專案根目錄：here() 回 %s，該處無 AMS2640.Rproj。", root), call. = FALSE)
  }
  root
}

h04_program <- function(name = "03_age.R") {
  file.path(h04_project_root(), "programs", "R", name)
}

# 已發佈的表所在；只給 sha256 用（內容一律經 harness_table() 讀，A-36）。
h04_tables_dir <- function() file.path(h04_project_root(), "output", "tables")

# sha256：走系統的 shasum，不在 R 內讀檔內容。回 64 位小寫十六進位。
h04_sha256 <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf("h04_sha256：檔案不存在 %s", path), call. = FALSE)
  }
  out <- suppressWarnings(
    system2("shasum", c("-a", "256", shQuote(path)), stdout = TRUE, stderr = TRUE)
  )
  digest <- sub("[[:space:]].*$", "", out[[1L]])
  if (!grepl("^[0-9a-f]{64}$", digest)) {
    stop(sprintf("h04_sha256：%s 的 shasum 輸出無法解析（%s）", path, paste(out, collapse = " ")),
         call. = FALSE)
  }
  digest
}

# 三張已發佈表的 sha256，具名向量（名稱 = 表名）。
h04_published_hash <- function(tables = H04_TABLES) {
  paths <- file.path(h04_tables_dir(), paste0(tables, ".csv"))
  stats::setNames(vapply(paths, h04_sha256, character(1)), tables)
}

## 4. 執行入口 -------------------------------------------------------------

# h04_run(script)：在一個新環境內 source 該腳本，輸出根取 harness_out_root()。
#
# 回傳 list：
#   error      腳本停止時的訊息（字串）；正常結束為 NULL
#   output     腳本被攔下來的 stdout（cat 的進度行），供失敗時診斷
#   tables     本次寫出的表：具名 sha256（名稱 = 檔名，含 .csv）
#   env        腳本自己的環境（bands／tests／strata 三個資料框留在這裡）
#   out_root   本次的輸出根（回傳前已刪除）
#
# 生命週期：harness_out_root() 的根由呼叫者刪除（A-25），故在本函式結束前清掉，
# 並還原 RTOOLKIT_OUT_ROOT。時間上限以 setTimeLimit() 套在 source 上（120 秒）。
h04_run <- function(script = h04_program(), out_root = NULL,
                    timeout_sec = H04_BUDGET$timeout_sec) {
  if (!file.exists(script)) {
    stop(sprintf("h04_run：找不到腳本 %s", script), call. = FALSE)
  }
  if (is.null(out_root)) out_root <- harness_out_root()
  tables_dir <- file.path(out_root, "tables")

  prior_root <- Sys.getenv("RTOOLKIT_OUT_ROOT", unset = "")
  Sys.setenv(RTOOLKIT_OUT_ROOT = out_root)
  on.exit({
    if (nzchar(prior_root)) {
      Sys.setenv(RTOOLKIT_OUT_ROOT = prior_root)
    } else {
      Sys.unsetenv("RTOOLKIT_OUT_ROOT")
    }
    unlink(out_root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  env <- new.env(parent = globalenv())
  setTimeLimit(elapsed = timeout_sec, transient = TRUE)
  on.exit(setTimeLimit(elapsed = Inf, transient = FALSE), add = TRUE)

  output <- utils::capture.output(
    outcome <- tryCatch(source(script, local = env), error = function(e) e)
  )

  files <- sort(list.files(tables_dir))
  hashes <- vapply(files, function(f) h04_sha256(file.path(tables_dir, f)), character(1))

  list(
    error = if (inherits(outcome, "error")) conditionMessage(outcome) else NULL,
    output = output,
    tables = stats::setNames(hashes, files),
    env = env,
    out_root = out_root
  )
}

## 5. 退化 fixture 與暫存副本 -----------------------------------------------

# h04_script()：把 03_age.R 原文寫成 `harness_dir()` 的一份副本，只換掉指定的行。
#   clean_path  不為 NULL 時，把 `CLEAN_PATH <- file.path(PROJ_ROOT, ...)` 換成指向該檔
#   single_values 不為 NULL 時，把 `single <- ... %in% SINGLE_VALUES` 換成該向量
# 每個替換都要求原文恰好命中一行，否則停止並指名注入點——命不中即代表生產檔案已改寫，
# 那時測試該紅，不該靜默跳過。回傳副本的絕對路徑。
h04_script <- function(clean_path = NULL, single_values = NULL) {
  lines <- readLines(h04_program(), warn = FALSE)
  edits <- character()
  hit_one <- function(pattern, what) {
    hit <- grep(pattern, lines)
    if (length(hit) != 1L) {
      stop(sprintf("h04_script：注入點「%s」在 programs/R/03_age.R 命中 %d 行（應為 1）",
                   what, length(hit)), call. = FALSE)
    }
    hit
  }

  if (!is.null(clean_path)) {
    hit <- hit_one("^CLEAN_PATH <- file\\.path\\(PROJ_ROOT", "CLEAN_PATH")
    lines[hit] <- sprintf('CLEAN_PATH <- normalizePath("%s", winslash = "/", mustWork = TRUE)',
                          clean_path)
    edits <- c(edits, "clean")
  }
  if (!is.null(single_values)) {
    hit <- hit_one("^single <- data\\[\\[COL_MARITAL\\]\\] %in% SINGLE_VALUES$", "single")
    literal <- paste0("c(", paste0(sort(as.integer(single_values)), "L", collapse = ", "), ")")
    lines[hit] <- sprintf("single <- data[[COL_MARITAL]] %%in%% %s", literal)
    edits <- c(edits, "single")
  }
  if (!length(edits)) {
    stop("h04_script：沒有指定任何替換（clean_path／single_values 皆為 NULL）。", call. = FALSE)
  }

  path <- file.path(harness_dir(), sprintf("03_age_%s.R", paste(edits, collapse = "-")))
  writeLines(lines, path, useBytes = TRUE)
  path
}

# h04_fixture(mutator)：把分析母體（3,630 列）交給 mutator，寫成清洗資料集形狀的
# 暫存檔（逗號分隔、欄名與數值原樣），供 h04_script(clean_path=) 注入。
# 列數不變是 00_setup.R 的釘值檢查（ANALYSIS_N）所要求，故在此先擋。
h04_fixture <- function(mutator, tag = "fixture") {
  frame <- harness_data("analysis")
  mutated <- mutator(frame)
  if (!is.data.frame(mutated)) {
    stop("h04_fixture：mutator 須回傳資料框。", call. = FALSE)
  }
  if (nrow(mutated) != H04_PIN$analysis_n) {
    stop(sprintf("h04_fixture：變異後 %d 列，應保持分析母體 %d 列。",
                 nrow(mutated), H04_PIN$analysis_n), call. = FALSE)
  }
  path <- file.path(harness_dir(), sprintf("%s_clean.csv", tag))
  utils::write.csv(mutated, path, row.names = FALSE, fileEncoding = "UTF-8")
  path
}

# 退化 fixture：把某一帶的婚姻狀況全部改成 SINGLE（已婚人數歸零），觸發三分支之①。
# 只動婚姻狀況一欄，不動列數、不動年齡，故帶的人數與其他欄位皆保持原值。
h04_degenerate_zero_married <- function(band = 2L, single_value = 1L) {
  force(band)
  force(single_value)
  function(frame) {
    age <- as.numeric(frame[[H04_COL_AGE]])
    index <- findInterval(age, H04_AGE_BREAKS) + 1L
    if (!band %in% index) {
      stop(sprintf("h04_degenerate_zero_married：第 %d 帶沒有任何列。", band), call. = FALSE)
    }
    frame[[H04_COL_MARITAL]][index == band] <- single_value
    frame
  }
}

## 6. 獨立重算 -------------------------------------------------------------

# 自 harness_data() 的樣本重算五帶的一切，不使用 03_age.R 的任何變數。
# single_values 可換，供負向控制（單身 = 1）對照。
# 回傳每帶一列的資料框：n、兩個率、婚配兩組的人數與率、四格、最小格、未經門檻的雙尾 p。
h04_recompute <- function(frame, single_values = H04_SINGLE_VALUES) {
  age <- as.numeric(frame[[H04_COL_AGE]])
  index <- findInterval(age, H04_AGE_BREAKS) + 1L
  n_bands <- length(H04_AGE_BREAKS) + 1L
  if (anyNA(index) || any(index < 1L | index > n_bands)) {
    stop("h04_recompute：年齡切帶落在界外。", call. = FALSE)
  }
  dropout <- frame[[H04_COL_RESULT]] == H04_DROPOUT
  unpaid <- as.numeric(frame[[H04_COL_TUITION]]) == H04_UNPAID_VALUE
  married <- frame[[H04_COL_MARITAL]] == H04_MARRIED_VALUE
  single <- frame[[H04_COL_MARITAL]] %in% single_values

  rows <- lapply(seq_len(n_bands), function(b) {
    sel <- index == b
    m <- sel & married
    s <- sel & single
    cells <- c(sum(m & dropout), sum(m & !dropout), sum(s & dropout), sum(s & !dropout))
    data.frame(
      band = H04_PIN$bands[b],
      n = as.integer(sum(sel)),
      dropout_n = as.integer(sum(sel & dropout)),
      dropout_rate = if (any(sel)) mean(dropout[sel]) else NA_real_,
      unpaid_n = as.integer(sum(sel & unpaid)),
      unpaid_rate = if (any(sel)) mean(unpaid[sel]) else NA_real_,
      married_n = as.integer(sum(m)),
      married_rate = if (any(m)) mean(dropout[m]) else NA_real_,
      single_n = as.integer(sum(s)),
      single_rate = if (any(s)) mean(dropout[s]) else NA_real_,
      cell_married_dropout = as.integer(cells[1L]),
      cell_married_grad = as.integer(cells[2L]),
      cell_single_dropout = as.integer(cells[3L]),
      cell_single_grad = as.integer(cells[4L]),
      min_cell = as.integer(min(cells)),
      p_value = h04_fisher_p(cells),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

# 2×2 的雙尾 Fisher p；邊際和為零時無 p 可言，回 NA。
h04_fisher_p <- function(cells, alternative = "two.sided") {
  tab <- matrix(as.numeric(cells), nrow = 2L, byrow = TRUE)
  if (anyNA(tab) || any(rowSums(tab) == 0) || any(colSums(tab) == 0)) return(NA_real_)
  unname(stats::fisher.test(tab, alternative = alternative)$p.value)
}

# 兩個帶的 2×2：metric 取 "dropout" 或 "unpaid"，band_a／band_b 為帶的序（1 起）。
# 回傳四格、三個 p（雙尾、單尾小、單尾大）、樣本勝算比與兩帶人數。
h04_compare <- function(frame, metric = c("dropout", "unpaid"), band_a = 3L, band_b = 5L) {
  metric <- match.arg(metric)
  event <- if (identical(metric, "dropout")) {
    frame[[H04_COL_RESULT]] == H04_DROPOUT
  } else {
    as.numeric(frame[[H04_COL_TUITION]]) == H04_UNPAID_VALUE
  }
  index <- findInterval(as.numeric(frame[[H04_COL_AGE]]), H04_AGE_BREAKS) + 1L
  a <- index == band_a
  b <- index == band_b
  cells <- c(sum(event & a), sum(!event & a), sum(event & b), sum(!event & b))
  list(
    band_a = H04_PIN$bands[band_a],
    band_b = H04_PIN$bands[band_b],
    n_a = as.integer(sum(a)),
    n_b = as.integer(sum(b)),
    cells = as.integer(cells),
    p_two = h04_fisher_p(cells, "two.sided"),
    p_less = h04_fisher_p(cells, "less"),
    p_greater = h04_fisher_p(cells, "greater"),
    odds_ratio = unname(cells[1L] * cells[4L] / (cells[2L] * cells[3L]))
  )
}

## 7. 四位有效數字的斷言 ---------------------------------------------------

# 四位有效數字後的值（只看呈現精度，見 A-19）。
h04_sig4 <- function(x) signif(as.numeric(x), H04_SIG_DIGITS)

# 「四位有效數字後相等」：兩邊先取四位有效數字，再以相對差 1e-12 兜住浮點尾差。
# 用於比率與 p 值；計數一律以整數相等斷言，不經此函式。
h04_expect_sig4 <- function(actual, expected, label = "四位有效數字後相等") {
  testthat::expect_equal(h04_sig4(actual), h04_sig4(expected), tolerance = 1e-12, label = label)
  invisible(actual)
}

# 取具名向量／資料框某一帶的值，找不到即停止（避免用空向量做恆真斷言）。
h04_band_value <- function(tbl, column, band) {
  hit <- which(as.character(tbl$band) == band)
  if (length(hit) != 1L) {
    stop(sprintf("h04_band_value：表內找不到帶 %s（實有：%s）",
                 band, paste(tbl$band, collapse = ", ")), call. = FALSE)
  }
  tbl[[column]][hit]
}
