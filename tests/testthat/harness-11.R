# harness-11.R — F11（交付）的預算、執行上限與入口（V11）
#
# 交界契約（REQ-A-7）：`test-11_F11.R` 只呼叫本檔的 `f11_*` 與 `helper-harness.R`
# 的具名函式。樣本、暫存與輸出根一律取自 helper；本檔不含讀資料檔的呼叫、不設種子、
# 不自建暫存目錄。本檔唯一「讀」的非資料檔是被測入口 `programs/R/run_all.R` 的存在性
# 與它寫出的 `output/logs/run_all.log`——那是交付行為本身，不是樣本。
#
# 本檔是 F11 的模型：把 T13（seam `programs/R/run_all.R`）的判定表翻成可證偽的純函式，
# 使「28 列覆蓋、每列帶 population 與 n、拒絕時 number_map.csv 不落地」在入口尚未
# 存在時也能被判定；入口存在之後，同一批斷言直接套到已發佈的產物上。
#
#   f11_spec_check(spec)        spec 的形狀：四欄齊備、恰 28 列、key 不重複不為空；
#                               任一不符即 refuse:incomplete-spec（T13 步驟 4）。
#   f11_profile_of(name, tbl)   一張表的逐列母體與 n；缺欄、缺值、非整數即
#                               refuse:missing-profile（PRD §3 不變量）。
#   f11_profiles(tables)        十張分析表逐表檢查，回 named list（每張一個資料框）。
#   f11_map(spec, ...)          逐列把 spec 的 (source_table, source_row) 解析成
#                               (population, n)，產出 28 列的 number_map 內容。
#                               解析不到唯一一列即 refuse:missing-profile。
#   f11_deliver(spec, dir, ...) 交付動作：兩個檢查都過才寫 number_map.csv；
#                               任一拒絕則**一個位元組都不寫**。
#   f11_run(out_root)           以子程序跑 `programs/R/run_all.R`（T13 未就位時由
#                               測試檔 skip，不以空跑冒充綠）。
#
# 樣本與種子：本流程無隨機來源，`harness_seed()` 不被呼叫，seed／收縮記 n/a；
# 退化 fixture 是「spec 與表的有限變異」（少一列、重複 key、拿掉一欄、指錯列），
# 以枚舉取代隨機最小化。單流程上限 600 秒（V11 的 Budget）。

## 0. 自我載入 helper（REQ-A-7／A-43）-------------------------------------

# 本檔的函式以「本檔被 source() 的求值環境」為 enclosure，故 helper 必須落在**同一個
# 環境**內；否則 `f11_*` 內的 `harness_data()`／`harness_table()` 在求值時沿 enclosure
# 鏈找不到（`test_dir()` 把 helper 載進它自己的測試環境，單獨 `test_dir()` 就解析
# 失敗——A-43 的三個入口要同綠，故本檔自己備妥 helper，不假設呼叫端先載入）。
h11_this_dir <- function() {
  candidates <- character()
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg) == 1L) {
    candidates <- c(candidates, dirname(sub("^--file=", "", file_arg[[1L]])))
  }
  frames <- sys.frames()
  for (i in rev(seq_along(frames))) {
    ofile <- frames[[i]]$ofile
    if (!is.null(ofile) && grepl("harness-11[.]R$", ofile)) {
      candidates <- c(candidates, dirname(ofile))
      break
    }
  }
  candidates <- c(candidates, getwd(), file.path(getwd(), "tests", "testthat"))
  for (dir in candidates) {
    if (file.exists(file.path(dir, "helper-harness.R"))) {
      return(normalizePath(dir, winslash = "/", mustWork = TRUE))
    }
  }
  stop("harness-11.R 找不到 helper-harness.R：應與本檔同目錄（tests/testthat/）。", call. = FALSE)
}

# 載入 helper 並逐一點名本檔要用的函式：缺一即停止——「以為載入了」比沒載入更難查。
h11_load_helper <- function(target) {
  helper <- file.path(h11_this_dir(), "helper-harness.R")
  if (!is.environment(target)) stop("h11_load_helper：target 須為環境。", call. = FALSE)
  if (!exists("harness_table", mode = "function", inherits = FALSE, envir = target)) {
    sys.source(helper, envir = target)
  }
  required <- c("harness_data", "harness_dir", "harness_out_root", "harness_table", "expect_profile")
  missing <- required[!vapply(
    required,
    function(name) exists(name, mode = "function", inherits = FALSE, envir = target),
    logical(1)
  )]
  if (length(missing)) {
    stop(sprintf("harness-11.R 載入 %s 後仍缺函式：%s", helper, paste(missing, collapse = ", ")), call. = FALSE)
  }
  invisible(target)
}

