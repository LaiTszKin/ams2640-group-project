# test-04_F4.R — F4（社會背景：年齡帶與婚配）的模型
#
# 模型的判定表（T05・修訂 A-11）逐條寫成可證偽性質：
#   ① 五帶齊備：n 為 1,621／1,033／355／403／218，合計 3,630，share 合計 1
#   ② 兩率：25–29 退學率 0.6930、40+ 0.5826；25–29 欠繳率 0.2789、40+ 0.2523
#   ③ 兩個檢定為雙尾：退學 p 0.008781、欠繳 p 0.4987（單尾值另算，用來排除單尾）
#   ④ 婚配映射已婚 = 2、單身 = 其餘：30–39 153／250、40+ 115／103，p 0.02455／0.1301
#   ⑤ 三分支互斥：零格拒絕／任一格 < 30 入表標 insufficient_n／其餘檢定
#   ⑥ 負向控制：單身改取 1 時 p 變 0.0024，40+ 因 20 人的小格轉 insufficient_n
#
# 樣本、暫存與輸出根一律取自 helper-harness.R 與 harness-04.R（REQ-A-7）。
# 容差一律為「四位有效數字後相等」（A-19：表存未格式化 double，四位只在呈現層）。

# testthat 只自動載入 helper*.R，而本流程的入口檔名由契約固定為 harness-04.R，
# 故在此明確載入。harness-04.R 在載入時會自行把 helper-harness.R 載進**同一個
# 求值環境**（見該檔 §0），所以 h04_* 內的 harness_*() 呼叫不依賴任何先載入動作。
#
# 落點是 globalenv（local = FALSE，`source()` 的預設）：本流程的入口檔與 helper
# 因此都在全域，任何以 globalenv 為 enclosure 的程式碼（例如其他流程的
# harness-0N.R，它們也是被各自的測試檔 source 進 globalenv）在同一個 session 內
# 都解析的到 harness_*()。改放本檔的區域環境會讓這些呼叫在 test_dir() 下失效。
local({
  candidate <- c(
    tryCatch(testthat::test_path("harness-04.R"), error = function(e) NA_character_),
    "harness-04.R",
    file.path("tests", "testthat", "harness-04.R")
  )
  found <- candidate[!is.na(candidate) & file.exists(candidate)]
  if (!length(found)) {
    stop("找不到 harness-04.R：應與 test-04_F4.R 同目錄。", call. = FALSE)
  }
  source(found[[1L]], local = FALSE)
})

test_that("五帶齊備：n 為 1,621／1,033／355／403／218，share 合計為 1", {
  bands <- harness_table("age_bands")
  expect_profile(bands)
  expect_identical(as.character(bands$band), H04_PIN$bands)
  expect_identical(as.integer(bands$n), H04_PIN$n)
  expect_identical(sum(as.integer(bands$n)), H04_PIN$analysis_n)
  expect_true(all(as.character(bands$population) == "analysis"),
              label = "三張表的 population 一律為 analysis")

  # share 以分析母體為分母：相加為 1（容差 1e-4），逐帶等於 n／3,630（對全精度 double）
  expect_equal(sum(bands$share), 1, tolerance = 1e-4)
  expect_rate_equal(bands$share, bands$n / H04_PIN$analysis_n)
})

test_that("兩率：25–29 與 40+ 的錨值，五帶逐帶與母體重算相符", {
  bands <- harness_table("age_bands")
  recomputed <- h04_recompute(harness_data("analysis"))

  expect_identical(as.integer(recomputed$n), as.integer(bands$n))
  h04_expect_sig4(bands$dropout_rate, recomputed$dropout_rate, "各帶退學率（自樣本重算）")
  h04_expect_sig4(bands$unpaid_rate, recomputed$unpaid_rate, "各帶欠繳率（自樣本重算）")

  h04_expect_sig4(h04_band_value(bands, "dropout_rate", "25-29"), H04_PIN$dropout_25_29,
                  "25–29 的退學率")
  h04_expect_sig4(h04_band_value(bands, "dropout_rate", "40+"), H04_PIN$dropout_40p,
                  "40+ 的退學率")
  h04_expect_sig4(h04_band_value(bands, "unpaid_rate", "25-29"), H04_PIN$unpaid_25_29,
                  "25–29 的欠繳率")
  h04_expect_sig4(h04_band_value(bands, "unpaid_rate", "40+"), H04_PIN$unpaid_40p,
                  "40+ 的欠繳率")

  # 兩個率的分母都是該帶人數，不是分析母體
  h04_expect_sig4(recomputed$unpaid_rate, recomputed$unpaid_n / recomputed$n,
                  "欠繳率的分母為帶內人數")
})

