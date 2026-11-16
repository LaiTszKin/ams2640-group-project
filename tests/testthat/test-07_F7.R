# test-07_F7.R — F7（語言文化）的性質與斷言（V07，涵蓋 T08 的 seam 06_language.R）
#
# 判定表（抄自 T08 ＋ 修訂 A-18／A-19，逐條對應下面每個 test_that）：
#
# | 輸入                        | 前置                     | 結果                                              | 拒絕類別                    | 後置                          |
# | 清洗資料集（4,424 列）       | Nacionality／target 無缺  | 三列固定序（葡語／西語／其他）、計數、率、區間、p、每組人數 | —                      | 表自帶 population 與 n（全 full） |
# | 某圈 1 ≤ n < 10             | 三圈人數不變              | 該列只出計數，率與區間留空，其餘組照出               | insufficient_n（不中止）     | 表三列齊備                     |
# | 某圈 n = 0                  | 三圈人數不變              | 該列 n=0、率與區間留空，記錄寫明                     | refuse:empty-denominator（不中止） | 既有表未被覆寫            |
#
# 性質（每條可證偽；括號為對應的 test_that）：
#   P1 三圈 n_members 74／17／19、合計 110；population 逐列 full；本地不佔列
#   P2 分析母體上的 n 為 60／11／15、合計 86；在讀 14／6／4 計入 n_members 但不入 n
#   P3 西語圈 dropout_rate 為 6/11：四位 0.5455，全精度與 6/11 相等；分母不是 n_members
#   P4 西語圈區間在 [0,1]、含 0.5455，且等於以 6/11 計的威爾遜區間（相對差 1e-3）
#   P5 西語圈 p_vs_local 0.3586，等於四格 [6 5; 1389 2155] 的雙尾精確檢定；葡語圈為空（同語）
#   P6 required_per_group 162（契約 165±10），以 α=0.05 雙尾、power=0.8 重算並向上取整
#   P7 模型與表逐欄同值（全精度）；同輸入重跑得同一份數字，記錄載明 α、power 與可比較總數
#   P8 分支一：某圈 n = 7 → 該列只出計數，其餘組照出，不中止
#   P9 分支二：某圈 n = 0 → 該列 n=0、記錄寫明 refuse:empty-denominator，不中止，已發佈表不動
#   P10 負向控制：五個單格 mutant 各自只紅對應的一條性質（隔離）
#
# 樣本、暫存與輸出根一律取自 helper-harness.R；退化 fixture 只在 harness_dir() 的暫存副本
# 與 harness_out_root() 的暫存根上造，專案的 output/ 與 programs/ 不經手。

# harness-07.R 以本檔的求值環境為目標載入（不用 local = FALSE：那會把函式放進 globalenv，
# 而 helper 可能只被 entry 的 source() 放進全域；改放在本檔自己的 env 內，parent 鏈上就有
# helper，故 test_dir()／test_file()／tests/testthat.R 三種入口下都能解析 harness_table()）。
source(testthat::test_path("harness-07.R"), local = environment())

# 模型的輸入：全量 4,424 列（無抽樣）。分析母體上的 n 由 target 界線在同一份資料上界定，
# 故 fixture 變異後仍須保持 4,424 列（母體人數不變是「換錯資料」與「該圈變小」的分界）。
clean_frame <- harness_data("full")
published <- h07_table()
model <- h07_model()
published_hash <- h07_published_hash()

flow_started <- Sys.time()