h11_load_helper(environment())

## 1. 預算 -----------------------------------------------------------------

H11_BUDGET <- list(
  rows = c(analysis = 3630L, ability = 2828L), # 兩個母體各全列一次，無抽樣
  seed = NA_integer_,                          # n/a：無隨機來源
  shrink_max = 200L,                           # n/a：fixture 為有限枚舉
  shrink_sec = 30,
  timeout_sec = 600,                           # 單流程上限（V11 的 Budget）
  retries = 0L
)

f11_budget <- function() {
  list(
    rows = H11_BUDGET$rows,
    sample = "全列（3,630 與 2,828 各一次，無抽樣）",
    seed = "n/a（無隨機來源；harness_seed() 未被呼叫）",
    shrink = "n/a（fixture 為 spec 與表的有限枚舉，非隨機最小化）",
    flow_seconds = H11_BUDGET$timeout_sec,
    retries = H11_BUDGET$retries
  )
}

## 2. 常數（契約面）--------------------------------------------------------

# 兩個產物與入口（相對專案根；專案根由 helper 以 AMS2640.Rproj 解析）
H11_SPEC_TABLE <- "number_map_spec"
H11_MAP_TABLE <- "number_map"
H11_PROGRAM_REL <- file.path("programs", "R", "run_all.R")

# spec 的 28 列（T13：報告的 28 個數字）與四欄
H11_SPEC_ROWS <- 28L
H11_SPEC_COLUMNS <- c("number_key", "value", "source_table", "source_row")

# number_map.csv 的八欄（T13 的 Owned 面，欄序即契約）
H11_MAP_COLUMNS <- c(
  "number_key", "spec_value", "table_value", "source_table",
  "source_row", "population", "n", "pass"
)

# 十張分析表與各自的母體／n 欄（T13 步驟 3 的列舉；age_tests 的 n 是 n_a／n_b）
H11_PROFILE_COLUMNS <- list(
  wealth_four_cell     = c("population", "n"),
  age_bands            = c("population", "n"),
  age_tests            = c("population", "n_a", "n_b"),
  marriage_strata      = c("population", "n"),
  ability_quartiles    = c("population", "n"),
  ability_transitions  = c("population", "n"),
  model_comparison     = c("population", "n"),
  language_groups      = c("population", "n"),
  macro_values         = c("population", "n"),
  correlation_audit    = c("population", "n")
)

# 列鍵：把 spec 的 `source_row` 指向表內某**一列**的欄位組合。
# 單欄不足以指名一列的表用兩欄——`model_comparison` 是「五個模型 × 兩個母體」六列
# （model 只有五個不同值）、`macro_values` 是十個年度區塊三十列（variable 只有三個
# 不同值）、`age_tests` 是兩個檢定（test 只有兩個值）。這是本模型對 T13 未定的
# `source_row` 格式所提的讀法，記於 pins/11_F11.md 第 7 節待 T13 裁決。
H11_ROW_KEY_COLUMNS <- list(
  wealth_four_cell    = "cell",
  age_bands           = "band",
  age_tests           = c("test", "group_a"),
  marriage_strata     = "band",
  ability_quartiles   = "quartile",
  ability_transitions = "from_sem1",
  model_comparison    = c("model", "population"),
  language_groups     = "group",
  macro_values        = c("variable", "year"),
  correlation_audit   = "variable"
)

# 列鍵的分隔符（單一列鍵內的欄值以它相接）
H11_KEY_SEP <- "|"

# 四位有效數字與 A-40 的比對精度（見 f11_value_equal）
H11_SIG_DIGITS <- 4L

## 3. 拒絕與呈現 -----------------------------------------------------------

# 拒絕一律以 `refuse:<類別>` 起頭，第二行起寫「缺什麼、在哪、下一步」（PRD §8）。
f11_refuse <- function(category, ...) {
  stop(
    sprintf("refuse:%s\n- %s", category, paste(c(...), collapse = "\n- ")),
    call. = FALSE
  )
}

