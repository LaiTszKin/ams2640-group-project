# harness-06.R — F6（三層的解釋力比較）的預算、執行上限與入口（V06）
#
# 交界契約（REQ-A-7、A-25）：
#   * 樣本、暫存與輸出根一律取自 `helper-harness.R`：本檔只呼叫 harness_data()、
#     harness_dir()、harness_out_root()、harness_table()、expect_profile()。
#     本檔不自行讀取資料檔、不自設種子、不自建暫存目錄（故 REQ-A-7 對 tests/ 的
#     三類禁令在本檔的命中數為 0）。
#   * 本檔唯一讀的非資料檔是 `programs/R/05_models.R` 的**原始碼**（注入 fixture 與
#     取出 `REPORTED_R2` 用）：那是被測程式本身，不是樣本。
#
# 本檔是 F6 的模型：把 T07（seam `programs/R/05_models.R`）的判定表翻成可證偽的
# 純函式，再由 `test-06_F6.R` 對「已發佈的表」、「重算」與「注入後的行為」逐一斷言：
#
#   h06_recompute(analysis, ability)
#       以 3,630 與 2,828 兩個母體獨立重算六列（McFadden R² 與秩式 AUC）。
#       切法與編碼寫死在此：年齡四帶是 `AGE_BREAKS_MODEL = c(25, 30, 40)`（<25 併為
#       一帶），能力分位與入學分位是 T06 的等量切法（升冪、`order(method = "radix")`、
#       組寬 floor(n / 4)、餘數全收末組）。**不呼叫 `programs/R/lib/stats.R`**——那是
#       被測實作的一部分；測試端的 oracle 必須獨立於受檢實作。
#   h06_age_r2(frame, breaks, levels)
#       單獨配適年齡帶模型。四帶與五帶各呼叫一次，用來把「兩種參數化不可混用」
#       變成可證偽的斷言（四帶 0.07557、五帶 0.08390）。
#   h06_reported_from_source()
#       自 `05_models.R` 的 `REPORTED_R2` 區塊抄出六個報告值（字串，末位即精度）。
#   h06_run(out_root, clean_path = NULL, reported = NULL)
#       在**暫存輸出根**上執行 `05_models.R`（或其注入副本），回傳腳本寫出的比較表
#       （由腳本自身環境的 `comparison` 取回，不另讀檔）、輸出、結束狀態與耗時。
#       兩種注入都只改**暫存副本**：`clean_path`（退化 fixture 的清洗資料集）與
#       `reported`（改 `REPORTED_R2` 的某個字串一位——負向控制）。
#   h06_write_frame(frame, path)
#       把變異後的資料框寫成清洗資料集形狀（逗號分隔、欄名與數值不動）。
#
# 樣本與收縮：本流程無隨機來源（glm 為確定性計算），種子與收縮一律記 n/a；退化
# fixture 是單點注入（一個欄位設為常數），沒有可枚舉的候選空間，故收縮亦記 n/a。
# 重試 0 次；單流程上限 120 秒。

## 0. 載入即載入測試台（REQ-A-7）-------------------------------------------

# 本檔所在目錄。順序：先看 source 堆疊上指向本檔的 `ofile`（`test_dir()`／`test_file()`
# 與入口都經 source()），再看 `--file=`（本檔被 Rscript 直接執行時），最後才退回工作
# 目錄。`tests/testthat.R` 的 `--file=` 是入口檔本身，先看它會把目錄誤判成 tests/。
h06_this_dir <- function() {
  frames <- sys.frames()
  for (i in rev(seq_along(frames))) {
    ofile <- frames[[i]]$ofile
    if (!is.null(ofile) && grepl("harness-06[.]R$", ofile)) {
      return(dirname(normalizePath(ofile, winslash = "/", mustWork = FALSE)))
    }
  }
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg) && grepl("harness-06[.]R$", file_arg[[1L]])) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[[1L]]), winslash = "/", mustWork = FALSE)))
  }
  for (dir in c(getwd(), file.path(getwd(), "tests", "testthat"))) {
    if (file.exists(file.path(dir, "harness-06.R"))) {
      return(normalizePath(dir, winslash = "/", mustWork = FALSE))
    }
  }
  getwd()
}

