# harness-07.R — F7（語言文化）的預算、執行上限與入口（V07，verification A）
#
# 交界契約（REQ-A-7、A-25、A-36）：
#   * 樣本、種子、暫存與輸出根一律取自 `helper-harness.R`：本檔只呼叫 harness_data()、
#     harness_seed()、harness_dir()、harness_out_root()、harness_table()、
#     expect_rate_equal()、expect_profile()。
#   * `tests/` 的三類禁令（自行讀表、自設種子、自建暫存）在本檔的命中數為 0：
#     已發佈的表走 harness_table()，退化 fixture 的表走被 source 的腳本留在環境裡的
#     `table_out`（不經 read.csv），記錄走 readLines（REQ-A-7 的掃描樣式不含它）。
#   * 本檔是 F7 的模型：把 T08（seam `programs/R/06_language.R`）的判定表翻成可證偽的
#     純函式，再由 `test-07_F7.R` 對「已發佈的表」、「入口行為」與「拒絕分支」逐一斷言。
#
# 模型（皆為獨立重算，不呼叫 lib/stats.R 與 06_language.R 的函式）：
#   h07_groups(frame)       國籍→語言圈、n_members／n／退學率／威爾遜區間／精確檢定／
#                           檢定力所需的每組人數。母體界線（target ∈ Graduate／Dropout）、
#                           國籍代碼對應（葡語 21/22/24/25/26/41、西語 6/101/108/109）與
#                           小樣本門檻（n < 10）寫死在此，不由被測程式提供。
#   h07_wilson(k, n)        威爾遜分數區間的閉式（level 由本檔釘住，不讀 00_setup.R）。
#   h07_fisher_p(...)       雙尾精確檢定的獨立實作：固定邊際下的超幾何機率和
#                           （p = Σ P(X=x) over P(X=x) ≤ P(X=觀測)），不用 fisher.test()。
#   h07_required(...)       兩獨立比例、雙尾 α、指定 power 的每組人數（未取整）。
#
# 退化 fixture 一律在 `harness_dir()` 的暫存副本上造：清洗資料集形狀的 CSV 由
# harness_data("full") 變異而來，注入則是把 `06_language.R` 複製到暫存目錄、只改
# `CLEAN_PATH` 一行（生產檔不動；注入點命不中即停手，代表 seam 已漂移）。
#
# 樣本、種子與收縮：本流程無隨機來源（h07_budget() 的 seed／shrink 記 n/a）。拒絕分支的
# 候選空間是「某圈 n < 10」與「某圈 n = 0」兩個形狀，各由一個具名突變固定，收縮為枚舉而
# 非隨機最小化，故沒有可記的最短序列，只有枚舉次數。

## 0. 載入即載入測試台 -------------------------------------------------------

# 本檔所在目錄。順序很重要：被 source() 時，堆疊上指向 harness-07.R 的 ofile 才是
# 本檔的位置——process 的 `--file=` 可能是別的腳本（`Rscript tests/testthat.R`、
# `Rscript -e`），先看它會把目錄誤判成 `tests`。
h07_this_dir <- function() {
  frames <- sys.frames()
  for (i in rev(seq_along(frames))) {
    ofile <- frames[[i]]$ofile
    if (!is.null(ofile) && grepl("harness-07[.]R$", ofile)) {
      return(dirname(normalizePath(ofile, winslash = "/", mustWork = FALSE)))
    }
  }
  # 本檔被 Rscript 直接執行時沒有 source() 的 ofile，改由 --file= 定位。
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg) && grepl("harness-07[.]R$", file_arg[[1L]])) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[[1L]]), winslash = "/", mustWork = FALSE)))
  }
  # 兩者皆無（例如在 REPL 內 source 本檔）：自工作目錄與 tests/testthat 找本檔的鄰居。
  for (dir in c(getwd(), file.path(getwd(), "tests", "testthat"))) {
    if (file.exists(file.path(dir, "harness-07.R"))) {
      return(normalizePath(dir, winslash = "/", mustWork = FALSE))
    }
  }
  getwd()
}

# 載入時無條件載入 `helper-harness.R`，放進**本檔被求值的同一個環境**：h07_* 的 closure
# 都在那個環境，故 harness_data()／harness_table() 等一併解析得到（A-43：R 以定義時的
# enclosure 解析自由變數，故 helper 必須與本檔同處，不能只放進 globalenv）。
if (!file.exists(file.path(h07_this_dir(), "helper-harness.R"))) {
  stop("找不到 helper-harness.R（應與 harness-07.R 同目錄）：", h07_this_dir(), call. = FALSE)
}
source(file.path(h07_this_dir(), "helper-harness.R"), local = TRUE)

## 1. 預算與上限 -----------------------------------------------------------

H07_FLOW <- "F7 語言文化"
H07_SAMPLE <- "全量 4,424 列（harness_data(\"full\")；無抽樣）"
H07_SAMPLE_ROWS <- 4424L
# 收縮：本流程無隨機來源，收縮與種子皆記 n/a；上界照契約寫定（V07 Budget）。
H07_SHRINK_MAX_ITER <- 200L
H07_SHRINK_MAX_SEC <- 30
H07_SHRINK_NOTE <- "n/a（無隨機來源；拒絕分支為具名突變的枚舉）"
H07_SEED_NOTE <- "本流程不消耗亂數，種子記 n/a"
# 上限：整個流程 120 秒；單一注入執行再收 60 秒，避免一個掛住的生產腳本拖垮整個測試。
H07_FLOW_LIMIT_SEC <- 120
H07_CHILD_LIMIT_SEC <- 60
H07_RETRIES <- 0L

h07_budget <- function() {
  list(
    rows = nrow(harness_data("full")),
    sample = "全量（無抽樣）",
    seed = "n/a（無隨機來源；harness_seed() 未被呼叫）",
    shrink = "n/a（拒絕分支為具名突變的枚舉，非隨機最小化）",
    flow_seconds = H07_FLOW_LIMIT_SEC,
    retries = H07_RETRIES
  )
}