# 四位有效數字（與 lib 的 fmt_sig 同形；本檔不 source 生產檔案）
f11_sig <- function(x, digits = H11_SIG_DIGITS) {
  template <- paste0("%#.", as.integer(digits), "g")
  vapply(as.numeric(x), function(value) {
    if (is.na(value)) NA_character_ else sprintf(template, value)
  }, character(1))
}

f11_sig_equal <- function(actual, expected, digits = H11_SIG_DIGITS) {
  identical(f11_sig(actual, digits), f11_sig(expected, digits))
}

# spec 值「寫到第幾位小數」。計數（無小數點）回 0，指數形式回 0 並由呼叫端改走四位。
f11_written_decimals <- function(text) {
  txt <- trimws(as.character(text))
  if (length(txt) != 1L || is.na(txt) || grepl("[eE]", txt) || !grepl("[.]", txt)) return(0L)
  as.integer(nchar(sub("^[^.]*[.]", "", txt)))
}

# 逐值比對：計數零差（D10）；有小數時「差在半個末位內即相等」（A-40：報告寫 0.0756
# 只有四位小數，用字串式四位有效數字會把 0.07557 判成不同）。
f11_value_equal <- function(actual, spec_value) {
  act <- suppressWarnings(as.numeric(actual))
  exp <- suppressWarnings(as.numeric(as.character(spec_value)))
  if (length(act) != length(exp) || anyNA(act) || anyNA(exp)) return(rep(NA, length(exp)))
  dec <- f11_written_decimals(spec_value)
  tol <- if (dec == 0L) 0 else 0.5 * 10^(-dec)
  abs(act - exp) <= tol
}

## 4. 路徑 -----------------------------------------------------------------

f11_project_root <- function() {
  marker <- file.path("AMS2640.Rproj")
  dir <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  repeat {
    if (file.exists(file.path(dir, marker))) return(dir)
    parent <- dirname(dir)
    if (identical(parent, dir)) {
      f11_refuse("input-missing", "找不到含 AMS2640.Rproj 的專案根，無法指名入口 ", H11_PROGRAM_REL, "。")
    }
    dir <- parent
  }
}

f11_program_path <- function() file.path(f11_project_root(), H11_PROGRAM_REL)

# spec 由 T13 寫定並置唯讀；路徑一律自專案根解析，不隨輸出根變動（T13 步驟 4）。
f11_spec_path <- function() {
  file.path(f11_project_root(), "output", "tables", paste0(H11_SPEC_TABLE, ".csv"))
}

f11_map_path <- function(tables_dir) file.path(tables_dir, paste0(H11_MAP_TABLE, ".csv"))

f11_log_path <- function(out_root) file.path(out_root, "logs", "run_all.log")

## 5. spec：形狀與 28 列 ----------------------------------------------------

# spec 的形狀檢查（T13 步驟 4）：四欄齊備、恰 28 列、key 非空且不重複、
# source_table／source_row 非空。任一不符即 refuse:incomplete-spec——缺列的表
# 意味著報告有一個數字沒有來源，交付不得繼續。
f11_spec_check <- function(spec) {
  if (!is.data.frame(spec)) {
    stop("f11_spec_check：spec 須為資料框（number_map_spec.csv 的內容）；實得 ", class(spec)[1], "。", call. = FALSE)
  }
  absent <- setdiff(H11_SPEC_COLUMNS, names(spec))
  if (length(absent)) {
    f11_refuse(
      "incomplete-spec",
      sprintf("spec 缺欄名 %s（實有：%s）", paste(absent, collapse = "、"), paste(names(spec), collapse = ", ")),
      "四欄為 T13 的契約面，缺一則無法逐列比對來源。"
    )
  }
  if (nrow(spec) != H11_SPEC_ROWS) {
    f11_refuse(
      "incomplete-spec",
      sprintf("spec 為 %d 列，契約為 %d 列（報告的 28 個數字）", nrow(spec), H11_SPEC_ROWS),
      "列數不符即停止；不以缺列的表交付（T13 步驟 4）。"
    )
  }
  keys <- as.character(spec$number_key)
  blank <- is.na(keys) | !nzchar(trimws(keys))
  if (any(blank)) {
    f11_refuse(
      "incomplete-spec",
      sprintf("spec 第 %s 列的 number_key 為空", paste(which(blank), collapse = "、")),
      "每個數字都要有名字，否則對照表無法被引用。"
    )
  }
  dup <- unique(keys[duplicated(keys)])
  if (length(dup)) {
    f11_refuse(
      "incomplete-spec",
      sprintf("spec 的 number_key 重複：%s", paste(dup, collapse = ", ")),
      "28 列須覆蓋 28 個不同的 key；重複即表示有兩列指到同一個數字、另有一個數字沒有列。"
    )
  }
  sources <- c("source_table", "source_row")
  for (col in sources) {
    values <- as.character(spec[[col]])
    bad <- is.na(values) | !nzchar(trimws(values))
    if (any(bad)) {
      f11_refuse(
        "incomplete-spec",
        sprintf("spec 第 %s 列的 %s 為空", paste(which(bad), collapse = "、"), col),
        "沒有來源位置的列取不到 population 與 n。"
      )
    }
  }
  invisible(list(rows = nrow(spec), keys = keys))
}

