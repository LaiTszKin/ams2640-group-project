# test-08_F8.R — F8 宏觀三欄 的性質與斷言（V08，涵蓋 T09 的 seam 07_macro.R）
#
# 判定表（抄自 T09 ＋ 修訂 A-17／A-19，逐條對應下面每個 test_that）：
#
# | 輸入                          | 前置                | 結果                                       | 拒絕類別               | 後置                        |
# | 清洗資料集（分析母體 3,630）  | 三欄無缺值          | 30 列、逐 (variable, year) 計數、role=control | —                    | 表自帶 population 與 n      |
# | 某欄不同值多於人數的十分之一  | 母體仍 3,630        | 停止，寫明欄名、實測值與上限                | refuse:input-schema    | 既有表未被覆寫（sha256 同） |
#
# 性質（每條可證偽；括號為對應的 test_that）：
#   P1 表長 30 列；每欄 10 列；不同值數 10／9／10（表、資料、模型三方一致）；
#      population 全為 analysis；列鍵 (variable, year) 唯一且走完 3 × 10 的網格
#   P2 每欄 n 合計 = 分析母體 3,630（與清冊的 analysis 列同值）；逐年度 n 為
#      452／424／435／356／328／316／326／355／347／291；同一 value 多列的 n 合計 =
#      該值在分析母體的人數（Inflation rate 的 1.4 兩列相加為 726）
#   P3 year 每列非 NA 且落在 2008–2017；year_inferred 全為 TRUE 時 07_macro.log
#      含十個三元組；表內「年份 ↔ 值 ↔ 人數」三者綁定（互換兩列 year 必須轉紅）
#   P4 role 全為 control（三欄只作控制變數）
#   P5 負向控制：互換兩列 year → 違反清單指名「年份與值的對應錯位」與「年份與人數的
#      綁定錯位」；撤掉該綁定後同一份 mutant 不再被判紅（證明這條斷言不是恆真）
#   P6 某欄不同值多於人數的十分之一 → refuse:input-schema、訊息寫明欄名與上限 363、
#      既有表的 sha256 不變、乾淨的輸出根下不寫任何表
#
# 樣本、暫存與輸出根一律取自 helper-harness.R；退化 fixture 只在 harness_dir() 的
# 暫存專案根與 harness_out_root() 的暫存根上造，專案的 output/、programs/、data/ 不經手。

# harness-08.R 不在 testthat 的自動載入清單，先自行定位再載入（與 test-05 同一個
# 定位法：`--file=` 先看，其次工作目錄，最後 tests/testthat）。harness-08.R 在載入時
# 會把 helper-harness.R 源進它自己的求值環境，故 h08_* 的 closure 在三個入口下都解析
# 得到 harness_data()／harness_table()（A-43）。
local({
  candidates <- c(
    if (length(grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))) {
      dirname(normalizePath(
        sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]),
        winslash = "/", mustWork = FALSE
      ))
    },
    getwd(),
    file.path(getwd(), "tests", "testthat")
  )
  for (dir in candidates) {
    path <- file.path(dir, "harness-08.R")
    if (file.exists(path)) {
      source(path)
      return(invisible(NULL))
    }
  }
  stop("找不到 harness-08.R：請在專案根目錄或 tests/testthat 下執行。", call. = FALSE)
})

# 性質成立 ⇔ 違反清單為空；違反清單的內容即紅燈時要讀的訊息。
expect_holds <- function(violations, label) {
  testthat::expect_equal(
    violations, character(0),
    label = sprintf(
      "%s（違反：%s）", label,
      if (length(violations)) paste(violations, collapse = "；") else "無"
    ),
    expected.label = "無違反"
  )
}

# 模型的輸入：分析母體全列（無抽樣）與完整清洗資料集（退化 fixture 的母體須保持
# 3,630，故變異後仍須以 00_setup.R 的釘值通過）
analysis_frame <- harness_data("analysis")
clean_frame <- harness_data("full")
published <- f8_table()
model <- f8_model(analysis_frame)