# 載入時無條件把 helper 載進**本檔被求值的同一個環境**（A-43）：h06_* 的 enclosure 就
# 在那裡，故 harness_data()／harness_table()／harness_dir() 一併解析得到。不依賴呼叫端
# 先 source 過 helper——`testthat::test_dir()` 把 helper 放進它自己的測試環境，靠
# globalenv 的閉包看不到；`local = TRUE` 落點是本檔 top-level 的求值環境，三種入口一致。
if (!file.exists(file.path(h06_this_dir(), "helper-harness.R"))) {
  stop("找不到 helper-harness.R（應與 harness-06.R 同目錄）：", h06_this_dir(), call. = FALSE)
}
source(file.path(h06_this_dir(), "helper-harness.R"), local = TRUE)

## 1. 預算與上限 -----------------------------------------------------------

H06_FLOW <- "F6 三層的解釋力比較"
H06_SAMPLE <- "兩個母體全列（analysis 3630、ability 2828），無抽樣"
H06_SAMPLE_ROWS <- c(3630L, 2828L)
H06_SEED_NOTE <- "n/a（glm 為確定性計算，無隨機來源；harness_seed() 未被呼叫）"
H06_SHRINK_NOTE <- "n/a（退化 fixture 是單點注入，無隨機最小化）"
H06_FLOW_LIMIT_SEC <- 120
H06_RETRIES <- 0L

## 2. 釘值與欄名 -----------------------------------------------------------

# 表與入口（相對專案根；專案根以 AMS2640.Rproj 解析，與 00_setup.R 同一個根）
H06_TABLE <- "model_comparison"
H06_QUARTILE_TABLE <- "ability_quartiles"
H06_PROGRAM_REL <- file.path("programs", "R", "05_models.R")
H06_PROJECT_MARKER <- "AMS2640.Rproj"

# 表的欄名（T07 的 Owned 面；缺一即無法判讀）
H06_COLUMNS <- c("model", "population", "n", "mcfadden_r2", "auc", "mechanism", "falsifier", "status")
H06_REQUIRED <- c("population", "n", "mcfadden_r2", "auc", "falsifier", "status")

# 六列的（模型, 母體, n）配對——順序即表序，也即 REPORTED_R2 的宣告序。
# 財務三欄出現兩次是規格的一部分：同一規格在兩個母體上各一列（PRD F6 boundary）。
H06_PAIRS <- data.frame(
  model = c("age_band", "financial_three", "financial_three",
            "ability_quartile", "financial_plus_ability", "admission_quartile"),
  population = c("analysis", "analysis", "ability", "ability", "ability", "ability"),
  n = c(3630L, 3630L, 2828L, 2828L, 2828L, 2828L),
  key = c("age_band", "financial_three", "financial_three_ability",
          "ability_quartile", "financial_plus_ability", "admission_quartile"),
  stringsAsFactors = FALSE
)

# 報告所載的六個 R²（A-46：一律四位有效數字）。存**字串**：末位就是比對精度，
# 換成數值會把「寫到第幾位」這件事洗掉（A-40）。這六個字串同時是
# h06_run() 的負向控制的對象——改一位即須轉 mismatch。
H06_REPORTED <- c(
  age_band               = "0.07557",
  financial_three        = "0.2227",
  financial_three_ability = "0.2011",
  ability_quartile       = "0.09577",
  financial_plus_ability = "0.2611",
  admission_quartile     = "0.004952"
)

# 半個末位的容差：末位即半個單位。0.004952（六位小數）→ 5e-7、0.09577 → 5e-6、
# 0.2227 → 5e-5。逐條列為釘值，使「精度規則」本身也被檢查（不是由實作自證）。
H06_TOLERANCE <- c(
  age_band               = 5e-6,
  financial_three        = 5e-5,
  financial_three_ability = 5e-5,
  ability_quartile       = 5e-6,
  financial_plus_ability = 5e-5,
  admission_quartile     = 5e-7
)

