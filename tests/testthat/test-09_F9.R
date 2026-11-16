# test-09_F9.R — V09：F9 相關審核 的模型（verification A）
#
# 判定表出處：PRD §4 F9、`REQ-F-F9-1`、修訂 A-24（第五類 weak、BH 家族 = 表列數）、
# 修訂 A-35（以實際欄名指稱四個同代欄）、A-34（准讀母體清冊）、A-8（性質須可證偽，
# 含拒絕分支與負向控制）。生產 seam 為 `programs/R/08_audit.R`，產物為
# `output/tables/correlation_audit.csv`（另有 `.txt` 可讀版與 `logs/08_audit.log`）。
#
# 本檔只做三件事：讀已發佈的表（harness_table()）、拿樣本（harness_data()）、
# 以性質函式（harness-09.R）判紅判綠。不自行讀檔、不設種子、不自建暫存目錄（REQ-A-7）；
# 退化 fixture 與注入只在 harness_dir()／harness_out_root() 的暫存副本上做，
# 不碰 programs/ 與 output/。
#
# 每個 test_that 的標題即判定表的一條性質；負向控制在第 3、7、8 節。

# harness-09.R 不在 testthat 的自動載入清單，先自行定位再載入。
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
    path <- file.path(dir, "harness-09.R")
    if (file.exists(path)) {
      source(path)
      return(invisible(NULL))
    }
  }
  stop("找不到 harness-09.R：請在專案根目錄或 tests/testthat 下執行。", call. = FALSE)
})

# 性質成立 ⇔ 違反清單為空；違反清單的內容即紅燈時要讀的訊息。
expect_holds <- function(violations, label) {
  testthat::expect_equal(
    violations, character(0),
    label = sprintf("%s（違反：%s）", label, if (length(violations)) paste(violations, collapse = "；") else "無"),
    expected.label = "無違反"
  )
}

## 1. 形狀、母體、n 與五類封閉詞彙 ------------------------------------------

test_that("F9 審核表：36 列、population=analysis、n 皆 3,630、verdict 屬五類封閉詞彙", {
  tbl <- harness_table(H09_TABLE)
  expect_profile(tbl)
  expect_holds(h09_violations_shape(tbl, harness_data("analysis")), "形狀、n 與封閉詞彙")
  expect_identical(names(tbl), H09_COLUMNS)
  expect_identical(nrow(tbl), H09_ROWS)
  expect_identical(unique(as.character(tbl$population)), H09_POPULATION)
  expect_identical(unique(as.integer(h09_num(tbl$n))), H09_N)
  expect_identical(sort(unique(as.character(tbl$verdict))), sort(H09_VERDICTS))
  # 樣本預算：分析母體全列，無抽樣。
  expect_identical(nrow(harness_data("analysis")), H09_SAMPLE_ROWS)
})

test_that("F9 判詞分佈：definitional 4／substantive 4／weak 17／noise 8／ecological 3", {
  tbl <- harness_table(H09_TABLE)
  counts <- as.integer(table(factor(as.character(tbl$verdict), levels = H09_VERDICTS)))
  expect_identical(counts, unname(H09_VERDICT_COUNTS))
  # 五類的分界不是裝飾：weak 與 noise 的邊界由 EFFECT_NOISE／EFFECT_MIN 釘住。
  expect_identical(sum(counts), H09_ROWS)
  expect_gt(H09_EFFECT_NOISE, 0)
  expect_gt(H09_EFFECT_MIN, H09_EFFECT_NOISE)
})

## 2. 四個同代欄：definitional 且 in_model=FALSE -----------------------------

test_that("F9 四個同代欄：verdict=definitional、in_model=FALSE、keep=TRUE", {
  tbl <- harness_table(H09_TABLE)
  expect_holds(h09_violations_definitional(tbl), "四個同代欄")
  idx <- match(H09_DEFINITIONAL_COLS, as.character(tbl$variable))
  expect_false(anyNA(idx))
  expect_identical(as.character(tbl$verdict[idx]), rep("definitional", length(H09_DEFINITIONAL_COLS)))
  expect_false(any(tbl$in_model[idx]))
  expect_true(all(tbl$keep[idx]))
  # 三欄短名（pass1／pass2／avg_grade）不是本表的欄名：definitional 以實際欄名指稱。
  expect_length(setdiff(c("pass1", "pass2", "avg_grade"), as.character(tbl$variable)), 3L)
})