flow_started <- Sys.time()

test_that("P1 表長 30 列、每欄 10 列、不同值 10／9／10、population 全為 analysis", {
  expect_profile(published)

  expect_equal(nrow(published), F8_EXPECTED_ROWS, label = "表長 30 列（三欄 × 十個年度）")
  expect_equal(
    as.character(published$population), rep(F8_POPULATION_LABEL, F8_EXPECTED_ROWS),
    label = "population 逐列填 analysis"
  )

  per_var <- table(factor(as.character(published$variable), levels = F8_MACRO_VARS))
  expect_equal(as.integer(per_var), rep(length(F8_YEARS), length(F8_MACRO_VARS)),
               label = "每欄 10 列（每年一列）")

  # 列鍵 (variable, year)：唯一且走完 3 × 10
  keys <- paste(as.character(published$variable), as.integer(published$year))
  expect_equal(length(unique(keys)), F8_EXPECTED_ROWS, label = "列鍵 (variable, year) 唯一")
  expect_setequal(keys, paste(rep(F8_MACRO_VARS, each = length(F8_YEARS)), rep(F8_YEARS, times = length(F8_MACRO_VARS))))

  # 不同值數：表、資料、模型三方
  distinct_published <- vapply(F8_MACRO_VARS, function(v) {
    length(unique(round(as.numeric(published$value)[as.character(published$variable) == v], 6)))
  }, integer(1))
  expect_equal(as.integer(distinct_published), F8_DISTINCT_PIN,
               label = sprintf("表的不同值數為 10／9／10（實得：%s）", paste(distinct_published, collapse = "／")))
  expect_equal(as.integer(f8_distinct(analysis_frame)), F8_DISTINCT_PIN,
               label = "分析母體的不同值數為 10／9／10")
  expect_equal(as.integer(distinct_published), as.integer(f8_distinct(analysis_frame)),
               label = "表與資料的不同值數逐欄相同")

  # 整份表一次過全部性質（違反清單為空），並與模型重建的 30 列同形
  expect_holds(f8_violations(published, analysis_frame), "已發佈的表通過全部性質")
  expect_equal(nrow(model), F8_EXPECTED_ROWS, label = "模型重建 30 列")
})

