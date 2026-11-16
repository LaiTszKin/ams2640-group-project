# test-05_F5.R — V05：F5 能力層 的模型（verification A）
#
# 判定表出處：PRD §4 F5、`REQ-F-F5-1`、`REQ-F-F5-2`、`A-8`（性質須可證偽，含拒絕分支與
# 負向控制）。生產 seam 為 `programs/R/04_ability.R`，產物為
# `output/tables/ability_quartiles.csv` 與 `output/tables/ability_transitions.csv`。
#
# 本檔只做三件事：讀已發佈的表（harness_table()）、拿樣本（harness_data()）、
# 以性質函式（harness-05.R）判紅判綠。不自行讀檔、不設種子、不自建暫存目錄（REQ-A-7）；
# 退化 fixture 與注入只在 harness_dir() 的暫存副本上做，不碰 programs/ 與 output/。
#
# 每個 test_that 的標題即判定表的一條性質；負向控制在各節末與專節。

# harness-05.R 不在 testthat 的自動載入清單，先自行定位再載入。
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
    path <- file.path(dir, "harness-05.R")
    if (file.exists(path)) {
      source(path)
      return(invisible(NULL))
    }
  }
  stop("找不到 harness-05.R：請在專案根目錄或 tests/testthat 下執行。", call. = FALSE)
})

# 性質成立 ⇔ 違反清單為空；違反清單的內容即紅燈時要讀的訊息。
expect_holds <- function(violations, label) {
  testthat::expect_equal(
    violations, character(0),
    label = sprintf("%s（違反：%s）", label, if (length(violations)) paste(violations, collapse = "；") else "無"),
    expected.label = "無違反"
  )
}

## 1. 分位表：四組各 707、母體 2,828 ---------------------------------------

test_that("F5 分位表：四組各 707 人、母體 2,828、欄位自帶母體與 n", {
  quart <- harness_table(H05_QUARTILE_TABLE)
  expect_profile(quart)
  expect_holds(h05_violations_quartile_shape(quart), "分位表形狀與人數")
  expect_identical(as.integer(h05_num(quart$n)), H05_QUARTILE_N)
  expect_identical(sum(as.integer(h05_num(quart$n))), H05_ABILITY_N)
  # 樣本預算：能力母體全列，無抽樣。
  expect_identical(nrow(harness_data("ability")), H05_SAMPLE_ROWS)
})

## 2. 畢業率：四位有效數字、整數計數、首尾差 --------------------------------

test_that("F5 畢業率：0.5177、0.7694、0.8388、0.8925（四位有效數字）", {
  quart <- harness_table(H05_QUARTILE_TABLE)
  expect_holds(h05_violations_rates(quart), "畢業率")
  expect_rate_equal(signif(h05_num(quart$graduation_rate), 4L), H05_RATES_4SF)
  # 畢業率必為已畢業 ÷（已畢業 + 已退學）：此處以「整數畢業人數 ÷ 該組人數」的可觀測形狀釘住。
  expect_identical(as.integer(round(h05_num(quart$graduation_rate) * h05_num(quart$n))), H05_GRADUATES)
})

## 3. 切法被釘住：等量切組，不是 quantile() 切點 ----------------------------

test_that("F5 切法：等量切組重算為 707×4；分位數切點法的 707/739/680/702 與本表不符", {
  quart <- harness_table(H05_QUARTILE_TABLE)
  ability <- harness_data("ability")
  analysis <- harness_data("analysis")
  expect_holds(h05_violations_split(ability, analysis, quart), "切法")
  # 反事實必須真的不同，否則這一節失去區辨力（負向控制 1）。
  expect_false(identical(H05_QUANTILE_CUT_N, H05_QUARTILE_N))
  expect_gte(sum(abs(H05_QUANTILE_CUT_N - H05_QUARTILE_N)), 2L * 32L)
})

## 4. 移動表：5 列 × 4 欄共 20 格 ------------------------------------------