# 年齡帶的兩種參數化（PRD §4 F6、A-16）：模型用四帶，五帶只當反面錨。
H06_AGE_BREAKS_MODEL <- c(25, 30, 40)
H06_AGE_LEVELS_MODEL <- c("<25", "25-29", "30-39", "40+")
H06_AGE_BREAKS_AGEGROUP <- c(20, 25, 30, 40)
H06_AGE_LEVELS_AGEGROUP <- c("<20", "20-24", "25-29", "30-39", "40+")
# 四帶與五帶的人數（3,630 人）：合計相同、切法不同——參數化不是換標籤。
H06_PIN_AGE_N_MODEL <- c(2654L, 355L, 403L, 218L)
H06_PIN_AGE_N_AGEGROUP <- c(1621L, 1033L, 355L, 403L, 218L)
# 五帶模型的 R²（四位有效數字）：0.08390。與四帶的 0.07557 在半個末位規則下不等。
H06_PIN_AGE_R2_AGEGROUP <- "0.08390"

# 能力／入學分位：T06 的等量切法，四組各 707 人（在 2,828 上）
H06_QUARTILE_LEVELS <- paste0("q", seq_len(4L))
H06_PIN_QUARTILE_N <- c(707L, 707L, 707L, 707L)

# 清洗資料集的欄名與編碼（與 05_models.R、00_setup.R 同義，測試端自行表達）
H06_COL_RESULT <- "target"
H06_COL_AGE <- "Age at enrollment"
H06_COL_TUITION <- "Tuition fees up to date"
H06_COL_DEBTOR <- "Debtor"
H06_COL_SCHOLARSHIP <- "Scholarship holder"
H06_COL_SEM2 <- "Curricular units 2nd sem (grade)"
H06_COL_ADMISSION <- "Admission grade"
H06_DROPOUT <- "Dropout"
H06_UNPAID_VALUE <- 0L
H06_DEBTOR_VALUE <- 1L
H06_SCHOLARSHIP_NONE_VALUE <- 0L

# 重算與表值的相對容差（PRD D10：對未格式化的 double 比對）。同一個 glm 在兩處
# 各跑一次，差只可能來自浮點運算次序，故 1e-9 遠寬於必要、又遠窄於任何真實差異。
H06_REL_TOL <- 1e-9

## 3. 呈現與比對 -----------------------------------------------------------

# 四位有效數字（與 lib 的 fmt_sig 同形，但本檔不 source 生產檔案）
h06_sig <- function(x, digits = 4L) {
  template <- paste0("%#.", as.integer(digits), "g")
  vapply(as.numeric(x), function(value) {
    if (is.na(value)) NA_character_ else sprintf(template, value)
  }, character(1))
}

# 報告數字的比對精度（A-40）：末位即半個單位。"0.07557" → 5e-6、"0.2227" → 5e-5、
# "0.004952" → 5e-7。
# 同時要求該位不超過四位有效數字——「0.0049523」這種寫法是靠容差活著，不是精度。
h06_precision <- function(text) {
  if (!is.character(text) || length(text) != 1L || !grepl("^[0-9]+[.][0-9]+$", text)) {
    stop("h06_precision：報告值須為 '0.xxx' 形式的字串；實得 ", paste(text, collapse = ", "), call. = FALSE)
  }
  decimals <- nchar(sub("^[^.]*[.]", "", text))
  significant <- nchar(gsub("[^1-9]", "", sub("^0+[.]?0*", "", text)))
  if (significant > 4L) {
    stop(sprintf("報告值 %s 寫到 %d 位有效數字，超過位數政策（4）", text, significant), call. = FALSE)
  }
  list(tolerance = 0.5 * 10^(-decimals), significant_digits = significant, decimals = decimals)
}

# 逐值「在半個末位內相等」：回邏輯向量，不呼叫 testthat（本檔須能單獨 source）
h06_matches <- function(actual, text) {
  vapply(seq_along(actual), function(i) {
    gap <- abs(as.numeric(actual[i]) - as.numeric(text[i]))
    gap <= h06_precision(text[i])$tolerance
  }, logical(1))
}

## 4. 路徑、指紋與注入 -----------------------------------------------------

# 專案根：與 00_setup.R 同一個標記檔。只用來指名入口程式與算已發佈表的指紋，
# 讀表一律經 harness_table()（A-36）。
h06_project_root <- function() {
  root <- tryCatch(here::here(), error = function(e) NA_character_)
  if (is.na(root) || !file.exists(file.path(root, H06_PROJECT_MARKER))) {
    stop("refuse:input-missing\n- here() 未解析到含 ", H06_PROJECT_MARKER,
         " 的專案根（實得 ", root, "）：無法指名 ", H06_PROGRAM_REL, "。", call. = FALSE)
  }
  normalizePath(root, winslash = "/", mustWork = TRUE)
}