test_that("P2 每欄 n 合計 3,630；逐年度 n 錨值；同一 value 的 n 合計 = 該值人數（1.4 → 726）", {
  n <- as.numeric(published$n)
  variable <- as.character(published$variable)

  for (v in F8_MACRO_VARS) {
    expect_equal(sum(n[variable == v]), as.numeric(F8_ANALYSIS_N),
                 label = sprintf("%s 的 n 合計 = 分析母體 3,630", v))
  }
  expect_equal(sum(n), as.numeric(F8_ANALYSIS_N) * length(F8_MACRO_VARS),
               label = "全表 n 合計 = 3 × 3,630 = 10,890")
  expect_equal(f8_ledger_n("analysis"), as.numeric(F8_ANALYSIS_N), label = "清冊的 analysis n 亦為 3,630")

  # 逐年度的人口數（三個年度區塊各 10 個，三欄同一年的人數必須相同）
  for (i in seq_along(F8_YEARS)) {
    got <- n[as.integer(published$year) == F8_YEARS[i]]
    expect_equal(got, rep(as.numeric(F8_BLOCK_N[i]), length(F8_MACRO_VARS)),
                 label = sprintf("%d 年的三列 n 皆為 %d", F8_YEARS[i], F8_BLOCK_N[i]))
  }
  expect_equal(as.integer(f8_blocks(analysis_frame)$n), F8_BLOCK_N,
               label = "模型由分析母體數出的十個年度人數 = 錨值（合計 3,630）")

  # 同一 value 多列的 n 合計：Inflation rate 的 1.4 在 2010 與 2017
  cross <- published[variable == F8_CROSS_VAR & abs(as.numeric(published$value) - F8_CROSS_VALUE) <= F8_VALUE_TOL, ]
  expect_equal(nrow(cross), 2L, label = "Inflation rate 的 1.4 有兩列（跨兩個年度）")
  expect_equal(as.integer(cross$year), F8_CROSS_YEARS, label = "1.4 的兩列為 2010 與 2017")
  expect_equal(as.numeric(cross$n), as.numeric(F8_CROSS_N), label = "兩列的 n 為 435 與 291")
  expect_equal(sum(as.numeric(cross$n)), as.numeric(F8_CROSS_SUM), label = "同一 value 的 n 合計為 726")

  # 逐值：表內每個值的 n 合計 = 該值在分析母體的人數（不只 1.4 這一例）
  counts <- f8_value_counts(analysis_frame)
  agg <- stats::aggregate(
    list(n = n), by = list(variable = variable, value = round(as.numeric(published$value), 6)),
    FUN = sum
  )
  expect_equal(nrow(agg), nrow(counts), label = "表的值個數與資料的值個數相同")
  matched <- counts[match(paste(agg$variable, agg$value), paste(counts$variable, round(counts$value, 6))), ]
  expect_equal(as.numeric(agg$n), as.numeric(matched$count), label = "逐值的 n 合計 = 該值在分析母體的人數")

  # 模型（獨立重算）與表的逐列 n 必須同值
  order_model <- model[match(paste(variable, as.integer(published$year)), model$key), ]
  expect_equal(as.numeric(published$n), as.numeric(order_model$n), label = "模型 n 與表的 n 逐列相同")
})

test_that("P3 year 非 NA 且在 2008–2017；記錄含十個三元組；年份與值／人數綁定", {
  year <- as.integer(published$year)
  expect_false(anyNA(year), label = "year 每列非 NA")
  expect_equal(sort(unique(year)), F8_YEARS, label = "十個年度齊備且落在 2008–2017")
  expect_true(all(as.logical(published$year_inferred)), label = "year_inferred 全為 TRUE（推定而非資料欄位）")
  expect_equal(length(unique(F8_TRIPLETS$key)), length(F8_YEARS),
               label = "十個三元組互異（年度對應可唯一反推）")

  # 記錄：一次乾淨的執行留在暫存根上的最後一段
  out_root <- harness_out_root()
  withr::defer(unlink(out_root, recursive = TRUE, force = TRUE))
  run <- f8_run(out_root)
  expect_equal(run$status, 0L, label = "happy path 的結束碼為 0")
  expect_true(file.exists(run$log), label = "執行留下 07_macro.log")
  expect_identical(f8_log_status(run$log), "ok", label = "記錄的 status 為 ok")

  triplets <- f8_log_triplets(run$log)
  expect_equal(nrow(triplets), length(F8_YEARS), label = "記錄含十個三元組")
  expect_equal(triplets$year, F8_YEARS, label = "三元組的年度依 2008–2017 排列")
  expect_equal(triplets$unemployment, F8_TRIPLETS$unemployment, tolerance = F8_VALUE_TOL,
               label = "記錄的 unemployment 值")
  expect_equal(triplets$inflation, F8_TRIPLETS$inflation, tolerance = F8_VALUE_TOL,
               label = "記錄的 inflation 值")
  expect_equal(triplets$gdp, F8_TRIPLETS$gdp, tolerance = F8_VALUE_TOL, label = "記錄的 gdp 值")
  expect_equal(triplets$n, F8_BLOCK_N, label = "記錄的十個 n = 表的年度人數")

  # 記錄的 n 與表同年度的人數一致（表與記錄不得各說一套）
  for (i in seq_along(F8_YEARS)) {
    expect_equal(
      as.numeric(published$n[as.integer(published$year) == F8_YEARS[i]]),
      rep(as.numeric(triplets$n[i]), length(F8_MACRO_VARS)),
      label = sprintf("%d 年：表的三列 n 皆等於記錄的 %d", F8_YEARS[i], triplets$n[i])
    )
  }

  # 表內的綁定：每個 (variable, year) 的值即該年度三元組的那一欄
  for (v in F8_MACRO_VARS) {
    column <- F8_TRIPLET_COLS[match(v, F8_MACRO_VARS)]
    rows <- as.character(published$variable) == v
    expect_equal(
      as.numeric(published$value[rows]),
      as.numeric(F8_TRIPLETS[[column]][match(as.integer(published$year[rows]), F8_TRIPLETS$year)]),
      tolerance = F8_VALUE_TOL,
      label = sprintf("%s 的值與年份逐列對應", v)
    )
  }
})

