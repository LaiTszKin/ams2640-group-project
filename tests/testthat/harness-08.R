# harness-08.R — F8 宏觀三欄 的預算、執行上限與入口（V08，verification A）
#
# 交界契約（REQ-A-7、A-1、A-25、A-42、A-43）：
#   * 樣本、種子、暫存與輸出根一律取自 `helper-harness.R`：本檔只呼叫 harness_data()、
#     harness_seed()、harness_dir()、harness_out_root()、harness_table()、
#     expect_rate_equal()、expect_profile()。
#   * 本檔不自行讀已發佈的表（一律 harness_table()）、不設種子（一律 harness_seed()）、
#     不自建暫存目錄（一律 harness_dir()／harness_out_root()），故 REQ-A-7 的三類禁令
#     在本檔的命中數為 0。
#   * 唯一的檔案讀取是**被測程式自己的記錄**（`<out_root>/logs/07_macro.log`）：那是
#     一次注入執行留在暫存根的產物，不是已發佈的表也不是資料集，helper 沒有對應的
#     存取器，故以 readLines() 就地解析（REQ-A-7 的樣式只涵蓋表與資料集）。
#   * 載入時把 helper 源進**本檔被求值的同一個環境**（A-43 的根因：R 以定義時的
#     enclosure 解析自由變數）。三個入口因此同綠：`Rscript tests/testthat.R`、
#     `testthat::test_dir("tests/testthat")`、逐檔 `testthat::test_file()`。
#
# 本檔是 F8 的模型：把 T09（seam `programs/R/07_macro.R`）的判定表翻成可證偽的純函式，
# 再由 test-08_F8.R 對「已發佈的表」、「記錄」與「入口行為」逐一斷言。
#
#   f8_triplet_key(u, i, g)      三元組的字串鍵（兩位的十進位，1.4 與 1.40 同鍵）。
#   f8_blocks(frame)             由分析母體獨立數出十個年度區塊的人數；三元組不在
#                                對應表內即 refuse:input-schema（與被測程式同類）。
#   f8_model(frame)              由 frame 重建 30 列的期望表（三欄 × 十個年度）。
#                                **不呼叫 07_macro.R、不 source 生產檔案**：年度對應是
#                                契約的釘值（A-17），人數由資料獨立數出。
#   f8_violations(tbl, frame, bind_year = TRUE)
#                                逐條比對，回**違反清單**（字元向量）；空＝性質成立。
#                                `bind_year = FALSE` 只撤掉「年份 ↔ 值 ↔ 人數」三者的
#                                綁定，用來證明互換年份的負向控制抓到的是這條綁定。
#   f8_value_counts(frame)       每個 (variable, value) 在分析母體的人數（同一值跨年
#                                時，n 合計要等於這個數）。
#   f8_swap_years(tbl, i, j)     把第 i、j 列的 year 互換（負向控制的輸入）。
#   f8_log_triplets(path)        解析 07_macro.log 最後一段的十個三元組（year、三值、n）。
#   f8_log_status(path)          解析 07_macro.log 最後一段的 status 行。
#   f8_fixture_root(frame)       在 harness_dir() 上造一個「自成專案根」的暫存副本：
#                                programs／renv／renv.lock／.Rprofile 以 symlink 指回
#                                真實樹，清洗資料集是呼叫者給的變異版。被測程式因此
#                                讀到變異輸入，而真實樹的 data/ 與 programs/ 未被動過。
#   f8_run(out_root, frame)      在暫存根上執行 07_macro.R，回結束碼、輸出、表與記錄
#                                的路徑、耗時。注入只有 RTOOLKIT_OUT_ROOT（寫入位置）；
#                                變異輸入以「子行程的工作目錄 = 暫存專案根」送進去，
#                                因為 07_macro.R 的 CLEAN_PATH 由 PROJ_ROOT 導出。
#   f8_sha256(path)              表指紋（外部 shasum／sha256sum；兩者皆缺即拒絕）。
#   f8_table()／f8_ledger_n()    已發佈的表與母體清冊的 analysis 列。
#   f8_budget()                  本流程的預算（V08 Budget）。
#
# 樣本、種子與收縮：本流程無隨機來源，種子與收縮記 n/a；退化 fixture 是**單一突變**
# （把 GDP 換成逐列唯一值，使不同值數超過人數的十分之一），不是隨機最小化。