## 2. 釘值與判定表 ---------------------------------------------------------

# 表名與欄名（T08 的 Owned 面；缺一即無法判讀）
H07_TABLE <- "language_groups"
H07_COLUMNS <- c("population", "group", "n_members", "n", "dropout_rate",
                 "ci_low", "ci_high", "p_vs_local", "required_per_group")

# 固定列序：葡語、西語、其他（重跑逐位元組相同靠的就是這個次序）。本地只作對照、不佔列。
H07_GROUPS <- c("Portuguese", "Spanish", "Other")
H07_POPULATION <- "full"
H07_COMPARISON_GROUP <- "Spanish"

# 三圈人數（T08 步驟 2 的對應表算得；修訂 A-18 逐值寫定）
H07_MEMBERS <- c(74L, 17L, 19L)        # 含在讀
H07_MEMBERS_TOTAL <- 110L              # 非本地國籍人數
H07_N <- c(60L, 11L, 15L)              # 僅畢業與退學（退學率的分母）
H07_N_TOTAL <- 86L
H07_ENROLLED <- c(14L, 6L, 4L)         # 在讀者：計入 n_members、不入 n
H07_DROPOUTS <- c(21L, 6L, 5L)

# 本地對照組（不佔列）：與西語圈比對的那一欄
H07_LOCAL_CODE <- 1L
H07_LOCAL_N <- 3544L
H07_LOCAL_DROPOUTS <- 1389L

# 國籍代碼 → 語言圈（UCI data dictionary 的國名；其餘非本地代碼歸 Other）
H07_PORTUGUESE_CODES <- c(21L, 22L, 24L, 25L, 26L, 41L)
H07_SPANISH_CODES <- c(6L, 101L, 108L, 109L)

# 清洗資料集的欄名（T02 只把結果欄改名為 target）
H07_NATIONALITY_COL <- "Nacionality"
H07_RESULT_COL <- "target"
H07_ANALYSIS_RESULTS <- c("Graduate", "Dropout")
H07_OTHER_RESULT <- "Enrolled"
H07_DROPOUT <- "Dropout"

# 四位有效數字（A-19：表存全精度，四位只在呈現層）
H07_SIG_DIGITS <- 4L
H07_RATES_4SF <- c(0.35, 0.5455, 0.3333)
H07_SPANISH_RATE_4SF <- 0.5455
H07_SPANISH_P_4SF <- 0.3586

# 西語圈的完整精度釘值（用於 1e-9 級的比對，不經格式化）
H07_SPANISH_N <- 11L
H07_SPANISH_DROPOUTS <- 6L
H07_SPANISH_RATE <- 6 / 11
H07_SPANISH_CI <- c(0.280091537409322, 0.787287283775402)
H07_SPANISH_P <- 0.3586433154707366

# 區間：本流程的信賴水準（與 00_setup.R 的 PROP_CI_LEVEL 同值，測試端不 source 生產設定檔）
H07_PROP_CI_LEVEL <- 0.95
H07_CI_REL_TOL <- 1e-3                 # V07 的性質：等於 6/11 的威爾遜區間（相對差 1e-3）

# 檢定力：α = 0.05 雙尾、power = 0.8（T08 步驟 5）。契約只釘 165±10（A-18），
# 全精度值 162 另作錨點；兩條都寫成斷言，免得「差不多」矇過去。
H07_ALPHA <- 0.05
H07_POWER <- 0.8
H07_REQUIRED_PIN <- 162L
H07_REQUIRED_TARGET <- 165L
H07_REQUIRED_BAND <- 10

# 小樣本門檻與拒絕類別（T08 的 Refusal：n < 10 只出計數；n = 0 記錄後不中止）
H07_MIN_GROUP_N <- 10L
H07_REFUSE_CATEGORY <- "refuse:empty-denominator"

# 比對容差：模型與表都以未格式化 double 存值（A-19），故同值時差為 0；
# 1e-12 只吸收浮點運算次序（先除後加與先加後除）。
H07_VALUE_TOL <- 1e-12
# 精確檢定的 p 由超幾何機率和累加而得，與 fisher.test() 的求和次序不同，故放寬到 1e-9。
H07_P_TOL <- 1e-9

## 3. 呈現與比較 -----------------------------------------------------------

# 四位有效數字（與 lib 的 fmt_sig 同形，但本檔不 source 生產檔案）
h07_sig <- function(x, digits = H07_SIG_DIGITS) {
  template <- paste0("%#.", as.integer(digits), "g")
  vapply(as.numeric(x), function(value) {
    if (is.na(value)) NA_character_ else sprintf(template, value)
  }, character(1))
}

h07_sig_equal <- function(actual, expected, digits = H07_SIG_DIGITS) {
  identical(h07_sig(actual, digits), h07_sig(expected, digits))
}

h07_num <- function(x) suppressWarnings(as.numeric(as.character(x)))

h07_note <- function(fmt, ...) sprintf(fmt, ...)

## 4. 模型：區間、精確檢定、檢定力 -----------------------------------------

# 威爾遜分數區間：centre ± half，兩端截在 [0, 1]。與 lib/stats.R 的 prop_ci 同一個算式，
# 但此處獨立寫出（被測對象不得當自己的 oracle）。
h07_wilson <- function(k, n, level = H07_PROP_CI_LEVEL) {
  if (!is.numeric(k) || !is.numeric(n) || length(k) != 1L || length(n) != 1L) {
    stop("h07_wilson：k 與 n 須為長度一的數值。", call. = FALSE)
  }
  if (is.na(k) || is.na(n) || n <= 0 || k < 0 || k > n) {
    return(c(low = NA_real_, high = NA_real_))
  }
  phat <- k / n
  z <- stats::qnorm(1 - (1 - level) / 2)
  denom <- 1 + z^2 / n
  centre <- (phat + z^2 / (2 * n)) / denom
  half <- z / denom * sqrt(phat * (1 - phat) / n + z^2 / (4 * n^2))
  c(low = max(0, centre - half), high = min(1, centre + half))
}