test_that("F5 移動表：5 列 × 4 個計數欄共 20 格，列序 q1–q4 與 missing_sem1", {
  trans <- harness_table(H05_TRANSITION_TABLE)
  expect_profile(trans)
  expect_holds(h05_violations_transition_cells(trans), "移動表 20 格")
  expect_identical(length(h05_cell_matrix(trans)), H05_CELLS)
  expect_identical(rownames(h05_cell_matrix(trans)), H05_FROM_LEVELS)
})

## 5. 對角線與缺第一學期成績列 ----------------------------------------------

test_that("F5 移動表：對角線 396/285/313/477；missing_sem1 列 13/7/3/3 合計 26", {
  trans <- harness_table(H05_TRANSITION_TABLE)
  expect_holds(h05_violations_diagonal_and_missing(trans), "對角線與缺列")
  expect_identical(as.integer(diag(h05_cell_matrix(trans))), H05_DIAGONAL)
  expect_identical(as.integer(h05_cell_matrix(trans)[H05_MISSING_LABEL, ]), H05_MISSING_CELLS)
  expect_identical(sum(h05_cell_matrix(trans)[H05_MISSING_LABEL, ]), H05_MISSING_N)
})

## 6. 邊際：四個 quartile 列 2,802，四個欄各 707 -----------------------------

test_that("F5 移動表邊際：四列合計 2,802、四欄各 707、20 格合計 2,828", {
  quart <- harness_table(H05_QUARTILE_TABLE)
  trans <- harness_table(H05_TRANSITION_TABLE)
  expect_holds(h05_violations_margins(quart, trans), "邊際")
  m <- h05_cell_matrix(trans)
  expect_identical(as.integer(rowSums(m[seq_len(H05_GROUPS), ])), H05_ROW_TOTALS[seq_len(H05_GROUPS)])
  expect_identical(as.integer(sum(rowSums(m[seq_len(H05_GROUPS), ]))), H05_NAMED_ROWS_N)
  expect_identical(as.integer(colSums(m)), H05_COL_TOTALS)
  expect_identical(length(m), H05_CELLS)
})

## 7. 拒絕分支：剔除後母體為零 ----------------------------------------------