## 0. 載入即載入測試台 -------------------------------------------------------

# 本檔所在目錄。順序很重要：被 source() 時，堆疊上指向 harness-08.R 的 ofile 才是
# 本檔的位置——process 的 `--file=` 可能是別的腳本（`Rscript tests/testthat.R`）。
h08_this_dir <- function() {
  frames <- sys.frames()
  for (i in rev(seq_along(frames))) {
    ofile <- frames[[i]]$ofile
    if (!is.null(ofile) && grepl("harness-08[.]R$", ofile)) {
      return(dirname(normalizePath(ofile, winslash = "/", mustWork = FALSE)))
    }
  }
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg) && grepl("harness-08[.]R$", file_arg[[1L]])) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[[1L]]), winslash = "/", mustWork = FALSE)))
  }
  for (dir in c(getwd(), file.path(getwd(), "tests", "testthat"))) {
    if (file.exists(file.path(dir, "harness-08.R"))) {
      return(normalizePath(dir, winslash = "/", mustWork = FALSE))
    }
  }
  getwd()
}

# `local = TRUE` 把它載進「本檔 top-level 的求值環境」，與 h08_* 的定義處相同，
# 故 h08_* 的 closure 一律解析得到 .harness_* 與 harness_*（A-43）。
if (!file.exists(file.path(h08_this_dir(), "helper-harness.R"))) {
  stop("找不到 helper-harness.R（應與 harness-08.R 同目錄）：", h08_this_dir(), call. = FALSE)
}
source(file.path(h08_this_dir(), "helper-harness.R"), local = TRUE)

## 1. 預算與上限 -----------------------------------------------------------

H08_FLOW <- "F8 宏觀三欄"
H08_FLOW_LIMIT_SEC <- 120
H08_CHILD_LIMIT_SEC <- 60
H08_RETRIES <- 0L
H08_SHRINK_MAX_ITER <- 200L
H08_SHRINK_MAX_SEC <- 30
H08_SAMPLE_LABEL <- "全列（無抽樣）"
H08_SEED_NOTE <- "n/a（無隨機來源；harness_seed() 未被呼叫）"
H08_SHRINK_NOTE <- "n/a（退化 fixture 為單一突變，非隨機最小化）"

## 2. 釘值（Properties 逐條落成常數）---------------------------------------

# 表名、入口與欄名（T09 的 Owned 面）
F8_TABLE <- "macro_values"
F8_PROGRAM_REL <- file.path("programs", "R", "07_macro.R")
F8_LOG_NAME <- "07_macro.log"
F8_PROJECT_MARKER <- "AMS2640.Rproj"
F8_COLUMNS <- c("population", "variable", "value", "year", "year_inferred", "n", "role")

# 三欄的清洗資料集欄名（表的 variable 欄沿用原名）
F8_MACRO_VARS <- c("Unemployment rate", "Inflation rate", "GDP")

# 固定標記（T09 步驟 4、PRD D6／Q37）
F8_POPULATION_LABEL <- "analysis"
F8_ROLE_LABEL <- "control"

# 年度（A-17：資料無年份欄，年度由三元組推定，故 year_inferred 全為 TRUE）
F8_YEARS <- 2008:2017
F8_EXPECTED_ROWS <- 30L

# 年度對應表：鍵為完整三元組，值為該區塊的年度。**這是本檔自己的抄本**（契約釘值），
# 不是從 07_macro.R 讀來的——被測檔案改了對應表，測試必須判紅而不是跟著改。
F8_TRIPLETS <- data.frame(
  unemployment = c(7.6, 9.4, 10.8, 12.7, 15.5, 16.2, 13.9, 12.4, 11.1, 8.9),
  inflation    = c(2.6, -0.8, 1.4, 3.7, 2.8, 0.3, -0.3, 0.5, 0.6, 1.4),
  gdp          = c(0.32, -3.12, 1.74, -1.70, -4.06, -0.92, 0.79, 1.79, 2.02, 3.51),
  year         = F8_YEARS,
  stringsAsFactors = FALSE
)
F8_TRIPLET_COLS <- c("unemployment", "inflation", "gdp")

# 每個年度區塊的人數（十個數，合計 3,630；由分析母體實測，見 pins/08_F8.md）
F8_BLOCK_N <- c(452L, 424L, 435L, 356L, 328L, 316L, 326L, 355L, 347L, 291L)