test_that("P1 三圈 n_members 74／17／19、合計 110，population 逐列 full", {
  expect_equal(nrow(published), 3L, label = "表為三列（本地只作對照、不佔列）")
  expect_identical(as.character(published$group), H07_GROUPS, label = "列序為葡語／西語／其他")
  expect_true(all(as.character(published$population) == "full"), label = "population 逐列填 full")
  expect_profile(published)

  expect_equal(as.numeric(published$n_members), as.numeric(H07_MEMBERS),
               label = "三圈 n_members 依固定列序")
  expect_equal(sum(as.numeric(published$n_members)), as.numeric(H07_MEMBERS_TOTAL),
               label = "三圈 n_members 合計 = 非本地 110 人")
  expect_equal(sum(as.numeric(published$n_members)), nrow(clean_frame) - sum(as.integer(clean_frame[[H07_NATIONALITY_COL]]) == H07_LOCAL_CODE, na.rm = TRUE),
               label = "三圈合計 = 全量減本地（4,424 − 4,314）")

  # 模型（獨立重算）與表的逐圈人數同值
  expect_equal(model$n_members, as.numeric(published$n_members), label = "模型 n_members 與表相同")
  expect_equal(sum(model$n_members), as.numeric(H07_MEMBERS_TOTAL), label = "模型三圈合計 = 110")
  expect_true(length(h07_violations_shape(published)) == 0L, label = "形狀性質成立")
  expect_true(length(h07_violations_counts(published)) == 0L, label = "計數性質成立")
})

test_that("P2 分析母體上的 n 為 60／11／15、合計 86；在讀不入分母", {
  n <- as.numeric(published$n)
  members <- as.numeric(published$n_members)

  expect_equal(n, as.numeric(H07_N), label = "三圈 n 依固定列序（僅畢業與退學）")
  expect_equal(sum(n), as.numeric(H07_N_TOTAL), label = "可比較人數合計 = 86")
  expect_true(all(n <= members), label = "每圈 n 不大於 n_members")
  expect_equal(members - n, as.numeric(H07_ENROLLED), label = "在讀人數 = n_members − n（14／6／4）")
  expect_equal(sum(members - n), as.numeric(H07_MEMBERS_TOTAL - H07_N_TOTAL),
               label = "在讀合計 = 110 − 86 = 24")

  # 分母確實是「畢業與退學」：以西語圈為例，n = 11 而 n_members = 17，差 6 人為在讀。
  expect_equal(sum(model$n), as.numeric(H07_N_TOTAL), label = "模型可比較人數合計 = 86")
  expect_equal(model$n, n, label = "模型 n 與表相同")
  # 反面錨：把在讀者算進分母會得到 17，與釘值 11 不同。
  expect_false(identical(as.integer(members[2]), as.integer(n[2])),
               label = "西語圈的 n 不是 n_members（17 ≠ 11）")
})

test_that("P3 西語圈 dropout_rate 為 6/11（四位 0.5455，全精度相等）", {
  rate <- as.numeric(published$dropout_rate)

  expect_identical(h07_sig(rate), h07_sig(H07_RATES_4SF), label = "三圈退學率四位有效數字")
  expect_rate_equal(rate[2], 6 / 11, tolerance = H07_VALUE_TOL)   # 表存全精度（A-19）
  expect_equal(rate[2], H07_SPANISH_RATE, tolerance = H07_VALUE_TOL, label = "西語圈率 = 6/11")
  expect_rate_equal(model$dropout_rate, rate)

  # 分母是 11 人、分子是 6 人：n × rate 回整數的退學人數
  expect_equal(as.numeric(published$n[2]) * rate[2], as.numeric(H07_SPANISH_DROPOUTS),
               tolerance = H07_VALUE_TOL, label = "11 × 0.5454… = 6")
  # 三個率不得相等（三圈人數與退學人數都不同）：這條擋住「整欄填同一個值」的失效
  expect_equal(length(unique(h07_sig(rate))), 3L, label = "三圈退學率互不相同")

  # 反面錨：以 n_members 為分母的版本是 6/17 = 0.3529，四位有效數字與 0.5455 不同。
  expect_false(h07_sig_equal(rate[2], 6 / 17),
               label = "西語圈率不是 6/17（分母是可比較的 11 人，不是在籍的 17 人）")
  expect_true(length(h07_violations_rate(published)) == 0L, label = "退學率性質成立")
})