test_that("F5 拒絕分支：剔除後母體為零 → refuse:empty-denominator，兩表 sha256 不變", {
  published <- h05_published_paths()
  pub_before <- h05_sha256(published)
  skip_if(anyNA(pub_before), "系統沒有 shasum／sha256sum，無法比對 sha256")

  prior_root <- Sys.getenv("RTOOLKIT_OUT_ROOT", unset = "")
  root <- h05_seeded_out_root()
  on.exit({
    if (nzchar(prior_root)) Sys.setenv(RTOOLKIT_OUT_ROOT = prior_root) else Sys.unsetenv("RTOOLKIT_OUT_ROOT")
    unlink(root$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  before <- h05_sha256(root$tables)
  expect_equal(unname(before), unname(pub_before), label = "暫存根的副本即已發佈的位元組")

  # 退化 fixture：分析母體仍在（3,630 人），但第二學期成績全為零 → 剔除後母體 0。
  fixture <- h05_clean_fixture(harness_dir(), function(frame) {
    frame[[H05_SEM2_COL]] <- 0
    frame
  })
  script <- h05_injected_script(harness_dir(), fixture)
  run <- h05_run_ability(script, root$root)

  expect_identical(run$outcome, "refuse")
  expect_match(run$message, H05_REFUSE_CATEGORY, fixed = TRUE)
  expect_match(run$message, "母體為 0 人", fixed = TRUE)
  expect_identical(run$retries, 0L)
  expect_lt(run$elapsed, H05_CHILD_LIMIT_SEC)

  # 後置：兩張表的 sha256 皆不變（不是「重寫成空表」）。
  after <- h05_sha256(root$tables)
  expect_equal(unname(after), unname(before), label = "拒絕後兩表 sha256")
  # 且專案的已發佈表完全沒被碰到（輸出根指到暫存，prd §3 的後置）。
  expect_equal(unname(h05_sha256(published)), unname(pub_before), label = "專案 output/tables 未被寫入")
})

test_that("F5 拒絕分支的負向控制：同一注入在真實輸入上成功，且兩表逐位元組重現", {
  skip_if(!exists(".harness_clean_path", mode = "function"), "測試台未提供清洗資料集路徑")
  published <- h05_published_paths()
  pub_before <- h05_sha256(published)
  skip_if(anyNA(pub_before), "系統沒有 shasum／sha256sum，無法比對 sha256")

  prior_root <- Sys.getenv("RTOOLKIT_OUT_ROOT", unset = "")
  root <- h05_seeded_out_root()
  on.exit({
    if (nzchar(prior_root)) Sys.setenv(RTOOLKIT_OUT_ROOT = prior_root) else Sys.unsetenv("RTOOLKIT_OUT_ROOT")
    unlink(root$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  # 同一支注入腳本、只把輸入換成真實的清洗資料集：若照樣拒絕，表示拒絕不是 fixture 造成的。
  script <- h05_injected_script(harness_dir(), .harness_clean_path())
  run <- h05_run_ability(script, root$root)
  expect_identical(run$outcome, "ok")
  expect_identical(run$message, "")
  expect_equal(unname(h05_sha256(root$tables)), unname(pub_before),
               label = "重跑寫出的兩表與已發佈的逐位元組相同")
})

## 8. 負向控制：每一支性質的 mutant 都必須判紅 ------------------------------

test_that("F5 負向控制：一格被改壞時對應的性質判紅（mutant kill）", {
  quart <- harness_table(H05_QUARTILE_TABLE)
  trans <- harness_table(H05_TRANSITION_TABLE)

  # M1 人數：q2 由 707 改為 706。
  m1 <- h05_mutant_quartiles(quart, n = c(707L, 706L, 707L, 707L))
  v1 <- h05_violations_quartile_shape(m1)
  expect_gt(length(v1), 0L, label = paste("M1 人數被改壞：", paste(v1, collapse = "；")))

  # M2 畢業率：q1 由 0.5177 改為 0.5180（第四位有效數字起變）。
  m2 <- h05_mutant_quartiles(quart, rate = c(0.5180, quart$graduation_rate[-1L]))
  v2 <- h05_violations_rates(m2)
  expect_gt(length(v2), 0L, label = paste("M2 畢業率被改壞：", paste(v2, collapse = "；")))

  # M3 切法：把分位表換成分位數切點法的人數。
  m3 <- h05_mutant_quartiles(quart, n = H05_QUANTILE_CUT_N)
  v3 <- h05_violations_split(harness_data("ability"), harness_data("analysis"), m3)
  expect_gt(length(v3), 0L, label = paste("M3 切法被換成 quantile()：", paste(v3, collapse = "；")))

  # M4 一格：q2→to_q2 由 285 改為 209（整列搬移的典型錯誤）。
  m4 <- h05_mutant_transitions(trans, cell = c(2L, 2L), cell_value = 209L)
  v4 <- h05_violations_transition_cells(m4)
  expect_gt(length(v4), 0L, label = paste("M4 一格被改壞：", paste(v4, collapse = "；")))
  expect_gt(length(h05_violations_diagonal_and_missing(m4)), 0L, label = "M4 亦破壞對角線")

  # M5 缺列：刪掉 missing_sem1 列（4 列退化表）。
  m5 <- h05_mutant_transitions(trans, drop_missing = TRUE)
  v5 <- h05_violations_diagonal_and_missing(m5)
  expect_gt(length(v5), 0L, label = paste("M5 缺列被刪：", paste(v5, collapse = "；")))

  # M6 邊際：q4 列一格 +1、同列另一格 −1；20 格合計不變，只有欄邊際壞掉。
  m6 <- h05_mutant_transitions(trans, shift_margin = TRUE)
  v6 <- h05_violations_margins(quart, m6)
  expect_gt(length(v6), 0L, label = paste("M6 邊際被移走：", paste(v6, collapse = "；")))
  expect_identical(sum(h05_cell_matrix(m6)), H05_ABILITY_N)
  expect_false(identical(as.integer(colSums(h05_cell_matrix(m6))), H05_COL_TOTALS))

  # M7 母體標籤：population 寫成 full（表不再自帶正確母體）。
  m7 <- quart
  m7$population <- "full"
  expect_gt(length(h05_violations_quartile_shape(m7)), 0L, label = "M7 母體標籤被改壞")
})