test_that("兩個檢定為雙尾：25–29 對 40+ 的退學 p = 0.008781、欠繳 p = 0.4987", {
  tests <- harness_table("age_tests", required = c("population", "test", "p_value", "tail"))
  expect_identical(nrow(tests), 2L)
  expect_identical(as.character(tests$test), c("dropout_rate", "unpaid_rate"))
  expect_identical(as.character(tests$tail), rep("two.sided", 2L))
  expect_identical(as.character(tests$status), rep("ok", 2L))
  expect_identical(as.character(tests$group_a), rep(H04_PIN$test_band_a, 2L))
  expect_identical(as.character(tests$group_b), rep(H04_PIN$test_band_b, 2L))
  expect_identical(as.integer(tests$n_a), rep(H04_PIN$n[3L], 2L))
  expect_identical(as.integer(tests$n_b), rep(H04_PIN$n[5L], 2L))

  h04_expect_sig4(tests$p_value, c(H04_PIN$p_dropout, H04_PIN$p_unpaid), "兩個 p 值")
  h04_expect_sig4(tests$odds_ratio, c(H04_PIN$odds_ratio_dropout, H04_PIN$odds_ratio_unpaid),
                  "兩個勝算比")

  # 雙尾的判別：p 須與自算的雙尾值相同，且嚴格落在兩個單尾 p 之間（單尾會落在端點）
  sample <- harness_data("analysis")
  comparisons <- list(
    dropout = h04_compare(sample, "dropout"),
    unpaid = h04_compare(sample, "unpaid")
  )
  for (metric in names(comparisons)) {
    cmp <- comparisons[[metric]]
    published <- tests$p_value[tests$test == paste0(metric, "_rate")]
    label <- sprintf("%s 對 %s 的 %s 雙尾 p", cmp$band_a, cmp$band_b, metric)
    expect_length(published, 1L)
    h04_expect_sig4(cmp$p_two, published, paste0(label, "（自樣本重算）"))
    expect_true(cmp$p_two > min(cmp$p_less, cmp$p_greater) &&
                  cmp$p_two < max(cmp$p_less, cmp$p_greater),
                label = paste0(label, " 落在兩個單尾 p 之間"))
    expect_false(any(h04_sig4(cmp$p_two) == h04_sig4(c(cmp$p_less, cmp$p_greater))),
                 label = paste0(label, " 與任一單尾 p 在四位有效數字上不同"))
  }
  expect_identical(comparisons$dropout$cells, as.integer(H04_PIN$cells_dropout_test))
  expect_identical(comparisons$unpaid$cells, as.integer(H04_PIN$cells_unpaid_test))
})

test_that("婚配映射已婚 = 2、單身 = 其餘：30–39 已婚 153／單身 250、40+ 115／103", {
  strata <- harness_table("marriage_strata")
  expect_profile(strata)
  expect_identical(as.character(strata$band), H04_PIN$bands)

  # 單身取其餘：兩組人數相加即該帶人數，每人恰入一組（映射沒有漏掉任何類別）
  expect_identical(as.integer(strata$married_n + strata$single_n), as.integer(strata$n))

  sample <- harness_data("analysis")
  recomputed <- h04_recompute(sample)
  expect_identical(as.integer(strata$married_n), recomputed$married_n)
  expect_identical(as.integer(strata$single_n), recomputed$single_n)
  h04_expect_sig4(strata$married_rate, recomputed$married_rate, "已婚組退學率（自樣本重算）")
  h04_expect_sig4(strata$single_rate, recomputed$single_rate, "單身組退學率（自樣本重算）")

  # 四格人數：由表內人數 × 率導出，對契約釘住的四格
  four_cell <- function(band) {
    m_n <- h04_band_value(strata, "married_n", band)
    m_r <- h04_band_value(strata, "married_rate", band)
    s_n <- h04_band_value(strata, "single_n", band)
    s_r <- h04_band_value(strata, "single_rate", band)
    m_drop <- round(m_n * m_r)
    s_drop <- round(s_n * s_r)
    as.integer(c(m_drop, m_n - m_drop, s_drop, s_n - s_drop))
  }
  expect_identical(four_cell("30-39"), as.integer(H04_PIN$cells_30_39))
  expect_identical(four_cell("40+"), as.integer(H04_PIN$cells_40p))
  expect_identical(as.integer(h04_band_value(strata, "married_n", "30-39")), H04_PIN$married_30_39)
  expect_identical(as.integer(h04_band_value(strata, "single_n", "30-39")), H04_PIN$single_30_39)
  expect_identical(as.integer(h04_band_value(strata, "married_n", "40+")), H04_PIN$married_40p)
  expect_identical(as.integer(h04_band_value(strata, "single_n", "40+")), H04_PIN$single_40p)

  h04_expect_sig4(h04_band_value(strata, "p_value", "30-39"), H04_PIN$p_30_39, "30–39 的 p")
  h04_expect_sig4(h04_band_value(strata, "p_value", "40+"), H04_PIN$p_40p, "40+ 的 p")
})