h06_program_path <- function() file.path(h06_project_root(), H06_PROGRAM_REL)

h06_published_path <- function() {
  file.path(h06_project_root(), "output", "tables", paste0(H06_TABLE, ".csv"))
}

# 表指紋：sha256。專案無 digest／openssl，故走外部工具；兩者皆缺即拒絕——
# 「算不出指紋就說表沒變」是把檢查變成恆真。
h06_sha256 <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  found <- Sys.which(c("shasum", "sha256sum"))
  found <- found[nzchar(found)]
  if (!length(found)) {
    stop("refuse:input-missing\n- 找不到 shasum／sha256sum：無法計算 ", path,
         " 的 sha256，拒絕在無法比對的情況下宣稱表未變。", call. = FALSE)
  }
  tool <- found[[1]]
  args <- if (grepl("sha256sum$", tool)) shQuote(path) else c("-a", "256", shQuote(path))
  out <- system2(tool, args, stdout = TRUE, stderr = TRUE)
  if (!length(out) || !grepl("^[0-9a-f]{64}([[:space:]]|$)", out[[1]])) {
    stop("refuse:input-missing\n- ", basename(tool), " 未回可解析的 sha256（",
         paste(out, collapse = " "), "）。", call. = FALSE)
  }
  sub("[[:space:]].*$", "", out[[1]])
}

.h06_source_lines <- function() readLines(h06_program_path(), warn = FALSE, encoding = "UTF-8")

# `REPORTED_R2` 區塊的起訖行號：被測程式的常數位置。取不到即拒絕——注入與釘值
# 都靠它，位置不明時「找不到就跳過」會讓兩條檢查一起變成恆真。
.h06_reported_block <- function(lines) {
  start <- grep("^REPORTED_R2 <- c\\(", lines)
  if (length(start) != 1L) {
    stop("refuse:input-missing\n- ", H06_PROGRAM_REL, " 找不到唯一的 `REPORTED_R2 <- c(`（實得 ",
         length(start), " 行）。", call. = FALSE)
  }
  rest <- seq.int(start + 1L, length(lines))
  closing <- rest[grepl("^[)]", lines[rest])]
  if (!length(closing)) {
    stop("refuse:input-missing\n- ", H06_PROGRAM_REL, " 的 REPORTED_R2 區塊沒有結束的 `)`。", call. = FALSE)
  }
  list(start = start, rows = seq.int(start + 1L, closing[[1]] - 1L))
}

# 自原始碼抄出報告值（六個字串）。測試用它證明釘值與被測程式的常數同值：
# 有人改了常數，這條就紅。
h06_reported_from_source <- function() {
  lines <- .h06_source_lines()
  block <- .h06_reported_block(lines)
  parsed <- regmatches(lines[block$rows],
                       regexec("^\\s*([A-Za-z_]+)\\s*=\\s*\"([0-9.]+)\"", lines[block$rows]))
  keep <- vapply(parsed, length, integer(1)) == 3L
  if (!any(keep)) {
    stop("refuse:input-missing\n- ", H06_PROGRAM_REL, " 的 REPORTED_R2 區塊沒有可解析的條目。", call. = FALSE)
  }
  values <- vapply(parsed[keep], `[[`, character(1), 3L)
  names(values) <- vapply(parsed[keep], `[[`, character(1), 2L)
  values
}

# 把某個報告值改成另一個字串（負向控制用）。只改 REPORTED_R2 區塊內的那一行：
# `MODEL_FIN <- "financial_three"` 與 SPECS 的 `reported = "..."` 都不在區塊內。
h06_patch_reported <- function(lines, key, value) {
  if (!is.character(value) || length(value) != 1L || !grepl("^[0-9]+[.][0-9]+$", value)) {
    stop("h06_patch_reported：value 須為 '0.xxx' 字串；實得 ", paste(value, collapse = ", "), call. = FALSE)
  }
  block <- .h06_reported_block(lines)
  pattern <- sprintf("^\\s*%s\\s*=\\s*\"[0-9.]+\"", key)
  hit <- block$rows[grepl(pattern, lines[block$rows])]
  if (length(hit) != 1L) {
    stop("h06_patch_reported：REPORTED_R2 區塊內找不到唯一的 `", key,
         " = \"...\"`（實得 ", length(hit), " 行）。", call. = FALSE)
  }
  lines[hit] <- sub("\"[0-9.]+\"", sprintf("\"%s\"", value), lines[hit])
  lines
}