# 分析母體人數與值域判定（PRD F8：某欄不同值多於人數的十分之一即拒絕）
F8_ANALYSIS_N <- 3630L
F8_DISTINCT_DIVISOR <- 10
F8_DISTINCT_LIMIT <- F8_ANALYSIS_N / F8_DISTINCT_DIVISOR  # 363
F8_DISTINCT_PIN <- c(10L, 9L, 10L)                          # 10／9／10（A-17）
F8_DISTINCT_NAMES <- F8_MACRO_VARS

# 同一 value 跨年的唯一情形（A-17）：Inflation rate 的 1.4 在 2010 與 2017，
# 兩列 n 相加為 726（435 + 291）。
F8_CROSS_VALUE <- 1.4
F8_CROSS_VAR <- "Inflation rate"
F8_CROSS_YEARS <- c(2010L, 2017L)
F8_CROSS_N <- c(435L, 291L)
F8_CROSS_SUM <- 726L

# 數值比較容差：表存未格式化 double（A-19），同值時差為 0；1e-9 只吸收浮點書寫。
F8_VALUE_TOL <- 1e-9

# 清洗資料集與其母體界線（與 helper 同一份界線，測試端不 source 生產設定檔）
F8_CLEAN_REL <- file.path("data", "processed", "ams2640_clean.csv")
F8_CLEAN_NAME <- "ams2640_clean.csv"
F8_RESULT_COL <- "target"
F8_ANALYSIS_RESULTS <- c("Graduate", "Dropout")

## 3. 純函式：三元組、區塊、模型、違反清單 ---------------------------------

# 三元組的鍵：兩位的十進位字串，1.4 與 1.40 因此同鍵，也免去浮點相等的判定。
f8_triplet_key <- function(unemployment, inflation, gdp) {
  paste(sprintf("%.2f", unemployment), sprintf("%.2f", inflation), sprintf("%.2f", gdp), sep = "|")
}

F8_TRIPLETS$key <- f8_triplet_key(
  F8_TRIPLETS$unemployment, F8_TRIPLETS$inflation, F8_TRIPLETS$gdp
)

# 分析母體：結果欄限 Graduate／Dropout（PRD D2）
f8_analysis_frame <- function(frame) {
  if (!is.data.frame(frame)) stop("f8_*：frame 須為資料框。", call. = FALSE)
  absent <- setdiff(c(F8_RESULT_COL, F8_MACRO_VARS), names(frame))
  if (length(absent)) {
    stop(
      "refuse:input-missing\n- 資料框缺欄位：", paste(absent, collapse = ", "),
      "；母體界線與三欄的值域以這些欄為準。", call. = FALSE
    )
  }
  out <- frame[as.character(frame[[F8_RESULT_COL]]) %in% F8_ANALYSIS_RESULTS, , drop = FALSE]
  rownames(out) <- NULL
  if (!nrow(out)) {
    stop("refuse:input-missing\n- 分析母體為 0 列：結果欄不在 ", paste(F8_ANALYSIS_RESULTS, collapse = "／"), " 之內。", call. = FALSE)
  }
  any_na <- vapply(F8_MACRO_VARS, function(v) sum(is.na(out[[v]])), integer(1))
  if (any(any_na > 0L)) {
    stop(
      "refuse:input-missing\n- 宏觀三欄在分析母體內有缺值：",
      paste(sprintf("%s=%d", names(any_na), any_na), collapse = "、"), call. = FALSE
    )
  }
  out
}

# 十個年度區塊：以三元組為鍵，人數自分析母體獨立數出。
# 三元組不在對應表內即 refuse:input-schema——年份無從推定，不得靜默留空。
f8_blocks <- function(frame) {
  population <- f8_analysis_frame(frame)
  keys <- f8_triplet_key(
    population[[F8_MACRO_VARS[1]]], population[[F8_MACRO_VARS[2]]], population[[F8_MACRO_VARS[3]]]
  )
  unmapped <- setdiff(sort(unique(keys)), F8_TRIPLETS$key)
  if (length(unmapped)) {
    stop(
      "refuse:input-schema\n- ", length(unmapped), " 個三元組不在年度對應表內：",
      paste(utils::head(unmapped, 5L), collapse = "; "), call. = FALSE
    )
  }
  counted <- table(factor(keys, levels = F8_TRIPLETS$key))
  data.frame(
    key = F8_TRIPLETS$key,
    year = as.integer(F8_TRIPLETS$year),
    n = as.integer(counted[F8_TRIPLETS$key]),
    stringsAsFactors = FALSE
  )
}