test_that("P4 西語圈區間等於以 6/11 計的威爾遜區間，且在 [0,1] 內含 0.5455", {
  low <- as.numeric(published$ci_low[2])
  high <- as.numeric(published$ci_high[2])
  rate <- as.numeric(published$dropout_rate[2])

  expect_true(all(is.finite(c(low, high))), label = "區間兩端為有限值")
  expect_true(low >= 0 && high <= 1, label = "區間在 [0,1] 內")
  expect_true(low < rate && rate < high, label = "區間嚴格包含 0.5455")

  # 與閉式重算（不經 lib/stats.R 的 prop_ci）比對：相對差 1e-3
  wilson <- h07_wilson(H07_SPANISH_DROPOUTS, H07_SPANISH_N)
  expect_lt(abs(low - wilson[["low"]]) / wilson[["low"]], H07_CI_REL_TOL, label = "下界 = 威爾遜下界")
  expect_lt(abs(high - wilson[["high"]]) / wilson[["high"]], H07_CI_REL_TOL, label = "上界 = 威爾遜上界")
  expect_rate_equal(c(low, high), unname(H07_SPANISH_CI), tolerance = H07_CI_REL_TOL)
  expect_equal(model$ci_low[2], low, tolerance = H07_VALUE_TOL, label = "模型下界 = 表的下界")
  expect_equal(model$ci_high[2], high, tolerance = H07_VALUE_TOL, label = "模型上界 = 表的上界")

  # 反面錨：同一組 k/n 的華德區間是 0.2512／0.8397，兩端都與表不同——
  # 「等於威爾遜」這條因此不是任何近似都滿足。
  wald <- h07_wald(H07_SPANISH_DROPOUTS, H07_SPANISH_N)
  expect_gt(abs(low - wald[["low"]]) / wald[["low"]], H07_CI_REL_TOL, label = "下界不是華德下界")
  expect_gt(abs(high - wald[["high"]]) / wald[["high"]], H07_CI_REL_TOL, label = "上界不是華德上界")
  expect_true(length(h07_violations_interval(published)) == 0L, label = "區間性質成立")
})

test_that("P5 西語圈 p = 0.3586；葡語圈與其他留空（同語不作跨語比較）", {
  p <- as.numeric(published$p_vs_local)

  expect_identical(h07_sig(p[2]), h07_sig(H07_SPANISH_P_4SF), label = "西語圈 p 四位有效數字 0.3586")
  expect_true(is.na(p[1]), label = "葡語圈 p 為空（與本地同語）")
  expect_true(is.na(p[3]), label = "其他圈 p 為空（只對西語圈做檢定）")

  # 由四格獨立重算：西語圈退學／未退學 = 6／5，本地退學／未退學 = 1389／2155
  exact <- h07_fisher_p(6, 5, 1389, 2155)
  expect_lt(abs(p[2] - exact) / exact, H07_P_TOL, label = "p = 四格的雙尾精確檢定")
  expect_equal(p[2], H07_SPANISH_P, tolerance = H07_P_TOL, label = "p 與全精度釘值相同")
  expect_equal(model$p_vs_local[2], p[2], tolerance = H07_P_TOL, label = "模型 p = 表的 p")

  # 對照組不是「最大一組」：最大組是葡語圈 74 人，而它的 p 必須是空的（A-18）。
  expect_gt(as.numeric(published$n_members[1]), as.numeric(published$n_members[2]),
            label = "葡語圈確實是最大組")
  expect_true(length(h07_violations_test(published)) == 0L, label = "對照檢定性質成立")
})