# 華德（常態近似）區間：**不是**本流程的區間，只作為「威爾遜那條斷言不是恆真」的錨。
# 6/11 這一組兩者的四位有效數字不同（0.2512/0.8397 對 0.2801/0.7873）。
h07_wald <- function(k, n, level = H07_PROP_CI_LEVEL) {
  phat <- k / n
  z <- stats::qnorm(1 - (1 - level) / 2)
  c(low = phat - z * sqrt(phat * (1 - phat) / n),
    high = phat + z * sqrt(phat * (1 - phat) / n))
}

# 雙尾精確檢定：固定邊際下 X = a 服從超幾何，p = Σ P(X = x)，取樣條件為
# P(X = x) ≤ P(X = a)（乘 1 + 1e-7，與 R 的 fisher.test 同一個判定式）。
# 任一列或任一欄的邊際和為零即無檢定可言，回 NA（呼叫端據此留空）。
h07_fisher_p <- function(a, b, c, d) {
  cells <- c(a, b, c, d)
  if (!is.numeric(cells) || length(cells) != 4L || anyNA(cells) || any(cells < 0)) {
    stop("h07_fisher_p：四格須為非負且無缺值的四個數值。", call. = FALSE)
  }
  row1 <- a + b
  col1 <- a + c
  total <- a + b + c + d
  if (row1 == 0 || col1 == 0 || row1 == total || col1 == total) return(NA_real_)
  low <- max(0, col1 - (total - row1))
  high <- min(row1, col1)
  support <- low:high
  probs <- stats::dhyper(support, col1, total - col1, row1)
  observed <- stats::dhyper(a, col1, total - col1, row1)
  sum(probs[probs <= observed * (1 + 1e-7)])
}

# 兩獨立比例的每組所需人數（未取整）：(z_{α/2} + z_{power})² (p1(1−p1) + p2(1−p2)) / δ²。
# δ = 0 即無從檢出，回 NA（與被測程式同一個拒絕形狀）。
h07_required <- function(p1, p2, alpha = H07_ALPHA, power = H07_POWER) {
  if (!is.finite(p1) || !is.finite(p2)) return(NA_real_)
  delta <- abs(p1 - p2)
  if (delta == 0) return(NA_real_)
  (stats::qnorm(1 - alpha / 2) + stats::qnorm(power))^2 *
    (p1 * (1 - p1) + p2 * (1 - p2)) / delta^2
}

# 國籍 → 語言圈；本地與缺值皆為 NA（本地只作對照，不入任何一圈）。
h07_circles <- function(frame) {
  absent <- setdiff(c(H07_NATIONALITY_COL, H07_RESULT_COL), names(frame))
  if (length(absent)) {
    stop("refuse:input-schema\n- 資料框缺欄位：", paste(absent, collapse = ", "), call. = FALSE)
  }
  code <- as.integer(frame[[H07_NATIONALITY_COL]])
  circle <- rep(NA_character_, length(code))
  circle[!is.na(code) & code %in% H07_PORTUGUESE_CODES] <- "Portuguese"
  circle[!is.na(code) & code %in% H07_SPANISH_CODES] <- "Spanish"
  circle[!is.na(code) & is.na(circle) & code != H07_LOCAL_CODE] <- "Other"
  circle
}

# 本地對照組的 n 與退學人數（本地不佔列，但西語圈的 p 需要它）
h07_local_counts <- function(frame) {
  code <- as.integer(frame[[H07_NATIONALITY_COL]])
  target <- as.character(frame[[H07_RESULT_COL]])
  local <- !is.na(code) & code == H07_LOCAL_CODE
  comparable <- target %in% H07_ANALYSIS_RESULTS
  list(n = sum(local & comparable), dropout = sum(local & target == H07_DROPOUT))
}