test_that("P4 role 全為 control（三欄只作控制變數，不承擔主效應）", {
  role <- as.character(published$role)
  expect_equal(role, rep(F8_ROLE_LABEL, F8_EXPECTED_ROWS), label = "role 逐列填 control")
  expect_equal(length(unique(role)), 1L, label = "role 只有一個值")
  expect_false(any(grepl("outcome|exposure|predictor", role, ignore.case = TRUE)),
               label = "role 不含主效應／解釋變數的標記")
  expect_holds(f8_violations(published, analysis_frame), "role 與其餘性質同時成立")
})

test_that("P5 負向控制：互換兩列的 year 必須轉紅，且紅的是年份綁定那一條", {
  # 2008 ↔ 2009 的兩列（Unemployment rate 7.6 與 9.4）。這一步不動任何骨架：
  # 網格仍完整、每欄 n 合計仍 3,630、不同值數仍 10／9／10。
  swapped <- f8_swap_years(published, 1L, 2L)
  expect_equal(sort(as.integer(swapped$year)), sort(as.integer(published$year)), label = "年份集合不變")
  expect_equal(sum(as.numeric(swapped$n)), sum(as.numeric(published$n)), label = "n 合計不變")

  violations <- f8_violations(swapped, analysis_frame)
  expect_gt(length(violations), 0L, label = "互換年份後違反清單非空")
  expect_true(any(grepl("年份與人數的綁定錯位", violations, fixed = TRUE)),
              label = sprintf("違反指名「年份與人數的綁定錯位」（實得：%s）", paste(violations, collapse = "；")))
  expect_true(any(grepl("年份與值的對應錯位", violations, fixed = TRUE)),
              label = "違反指名「年份與值的對應錯位」")

  # 這條斷言不是恆真：撤掉年份綁定（bind_year = FALSE）後，同一份 mutant 不再被判紅。
  # 也就是說 P3 的紅燈確實來自綁定本身，不是其他檢查的副作用。
  expect_holds(f8_violations(swapped, analysis_frame, bind_year = FALSE),
               "撤掉年份綁定後同一份 mutant 不再有違反（證明綁定是唯一的紅燈來源）")

  # 跨欄互換（Unemployment 2008 ↔ Inflation 2009）會使同一欄的年份重複，同樣必須紅
  cross_swap <- f8_swap_years(published, 1L, which(as.character(published$variable) == "Inflation rate")[2L])
  cross_violations <- f8_violations(cross_swap, analysis_frame)
  expect_gt(length(cross_violations), 0L, label = "跨欄互換年份後違反清單非空")
  expect_true(any(grepl("year 有重複", cross_violations, fixed = TRUE)),
              label = "跨欄互換使某欄的年份重複")
})