# 由資料重建 30 列的期望表：三欄 × 十個年度，值是契約的對應表，人數是數出來的區塊人數。
f8_model <- function(frame) {
  blocks <- f8_blocks(frame)
  parts <- lapply(seq_along(F8_MACRO_VARS), function(i) {
    data.frame(
      population = rep(F8_POPULATION_LABEL, length(F8_YEARS)),
      variable = rep(F8_MACRO_VARS[i], length(F8_YEARS)),
      value = as.numeric(F8_TRIPLETS[[F8_TRIPLET_COLS[i]]]),
      year = as.integer(F8_YEARS),
      year_inferred = rep(TRUE, length(F8_YEARS)),
      n = as.integer(blocks$n),
      role = rep(F8_ROLE_LABEL, length(F8_YEARS)),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  out$key <- paste(out$variable, out$year)
  out
}

# 每個 (variable, value) 在分析母體的人數。同一值跨年時，表裡那幾列的 n 合計要等於它。
f8_value_counts <- function(frame) {
  population <- f8_analysis_frame(frame)
  parts <- lapply(F8_MACRO_VARS, function(v) {
    values <- population[[v]]
    counted <- table(values)
    data.frame(
      variable = rep(v, length(counted)),
      value = as.numeric(names(counted)),
      count = as.integer(counted),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  out
}

# 每欄在分析母體的不同值數（10／9／10）
f8_distinct <- function(frame) {
  population <- f8_analysis_frame(frame)
  out <- vapply(F8_MACRO_VARS, function(v) length(unique(population[[v]])), integer(1))
  stats::setNames(out, F8_MACRO_VARS)
}

f8_num_equal <- function(actual, expected, tolerance = F8_VALUE_TOL) {
  a <- as.numeric(actual)
  e <- as.numeric(expected)
  length(a) == length(e) && all(abs(a - e) <= tolerance, na.rm = FALSE) && !anyNA(c(a, e))
}

# 負向控制的輸入：把第 i、j 列的 year 互換。列鍵是 (variable, year)，故互換之後
# 網格仍完整、每欄 n 合計仍 3,630、不同值數仍 10／9／10——唯一壞掉的是
# 「年份 ↔ 值 ↔ 人數」的綁定。這正是 P3 要抓的東西。
f8_swap_years <- function(tbl, i, j) {
  if (!is.data.frame(tbl)) stop("f8_swap_years：tbl 須為資料框。", call. = FALSE)
  if (length(i) != 1L || length(j) != 1L || i == j) stop("f8_swap_years：需兩個不同的列號。", call. = FALSE)
  if (i > nrow(tbl) || j > nrow(tbl)) stop("f8_swap_years：列號超出表長。", call. = FALSE)
  out <- tbl
  swapped <- out$year[i]
  out$year[i] <- out$year[j]
  out$year[j] <- swapped
  out
}

# 逐條比對，回違反清單。空向量＝全部成立。每一條訊息都寫「實得 vs 釘值」，
# 使紅燈輸出本身就能定位。
f8_violations <- function(tbl, frame, bind_year = TRUE) {
  if (!is.data.frame(tbl) || !nrow(tbl)) return("表不是非空的資料框")
  absent <- setdiff(F8_COLUMNS, names(tbl))
  if (length(absent)) {
    return(sprintf(
      "表缺欄名：%s（契約為 %s）", paste(absent, collapse = ", "), paste(F8_COLUMNS, collapse = ", ")
    ))
  }

  v <- character()
  add <- function(fmt, ...) v <<- c(v, sprintf(fmt, ...))

  pop <- as.character(tbl$population)
  role <- as.character(tbl$role)
  variable <- as.character(tbl$variable)
  value <- suppressWarnings(as.numeric(tbl$value))
  n <- suppressWarnings(as.numeric(tbl$n))
  year <- suppressWarnings(as.integer(as.character(tbl$year)))
  inferred <- suppressWarnings(as.logical(tbl$year_inferred))

  # P1：表長與兩個固定標記
  if (nrow(tbl) != F8_EXPECTED_ROWS) {
    add(
      "表長 %d 列，契約要求 %d 列（%d 欄 × %d 個年度）",
      nrow(tbl), F8_EXPECTED_ROWS, length(F8_MACRO_VARS), length(F8_YEARS)
    )
  }
  bad <- which(pop != F8_POPULATION_LABEL)
  if (length(bad)) {
    add(
      "第 %s 列的 population 為 %s，契約一律為 %s",
      paste(bad, collapse = "、"), paste(unique(pop[bad]), collapse = "、"), F8_POPULATION_LABEL
    )
  }

  # P4：role 全為 control
  bad <- which(role != F8_ROLE_LABEL)
  if (length(bad)) {
    add(
      "第 %s 列的 role 為 %s，契約一律為 %s（A-17／Q37：三欄只作控制變數）",
      paste(bad, collapse = "、"), paste(unique(role[bad]), collapse = "、"), F8_ROLE_LABEL
    )
  }

  # P3 之一：year 非 NA、落在 2008–2017、year_inferred 全為 TRUE
  if (anyNA(year)) {
    add("第 %s 列的 year 為 NA 或不可轉為整數（每列須有年份）", paste(which(is.na(year)), collapse = "、"))
  }
  outside <- which(!is.na(year) & !(year %in% F8_YEARS))
  if (length(outside)) {
    add(
      "第 %s 列的 year 為 %s，契約為 %d–%d",
      paste(outside, collapse = "、"), paste(unique(year[outside]), collapse = "、"),
      min(F8_YEARS), max(F8_YEARS)
    )
  }
  if (anyNA(inferred) || !all(inferred)) {
    add(
      "year_inferred 有 %d 列不為 TRUE（NA %d 列）；資料無年份欄，年度由三元組推定（A-17）",
      sum(!inferred, na.rm = TRUE), sum(is.na(inferred))
    )
  }

  # 三欄齊備、每欄每年一列；列鍵 (variable, year) 唯一
  unknown <- setdiff(unique(variable), F8_MACRO_VARS)
  if (length(unknown)) {
    add("表含契約以外的 variable：%s（契約為 %s）", paste(unknown, collapse = "、"), paste(F8_MACRO_VARS, collapse = "、"))
  }
  for (vname in F8_MACRO_VARS) {
    hits <- which(variable == vname)
    if (length(hits) != length(F8_YEARS)) {
      add("%s 有 %d 列，契約要求 %d 列（每欄每年一列）", vname, length(hits), length(F8_YEARS))
    }
    years_here <- year[hits]
    if (anyDuplicated(years_here[!is.na(years_here)])) {
      add("%s 的 year 有重複：%s（列鍵為 (variable, year)）", vname, paste(unique(years_here[duplicated(years_here)]), collapse = "、"))
    }
  }

  # P1 之二：每欄不同值數（10／9／10），且與資料上的不同值數同值
  distinct_tbl <- vapply(F8_MACRO_VARS, function(vname) {
    length(unique(round(value[variable == vname], 6)))
  }, integer(1))
  names(distinct_tbl) <- F8_MACRO_VARS
  shifted <- which(distinct_tbl != F8_DISTINCT_PIN)
  if (length(shifted)) {
    add(
      "表的不同值數為 %s，契約為 %s",
      paste(sprintf("%s=%d", names(distinct_tbl)[shifted], distinct_tbl[shifted]), collapse = "、"),
      paste(sprintf("%s=%d", F8_DISTINCT_NAMES[shifted], F8_DISTINCT_PIN[shifted]), collapse = "、")
    )
  }
  distinct_data <- f8_distinct(frame)
  shifted <- which(distinct_tbl != distinct_data)
  if (length(shifted)) {
    add(
      "不同值數與分析母體不符：%s（表的 %s，資料的 %s）",
      paste(F8_MACRO_VARS[shifted], collapse = "、"),
      paste(distinct_tbl[shifted], collapse = "、"),
      paste(distinct_data[shifted], collapse = "、")
    )
  }

  # 每欄 n 合計 = 分析母體（每欄每年一列，故三欄各自都要走完母體）
  for (vname in F8_MACRO_VARS) {
    total <- sum(n[variable == vname], na.rm = TRUE)
    if (anyNA(n[variable == vname])) {
      add("%s 有 %d 列的 n 為缺值", vname, sum(is.na(n[variable == vname])))
    } else if (total != F8_ANALYSIS_N) {
      add("%s 的 n 合計為 %s，分析母體為 %d", vname, format(total, scientific = FALSE), F8_ANALYSIS_N)
    }
  }

  # P2：同一 value 多列的 n 合計 = 該值在分析母體的人數
  counts <- f8_value_counts(frame)
  agg <- stats::aggregate(
    list(n = n), by = list(variable = variable, value = round(value, 6)), FUN = sum, na.rm = TRUE
  )
  for (i in seq_len(nrow(agg))) {
    hit <- counts[counts$variable == agg$variable[i] & abs(counts$value - agg$value[i]) <= 1e-6, , drop = FALSE]
    if (!nrow(hit)) {
      add("表中 %s 的值 %s 不在分析母體的值域內", agg$variable[i], format(agg$value[i], trim = TRUE))
      next
    }
    if (!identical(as.integer(agg$n[i]), as.integer(hit$count))) {
      rows <- which(variable == agg$variable[i] & abs(value - agg$value[i]) <= 1e-6)
      add(
        "%s=%s 的 n 合計為 %d（%d 列：%s），該值在分析母體有 %d 人",
        agg$variable[i], format(agg$value[i], trim = TRUE), as.integer(agg$n[i]), length(rows),
        paste(sprintf("year=%s n=%s", year[rows], n[rows]), collapse = "、"), as.integer(hit$count)
      )
    }
  }
  miss <- counts[!paste(counts$variable, round(counts$value, 6)) %in%
                   paste(agg$variable, round(agg$value, 6)), , drop = FALSE]
  if (nrow(miss)) {
    add(
      "分析母體的值 %s 沒有出現在表上",
      paste(sprintf("%s=%s（%d 人）", miss$variable, format(miss$value, trim = TRUE), miss$count), collapse = "、")
    )
  }

  # P3 之二：年份 ↔ 值 ↔ 人數 的綁定（互換兩列的 year 只壞這一條）
  if (bind_year) {
    model <- f8_model(frame)
    for (i in seq_len(nrow(tbl))) {
      if (is.na(year[i])) next
      key <- paste(variable[i], year[i])
      hit <- model[model$key == key, , drop = FALSE]
      if (!nrow(hit)) {
        add("表的 (%s, %d) 不在契約的年度網格內", variable[i], year[i])
        next
      }
      if (!f8_num_equal(value[i], hit$value[1L])) {
        add(
          "(%s, %d) 的 value 為 %s，契約的該年度值為 %s（年份與值的對應錯位）",
          variable[i], year[i], format(value[i], trim = TRUE), format(hit$value[1L], trim = TRUE)
        )
      }
      if (!f8_num_equal(n[i], hit$n[1L])) {
        add(
          "(%s, %d) 的 n 為 %s，分析母體在該年度的人數為 %d（年份與人數的綁定錯位）",
          variable[i], year[i], format(n[i], scientific = FALSE), as.integer(hit$n[1L])
        )
      }
    }
  }

  v
}

## 4. 記錄的解析（07_macro.log）--------------------------------------------

# 記錄是追加式的（每次執行一段）。取**最後一段**：同一輸出根重跑時，判讀的是最後
# 那一次執行的結果，不是第一次的殘留。
f8_log_lines <- function(path) {
  if (!file.exists(path)) {
    stop("refuse:input-missing\n- 缺記錄 ", path, "：07_macro.R 的每次執行都應留下它。", call. = FALSE)
  }
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  starts <- grep("^== 07_macro ", lines)
  if (!length(starts)) {
    stop("refuse:input-missing\n- 記錄 ", path, " 沒有 '== 07_macro' 段首：無法確定是哪一次執行。", call. = FALSE)
  }
  lines[starts[length(starts)]:length(lines)]
}

# 最後一段的 status 行（ok／refuse:input-schema）
f8_log_status <- function(path) {
  lines <- f8_log_lines(path)
  hit <- grep("^status: ", lines, value = TRUE)
  if (!length(hit)) return(NA_character_)
  trimws(sub("^status: ", "", hit[[1L]]))
}

# 最後一段的十個三元組：year、三值、n
f8_log_triplets <- function(path) {
  pattern <- paste0(
    "^- triplet: year=[0-9]+ unemployment=", "[-0-9.]+ inflation=", "[-0-9.]+ gdp=", "[-0-9.]+ n=[0-9]+$"
  )
  hits <- grep(pattern, f8_log_lines(path), value = TRUE)
  if (!length(hits)) {
    return(data.frame(
      year = integer(0), unemployment = numeric(0), inflation = numeric(0),
      gdp = numeric(0), n = integer(0), stringsAsFactors = FALSE
    ))
  }
  n_tokens <- length(strsplit(hits[[1L]], " ", fixed = TRUE)[[1L]])
  if (n_tokens < 6L) {
    stop("refuse:input-missing\n- 記錄的三元組行格式不符（欄位數 ", n_tokens, "）：", hits[[1L]], call. = FALSE)
  }
  # 逐 token 取 "label=值"：以固定分隔切開再比對前綴，避免以正則抓數值時把
  # "inflation=" 的尾字 n= 誤認成 n 欄。
  token_value <- function(label) {
    prefix <- paste0(label, "=")
    vapply(strsplit(hits, " ", fixed = TRUE), function(tokens) {
      hit <- tokens[startsWith(tokens, prefix)]
      if (!length(hit)) NA_character_ else sub(prefix, "", hit[[1L]], fixed = TRUE)
    }, character(1))
  }
  data.frame(
    year = as.integer(token_value("year")),
    unemployment = as.numeric(token_value("unemployment")),
    inflation = as.numeric(token_value("inflation")),
    gdp = as.numeric(token_value("gdp")),
    n = as.integer(token_value("n")),
    stringsAsFactors = FALSE
  )
}

## 5. 路徑、fixture 與執行 --------------------------------------------------

# 專案根：與 00_setup.R 同一個標記檔（here() 由 AMS2640.Rproj 決定根）。
# 只用來指名入口程式與要 symlink 的樹，不用來讀表——表一律經 harness_table()（A-36）。
f8_project_root <- function() {
  root <- tryCatch(here::here(), error = function(e) NA_character_)
  if (is.na(root) || !file.exists(file.path(root, F8_PROJECT_MARKER))) {
    stop(
      "refuse:input-missing\n- here() 未解析到含 ", F8_PROJECT_MARKER,
      " 的專案根（實得 ", root, "）：無法指名入口程式 ", F8_PROGRAM_REL, "。", call. = FALSE
    )
  }
  normalizePath(root, winslash = "/", mustWork = TRUE)
}

f8_program_path <- function() file.path(f8_project_root(), F8_PROGRAM_REL)

f8_rscript <- function() {
  exe <- file.path(R.home("bin"), "Rscript")
  if (!file.exists(exe)) exe <- unname(Sys.which("Rscript"))
  if (!nzchar(exe)) {
    stop("refuse:input-missing\n- 找不到 Rscript：無法執行 ", F8_PROGRAM_REL, "。", call. = FALSE)
  }
  exe
}

f8_table_path <- function(out_root) file.path(out_root, "tables", paste0(F8_TABLE, ".csv"))

f8_log_path <- function(out_root) file.path(out_root, "logs", F8_LOG_NAME)

# 暫存的「自成專案根」副本：只以 symlink 指回真實的 programs／renv／renv.lock／
# .Rprofile／AMS2640.Rproj（3.6 MB 的 sas7bdat 與 xpt 不必複製），清洗資料集換成
# 呼叫者給的變異版。0 個位元組落在真實樹上：data/ 與 data/processed/ 兩層都是
# harness_dir() 的目錄，變異檔寫在第二層。
f8_fixture_root <- function(frame) {
  if (!is.data.frame(frame)) stop("f8_fixture_root：frame 須為資料框。", call. = FALSE)
  real <- f8_project_root()
  root <- harness_dir()

  for (name in c(F8_PROJECT_MARKER, "programs", "renv", "renv.lock", ".Rprofile")) {
    src <- file.path(real, name)
    if (!file.exists(src)) {
      stop("refuse:input-missing\n- 專案根缺 ", name, "：暫存副本需要它才能自成一個專案。", call. = FALSE)
    }
    if (!isTRUE(file.symlink(src, file.path(root, name)))) {
      stop("refuse:input-missing\n- 無法建立 symlink ", file.path(root, name), " -> ", src, "。", call. = FALSE)
    }
  }

  data_dir <- harness_dir()
  processed_dir <- harness_dir()
  if (!isTRUE(file.symlink(data_dir, file.path(root, "data")))) {
    stop("refuse:input-missing\n- 無法建立 symlink ", file.path(root, "data"), "。", call. = FALSE)
  }
  if (!isTRUE(file.symlink(processed_dir, file.path(data_dir, "processed")))) {
    stop("refuse:input-missing\n- 無法建立 symlink ", file.path(data_dir, "processed"), "。", call. = FALSE)
  }
  utils::write.csv(frame, file.path(processed_dir, F8_CLEAN_NAME), row.names = FALSE, na = "", fileEncoding = "UTF-8")
  normalizePath(root, winslash = "/", mustWork = TRUE)
}

# 執行 07_macro.R。寫入位置一律是呼叫者給的暫存根（RTOOLKIT_OUT_ROOT）；給了 frame
# 就以暫存專案根為子行程的工作目錄，使被測程式讀到變異的清洗資料集（07_macro.R 的
# CLEAN_PATH 由 PROJ_ROOT 導出，故沒有別的注入點）。工作目錄借 withr::with_dir()
# 切換、離開即還原（與 harness-03 相同的做法）。
f8_run <- function(out_root, frame = NULL) {
  if (!is.character(out_root) || length(out_root) != 1L || !nzchar(out_root) || !dir.exists(out_root)) {
    stop("f8_run：out_root 須為既有的輸出根（由 harness_out_root() 取得）。", call. = FALSE)
  }
  work_dir <- if (is.null(frame)) f8_project_root() else f8_fixture_root(frame)
  env <- paste0(
    "RTOOLKIT_OUT_ROOT=",
    shQuote(normalizePath(out_root, winslash = "/", mustWork = TRUE))
  )
  args <- shQuote(f8_program_path())
  started <- Sys.time()
  output <- withr::with_dir(
    work_dir,
    suppressWarnings(system2(f8_rscript(), args, env = env, stdout = TRUE, stderr = TRUE))
  )
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  list(
    status = as.integer(status),
    output = as.character(output),
    out_root = out_root,
    work_dir = work_dir,
    table = f8_table_path(out_root),
    log = f8_log_path(out_root),
    elapsed = elapsed
  )
}

# 表指紋：sha256。專案無 digest／openssl，故走外部 shasum／sha256sum；兩者皆缺即以
# refuse:input-missing 停止——「算不出 sha256 就說表沒變」是把檢查變成恆真。
f8_sha256 <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  found <- Sys.which(c("shasum", "sha256sum"))
  found <- found[nzchar(found)]
  if (!length(found)) {
    stop(
      "refuse:input-missing\n- 找不到 shasum／sha256sum：無法計算 ", path,
      " 的 sha256，拒絕在無法比對的情況下宣稱表未變。", call. = FALSE
    )
  }
  tool <- found[[1]]
  args <- if (grepl("sha256sum$", tool)) shQuote(path) else c("-a", "256", shQuote(path))
  out <- system2(tool, args, stdout = TRUE, stderr = TRUE)
  if (!length(out) || !grepl("^[0-9a-f]{64}([[:space:]]|$)", out[[1]])) {
    stop("refuse:input-missing\n- ", basename(tool), " 未回可解析的 sha256（", paste(out, collapse = " "), "）。", call. = FALSE)
  }
  sub("[[:space:]].*$", "", out[[1]])
}

## 6. 已發佈的表與母體清冊 ------------------------------------------------

# 已發佈的表（固定讀 PROJ_ROOT/output/tables，A-36）。欄名缺一即拒絕。
f8_table <- function() harness_table(F8_TABLE, required = F8_COLUMNS)

# 母體清冊的 analysis 列：n 合計的另一個來源（A-21／REQ-F-F2-1）
f8_ledger_n <- function(population = "analysis") {
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

## 7. 預算 ----------------------------------------------------------------

# 樣本：分析母體 3,630 全列，無抽樣。種子與收縮：無隨機來源，記 n/a。
f8_budget <- function() {
  list(
    flow = H08_FLOW,
    rows = nrow(harness_data("analysis")),
    sample = H08_SAMPLE_LABEL,
    seed = H08_SEED_NOTE,
    shrink = H08_SHRINK_NOTE,
    shrink_max_iter = H08_SHRINK_MAX_ITER,
    shrink_max_sec = H08_SHRINK_MAX_SEC,
    flow_seconds = H08_FLOW_LIMIT_SEC,
    child_seconds = H08_CHILD_LIMIT_SEC,
    retries = H08_RETRIES
  )
}