## 3. BH：以全部 p_raw、m = 36 重算；Bonferroni 為負向控制 -------------------

test_that("F9 BH：以表中全部 36 個 p_raw 重算，逐列相對差 ≤ 1e-12", {
  tbl <- harness_table(H09_TABLE)
  expect_holds(h09_violations_bh(tbl), "BH 重算")
  expect_holds(h09_violations_bh_family(tbl), "BH 家族大小 = 表列數")
  # 直接對照一次：重算值與表值逐列相等。
  recomputed <- stats::p.adjust(h09_num(tbl$p_raw), method = "BH")
  expect_identical(length(recomputed), H09_ROWS)
  expect_true(all(h09_p_diff(h09_num(tbl$p_bh), recomputed, H09_BH_REL_TOL) == FALSE))
})

test_that("F9 BH 負向控制：改用 Bonferroni 校正後至少 20 列不同（性質會紅）", {
  tbl <- harness_table(H09_TABLE)
  wrong <- h09_violations_bh(tbl, method = "bonferroni")
  expect_gt(length(wrong), 0L)
  expect_gte(h09_mismatch_count(tbl, method = "bonferroni"), H09_BONF_MISMATCH_MIN)
  # 家族大小也要有來源：只用前 6 個 p_raw 的 BH 與表中前 6 列不同（A-24 的舊缺陷）。
  six <- stats::p.adjust(h09_num(tbl$p_raw)[1:6], method = "BH")
  expect_gt(sum(h09_p_diff(h09_num(tbl$p_bh)[1:6], six, H09_BH_REL_TOL)), 0L)
})

## 4. 三個生態謬誤欄 --------------------------------------------------------

test_that("F9 三個生態欄：verdict=ecological、keep/in_model 皆 FALSE；值域九至十、單值數百人共用", {
  tbl <- harness_table(H09_TABLE)
  analysis <- harness_data("analysis")
  expect_holds(h09_violations_ecological(tbl, analysis), "三個生態欄")
  idx <- match(H09_ECOLOGICAL_COLS, as.character(tbl$variable))
  expect_identical(as.character(tbl$verdict[idx]), rep("ecological", length(H09_ECOLOGICAL_COLS)))
  expect_false(any(tbl$keep[idx]))
  expect_false(any(tbl$in_model[idx]))
  levels_obs <- vapply(H09_ECOLOGICAL_COLS, function(v) length(unique(analysis[[v]])), integer(1))
  expect_identical(unname(levels_obs), unname(H09_ECO_LEVELS))
})

## 5. keep 與 in_model 的封閉規則 --------------------------------------------

test_that("F9 keep 8 欄、in_model 4 欄；keep ⇔ definitional|substantive，in_model ⇔ substantive", {
  tbl <- harness_table(H09_TABLE)
  expect_holds(h09_violations_flags(tbl), "keep 與 in_model 規則")
  expect_identical(sum(tbl$keep), H09_KEEP_N)
  expect_identical(sum(tbl$in_model), H09_IN_MODEL_N)
  expect_identical(sort(as.character(tbl$variable[tbl$in_model])), sort(H09_IN_MODEL_VARS))
  # in_model 與 definitional／ecological 不相交（同代與生態欄永不進模型）。
  expect_length(intersect(as.character(tbl$variable[tbl$in_model]), H09_DEFINITIONAL_COLS), 0L)
  expect_length(intersect(as.character(tbl$variable[tbl$in_model]), H09_ECOLOGICAL_COLS), 0L)
})

## 6. 拒絕分支：分母不符 → refuse:input-schema，且不寫表 ---------------------