# 被測程式的（可能注入過的）原始碼。兩種注入都只在記憶體裡改字串，寫出的副本一律落在
# harness_dir()；`programs/` 與 `output/` 不經手。
h06_script_lines <- function(clean_path = NULL, reported = NULL) {
  lines <- .h06_source_lines()
  if (!is.null(clean_path)) {
    if (!is.character(clean_path) || length(clean_path) != 1L || !file.exists(clean_path)) {
      stop("h06_script_lines：clean_path 不存在：", paste(clean_path, collapse = ", "), call. = FALSE)
    }
    hit <- grep("^CLEAN_PATH <-", lines)
    if (length(hit) != 1L) {
      stop("refuse:input-missing\n- ", H06_PROGRAM_REL, " 找不到唯一的 `CLEAN_PATH <-`（實得 ",
           length(hit), " 行）：退化 fixture 無處注入。", call. = FALSE)
    }
    lines[hit] <- sprintf("CLEAN_PATH <- \"%s\"",
                          normalizePath(clean_path, winslash = "/", mustWork = TRUE))
  }
  if (!is.null(reported)) {
    if (is.null(names(reported)) || any(!nzchar(names(reported)))) {
      stop("h06_script_lines：reported 須為具名向量（key = 報告值字串）。", call. = FALSE)
    }
    for (key in names(reported)) lines <- h06_patch_reported(lines, key, reported[[key]])
  }
  lines
}

# 把 T06 的分位表放進暫存輸出根：05_models.R 讀 <OUT_ROOT>/tables/ability_quartiles.csv。
# 內容取自已發佈的表（經 harness_table()），故注入的只是位置、不是數值。
h06_plant_quartiles <- function(out_root) {
  tables <- file.path(out_root, "tables")
  if (!dir.exists(tables)) {
    stop("h06_plant_quartiles：", out_root, " 不是 harness_out_root() 給的根（缺 tables/）。", call. = FALSE)
  }
  target <- file.path(tables, paste0(H06_QUARTILE_TABLE, ".csv"))
  if (file.exists(target)) return(target)
  quartiles <- harness_table(H06_QUARTILE_TABLE,
                             required = c("population", "quartile", "n", "graduation_rate"))
  utils::write.csv(quartiles, target, row.names = FALSE, fileEncoding = "UTF-8")
  target
}

## 5. 入口：在暫存根上執行 05_models.R --------------------------------------

# 在本行程內 source 腳本（或其注入副本）。理由與 V04 同：subprocess 每次要付 R 啟動與
# renv 的代價，而本流程要跑三次（原樣、負向控制、退化 fixture）。
#
# 回傳的比較表取自**腳本自身環境**的 `comparison`（它就是寫進 csv 的那一份），
# 不另讀檔：測試端不得自行讀表（REQ-A-7），harness_table() 又只讀已發佈的表。
h06_run <- function(out_root, clean_path = NULL, reported = NULL) {
  if (!is.character(out_root) || length(out_root) != 1L || !dir.exists(out_root)) {
    stop("h06_run：out_root 須為既有的輸出根（由 harness_out_root() 取得）。", call. = FALSE)
  }
  h06_plant_quartiles(out_root)

  prior <- Sys.getenv("RTOOLKIT_OUT_ROOT", unset = "")
  on.exit({
    if (nzchar(prior)) Sys.setenv(RTOOLKIT_OUT_ROOT = prior) else Sys.unsetenv("RTOOLKIT_OUT_ROOT")
  }, add = TRUE)

  script <- file.path(harness_dir(), "05_models_injected.R")
  writeLines(h06_script_lines(clean_path = clean_path, reported = reported), script, useBytes = TRUE)

  Sys.setenv(RTOOLKIT_OUT_ROOT = normalizePath(out_root, winslash = "/", mustWork = TRUE))
  child <- new.env(parent = globalenv())
  error_message <- NULL
  started <- Sys.time()
  output <- utils::capture.output(
    tryCatch(
      sys.source(script, envir = child),
      error = function(e) {
        error_message <<- conditionMessage(e)
        invisible(NULL)
      }
    )
  )
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))

  table <- file.path(out_root, "tables", paste0(H06_TABLE, ".csv"))
  list(
    status = if (is.null(error_message)) "ok" else "error",
    error = error_message,
    output = as.character(output),
    out_root = out_root,
    script = script,
    table = table,
    table_written = file.exists(table),
    # 腳本環境裡的成品；腳本若在寫表前停手（halt）則不存在
    comparison = if (exists("comparison", envir = child, inherits = FALSE)) child$comparison else NULL,
    elapsed = elapsed
  )
}