## 6. 分析表的母體與 n -----------------------------------------------------

# 一張表的列鍵：把 H11_ROW_KEY_COLUMNS 指名的欄位以 H11_KEY_SEP 相接。
f11_row_key <- function(name, frame) {
  cols <- H11_ROW_KEY_COLUMNS[[name]]
  if (is.null(cols)) {
    stop("f11_row_key：", name, " 不在 F11 的十張分析表清單內。", call. = FALSE)
  }
  absent <- setdiff(cols, names(frame))
  if (length(absent)) {
    f11_refuse(
      "missing-profile",
      sprintf("表 %s 缺列鍵欄 %s（實有：%s）", name, paste(absent, collapse = "、"), paste(names(frame), collapse = ", ")),
      "列鍵缺欄即無法把 spec 的 source_row 指到一列。"
    )
  }
  parts <- lapply(cols, function(col) {
    value <- as.character(frame[[col]])
    if (anyNA(value)) {
      f11_refuse("missing-profile", sprintf("表 %s 的列鍵欄 %s 有缺值", name, col))
    }
    value
  })
  do.call(paste, c(parts, list(sep = H11_KEY_SEP)))
}

# 一張分析表的逐列 profile：row_key／population／n／n_role。
# 缺 population 或 n（age_tests 為 n_a／n_b）即 refuse:missing-profile；population 須
# 取三個具名值之一、n 須為非負整數（PRD §3 不變量）。n 有多欄時逐欄各出一列，
# 由 f11_map 以「恰一列」的規則發現歧義。
f11_profile_of <- function(name, tbl) {
  cols <- H11_PROFILE_COLUMNS[[name]]
  if (is.null(cols)) {
    f11_refuse(
      "missing-profile",
      sprintf("表 %s 不在 F11 的十張分析表清單內", name),
      "spec 只能指向分析表；非分析表沒有母體與 n 可帶。"
    )
  }
  if (!is.data.frame(tbl)) {
    stop("f11_profile_of：", name, " 須為資料框；實得 ", class(tbl)[1], "。", call. = FALSE)
  }
  if (!nrow(tbl)) {
    f11_refuse("missing-profile", sprintf("表 %s 為 0 列", name), "沒有列就沒有母體與 n 可帶。")
  }
  absent <- setdiff(cols, names(tbl))
  if (length(absent)) {
    f11_refuse(
      "missing-profile",
      sprintf("表 %s 缺 %s（實有：%s）", name, paste(absent, collapse = "、"), paste(names(tbl), collapse = ", ")),
      "每張表須自帶母體與 n（PRD §3 不變量）；缺一即拒絕交付，且 number_map.csv 不落地。"
    )
  }
  population <- as.character(tbl$population)
  if (anyNA(population)) {
    f11_refuse("missing-profile", sprintf("表 %s 的 population 有 %d 個缺值", name, sum(is.na(population))))
  }
  rogue <- setdiff(unique(population), HARNESS_POPULATIONS)
  if (length(rogue)) {
    f11_refuse(
      "missing-profile",
      sprintf("表 %s 的 population 出現未具名值：%s", name, paste(rogue, collapse = ", ")),
      sprintf("只接受 %s（PRD §2 的三個具名母體）。", paste(HARNESS_POPULATIONS, collapse = "／"))
    )
  }
  n_cols <- setdiff(cols, "population")
  row_keys <- f11_row_key(name, tbl)
  rows <- lapply(n_cols, function(n_col) {
    value <- suppressWarnings(as.numeric(as.character(tbl[[n_col]])))
    if (anyNA(value)) {
      f11_refuse("missing-profile", sprintf("表 %s 的 %s 有缺值或無法轉為數值", name, n_col))
    }
    if (any(value < 0) || any(value != round(value))) {
      f11_refuse("missing-profile", sprintf("表 %s 的 %s 不是非負整數", name, n_col))
    }
    data.frame(
      table = rep(name, nrow(tbl)),
      row_key = row_keys,
      population = population,
      n = value,
      n_role = rep(n_col, nrow(tbl)),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

# 十張分析表逐表檢查。tables 為 named list（name → 資料框）；不給時讀已發佈的表
# （經 harness_table()，A-36：一律自 PROJ_ROOT/output/tables）。
f11_published_tables <- function() {
  tables <- lapply(names(H11_PROFILE_COLUMNS), function(name) {
    harness_table(name, required = character())
  })
  names(tables) <- names(H11_PROFILE_COLUMNS)
  tables
}

f11_profiles <- function(tables = NULL) {
  if (is.null(tables)) tables <- f11_published_tables()
  if (!is.list(tables) || is.null(names(tables))) {
    stop("f11_profiles：tables 須為 named list（表名 → 資料框）。", call. = FALSE)
  }
  absent <- setdiff(names(H11_PROFILE_COLUMNS), names(tables))
  if (length(absent)) {
    f11_refuse(
      "missing-profile",
      sprintf("缺分析表 %s", paste(absent, collapse = "、")),
      "交付前每張分析表都要在位；缺表即無從檢查其母體與 n。"
    )
  }
  profiles <- lapply(names(H11_PROFILE_COLUMNS), function(name) f11_profile_of(name, tables[[name]]))
  names(profiles) <- names(H11_PROFILE_COLUMNS)
  profiles
}

## 7. number_map：28 列覆蓋與逐列的 population／n -------------------------

# 逐列解析：spec 的 (source_table, source_row) 必須對到**恰一筆** profile。
# 0 筆 → 來源指錯；多筆 → 該表的 n 有多欄（age_tests 的 n_a／n_b），單一 n 欄無從決定。
f11_resolve_row <- function(profiles, table, row_key, spec_row) {
  prof <- profiles[[table]]
  if (is.null(prof)) {
    f11_refuse(
      "missing-profile",
      sprintf("spec 第 %d 列指向 %s，該表不在十張分析表清單內", spec_row, table),
      "非分析表沒有母體與 n 可帶進對照表的每一列。"
    )
  }
  hit <- prof[prof$row_key == as.character(row_key), , drop = FALSE]
  if (!nrow(hit)) {
    f11_refuse(
      "missing-profile",
      sprintf(
        "spec 第 %d 列的 source_row「%s」在表 %s 找不到（可用的列鍵：%s）",
        spec_row, as.character(row_key), table, paste(head(unique(prof$row_key), 8L), collapse = "、")
      ),
      "對照表的一列必須指到表內一列；指不到即無法帶出 population 與 n。"
    )
  }
  if (nrow(hit) > 1L) {
    f11_refuse(
      "missing-profile",
      sprintf(
        "spec 第 %d 列的來源 %s「%s」對到 %d 個 n（%s）",
        spec_row, table, as.character(row_key), nrow(hit), paste(unique(hit$n_role), collapse = "、")
      ),
      "number_map.csv 只有一個 n 欄；該表的 n 是哪一欄須由 T13 裁決，本模型不自行挑一個。"
    )
  }
  hit[1L, , drop = FALSE]
}

# 產出 number_map 的內容（28 列，欄序即 H11_MAP_COLUMNS）。
# resolve 可注入：給一個 `function(spec_row, tables)` 回該列的表中值；預設 NULL 表示
# 「無從解析」，此時 table_value 與 pass 皆為 NA——**不得**因此記成 TRUE。
f11_map <- function(spec, tables = NULL, resolve = NULL) {
  checked <- f11_spec_check(spec)
  profiles <- f11_profiles(tables)

  keys <- as.character(spec$number_key)
  rows <- lapply(seq_len(nrow(spec)), function(i) {
    table <- as.character(spec$source_table[i])
    row_key <- as.character(spec$source_row[i])
    hit <- f11_resolve_row(profiles, table, row_key, i)
    value <- if (is.null(resolve)) NA_real_ else resolve(spec[i, , drop = FALSE], tables)
    value <- suppressWarnings(as.numeric(value))
    pass <- if (length(value) != 1L || is.na(value)) NA else f11_value_equal(value, spec$value[i])
    data.frame(
      number_key = keys[i],
      spec_value = as.character(spec$value[i]),
      table_value = if (is.na(value)) NA_real_ else value,
      source_table = table,
      source_row = row_key,
      population = hit$population,
      n = hit$n,
      pass = pass,
      stringsAsFactors = FALSE
    )
  })
  map <- do.call(rbind, rows)
  rownames(map) <- NULL

  # 覆蓋：恰 28 列、key 與 spec 一一對應、無多無少（T13 步驟 5）
  if (nrow(map) != checked$rows || !identical(map$number_key, checked$keys)) {
    f11_refuse(
      "incomplete-spec",
      sprintf("number_map 的 %d 列與 spec 的 %d 個 key 不對應", nrow(map), checked$rows)
    )
  }
  map[, H11_MAP_COLUMNS, drop = FALSE]
}

# 交付動作：兩個檢查都過才寫檔。寫入是**最後一步**，故任一拒絕分支下
# number_map.csv 都不落地（不以「先寫再刪」達成，那會在磁碟上留下半成品）。
f11_deliver <- function(spec, tables_dir, tables = NULL, resolve = NULL) {
  if (!is.character(tables_dir) || length(tables_dir) != 1L || !dir.exists(tables_dir)) {
    stop("f11_deliver：tables_dir 須為既有目錄（由 harness_out_root() 的 tables/ 取得）。", call. = FALSE)
  }
  map <- f11_map(spec, tables = tables, resolve = resolve)
  path <- f11_map_path(tables_dir)
  utils::write.csv(map, path, row.names = FALSE, fileEncoding = "UTF-8")
  list(status = "apply", map = map, path = path, rows = nrow(map))
}

# number_map.csv 讀回來（交付後的斷言用）。helper 的 harness_table() 固定讀
# PROJ_ROOT/output/tables（A-36），讀不到暫存根裡的交付產物，故這裡自備讀取；
# 這是**交付產物**的讀回，不是分析樣本——樣本仍只經 harness_table()／harness_data()。
f11_read_map <- function(tables_dir) {
  path <- f11_map_path(tables_dir)
  if (!file.exists(path)) {
    f11_refuse("input-missing", sprintf("缺交付產物 %s（T13 尚未產出，見 pins/11_F11.md 的 B2）", basename(path)))
  }
  tbl <- utils::read.table(path, sep = ",", header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
  absent <- setdiff(H11_MAP_COLUMNS, names(tbl))
  if (length(absent)) {
    f11_refuse(
      "incomplete-spec",
      sprintf("number_map.csv 缺欄名 %s（實有：%s）", paste(absent, collapse = "、"), paste(names(tbl), collapse = ", "))
    )
  }
  tbl
}

## 8. fixture：以已發佈的表造 28 列 spec ----------------------------------

# 固定取列計畫（表、取幾列、值取自哪一欄）。合計恰 28 列：4+5+4+5+6+3+1。
# 每一列都是**真的**已發佈表的列，故 population 與 n 是實測值，不是造出來的字串。
F11_FIXTURE_PLAN <- data.frame(
  table = c(
    "wealth_four_cell", "age_bands", "ability_quartiles",
    "ability_transitions", "model_comparison", "language_groups", "marriage_strata"
  ),
  value_col = c("dropout_rate", "dropout_rate", "graduation_rate", "n", "mcfadden_r2", "n", "n"),
  take = c(4L, 5L, 4L, 5L, 6L, 3L, 1L),
  stringsAsFactors = FALSE
)

# 28 列 spec：key 形如 `<表>.<列鍵>`，value 取 plan 指定的欄、以四位小數寫出
# （模擬報告的寫法，故 f11_value_equal 走「半個末位」那一路）。
f11_fixture_spec <- function(tables) {
  if (!is.list(tables) || is.null(names(tables))) {
    stop("f11_fixture_spec：tables 須為 named list。", call. = FALSE)
  }
  parts <- lapply(seq_len(nrow(F11_FIXTURE_PLAN)), function(i) {
    name <- F11_FIXTURE_PLAN$table[i]
    frame <- tables[[name]]
    if (is.null(frame)) stop("f11_fixture_spec：缺表 ", name, "。", call. = FALSE)
    n_take <- min(F11_FIXTURE_PLAN$take[i], nrow(frame))
    frame <- frame[seq_len(n_take), , drop = FALSE]
    keys <- f11_row_key(name, frame)
    value <- as.numeric(frame[[F11_FIXTURE_PLAN$value_col[i]]])
    data.frame(
      number_key = paste0(name, ".", keys),
      value = sprintf("%.4f", value),
      source_table = name,
      source_row = keys,
      stringsAsFactors = FALSE
    )
  })
  spec <- do.call(rbind, parts)
  rownames(spec) <- NULL
  if (nrow(spec) != H11_SPEC_ROWS) {
    stop("f11_fixture_spec：造出 ", nrow(spec), " 列，契約為 ", H11_SPEC_ROWS, " 列。", call. = FALSE)
  }
  spec
}

# fixture 的解析器：由 plan 的 value_col 取該列表中的值（模擬 T13 的取值步驟）。
f11_fixture_resolver <- function(tables) {
  force(tables)
  function(spec_row, tbls = tables) {
    name <- as.character(spec_row$source_table)
    idx <- match(name, F11_FIXTURE_PLAN$table)
    if (is.na(idx)) return(NA_real_)
    frame <- tbls[[name]]
    hit <- which(f11_row_key(name, frame) == as.character(spec_row$source_row))
    if (length(hit) != 1L) return(NA_real_)
    as.numeric(frame[[F11_FIXTURE_PLAN$value_col[idx]]][hit])
  }
}

## 9. 入口（T13 未就位時由測試檔 skip）------------------------------------

f11_rscript <- function() {
  exe <- file.path(R.home("bin"), "Rscript")
  if (!file.exists(exe)) exe <- unname(Sys.which("Rscript"))
  if (!nzchar(exe)) f11_refuse("input-missing", "找不到 Rscript：無法執行 ", H11_PROGRAM_REL, "。")
  exe
}

# 以子程序跑 run_all.R（不得以 source() 呼叫，A-15／REQ-A-3）。注入只有一個環境
# 變數：RTOOLKIT_OUT_ROOT（寫入位置）。工作目錄借 withr::with_dir() 移回專案根。
f11_run <- function(out_root) {
  if (!is.character(out_root) || length(out_root) != 1L || !dir.exists(out_root)) {
    stop("f11_run：out_root 須為既有輸出根（由 harness_out_root() 取得）。", call. = FALSE)
  }
  program <- f11_program_path()
  if (!file.exists(program)) {
    f11_refuse(
      "input-missing",
      sprintf("缺交付入口 %s", H11_PROGRAM_REL),
      "T13 未建（阻塞於 B2：T12 缺 SAS 對照值）；本流程只能以模型骨架判定。"
    )
  }
  env <- paste0("RTOOLKIT_OUT_ROOT=", shQuote(normalizePath(out_root, winslash = "/", mustWork = TRUE)))
  started <- Sys.time()
  output <- withr::with_dir(
    f11_project_root(),
    suppressWarnings(system2(f11_rscript(), shQuote(program), env = env, stdout = TRUE, stderr = TRUE))
  )
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  list(
    status = as.integer(status),
    output = as.character(output),
    out_root = out_root,
    map = f11_map_path(file.path(out_root, "tables")),
    log = f11_log_path(out_root),
    elapsed = elapsed
  )
}

# 執行記錄的段落解析：每步耗時與套件版本（F11「記錄寫明執行時間與套件版本」）。
f11_log_facts <- function(out_root) {
  path <- f11_log_path(out_root)
  if (!file.exists(path)) {
    f11_refuse("input-missing", sprintf("缺執行記錄 %s", basename(path)))
  }
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  list(
    lines = lines,
    has_version = any(grepl("R version|R 版本", lines)),
    has_elapsed = any(grepl("elapsed|耗時", lines)),
    has_timestamp = any(grepl("[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}", lines))
  )
}