test_that("三分支之②：任一格 < 30 的帶入表、p 留空並標 insufficient_n，其餘做檢定", {
  strata <- harness_table("marriage_strata")
  recomputed <- h04_recompute(harness_data("analysis"))

  # 分支條件自樣本重算（不從 status 反推）：四格最小者 < 30 即 insufficient_n
  small <- recomputed$min_cell < H04_SMALL_CELL_MIN
  expect_identical(as.character(strata$status), ifelse(small, "insufficient_n", "ok"))
  expect_identical(as.character(strata$band[small]), H04_PIN$insufficient)
  expect_true(all(is.na(strata$p_value[small])), label = "小帶的 p_value 留空")
  expect_false(anyNA(strata$p_value[!small]), label = "其餘各帶皆有 p")

  # 不判失敗：三帶仍在表內、兩組人數與兩率照給（入表而非拒絕）
  expect_identical(as.integer(strata$n[small]), as.integer(H04_PIN$n[match(
    H04_PIN$insufficient, H04_PIN$bands)]))
  expect_false(anyNA(strata$married_rate[small]) || anyNA(strata$single_rate[small]),
               label = "小帶仍給兩組的率")

  # 小格門檻只管婚配四格，不外溢到 age_tests：25–29 的聚合檢定照做
  tests <- harness_table("age_tests", required = c("test", "p_value", "status"))
  expect_false(anyNA(tests$p_value))
})

test_that("三分支之①：帶內已婚為零時 refuse:empty-denominator，三張表皆不寫、已發佈表不變", {
  fixture <- h04_fixture(h04_degenerate_zero_married(2L), tag = "zero_married")
  script <- h04_script(clean_path = fixture)
  before <- h04_published_hash()

  run <- h04_run(script)
  expect_false(is.null(run$error), label = "零格時整支停止")
  stopped <- if (is.null(run$error)) "" else run$error
  expect_match(stopped, "refuse:empty-denominator", fixed = TRUE)
  expect_match(stopped, H04_PIN$bands[2L], fixed = TRUE)
  expect_length(run$tables, 0L)
  expect_identical(h04_published_hash(), before)
})

test_that("負向控制：單身改取 1 時 p 變 0.0024，40+ 因 20 人的小格轉 insufficient_n", {
  run <- h04_run(h04_script(single_values = 1L))
  expect_null(run$error)
  strata <- run$env$strata

  # 30–39：映射一換，p 由 0.02455 變 0.0024（四位有效數字後），證明映射是釘值的承載者
  p_30_39 <- h04_band_value(strata, "p_value", "30-39")
  h04_expect_sig4(p_30_39, H04_PIN$p_30_39_single1, "單身 = 1 時 30–39 的 p")
  expect_false(identical(h04_sig4(p_30_39), h04_sig4(H04_PIN$p_30_39)),
               label = "單身 = 1 時 30–39 的 p 不再是 0.02455")

  # 40+：單身組縮到 63 人，四格 61／54／43／20，20 < 30 → 分支②先於③，p 留空
  recomputed <- h04_recompute(harness_data("analysis"), single_values = 1L)
  cells_40p <- as.integer(unlist(
    recomputed[recomputed$band == "40+", c("cell_married_dropout", "cell_married_grad",
                                           "cell_single_dropout", "cell_single_grad")],
    use.names = FALSE
  ))
  expect_identical(cells_40p, as.integer(c(61L, 54L, 43L, 20L)))
  expect_identical(as.integer(h04_band_value(strata, "single_n", "40+")),
                   as.integer(recomputed$single_n[recomputed$band == "40+"]))
  expect_identical(as.character(h04_band_value(strata, "status", "40+")), "insufficient_n")
  expect_true(is.na(h04_band_value(strata, "p_value", "40+")),
              label = "40+ 轉 insufficient_n，p 留空")

  # 未經門檻的雙尾 Fisher p 即契約所記的 0.0571（四位有效數字為 0.05706）
  h04_expect_sig4(h04_fisher_p(cells_40p), H04_PIN$p_40p_single1,
                  "40+ 未經門檻的雙尾 p")
})

test_that("03_age.R 的一次執行逐位元重建已發佈的三張表", {
  run <- h04_run(h04_program())
  expect_null(run$error)
  expected <- paste0(H04_TABLES, ".csv")
  expect_identical(sort(names(run$tables)), sort(expected))
  expect_identical(unname(run$tables[expected]), unname(h04_published_hash()))
})
