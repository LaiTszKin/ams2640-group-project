# test-03_F3.R — F3（財富層）的性質與斷言（V03，涵蓋 T04 的 seam 02_wealth.R）
#
# 判定表（抄自 T04 ＋ 修訂 A-10／A-22，逐條對應下面每個 test_that）：
#
# | 輸入                        | 前置           | 結果                                   | 拒絕類別                  | 後置                        |
# | 清洗資料集（分析母體 3,630）| 三欄無缺值     | 四列固定序、n／dropout_rate／share／phi | —                        | 表自帶 population 與 n      |
# | 任一格人數為 0              | 母體仍 3,630   | 停止，寫明空格位置                      | refuse:empty-denominator  | 既有表未被覆寫（sha256 同） |
#
# 性質（每條可證偽；括號為對應的 test_that）：
#   P1 四格 n 合計等於分析母體，且與 population_ledger.csv 的 analysis 列同值
#   P2 share 以分析母體為分母，四格合計為 1（容差 1e-4）
#   P3 dropout_rate 以**格內人數**為分母，四位有效數字為 0.9513／0.9308／0.5187／0.2932
#   P4 phi = +0.4349（四位有效數字，容差 1e-3），編碼 欠繳=1、欠債=1
#   P5 負向控制一：整列或整欄互換後 phi 變號且絕對值不變
#   P6 負向控制二：對角互換後 phi 不變
#   P7 空格 → refuse:empty-denominator（兩個形狀：整列空、整欄空），且表 sha256 不變
#
# 樣本、暫存與輸出根一律取自 helper-harness.R；退化 fixture 只在 harness_dir() 的
# 暫存副本與 harness_out_root() 的暫存根上造，專案的 output/ 與 programs/ 不經手。

# harness-03.R 以本檔的求值環境為目標載入（不用 local = FALSE：那會把函式放進
# globalenv，而 helper 可能只被 entry 的 source() 放進全域；改放在本檔自己的 env
# 內，parent 鏈上就有 helper，故 test_dir()／test_file()／tests/testthat.R 三種
# 入口下都能解析 harness_table()／harness_data()。
source(testthat::test_path("harness-03.R"), local = environment())

# 模型的輸入：分析母體全列（無抽樣）與完整清洗資料集（4,424 列，退化 fixture 的母體
# 必須保持 3,630，故變異後仍須以 00_setup.R 的釘值通過）
analysis_frame <- harness_data("analysis")
clean_frame <- harness_data("full")

flow_started <- Sys.time()

test_that("P1 四格 n 合計等於分析母體，且清冊與釘值三方一致", {
  published <- f3_table()
  model <- f3_cells(analysis_frame)

  expect_equal(nrow(published), 4L, label = "四格表為四列")
  expect_equal(as.character(published$population), rep("analysis", 4L), label = "population 逐列填 analysis")

  # 三個獨立來源：表、母體清冊、契約釘值
  expect_equal(sum(as.numeric(published$n)), f3_ledger_n("analysis"), label = "四格 n 合計 = 清冊的 analysis n")
  expect_equal(sum(as.numeric(published$n)), as.numeric(F3_ANALYSIS_N), label = "四格 n 合計 = 分析母體 3,630")
  expect_equal(as.numeric(published$n), as.numeric(F3_PIN_N), label = "逐格 n 依固定列序")

  # 模型（獨立重算）與表的逐格 n 必須同值，且合計等於同一母體
  expect_equal(model$n, as.numeric(published$n), label = "模型 n 與表的 n 逐格相同")
  expect_equal(sum(model$n), as.numeric(F3_ANALYSIS_N), label = "模型四格合計 = 分析母體")
})

test_that("P2 share 以分析母體為分母，四格合計為 1（容差 1e-4）", {
  published <- f3_table()
  model <- f3_cells(analysis_frame)
  n <- as.numeric(published$n)

  expect_equal(sum(published$share), 1, tolerance = F3_SHARE_TOL, label = "表內 share 合計為 1")
  expect_equal(sum(model$share), 1, tolerance = F3_SHARE_TOL, label = "模型 share 合計為 1")
  expect_equal(published$share, n / sum(n), tolerance = F3_VALUE_TOL, label = "逐格 share = n／分析母體")
  expect_rate_equal(model$share, published$share)
})