test_that("P6 required_per_group = 162（契約 165±10），由 α=0.05、power=0.8 重算", {
  required <- as.numeric(published$required_per_group)

  expect_equal(as.integer(required[2]), as.integer(H07_REQUIRED_PIN), label = "西語圈每組需 162 人")
  expect_lte(abs(required[2] - H07_REQUIRED_TARGET), H07_REQUIRED_BAND,
             label = "落在契約的 165±10 之內")
  expect_true(is.na(required[1]) && is.na(required[3]),
              label = "葡語圈與其他圈的 required_per_group 留空")

  raw <- h07_required(6 / 11, 1389 / 3544, alpha = H07_ALPHA, power = H07_POWER)
  expect_equal(raw, 161.9257925446, tolerance = 1e-9, label = "未取整值 161.93")
  expect_equal(as.integer(required[2]), as.integer(ceiling(raw)), label = "人數向上取整")
  expect_equal(as.numeric(model$required_per_group[2]), required[2], label = "模型與表同值")

  # α 與 power 被釘住：換一個 power（0.9）會得不同的人數，故這條不是任意數都成立。
  other <- ceiling(h07_required(6 / 11, 1389 / 3544, alpha = H07_ALPHA, power = 0.9))
  expect_false(identical(as.integer(other), as.integer(required[2])),
               label = "power 0.9 會給不同的人數（0.8 不是隨意寫的）")
  expect_true(length(h07_violations_power(published)) == 0L, label = "檢定力性質成立")
})

test_that("P7 模型與表逐欄同值；同輸入重跑同值，記錄載明 α、power 與可比較總數", {
  expect_identical(model$status, rep("ok", 3L), label = "全量的三圈都在 happy path（無拒絕、無小樣本）")
  expect_true(length(h07_violations_model(published, model)) == 0L,
              label = paste(h07_violations_model(published, model), collapse = "；"))

  # 在乾淨的暫存根上重跑生產腳本（不注入）：得到同一份數字，並取得記錄
  out_root <- harness_out_root()
  withr::defer(unlink(out_root, recursive = TRUE, force = TRUE))
  run <- h07_run(out_root = out_root)
  expect_identical(run$outcome, "ok", label = paste("重跑的結局為 ok；實得", run$outcome, run$message))
  expect_true(file.exists(run$table), label = "重跑寫出 language_groups.csv")
  expect_lt(run$elapsed, H07_FLOW_LIMIT_SEC, label = "單流程在執行上限內")

  rerun <- h07_script_table(run)
  expect_equal(as.numeric(rerun$n_members), as.numeric(published$n_members), label = "重跑的三圈人數不變")
  expect_equal(as.numeric(rerun$n), as.numeric(published$n), label = "重跑的可比較人數不變")
  expect_rate_equal(as.numeric(rerun$dropout_rate), as.numeric(published$dropout_rate), tolerance = H07_VALUE_TOL)
  expect_equal(as.numeric(rerun$p_vs_local[2]), as.numeric(published$p_vs_local[2]), tolerance = H07_P_TOL,
               label = "重跑的 p 不變")
  expect_equal(as.numeric(rerun$required_per_group[2]), as.numeric(published$required_per_group[2]),
               label = "重跑的每組人數不變")

  # 記錄：α、power 與可比較總數逐字出現（F7 邊界的兩個數字）
  log <- h07_log_lines(run)
  expect_true(any(grepl("alpha=0.05", log, fixed = TRUE)), label = "記錄寫明 α = 0.05 雙尾")
  expect_true(any(grepl("power=0.8", log, fixed = TRUE)), label = "記錄寫明 power = 0.8")
  expect_true(any(grepl("comparable_total: 86", log, fixed = TRUE)), label = "記錄寫明可比較總數 86")
  expect_true(any(grepl("circle_members: Portuguese=74 Spanish=17 Other=19", log, fixed = TRUE)),
              label = "記錄寫明三圈人數 74／17／19")
})