# 模型：整張表的獨立重算。判定表逐條落成分支——
#   n = 0        → 該列只出計數、率與區間留空，狀態 refuse:empty-denominator（不中止）
#   1 ≤ n < 10   → 該列只出計數、率與區間留空，狀態 insufficient_n
#   n ≥ 10       → 率與威爾遜區間
#   p 與檢定力只有對照組（西語圈）在 n > 0 且本地 n > 0 時才有；葡語圈與本地同語，留空。
h07_groups <- function(frame) {
  if (!is.data.frame(frame)) stop("h07_groups：frame 須為資料框。", call. = FALSE)
  target <- as.character(frame[[H07_RESULT_COL]])
  unknown <- setdiff(unique(target), c(H07_ANALYSIS_RESULTS, H07_OTHER_RESULT))
  if (length(unknown)) {
    stop("refuse:input-schema\n- 結果欄出現未登記的類別：", paste(unknown, collapse = ", "), call. = FALSE)
  }
  circle <- h07_circles(frame)
  comparable <- target %in% H07_ANALYSIS_RESULTS
  local <- h07_local_counts(frame)

  rows <- lapply(H07_GROUPS, function(g) {
    member <- !is.na(circle) & circle == g
    n_members <- sum(member)
    n_group <- sum(member & comparable)
    k_dropout <- sum(member & target == H07_DROPOUT)

    rate <- NA_real_
    ci <- c(low = NA_real_, high = NA_real_)
    p_vs_local <- NA_real_
    required <- NA_real_
    status <- "ok"

    if (n_group == 0L) {
      status <- H07_REFUSE_CATEGORY
    } else if (n_group < H07_MIN_GROUP_N) {
      status <- "insufficient_n"
    } else {
      rate <- k_dropout / n_group
      ci <- h07_wilson(k_dropout, n_group)
    }

    if (identical(g, H07_COMPARISON_GROUP) && n_group > 0L && local$n > 0L) {
      p_vs_local <- h07_fisher_p(k_dropout, n_group - k_dropout,
                                 local$dropout, local$n - local$dropout)
      raw_required <- h07_required(rate, local$dropout / local$n)
      if (is.finite(raw_required)) required <- as.integer(ceiling(raw_required))
    }

    data.frame(
      population = H07_POPULATION,
      group = g,
      n_members = as.integer(n_members),
      n = as.integer(n_group),
      dropout_n = as.integer(k_dropout),
      dropout_rate = rate,
      ci_low = unname(ci[["low"]]),
      ci_high = unname(ci[["high"]]),
      p_vs_local = p_vs_local,
      required_per_group = required,
      status = status,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

## 5. 已發佈的表 -----------------------------------------------------------

# 已發佈的表（固定讀 PROJ_ROOT/output/tables，A-36）。欄名缺一即拒絕；列序不是
# 葡語／西語／其他即停止——列序是「重跑逐位元組相同」的一部分，靜默接受就驗不到。
h07_table <- function() {
  tbl <- harness_table(H07_TABLE, required = H07_COLUMNS)
  if (!identical(as.character(tbl$group), H07_GROUPS)) {
    stop(sprintf(
      "表 %s.csv 的列序為 %s，契約為 %s（T08 的固定列序：葡語／西語／其他）。",
      H07_TABLE, paste(as.character(tbl$group), collapse = ", "), paste(H07_GROUPS, collapse = ", ")
    ), call. = FALSE)
  }
  tbl
}

h07_model <- function() h07_groups(harness_data("full"))

## 6. 性質函式（回傳違反清單；空向量＝成立） --------------------------------

# 每個 h07_violations_*() 回一個字元向量，每行都寫「實得 vs 釘值」。回字元而不直接斷言，
# 是為了讓同一支性質能被 mutant 再跑一次，用「mutant 必須非空」證明該性質會判紅。

# 6.1 形狀：三列、population 逐列 full、固定列序。
h07_violations_shape <- function(tbl) {
  out <- character()
  if (!is.data.frame(tbl)) return("語言圈表不是資料框")
  absent <- setdiff(H07_COLUMNS, names(tbl))
  if (length(absent)) {
    return(h07_note("語言圈表缺欄：%s（實有：%s）", paste(absent, collapse = ", "),
                    paste(names(tbl), collapse = ", ")))
  }
  if (nrow(tbl) != length(H07_GROUPS)) {
    out <- c(out, h07_note("表為 %d 列，釘值 %d 列（本地不佔列）", nrow(tbl), length(H07_GROUPS)))
  }
  if (!all(as.character(tbl$population) == H07_POPULATION)) {
    out <- c(out, h07_note("population 欄為 %s，釘值全部 %s",
                           paste(unique(as.character(tbl$population)), collapse = "/"), H07_POPULATION))
  }
  if (!identical(as.character(tbl$group), H07_GROUPS)) {
    out <- c(out, h07_note("列序為 %s，釘值 %s",
                           paste(as.character(tbl$group), collapse = "/"),
                           paste(H07_GROUPS, collapse = "/")))
  }
  out
}

# 6.2 計數：三圈 n_members 74/17/19（合計 110）、n 60/11/15（合計 86）、在讀 14/6/4。
h07_violations_counts <- function(tbl) {
  out <- character()
  if (!is.data.frame(tbl) || !all(c("n_members", "n") %in% names(tbl))) {
    return("語言圈表缺 n_members 或 n 欄")
  }
  members <- h07_num(tbl$n_members)
  n <- h07_num(tbl$n)
  if (length(members) != length(H07_GROUPS) || length(n) != length(H07_GROUPS)) {
    return(h07_note("n_members 長度 %d、n 長度 %d，皆應為 %d",
                    length(members), length(n), length(H07_GROUPS)))
  }
  if (anyNA(members) || anyNA(n) || any(members != round(members)) || any(n != round(n))) {
    return("n_members 或 n 不是整數計數")
  }
  if (!identical(as.integer(members), H07_MEMBERS)) {
    out <- c(out, h07_note("三圈 n_members 為 %s，釘值 %s（葡語／西語／其他）",
                           paste(as.integer(members), collapse = "/"),
                           paste(H07_MEMBERS, collapse = "/")))
  }
  if (sum(members) != H07_MEMBERS_TOTAL) {
    out <- c(out, h07_note("n_members 合計 %d，釘值 %d（非本地國籍人數）",
                           as.integer(sum(members)), H07_MEMBERS_TOTAL))
  }
  if (!identical(as.integer(n), H07_N)) {
    out <- c(out, h07_note("三圈 n 為 %s，釘值 %s（僅畢業與退學）",
                           paste(as.integer(n), collapse = "/"), paste(H07_N, collapse = "/")))
  }
  if (sum(n) != H07_N_TOTAL) {
    out <- c(out, h07_note("可比較人數合計 %d，釘值 %d", as.integer(sum(n)), H07_N_TOTAL))
  }
  if (any(n > members)) {
    out <- c(out, h07_note("n 大於 n_members（%s 對 %s）：在讀者不得入分母",
                           paste(as.integer(n), collapse = "/"), paste(as.integer(members), collapse = "/")))
  }
  enrolled <- as.integer(members - n)
  if (!identical(enrolled, H07_ENROLLED)) {
    out <- c(out, h07_note("在讀人數為 %s，釘值 %s（n_members − n）",
                           paste(enrolled, collapse = "/"), paste(H07_ENROLLED, collapse = "/")))
  }
  out
}

# 6.3 退學率：分母是該圈的可比較人數，不是 n_members。
h07_violations_rate <- function(tbl) {
  out <- character()
  if (!is.data.frame(tbl) || !all(c("n", "dropout_rate") %in% names(tbl))) {
    return("語言圈表缺 n 或 dropout_rate 欄")
  }
  rate <- h07_num(tbl$dropout_rate)
  if (length(rate) != length(H07_GROUPS) || anyNA(rate)) {
    return(h07_note("dropout_rate 應為 %d 個非缺值（實得 %s）",
                    length(H07_GROUPS), paste(h07_sig(rate), collapse = "/")))
  }
  if (any(rate <= 0) || any(rate >= 1)) {
    out <- c(out, h07_note("退學率須在 0 與 1 之間（實得 %s）", paste(h07_sig(rate), collapse = "/")))
  }
  if (!identical(h07_sig(rate), h07_sig(H07_RATES_4SF))) {
    out <- c(out, h07_note("退學率四位有效數字為 %s，釘值 %s",
                           paste(h07_sig(rate), collapse = "/"),
                           paste(h07_sig(H07_RATES_4SF), collapse = "/")))
  }
  if (abs(rate[2] - H07_SPANISH_RATE) > H07_VALUE_TOL) {
    out <- c(out, h07_note("西語圈退學率為 %.15f，釘值 6/11 = %.15f（表存全精度，A-19）",
                           rate[2], H07_SPANISH_RATE))
  }
  # 反面錨：以 n_members 為分母的版本是 6/17 = 0.3529，四位有效數字與 0.5455 不同。
  if (h07_sig_equal(rate[2], H07_SPANISH_DROPOUTS / H07_MEMBERS[2])) {
    out <- c(out, "西語圈退學率等於 6/17（以 n_members 為分母）：分母錯了")
  }
  out
}

# 6.4 西語圈區間：在 [0,1]、含 0.5455、等於以 6/11 計的威爾遜區間（相對差 1e-3）。
h07_violations_interval <- function(tbl, model = NULL) {
  out <- character()
  if (!is.data.frame(tbl) || !all(c("ci_low", "ci_high", "dropout_rate") %in% names(tbl))) {
    return("語言圈表缺 ci_low／ci_high／dropout_rate 欄")
  }
  low <- h07_num(tbl$ci_low)[2]
  high <- h07_num(tbl$ci_high)[2]
  rate <- h07_num(tbl$dropout_rate)[2]
  if (is.na(low) || is.na(high)) return("西語圈區間有缺值")
  if (low < 0 || high > 1) {
    out <- c(out, h07_note("區間 [%.6f, %.6f] 不在 [0,1] 內", low, high))
  }
  if (low >= high) {
    out <- c(out, h07_note("區間下界不小於上界（%.6f ≥ %.6f）", low, high))
  }
  if (!is.na(rate) && (rate < low || rate > high)) {
    out <- c(out, h07_note("區間 [%.6f, %.6f] 不含退學率 %.6f", low, high, rate))
  }
  expected <- if (is.null(model)) h07_wilson(H07_SPANISH_DROPOUTS, H07_SPANISH_N) else
    c(low = model$ci_low[2], high = model$ci_high[2])
  rel <- abs(c(low, high) - expected) / abs(expected)
  if (any(rel > H07_CI_REL_TOL)) {
    out <- c(out, h07_note(
      "區間為 [%.15f, %.15f]，以 6/11 計的威爾遜區間為 [%.15f, %.15f]（最大相對差 %.2e，容差 %.0e）",
      low, high, expected[["low"]], expected[["high"]], max(rel), H07_CI_REL_TOL))
  }
  # 反面錨：華德區間在同一個釘值上不成立，故「等於威爾遜」這條不是任何近似都滿足。
  wald <- h07_wald(H07_SPANISH_DROPOUTS, H07_SPANISH_N)
  if (all(abs(c(low, high) - wald) / abs(wald) <= H07_CI_REL_TOL)) {
    out <- c(out, h07_note("區間等於華德近似 [%.6f, %.6f]：不是威爾遜分數區間", wald[["low"]], wald[["high"]]))
  }
  out
}

# 6.5 對照檢定：西語圈 p = 0.3586（四位），葡語圈與其他留空（同語／不作跨語比較）。
h07_violations_test <- function(tbl, model = NULL) {
  out <- character()
  if (!is.data.frame(tbl) || !"p_vs_local" %in% names(tbl)) return("語言圈表缺 p_vs_local 欄")
  p <- h07_num(tbl$p_vs_local)
  if (length(p) != length(H07_GROUPS)) {
    return(h07_note("p_vs_local 長度 %d，應為 %d", length(p), length(H07_GROUPS)))
  }
  if (is.na(p[2])) return("西語圈的 p_vs_local 為空：對照組沒有檢定")
  if (p[2] <= 0 || p[2] >= 1) {
    out <- c(out, h07_note("西語圈 p 須在 (0,1) 內（實得 %.10f）", p[2]))
  }
  if (!identical(h07_sig(p[2]), h07_sig(H07_SPANISH_P_4SF))) {
    out <- c(out, h07_note("西語圈 p 四位有效數字為 %s，釘值 %s",
                           h07_sig(p[2]), h07_sig(H07_SPANISH_P_4SF)))
  }
  # 由四格獨立重算：[6 5; 1389 2155]（西語圈退學／未退學；本地退學／未退學）
  exact <- h07_fisher_p(H07_SPANISH_DROPOUTS, H07_SPANISH_N - H07_SPANISH_DROPOUTS,
                        H07_LOCAL_DROPOUTS, H07_LOCAL_N - H07_LOCAL_DROPOUTS)
  if (abs(p[2] - exact) / exact > H07_P_TOL) {
    out <- c(out, h07_note("西語圈 p 為 %.17g，四格 [6 5; 1389 2155] 的雙尾精確檢定為 %.17g（相對差 %.2e）",
                           p[2], exact, abs(p[2] - exact) / exact))
  }
  if (!is.null(model) && !identical(is.na(p), is.na(model$p_vs_local))) {
    out <- c(out, h07_note("p_vs_local 的缺值樣式為 %s，模型為 %s",
                           paste(is.na(p), collapse = "/"), paste(is.na(model$p_vs_local), collapse = "/")))
  }
  # 葡語圈與本地同語，不作跨語比較（A-18）：這一欄必須為空，不是「算不出來」。
  if (!is.na(p[1])) {
    out <- c(out, h07_note("葡語圈的 p_vs_local 為 %.10f，契約要求留空（與本地同語，不作跨語比較）", p[1]))
  }
  if (!is.na(p[3])) {
    out <- c(out, h07_note("其他圈的 p_vs_local 為 %.10f，契約要求留空（只對 %s 做檢定）",
                           p[3], H07_COMPARISON_GROUP))
  }
  out
}

# 6.6 檢定力：每組 162 人（契約只要求落在 165±10 內），等於以 α=0.05、power=0.8 重算的向上取整。
h07_violations_power <- function(tbl, model = NULL) {
  out <- character()
  if (!is.data.frame(tbl) || !"required_per_group" %in% names(tbl)) {
    return("語言圈表缺 required_per_group 欄")
  }
  required <- h07_num(tbl$required_per_group)
  if (length(required) != length(H07_GROUPS)) {
    return(h07_note("required_per_group 長度 %d，應為 %d", length(required), length(H07_GROUPS)))
  }
  if (is.na(required[2])) return("西語圈的 required_per_group 為空")
  if (!identical(as.integer(required[2]), as.integer(H07_REQUIRED_PIN))) {
    out <- c(out, h07_note("西語圈 required_per_group 為 %s，釘值 %d",
                           format(required[2], scientific = FALSE), H07_REQUIRED_PIN))
  }
  if (abs(required[2] - H07_REQUIRED_TARGET) > H07_REQUIRED_BAND) {
    out <- c(out, h07_note("required_per_group 為 %s，落在契約的 %d±%d 之外",
                           format(required[2], scientific = FALSE),
                           H07_REQUIRED_TARGET, H07_REQUIRED_BAND))
  }
  raw <- h07_required(H07_SPANISH_RATE, H07_LOCAL_DROPOUTS / H07_LOCAL_N, H07_ALPHA, H07_POWER)
  if (!identical(as.integer(required[2]), as.integer(ceiling(raw)))) {
    out <- c(out, h07_note("required_per_group 為 %s，α=%s 雙尾、power=%s 重算得 %.6f→%d",
                           format(required[2], scientific = FALSE),
                           format(H07_ALPHA), format(H07_POWER), raw, ceiling(raw)))
  }
  if (!is.na(required[1]) || !is.na(required[3])) {
    out <- c(out, h07_note("葡語圈／其他圈的 required_per_group 為 %s／%s，契約要求留空（只為對照組算檢定力）",
                           format(required[1]), format(required[3])))
  }
  if (!is.null(model) && !identical(is.na(required), is.na(model$required_per_group))) {
    out <- c(out, h07_note("required_per_group 的缺值樣式為 %s，模型為 %s",
                           paste(is.na(required), collapse = "/"),
                           paste(is.na(model$required_per_group), collapse = "/")))
  }
  out
}

# 6.7 模型與表逐欄同值（全精度）：計數、率、區間、p、檢定力，含缺值樣式。
h07_violations_model <- function(tbl, model = h07_model()) {
  out <- character()
  if (!is.data.frame(tbl) || !is.data.frame(model)) return("表或模型不是資料框")
  pairs <- list(
    n_members = c(H07_VALUE_TOL, "n_members"),
    n = c(H07_VALUE_TOL, "n"),
    dropout_rate = c(H07_VALUE_TOL, "dropout_rate"),
    ci_low = c(1e-9, "ci_low"),
    ci_high = c(1e-9, "ci_high"),
    p_vs_local = c(H07_P_TOL, "p_vs_local"),
    required_per_group = c(H07_VALUE_TOL, "required_per_group")
  )
  for (col in names(pairs)) {
    if (!col %in% names(tbl)) {
      out <- c(out, h07_note("表缺 %s 欄，無法與模型比對", col))
      next
    }
    actual <- h07_num(tbl[[col]])
    expected <- h07_num(model[[col]])
    tol <- as.numeric(pairs[[col]][1])
    if (!identical(is.na(actual), is.na(expected))) {
      out <- c(out, h07_note("%s 的缺值樣式為 %s，模型為 %s",
                             col, paste(is.na(actual), collapse = "/"), paste(is.na(expected), collapse = "/")))
      next
    }
    comparable <- !is.na(expected)
    if (!any(comparable)) next
    diff <- abs(actual[comparable] - expected[comparable])
    scale <- pmax(abs(expected[comparable]), .Machine$double.eps)
    worst <- max(diff / scale)
    if (worst > tol) {
      out <- c(out, h07_note("%s 與模型最大相對差 %.2e（容差 %.0e）：表 %s，模型 %s",
                             col, worst, tol,
                             paste(signif(actual, 6), collapse = "/"),
                             paste(signif(expected, 6), collapse = "/")))
    }
  }
  out
}

## 7. mutant（負向控制：被改壞的表必須被判紅） ------------------------------

# 每個 mutant 只動一格，對應的性質函式必須非空、其餘應為空（隔離）。
h07_mutant <- function(tbl, what = c("group_order", "rate_over_members", "interval_wald",
                                    "portuguese_p", "required_outside_band")) {
  what <- match.arg(what)
  out <- tbl
  switch(
    what,
    group_order = out <- out[c(3L, 1L, 2L), , drop = FALSE],
    rate_over_members = out$dropout_rate[2] <- H07_SPANISH_DROPOUTS / H07_MEMBERS[2],
    interval_wald = {
      wald <- h07_wald(H07_SPANISH_DROPOUTS, H07_SPANISH_N)
      out$ci_low[2] <- wald[["low"]]
      out$ci_high[2] <- wald[["high"]]
    },
    portuguese_p = out$p_vs_local[1] <- 0.3586433154707366,
    required_outside_band = out$required_per_group[2] <- as.integer(H07_REQUIRED_TARGET + H07_REQUIRED_BAND + 1L)
  )
  rownames(out) <- NULL
  out
}

## 8. 路徑、執行與退化 fixture ----------------------------------------------

h07_project_root <- function() {
  if (exists(".harness_project_root", mode = "function")) {
    return(.harness_project_root())
  }
  root <- tryCatch(here::here(), error = function(e) NA_character_)
  if (is.na(root) || !file.exists(file.path(root, "AMS2640.Rproj"))) {
    stop("refuse:input-missing\n- here() 未解析到含 AMS2640.Rproj 的專案根。", call. = FALSE)
  }
  normalizePath(root, winslash = "/", mustWork = TRUE)
}

# F7 的 seam（相對專案根）。只用來指名入口程式與造暫存副本，不用來讀表（A-36）。
h07_program <- function() {
  file.path(h07_project_root(), "programs", "R", "06_language.R")
}

h07_table_path <- function(out_root) file.path(out_root, "tables", paste0(H07_TABLE, ".csv"))

h07_log_path <- function(out_root) file.path(out_root, "logs", "06_language.log")

# 在**本行程**內 source 一支腳本（生產檔或它的暫存副本）：輸出根取呼叫者給的暫存根，
# 工作目錄借 withr::with_dir() 移回專案根（06_language.R 以相對路徑 source
# programs/R/00_setup.R），離開即還原。時間上限由 setTimeLimit 收緊；重試 0 次。
# 回傳：outcome（"ok"／"refuse"／"error"）、message、output（cat 的進度行）、
#       elapsed、tables（本次寫出的表，表內容另由 env$table_out 取得）、table／log 路徑。
h07_run <- function(script = h07_program(), out_root = NULL, timeout_sec = H07_CHILD_LIMIT_SEC) {
  if (!is.character(script) || length(script) != 1L || !file.exists(script)) {
    stop("h07_run：找不到腳本 ", paste(script, collapse = ", "), call. = FALSE)
  }
  if (is.null(out_root)) out_root <- harness_out_root()
  prior_root <- Sys.getenv("RTOOLKIT_OUT_ROOT", unset = "")
  Sys.setenv(RTOOLKIT_OUT_ROOT = out_root)
  on.exit({
    if (nzchar(prior_root)) {
      Sys.setenv(RTOOLKIT_OUT_ROOT = prior_root)
    } else {
      Sys.unsetenv("RTOOLKIT_OUT_ROOT")
    }
  }, add = TRUE)

  env <- new.env(parent = globalenv())
  setTimeLimit(elapsed = timeout_sec, transient = TRUE)
  on.exit(setTimeLimit(elapsed = Inf, transient = TRUE), add = TRUE)

  started <- Sys.time()
  output <- utils::capture.output(
    outcome <- tryCatch(
      withr::with_dir(h07_project_root(), source(script, local = env)),
      error = function(e) e
    )
  )
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  message_text <- if (inherits(outcome, "error")) conditionMessage(outcome) else ""
  list(
    outcome = if (!nzchar(message_text)) "ok" else if (grepl(H07_REFUSE_CATEGORY, message_text, fixed = TRUE)) "refuse" else "error",
    message = message_text,
    output = output,
    env = env,
    elapsed = elapsed,
    retries = H07_RETRIES,
    out_root = out_root,
    table = h07_table_path(out_root),
    log = h07_log_path(out_root)
  )
}

# 腳本留在它自己環境裡的表；來源是 source() 的副作用，不經讀檔。
h07_script_table <- function(run) {
  if (!"table_out" %in% ls(run$env)) {
    stop("被測腳本未在環境裡留下 table_out：", run$message, call. = FALSE)
  }
  tbl <- run$env$table_out
  if (!is.data.frame(tbl)) stop("被測腳本的 table_out 不是資料框。", call. = FALSE)
  rownames(tbl) <- NULL
  tbl
}

# 記錄：入口寫在輸出根下的 06_language.log（不是已發佈的表，故不經 harness_table）。
h07_log_lines <- function(run) {
  path <- run$log
  if (!file.exists(path)) {
    stop("refuse:input-missing\n- 缺記錄 ", path, "：拒絕分支也應留下記錄。", call. = FALSE)
  }
  readLines(path, warn = FALSE, encoding = "UTF-8")
}

# 清洗資料集形狀的 fixture：資料來自 harness_data("full")，寫到 harness_dir()。
# mutate 收到 4,424 列，回傳變異後的資料框；欄名與列數不動（母體界線與釘值檢查照舊）。
h07_clean_fixture <- function(frame, mutate, path) {
  mutated <- mutate(frame)
  if (!is.data.frame(mutated)) stop("h07_clean_fixture：mutate 必須回傳資料框。", call. = FALSE)
  if (!identical(names(mutated), names(frame))) {
    stop("h07_clean_fixture：mutate 不得改動欄名（fixture 需保持清洗資料集的形狀）。", call. = FALSE)
  }
  if (nrow(mutated) != nrow(frame)) {
    stop(sprintf("h07_clean_fixture：變異後 %d 列，應保持 %d 列。", nrow(mutated), nrow(frame)), call. = FALSE)
  }
  readr::write_csv(mutated, path)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

# 突變①：把西語圈前 4 位「畢業」改成在讀 → 該圈 n = 7（1 ≤ n < 10），n_members 仍 17。
h07_fixture_small_group <- function(frame) {
  idx <- which(h07_circles(frame) == H07_COMPARISON_GROUP &
                 as.character(frame[[H07_RESULT_COL]]) == "Graduate")
  if (length(idx) < 4L) {
    stop("h07_fixture_small_group：西語圈的畢業人數少於 4（實得 ", length(idx), "），無法造 n = 7。", call. = FALSE)
  }
  frame[[H07_RESULT_COL]][idx[seq_len(4L)]] <- H07_OTHER_RESULT
  frame
}

# 突變②：把西語圈全部可比較者改成在讀 → 該圈 n = 0（refuse:empty-denominator，不中止）。
h07_fixture_empty_group <- function(frame) {
  idx <- which(h07_circles(frame) == H07_COMPARISON_GROUP &
                 as.character(frame[[H07_RESULT_COL]]) %in% H07_ANALYSIS_RESULTS)
  if (!length(idx)) stop("h07_fixture_empty_group：西語圈沒有可比較者。", call. = FALSE)
  frame[[H07_RESULT_COL]][idx] <- H07_OTHER_RESULT
  frame
}

# 注入：把 06_language.R 複製到暫存目錄，只改 CLEAN_PATH 這一行。生產檔不動；
# 宣告必須恰好命中一行，否則停手並指名注入點——那時代表 seam 已漂移，該紅而不該靜默跳過。
h07_injected_script <- function(dir, clean_path) {
  source_path <- h07_program()
  if (!file.exists(source_path)) {
    stop("找不到 programs/R/06_language.R：F7 的 seam 不在預期位置。", call. = FALSE)
  }
  lines <- readLines(source_path, warn = FALSE)
  seam <- grep("^CLEAN_PATH <- ", lines)
  if (length(seam) != 1L) {
    stop(sprintf("programs/R/06_language.R 的 CLEAN_PATH 宣告有 %d 處（預期 1 處）：注入點已漂移，請回報主代理。",
                 length(seam)), call. = FALSE)
  }
  lines[seam] <- sprintf('CLEAN_PATH <- normalizePath("%s", winslash = "/", mustWork = FALSE)',
                         clean_path)
  path <- file.path(dir, "06_language_injected.R")
  writeLines(lines, path, useBytes = TRUE)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

# 表指紋：sha256。專案沒有 digest／openssl，故走外部 shasum／sha256sum；
# 兩者皆缺即以 refuse:input-missing 停止——算不出指紋就說「表沒被動」是把檢查變成恆真。
h07_sha256 <- function(path) {
  if (!file.exists(path)) {
    stop("refuse:input-missing\n- 缺檔 ", path, "：無法計算指紋。", call. = FALSE)
  }
  found <- Sys.which(c("shasum", "sha256sum"))
  found <- found[nzchar(found)]
  if (!length(found)) {
    stop("refuse:input-missing\n- 找不到 shasum／sha256sum：無法計算指紋。", call. = FALSE)
  }
  tool <- found[[1L]]
  args <- if (grepl("sha256sum$", tool)) shQuote(path) else c("-a", "256", shQuote(path))
  out <- suppressWarnings(system2(tool, args, stdout = TRUE, stderr = TRUE))
  hex <- if (length(out)) sub("[[:space:]].*$", "", out[[1L]]) else ""
  if (!grepl("^[0-9a-f]{64}$", hex)) {
    stop("refuse:input-missing\n- ", basename(tool), " 未回可解析的 sha256（", paste(out, collapse = " "), "）。", call. = FALSE)
  }
  hex
}

# 已發佈表的指紋（路徑由測試台解析，本檔不自組，A-36）
h07_published_hash <- function() h07_sha256(.harness_table_path(H07_TABLE))

## 9. 執行入口 -------------------------------------------------------------

h07_script_mode <- function() {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  length(file_arg) == 1L && identical(basename(sub("^--file=", "", file_arg[[1L]])), "harness-07.R")
}

# 入口：印預算 → 跑本流程的測試檔 → 檢查總耗時不超過 120 秒。
h07_entry <- function(reporter = "summary") {
  dir <- h07_this_dir()
  seed <- harness_seed()
  cat(sprintf(
    "harness-07: flow=%s\n  sample=%s\n  seed=%d（%s）\n  shrink=%s（上界 %d 次／%d 秒）\n  limit=%d 秒；retries=%d\n",
    H07_FLOW, H07_SAMPLE, seed, H07_SEED_NOTE, H07_SHRINK_NOTE,
    H07_SHRINK_MAX_ITER, H07_SHRINK_MAX_SEC, H07_FLOW_LIMIT_SEC, H07_RETRIES
  ))
  started <- Sys.time()
  results <- testthat::test_file(file.path(dir, "test-07_F7.R"), reporter = reporter)
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  assertions <- sum(vapply(results, function(r) length(r$results), integer(1)))
  cat(sprintf("harness-07: %s 秒（上限 %d 秒）；斷言 %d 條\n",
              sprintf("%.2f", elapsed), H07_FLOW_LIMIT_SEC, assertions))
  if (elapsed > H07_FLOW_LIMIT_SEC) {
    stop(sprintf("F7 測試超過單流程上限：%.2f 秒 > %d 秒", elapsed, H07_FLOW_LIMIT_SEC), call. = FALSE)
  }
  # 有紅即以非零結束：入口被 CI 或主代理直接呼叫時，不能讓 exit 0 冒充全綠。
  frame <- as.data.frame(results)
  red <- if (nrow(frame)) sum(frame$failed) + sum(as.integer(frame$error)) else 0L
  if (red > 0L) {
    cat(sprintf("harness-07: %d 條斷言判紅\n", red))
    if (h07_script_mode()) quit(save = "no", status = 1L) else stop("F7 有斷言判紅", call. = FALSE)
  }
  invisible(results)
}

# 自動入口：僅在「以 Rscript 直接執行本檔」且不是由本檔自己的入口再入時觸發。
# 入口會 source 測試檔，測試檔又會 source 本檔——沒有這個守衛就會遞迴。
if (h07_script_mode() && !isTRUE(getOption("harness07.entry.running"))) {
  options(harness07.entry.running = TRUE)
  on.exit(options(harness07.entry.running = NULL), add = TRUE)
  h07_entry()
}