test_that("P3 dropout_rate 以格內人數為分母（0.9513／0.9308／0.5187／0.2932）", {
  published <- f3_table()
  model <- f3_cells(analysis_frame)
  n <- as.numeric(published$n)
  rate <- as.numeric(published$dropout_rate)

  expect_identical(
    f3_sig(rate), f3_sig(F3_PIN_DROPOUT_RATE),
    label = "四位有效數字的退學率依固定列序"
  )
  expect_rate_equal(model$dropout_rate, rate)

  # 「必須永不發生」的那一版：以分析母體為分母。0.9513 的分母是 226，不是 3,630。
  whole_sample <- model$dropout_n / sum(model$n)
  expect_false(
    f3_sig_equal(rate[1], whole_sample[1]),
    label = "第一格退學率不是佔全樣本的比例（分母是 226 而非 3,630）"
  )
  # 四格率不得被當成 100%（REQ-F-F3-1 的失效形狀）：以 share 加權後的和才是全體退學率
  expect_equal(sum(model$share * model$dropout_rate), 0.3915, tolerance = 1e-4,
               label = "以 share 加權的四格率和 = 全體退學率 0.3915")
  expect_equal(sum(model$dropout_rate), 2.694, tolerance = 1e-3,
               label = "未加權的四格率和為 2.694，不是 1")

  # 分母確實是格內人數：n × rate 回得整數的退學人數
  expect_equal(round(n * rate), n * rate, tolerance = F3_VALUE_TOL, label = "n × dropout_rate 為整數")
  expect_equal(n * rate, model$dropout_n, tolerance = F3_VALUE_TOL, label = "n × dropout_rate = 該格退學人數")
})

test_that("P4 phi = +0.4349（四位有效數字，容差 1e-3；編碼 欠繳=1、欠債=1）", {
  published <- f3_table()
  n <- as.numeric(published$n)
  phi <- as.numeric(published$phi)

  expect_equal(phi, rep(F3_PIN_PHI, 4L), tolerance = F3_PHI_TOL, label = "四列同一個 phi 值，且等於釘值")
  expect_identical(unique(f3_sig(phi)), f3_sig(F3_PIN_PHI), label = "四位有效數字後為 0.4349")
  expect_true(all(phi > 0), label = "符號為正（編碼 欠繳=1、欠債=1）")

  # 由表內 n 以獨立閉式重算（不經 lib/stats.R）
  expect_equal(n[1], as.numeric(F3_PIN_N[1]), label = "a = 兩者俱有的 226 人")
  expect_equal(phi[1], f3_phi(n[1], n[2], n[3], n[4]), tolerance = F3_VALUE_TOL, label = "表內 phi = 由 n 重算")
  expect_equal(f3_phi(n[1], n[2], n[3], n[4]), f3_cells(analysis_frame)$phi[1],
               tolerance = F3_VALUE_TOL, label = "模型 phi = 表內 phi")
})

test_that("P5 負向控制一：整列或整欄互換使 phi 變號且絕對值不變", {
  n <- as.numeric(f3_table()$n)
  a <- n[1]; b <- n[2]; c <- n[3]; d <- n[4]
  base <- f3_phi(a, b, c, d)

  expect_equal(base, F3_PIN_PHI, tolerance = F3_PHI_TOL, label = "基準 phi")
  expect_equal(f3_phi(c, d, a, b), -base, tolerance = F3_VALUE_TOL, label = "整列互換（列 1 ↔ 列 2）後變號")
  expect_equal(f3_phi(b, a, d, c), -base, tolerance = F3_VALUE_TOL, label = "整欄互換（欄 1 ↔ 欄 2）後變號")
  expect_equal(abs(c(f3_phi(c, d, a, b), f3_phi(b, a, d, c))), rep(abs(base), 2L),
               tolerance = F3_VALUE_TOL, label = "絕對值不變")

  # 這條斷言不是恆真：單格對調不變號（A-10 駁回的就是這一條）。
  single <- f3_phi(b, a, c, d)
  expect_false(f3_sig_equal(single, -base), label = "單格對調（a↔b）不得誤判為變號")
  expect_equal(single, F3_PIN_PHI_SINGLE_SWAP, tolerance = 1e-6, label = "單格對調得 0.4928")

  # 符號的來源是編碼：把「欠繳」讀成「繳清」即整體變號
  expect_equal(-f3_phi(a, b, c, d), -base, tolerance = F3_VALUE_TOL, label = "編碼反轉後 phi 為 −0.4349")
})

test_that("P6 負向控制二：對角互換（轉置）後 phi 不變", {
  n <- as.numeric(f3_table()$n)
  a <- n[1]; b <- n[2]; c <- n[3]; d <- n[4]
  base <- f3_phi(a, b, c, d)

  expect_equal(f3_phi(a, c, b, d), base, tolerance = F3_VALUE_TOL, label = "b ↔ c 後 phi 不變")
  expect_identical(f3_sig(f3_phi(a, c, b, d)), f3_sig(base), label = "四位有效數字亦不變")
})