test_that("P6 某欄不同值多於人數的十分之一 → refuse:input-schema，表不被覆寫", {
  prior_root <- Sys.getenv("RTOOLKIT_OUT_ROOT", unset = "")
  out_root <- harness_out_root()
  withr::defer({
    if (nzchar(prior_root)) Sys.setenv(RTOOLKIT_OUT_ROOT = prior_root) else Sys.unsetenv("RTOOLKIT_OUT_ROOT")
    unlink(out_root, recursive = TRUE, force = TRUE)
  })

  # (0) happy path：同一份母體在乾淨的暫存根上先寫出一張表，作為「不被覆寫」的基準
  happy <- f8_run(out_root)
  expect_equal(happy$status, 0L, label = "happy path 的結束碼為 0")
  expect_true(file.exists(happy$table), label = "happy path 寫出 macro_values.csv")
  expect_lt(happy$elapsed, H08_CHILD_LIMIT_SEC, label = "單次子行程在 60 秒上限內")
  sha_before <- f8_sha256(happy$table)
  expect_true(grepl("^[0-9a-f]{64}$", sha_before), label = "指紋為 64 位十六進位")

  # (1) 變異：GDP 換成逐列唯一值 → 分析母體的不同值數 3,630 > 上限 363
  mutated <- clean_frame
  mutated[["GDP"]] <- mutated[["GDP"]] + seq_len(nrow(mutated)) / 1e5
  mutated_analysis <- f8_analysis_frame(mutated)
  expect_gt(length(unique(mutated_analysis[["GDP"]])), F8_DISTINCT_LIMIT,
            label = "變異後 GDP 的不同值數超過人數的十分之一（實測對上限 363）")
  expect_equal(nrow(mutated_analysis), as.numeric(F8_ANALYSIS_N),
               label = "變異不動母體（仍 3,630，故落到值域分支而不是母體分支）")

  refused <- f8_run(out_root, frame = mutated)
  expect_gt(refused$status, 0L, label = "值域超限使程式以非零結束碼停止")
  expect_true(any(grepl("refuse:input-schema", refused$output, fixed = TRUE)),
              label = "訊息帶 refuse:input-schema")
  expect_true(any(grepl("GDP", refused$output, fixed = TRUE)), label = "訊息寫明超限的欄 GDP")
  expect_true(any(grepl("363", refused$output, fixed = TRUE)), label = "訊息寫明上限 363")
  expect_identical(f8_log_status(refused$log), "refuse:input-schema", label = "記錄的 status 為 refuse:input-schema")
  expect_true(file.exists(refused$table), label = "拒絕後既有表仍在")
  expect_identical(f8_sha256(refused$table), sha_before, label = "拒絕後表的 sha256 不變（未被覆寫）")

  # (2) 乾淨的輸出根：拒絕時不得寫下任何表，但記錄仍要留下
  fresh_root <- harness_out_root()
  withr::defer(unlink(fresh_root, recursive = TRUE, force = TRUE))
  refused_fresh <- f8_run(fresh_root, frame = mutated)
  expect_gt(refused_fresh$status, 0L, label = "乾淨輸出根下同樣拒絕")
  expect_false(file.exists(refused_fresh$table), label = "拒絕時不寫出任何表")
  expect_true(file.exists(refused_fresh$log), label = "拒絕仍留下記錄")
})

test_that("預算：全列母體、無抽樣、無隨機來源（seed 與收縮記 n/a），入口在上限內", {
  budget <- f8_budget()
  expect_equal(budget$rows, as.numeric(F8_ANALYSIS_N), label = "模型跑在 3,630 全列上")
  expect_identical(budget$sample, "全列（無抽樣）")
  expect_match(budget$seed, "^n/a", label = "無隨機來源：seed 記 n/a")
  expect_match(budget$shrink, "^n/a", label = "退化 fixture 為單一突變：收縮記 n/a")
  expect_equal(budget$flow_seconds, 120, label = "單流程上限 120 秒")
  expect_equal(budget$retries, 0L, label = "重試 0 次")

  elapsed <- as.numeric(difftime(Sys.time(), flow_started, units = "secs"))
  expect_lt(elapsed, budget$flow_seconds, label = "本流程總耗時在單流程上限內")
})