test_that("P8 分支一：某圈 1 ≤ n < 10 時該列只出計數，其餘組照出，不中止", {
  fixture <- h07_clean_fixture(
    clean_frame, h07_fixture_small_group,
    file.path(harness_dir(), "spanish_n7.csv")
  )
  script <- h07_injected_script(harness_dir(), fixture)
  out_root <- harness_out_root()
  withr::defer(unlink(out_root, recursive = TRUE, force = TRUE))

  run <- h07_run(script, out_root)
  expect_identical(run$outcome, "ok", label = paste("小樣本分支不中止；實得", run$outcome, run$message))
  tbl <- h07_script_table(run)

  expect_equal(as.numeric(tbl$n_members), as.numeric(H07_MEMBERS), label = "三圈人數不變（74／17／19）")
  expect_equal(as.numeric(tbl$n), c(60, 7, 15), label = "西語圈 n 降為 7，其餘組不變")
  expect_true(is.na(tbl$dropout_rate[2]), label = "西語圈 dropout_rate 為 NA（n < 10 只出計數）")
  expect_true(is.na(tbl$ci_low[2]) && is.na(tbl$ci_high[2]), label = "西語圈區間留空")
  expect_true(is.na(tbl$required_per_group[2]), label = "西語圈 required_per_group 留空")

  # 其餘組照出：計數與率都在
  expect_equal(as.numeric(tbl$dropout_rate[c(1, 3)]), c(0.35, 1 / 3), tolerance = H07_VALUE_TOL,
               label = "葡語圈與其他圈照出退學率")
  expect_true(all(is.finite(as.numeric(tbl$ci_low[c(1, 3)]))), label = "其餘組的區間照出")

  # 模型走同一個分支（該圈 insufficient_n，其餘 ok），且與腳本逐欄同值
  model_small <- h07_groups(h07_fixture_small_group(clean_frame))
  expect_identical(model_small$status, c("ok", "insufficient_n", "ok"), label = "模型逐圈狀態")
  expect_true(length(h07_violations_model(tbl, model_small)) == 0L,
              label = paste(h07_violations_model(tbl, model_small), collapse = "；"))
})

test_that("P9 分支二：某圈 n = 0 時該列 n=0、記錄寫明，不中止，已發佈表不動", {
  fixture <- h07_clean_fixture(
    clean_frame, h07_fixture_empty_group,
    file.path(harness_dir(), "spanish_n0.csv")
  )
  script <- h07_injected_script(harness_dir(), fixture)
  out_root <- harness_out_root()
  withr::defer(unlink(out_root, recursive = TRUE, force = TRUE))

  run <- h07_run(script, out_root)
  expect_identical(run$outcome, "ok", label = paste("n = 0 不中止；實得", run$outcome, run$message))
  expect_equal(length(run$output) > 0L, TRUE, label = "腳本留下進度輸出（不是靜默結束）")

  tbl <- h07_script_table(run)
  expect_equal(nrow(tbl), 3L, label = "三列齊備（n = 0 的那一圈仍佔一列）")
  expect_equal(as.numeric(tbl$n_members), as.numeric(H07_MEMBERS), label = "三圈人數不變")
  expect_equal(as.numeric(tbl$n[2]), 0, label = "西語圈 n = 0")
  expect_true(is.na(tbl$dropout_rate[2]), label = "西語圈 dropout_rate 為 NA（分母為零）")
  expect_true(is.na(tbl$ci_low[2]) && is.na(tbl$ci_high[2]), label = "西語圈區間留空")
  expect_true(is.na(tbl$p_vs_local[2]), label = "西語圈 p 留空（無可比的退學率）")
  expect_equal(as.numeric(tbl$dropout_rate[c(1, 3)]), c(0.35, 1 / 3), tolerance = H07_VALUE_TOL,
               label = "其餘組照出退學率")

  # 記錄寫明 refuse:empty-denominator 與是哪一圈
  log <- h07_log_lines(run)
  expect_true(any(grepl("refuse:empty-denominator", log, fixed = TRUE)),
              label = "記錄帶 refuse:empty-denominator")
  expect_true(any(grepl("Spanish", log, fixed = TRUE)), label = "記錄指名西語圈")
  expect_true(any(grepl("可比較人數為 0", log, fixed = TRUE)), label = "記錄寫明該圈可比較人數為 0")

  # 模型的拒絕分支與腳本同一個形狀
  model_zero <- h07_groups(h07_fixture_empty_group(clean_frame))
  expect_identical(model_zero$status, c("ok", H07_REFUSE_CATEGORY, "ok"), label = "模型逐圈狀態")
  expect_equal(as.numeric(model_zero$n), c(60, 0, 15), label = "模型西語圈 n = 0")
  expect_true(length(h07_violations_model(tbl, model_zero)) == 0L,
              label = paste(h07_violations_model(tbl, model_zero), collapse = "；"))

  # 已發佈的表未被覆寫：兩次注入都寫在暫存根，專案 output/tables 沒有動過
  expect_identical(h07_published_hash(), published_hash, label = "已發佈表的 sha256 不變")
})