test_that("F9 拒絕分支：清冊分母 4,424 與常數 3,630 不符 → refuse:input-schema，不寫表", {
  published <- h09_published_paths()
  pub_before <- h09_sha256(published)
  skip_if(anyNA(pub_before), "系統沒有 shasum／sha256sum，無法比對 sha256")

  prior_root <- Sys.getenv("RTOOLKIT_OUT_ROOT", unset = "")
  root <- h09_out_root_with_ledger()
  on.exit({
    if (nzchar(prior_root)) Sys.setenv(RTOOLKIT_OUT_ROOT = prior_root) else Sys.unsetenv("RTOOLKIT_OUT_ROOT")
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  # 退化 fixture：清冊的 analysis 列寫回舊分母 4,424（清冊是輸入登記，A-34 准許直寫暫存副本）。
  bad <- h09_ledger_fixture(harness_dir(), n = 4424L, value = 3630L)
  expect_true(file.copy(bad, file.path(root, "tables", "population_ledger.csv"), overwrite = TRUE))

  run <- h09_run_audit(.harness_clean_path(), root)
  expect_identical(run$outcome, "refuse")
  expect_match(run$message, H09_REFUSE_CATEGORY, fixed = TRUE)
  expect_match(run$message, "分母不符", fixed = TRUE)
  expect_identical(run$retries, 0L)
  expect_lt(run$elapsed, H09_CHILD_LIMIT_SEC)

  # 後置：審核表沒被寫出（不是「寫一張空的」），記錄寫明拒絕類別。
  expect_false(file.exists(file.path(root, "tables", "correlation_audit.csv")))
  log_path <- file.path(root, "logs", "08_audit.log")
  expect_true(file.exists(log_path))
  log_lines <- readLines(log_path, warn = FALSE)
  expect_true(any(grepl("status: refuse:input-schema", log_lines, fixed = TRUE)))
  expect_true(any(grepl("本次未寫出審核表", log_lines, fixed = TRUE)))

  # 專案已發佈的產物完全沒被碰到。
  expect_equal(unname(h09_sha256(published)), unname(pub_before), label = "拒絕後已發佈產物的 sha256")
})

test_that("F9 拒絕分支（資料側）：清洗資料集的分析母體 3,629 ≠ 3,630 → refuse:input-schema", {
  prior_root <- Sys.getenv("RTOOLKIT_OUT_ROOT", unset = "")
  root <- h09_out_root_with_ledger()
  on.exit({
    if (nzchar(prior_root)) Sys.setenv(RTOOLKIT_OUT_ROOT = prior_root) else Sys.unsetenv("RTOOLKIT_OUT_ROOT")
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  # 自全樣本刪去一列退學者：三個結果類別仍在，分析母體因此少一列。
  fixture <- h09_clean_fixture(harness_dir(), function(frame) {
    drop <- which(frame$target == "Dropout")[1L]
    frame[-drop, , drop = FALSE]
  })
  run <- h09_run_audit(fixture, root)
  expect_identical(run$outcome, "refuse")
  expect_match(run$message, H09_REFUSE_CATEGORY, fixed = TRUE)
  expect_match(run$message, "分析母體為 3629 列", fixed = TRUE)
  expect_false(file.exists(file.path(root, "tables", "correlation_audit.csv")))
})

## 7. 拒絕分支的負向控制：真實輸入照樣成功並逐位元組重現 ---------------------

test_that("F9 負向控制：同一支腳本在真實輸入上成功，審核表逐位元組重現且 n=3,630", {
  skip_if(!exists(".harness_clean_path", mode = "function"), "測試台未提供清洗資料集路徑")
  published <- h09_published_paths()
  pub_before <- h09_sha256(published)
  skip_if(anyNA(pub_before), "系統沒有 shasum／sha256sum，無法比對 sha256")

  prior_root <- Sys.getenv("RTOOLKIT_OUT_ROOT", unset = "")
  root <- h09_out_root_with_ledger()
  on.exit({
    if (nzchar(prior_root)) Sys.setenv(RTOOLKIT_OUT_ROOT = prior_root) else Sys.unsetenv("RTOOLKIT_OUT_ROOT")
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  run <- h09_run_audit(.harness_clean_path(), root)
  expect_identical(run$outcome, "ok")
  expect_identical(run$message, "")
  expect_identical(run$retries, 0L)
  expect_lt(run$elapsed, H09_CHILD_LIMIT_SEC)

  written <- file.path(root, "tables", "correlation_audit.csv")
  expect_true(file.exists(written))
  expect_equal(unname(h09_sha256(written)), unname(pub_before[1L]),
               label = "重跑寫出的審核表與已發佈的逐位元組相同")

  # 可讀版存在且自帶母體與 n（TXT 的表頭會寫出暫存清冊路徑，故只比對這一行）。
  txt <- file.path(root, "tables", "correlation_audit.txt")
  expect_true(file.exists(txt))
  expect_true(any(grepl("# population: analysis    n: 3630", readLines(txt, warn = FALSE), fixed = TRUE)))

  log_lines <- readLines(file.path(root, "logs", "08_audit.log"), warn = FALSE)
  expect_true(any(grepl("denominator_check: ok", log_lines, fixed = TRUE)))
  expect_true(any(grepl("status: ok", log_lines, fixed = TRUE)))
  expect_equal(unname(h09_sha256(published)), unname(pub_before), label = "專案產物未被寫入")
})

## 8. 負向控制：每一支性質的 mutant 都必須判紅 ------------------------------

test_that("F9 負向控制：一格被改壞時對應的性質判紅（mutant kill）", {
  tbl <- harness_table(H09_TABLE)
  analysis <- harness_data("analysis")
  def_idx <- match(H09_DEFINITIONAL_COLS, as.character(tbl$variable))
  eco_idx <- match(H09_ECOLOGICAL_COLS, as.character(tbl$variable))

  # M1 分母：第一列 n 由 3,630 改為 3,629。
  m1 <- tbl
  m1$n[1L] <- 3629L
  v1 <- h09_violations_shape(m1, analysis)
  expect_gt(length(v1), 0L, label = paste("M1 分母被改壞：", paste(v1, collapse = "；")))

  # M2 母體標籤：population 寫成 full。
  m2 <- tbl
  m2$population <- "full"
  expect_gt(length(h09_violations_shape(m2, analysis)), 0L, label = "M2 母體標籤被改壞")

  # M3 詞彙外的判詞：第一列 verdict 寫成 pass1（舊短名）。
  m3 <- tbl
  m3$verdict[1L] <- "pass1"
  expect_gt(length(h09_violations_shape(m3, analysis)), 0L, label = "M3 判詞超出封閉詞彙")

  # M4 同代欄被標進模型：cu1 approved 的 in_model 改為 TRUE。
  m4 <- tbl
  m4$in_model[def_idx[1L]] <- TRUE
  v4 <- h09_violations_definitional(m4)
  expect_gt(length(v4), 0L, label = paste("M4 同代欄進模型：", paste(v4, collapse = "；")))
  expect_gt(length(h09_violations_flags(m4)), 0L, label = "M4 亦破壞 in_model 規則")

  # M5 同代欄被判成別類：cu2 grade 的 verdict 改為 substantive。
  m5 <- tbl
  m5$verdict[def_idx[4L]] <- "substantive"
  expect_gt(length(h09_violations_definitional(m5)), 0L, label = "M5 同代欄判詞被改壞")

  # M6 BH 被換成 Bonferroni：p_bh 整欄改寫。
  m6 <- tbl
  m6$p_bh <- stats::p.adjust(h09_num(tbl$p_raw), method = "bonferroni")
  v6 <- h09_violations_bh(m6)
  expect_gt(length(v6), 0L, label = paste("M6 BH 被換成 Bonferroni：", paste(v6, collapse = "；")))

  # M7 家族縮回 6：前 6 列的 p_bh 改用「只用這 6 個 p_raw」的 BH。
  m7 <- tbl
  m7$p_bh[1:6] <- stats::p.adjust(h09_num(tbl$p_raw)[1:6], method = "BH")
  expect_gt(length(h09_violations_bh_family(m7)), 0L, label = "M7 家族大小被縮成 6")

  # M8 生態欄被判成 weak（年度值被當成個人層變數）。
  m8 <- tbl
  m8$verdict[eco_idx[1L]] <- "weak"
  v8 <- h09_violations_ecological(m8, analysis)
  expect_gt(length(v8), 0L, label = paste("M8 生態欄判詞被改壞：", paste(v8, collapse = "；")))

  # M9 生態欄被保留：keep 改為 TRUE。
  m9 <- tbl
  m9$keep[eco_idx[2L]] <- TRUE
  expect_gt(length(h09_violations_ecological(m9, analysis)), 0L, label = "M9 生態欄被保留")

  # M10 keep 與判詞不一致：第一列 keep 反轉。
  m10 <- tbl
  m10$keep[1L] <- !m10$keep[1L]
  expect_gt(length(h09_violations_flags(m10)), 0L, label = "M10 keep 與判詞不一致")

  # 原始表未被上述操作改動（mutant 都在副本上做）。
  expect_identical(as.character(tbl$verdict)[1L], "weak")
  expect_identical(sum(tbl$in_model), H09_IN_MODEL_N)
})