# 把變異後的資料框寫成清洗資料集形狀（逗號分隔、欄名與數值不動）。
h06_write_frame <- function(frame, path) {
  if (!is.data.frame(frame)) stop("h06_write_frame：frame 須為資料框。", call. = FALSE)
  utils::write.csv(frame, path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

## 6. 模型：獨立重算六列 ---------------------------------------------------

# 等量切組（T06 的切法）：升冪、穩定排序（同分依原始列序）、組寬 floor(n / groups)、
# 餘數全收末組。與 04_ability.R、05_models.R 同一個規格；本檔自行實作，不共用。
h06_equal_split <- function(score, groups) {
  n <- length(score)
  if (!n) stop("h06_equal_split：分數為空。", call. = FALSE)
  if (groups < 2L || groups > n) stop("h06_equal_split：組數不合法。", call. = FALSE)
  placement <- order(score, method = "radix")
  width <- n %/% groups
  membership <- integer(n)
  for (g in seq_len(groups - 1L)) {
    membership[placement[((g - 1L) * width + 1L):(g * width)]] <- g
  }
  membership[placement[((groups - 1L) * width + 1L):n]] <- groups
  membership
}

# 帶：findInterval 的左閉右開 [a, b)，標籤索引 +1（與 05_models.R、03_age.R 同）
h06_band <- function(value, breaks, levels) {
  factor(levels[findInterval(value, breaks) + 1L], levels = levels)
}

h06_dropout <- function(frame) as.integer(as.character(frame[[H06_COL_RESULT]]) == H06_DROPOUT)

h06_financial <- function(frame) {
  data.frame(
    tuition_unpaid = as.integer(frame[[H06_COL_TUITION]] == H06_UNPAID_VALUE),
    debtor         = as.integer(frame[[H06_COL_DEBTOR]] == H06_DEBTOR_VALUE),
    no_scholarship = as.integer(frame[[H06_COL_SCHOLARSHIP]] == H06_SCHOLARSHIP_NONE_VALUE),
    stringsAsFactors = FALSE
  )
}

# 秩式 AUC（正類為退學、分數為 predict(type = "response")、同分取平均秩）。
# 與 lib 的 auc_rank 同一個定義，但本檔自行實作（oracle 不得共用受檢實作）。
h06_auc <- function(score, positive) {
  positive <- as.logical(positive)
  n_pos <- sum(positive)
  n_neg <- sum(!positive)
  if (!n_pos || !n_neg) return(NA_real_)
  ranks <- rank(score, ties.method = "average")
  (sum(ranks[positive]) - n_pos * (n_pos + 1) / 2) / (n_pos * n_neg)
}

# 一列配適：McFadden R² = 1 − ll_model / ll_null，ll_null 取 −null.deviance / 2
# （即僅截距模型的對數似然）。不收斂時直接停——退化 fixture 的那一列由被測程式
# 判 refuse:empty-denominator，測試端不重造那個分支。
h06_fit <- function(dat, terms) {
  formula <- stats::as.formula(paste("dropout ~", paste(terms, collapse = " + ")))
  fit <- stats::glm(formula, data = dat, family = stats::binomial())
  ll_model <- as.numeric(stats::logLik(fit))
  ll_null <- -fit$null.deviance / 2
  list(
    n = nrow(dat),
    r2 = 1 - ll_model / ll_null,
    auc = h06_auc(stats::predict(fit, type = "response"), dat$dropout == 1L),
    converged = isTRUE(fit$converged)
  )
}

# 四帶／五帶的年齡模型（只用來把兩種參數化分開量）；回 n（逐帶）與 R²。
h06_age_fit <- function(frame, breaks, levels) {
  dat <- data.frame(
    dropout = h06_dropout(frame),
    age_band = h06_band(frame[[H06_COL_AGE]], breaks, levels),
    stringsAsFactors = FALSE
  )
  list(fit = h06_fit(dat, "age_band"), n = tabulate(as.integer(dat$age_band), nbins = length(levels)))
}

# 六列的獨立重算：兩個母體分開（analysis 3,630；ability 2,828），表序與 H06_PAIRS 同。
h06_recompute <- function(analysis, ability) {
  financial_terms <- c("tuition_unpaid", "debtor", "no_scholarship")

  analysis_dat <- data.frame(
    dropout = h06_dropout(analysis),
    h06_financial(analysis),
    age_band = h06_band(analysis[[H06_COL_AGE]], H06_AGE_BREAKS_MODEL, H06_AGE_LEVELS_MODEL),
    stringsAsFactors = FALSE
  )

  ability_quartile <- h06_equal_split(ability[[H06_COL_SEM2]], length(H06_QUARTILE_LEVELS))
  admission_quartile <- h06_equal_split(ability[[H06_COL_ADMISSION]], length(H06_QUARTILE_LEVELS))
  ability_dat <- data.frame(
    dropout = h06_dropout(ability),
    h06_financial(ability),
    ability_band = factor(H06_QUARTILE_LEVELS[ability_quartile], levels = H06_QUARTILE_LEVELS),
    admission_band = factor(H06_QUARTILE_LEVELS[admission_quartile], levels = H06_QUARTILE_LEVELS),
    stringsAsFactors = FALSE
  )

  specs <- list(
    list(dat = analysis_dat, terms = "age_band"),
    list(dat = analysis_dat, terms = financial_terms),
    list(dat = ability_dat,  terms = financial_terms),
    list(dat = ability_dat,  terms = "ability_band"),
    list(dat = ability_dat,  terms = c(financial_terms, "ability_band")),
    list(dat = ability_dat,  terms = "admission_band")
  )

  fits <- lapply(specs, function(spec) h06_fit(spec$dat, spec$terms))
  data.frame(
    model = H06_PAIRS$model,
    population = H06_PAIRS$population,
    n = vapply(fits, function(f) as.numeric(f$n), numeric(1)),
    mcfadden_r2 = vapply(fits, function(f) as.numeric(f$r2), numeric(1)),
    auc = vapply(fits, function(f) as.numeric(f$auc), numeric(1)),
    converged = vapply(fits, function(f) isTRUE(f$converged), logical(1)),
    stringsAsFactors = FALSE
  )
}

## 7. 已發佈的表與母體清冊 ------------------------------------------------

# 已發佈的比較表（固定讀 PROJ_ROOT/output/tables，A-36）。欄名缺一即拒絕。
h06_table <- function() {
  tbl <- harness_table(H06_TABLE, required = H06_REQUIRED)
  if (nrow(tbl) != nrow(H06_PAIRS)) {
    stop(sprintf("表 %s.csv 有 %d 列，契約為六列（五個規格 × 兩個母體的配對）。",
                 H06_TABLE, nrow(tbl)), call. = FALSE)
  }
  tbl
}

# 以（模型, 母體）取一列：配對是六列的鍵，財務三欄因此有兩列而不得混淆。
# 逐列釘值一律經此取列，不依賴列序。
h06_pick <- function(tbl, model, population) {
  rows <- tbl[as.character(tbl$model) == model & as.character(tbl$population) == population, , drop = FALSE]
  if (nrow(rows) != 1L) {
    stop(sprintf("表內（%s, %s）有 %d 列，應為 1 列（六列的鍵是配對本身）。",
                 model, population, nrow(rows)), call. = FALSE)
  }
  rows
}

# 母體清冊的 n：3,630（analysis）與 2,828（ability）的另一個來源（REQ-F-F2-1）
h06_ledger_n <- function(population) {
  ledger <- harness_table("population_ledger")
  absent <- setdiff(c("population", "metric", "n"), names(ledger))
  if (length(absent)) {
    stop("refuse:input-missing\n- population_ledger.csv 缺欄名：",
         paste(absent, collapse = ", "), call. = FALSE)
  }
  rows <- ledger[as.character(ledger$population) == population &
                   as.character(ledger$metric) == population, , drop = FALSE]
  if (nrow(rows) != 1L) {
    stop("refuse:input-missing\n- 母體清冊的 ", population, " 列有 ", nrow(rows),
         " 筆，應為 1 筆。", call. = FALSE)
  }
  as.numeric(rows$n)
}