test_that("P7 空格以 refuse:empty-denominator 停止，且 wealth_four_cell.csv 的 sha256 不變", {
  prior_out_root <- Sys.getenv("RTOOLKIT_OUT_ROOT", unset = "")
  out_root <- harness_out_root()
  withr::defer({
    if (nzchar(prior_out_root)) Sys.setenv(RTOOLKIT_OUT_ROOT = prior_out_root) else Sys.unsetenv("RTOOLKIT_OUT_ROOT")
    unlink(out_root, recursive = TRUE, force = TRUE)
  })

  # (0) happy path：同一份母體在乾淨的暫存根上重跑，得到同一張表；重跑逐位元組相同
  first <- f3_run(out_root)
  expect_equal(first$status, 0L, label = "happy path 的結束碼為 0")
  expect_true(file.exists(first$table), label = "happy path 寫出 wealth_four_cell.csv")
  expect_lt(first$elapsed, F3_FLOW_SECONDS, label = "單流程在執行上限內")

  sha_before <- f3_sha256(first$table)
  expect_true(grepl("^[0-9a-f]{64}$", sha_before), label = "指紋為 64 位十六進位")

  second <- f3_run(out_root)
  expect_equal(second$status, 0L, label = "重跑的結束碼為 0")
  expect_identical(f3_sha256(second$table), sha_before, label = "同一輸入重跑得同一份位元組")

  # (1) 空的整列：Debtor 全為 0 → 兩者俱有與僅欠債皆無人
  no_debtor <- clean_frame
  no_debtor[[F3_DEBTOR_COL]] <- 0
  no_debtor_path <- f3_write_frame(no_debtor, file.path(harness_dir(), "empty_debtor.csv"))

  expect_error(f3_cells(no_debtor), "refuse:empty-denominator", fixed = TRUE)

  refused <- f3_run(out_root, clean_path = no_debtor_path)
  expect_gt(refused$status, 0L, label = "空的整列使程式以非零結束碼停止")
  expect_true(any(grepl("refuse:empty-denominator", refused$output, fixed = TRUE)),
              label = "訊息帶 refuse:empty-denominator")
  expect_true(any(grepl("w_both", refused$output, fixed = TRUE)),
              label = "訊息寫明空格位置 w_both")
  expect_true(any(grepl("w_only_debt", refused$output, fixed = TRUE)),
              label = "訊息寫明空格位置 w_only_debt")
  expect_true(file.exists(refused$table), label = "拒絕後既有表仍在")
  expect_identical(f3_sha256(refused$table), sha_before, label = "拒絕後表的 sha256 不變")

  # (2) 空的整欄：學費全繳清 → 兩者俱有與僅欠繳皆無人；且不得生出任何表
  all_paid <- clean_frame
  all_paid[[F3_UNPAID_COL]] <- 1
  all_paid_path <- f3_write_frame(all_paid, file.path(harness_dir(), "all_paid.csv"))

  fresh_root <- harness_out_root()
  withr::defer(unlink(fresh_root, recursive = TRUE, force = TRUE))
  refused_col <- f3_run(fresh_root, clean_path = all_paid_path)

  expect_gt(refused_col$status, 0L, label = "空的整欄使程式以非零結束碼停止")
  expect_true(any(grepl("refuse:empty-denominator", refused_col$output, fixed = TRUE)),
              label = "訊息帶 refuse:empty-denominator")
  expect_true(any(grepl("w_only_unpaid", refused_col$output, fixed = TRUE)),
              label = "訊息寫明空格位置 w_only_unpaid")
  expect_false(file.exists(refused_col$table),
               label = "拒絕時不寫出任何表（乾淨的輸出根仍無表）")
  expect_true(file.exists(refused_col$log), label = "拒絕仍留下記錄")
})

test_that("預算：全列母體、無抽樣、無隨機來源（seed 與收縮記 n/a）", {
  budget <- f3_budget()
  expect_equal(budget$rows, as.numeric(F3_ANALYSIS_N), label = "模型跑在 3,630 全列上")
  expect_identical(budget$sample, "全列（無抽樣）")
  expect_match(budget$seed, "^n/a", label = "無隨機來源：seed 記 n/a")
  expect_match(budget$shrink, "^n/a", label = "退化 fixture 為有限枚舉：收縮記 n/a")
  expect_equal(budget$flow_seconds, 120, label = "單流程上限 120 秒")

  elapsed <- as.numeric(difftime(Sys.time(), flow_started, units = "secs"))
  expect_lt(elapsed, budget$flow_seconds, label = "本流程總耗時在單流程上限內")
})