test_that("P10 負向控制：五個單格 mutant 各自只紅對應的一條性質", {
  # 基準：未改動的表五條性質全空
  expect_length(h07_violations_shape(published), 0L)
  expect_length(h07_violations_counts(published), 0L)
  expect_length(h07_violations_rate(published), 0L)
  expect_length(h07_violations_interval(published), 0L)
  expect_length(h07_violations_test(published), 0L)
  expect_length(h07_violations_power(published), 0L)

  # (1) 列序改成其他／葡語／西語 → 形狀紅
  shape_mutant <- h07_mutant(published, "group_order")
  expect_gt(length(h07_violations_shape(shape_mutant)), 0L, label = "列序改錯 → 形狀判紅")

  # (2) 西語圈率改用以 n_members 為分母的 6/17 → 退學率紅，計數不動
  rate_mutant <- h07_mutant(published, "rate_over_members")
  expect_gt(length(h07_violations_rate(rate_mutant)), 0L, label = "分母換成 17 → 退學率判紅")
  expect_length(h07_violations_counts(rate_mutant), 0L)

  # (3) 區間換成華德近似 → 區間紅，退學率不動
  ci_mutant <- h07_mutant(published, "interval_wald")
  expect_gt(length(h07_violations_interval(ci_mutant)), 0L, label = "區間換成華德 → 區間判紅")
  expect_length(h07_violations_rate(ci_mutant), 0L)

  # (4) 葡語圈填上 p（把同語圈也拿去做跨語比較）→ 對照檢定紅
  p_mutant <- h07_mutant(published, "portuguese_p")
  expect_gt(length(h07_violations_test(p_mutant)), 0L, label = "葡語圈填 p → 對照檢定判紅")
  expect_length(h07_violations_counts(p_mutant), 0L)

  # (5) required_per_group 改成 176（出 165±10）→ 檢定力紅
  power_mutant <- h07_mutant(published, "required_outside_band")
  expect_gt(length(h07_violations_power(power_mutant)), 0L, label = "每組人數出界 → 檢定力判紅")
  expect_length(h07_violations_rate(power_mutant), 0L)
  expect_true(any(grepl("之外", h07_violations_power(power_mutant), fixed = TRUE)),
              label = "判紅的理由寫明落在 165±10 之外")
})

test_that("預算：全量 4,424 列、無抽樣、無隨機來源（seed 與收縮記 n/a）", {
  budget <- h07_budget()
  expect_equal(budget$rows, as.numeric(H07_SAMPLE_ROWS), label = "模型跑在 4,424 全列上")
  expect_identical(budget$sample, "全量（無抽樣）")
  expect_match(budget$seed, "^n/a", label = "無隨機來源：seed 記 n/a")
  expect_match(budget$shrink, "^n/a", label = "拒絕分支為枚舉：收縮記 n/a")
  expect_equal(budget$flow_seconds, 120, label = "單流程上限 120 秒")

  elapsed <- as.numeric(difftime(Sys.time(), flow_started, units = "secs"))
  expect_lt(elapsed, budget$flow_seconds, label = "本流程總耗時在單流程上限內")
})
