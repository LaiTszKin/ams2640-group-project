# test-06_F6.R — F6（三層的解釋力比較）的性質與斷言（V06，涵蓋 T07 的 seam 05_models.R）
#
# 判定表（抄自 T07 ＋ 修訂 A-23／A-40／A-45／A-46，逐條對應下面每個 test_that）：
#
# | 輸入                          | 前置                 | 結果                                          | 拒絕類別                  | 後置                          |
# | 清洗資料集（3,630／2,828）    | 七欄無缺值、分位表在 | 六列：model／population／n／R²／AUC／機制／否證 | —                        | 表自帶母體與 n；status 全 ok  |
# | 報告值改一位（REPORTED_R2）   | 其餘不動             | 該列 status 轉 mismatch、數值不被改寫          | mismatch（不是拒絕）      | 還原後回到 ok；已發佈表不變   |
# | 年齡帶整欄為常數（不收斂）    | 母體仍 3,630         | 該列 refuse:empty-denominator、其餘五列不變    | refuse:empty-denominator  | 表仍寫出六列                  |
#
# 性質（每條可證偽；括號為對應的 test_that）：
#   P1 六列；(model, population) 配對集合等於六個配對；(model, population) 為唯一鍵
#   P2 逐列 n 與 population 相符，n 合計與 population_ledger.csv 及釘值三方一致
#   P3 R² 逐列在「半個末位」內等於報告值（0.07557／0.2227／0.2011／0.09577／0.2611／0.004952），
#      且等於獨立重算（相對差 ≤ 1e-9）；報告值與程式的 REPORTED_R2 六字串同值
#   P4 年齡帶用四帶參數化（<25 併為一帶）得 0.07557；五帶得 0.08390，兩者不可混用
#   P5 auc 以同一分數與結果獨立重算，逐列相對差 ≤ 1e-9；falsifier 逐列非空且引用表內欄名
#   P6 全 ok 時重跑重現同一張表，且已發佈的 model_comparison.csv 逐位元組不變（sha256）
#   P7 負向控制：REPORTED_R2 改一位 → 該列 mismatch、該列不被寫成 ok、數值未被改寫；
#      還原後六列回到 ok 且與原樣重跑的表相同
#   P8 年齡帶整欄常數 → 年齡帶那一列 refuse:empty-denominator，其餘五列數值不變
#
# 樣本、暫存與輸出根一律取自 helper-harness.R 與 harness-06.R（REQ-A-7）；三種注入
# （清洗資料集、REPORTED_R2、輸出根）都只落在 harness_dir()／harness_out_root() 的
# 暫存副本上，專案的 output/ 與 programs/ 不經手。

# harness-06.R 在載入時把 helper-harness.R 載進**同一個求值環境**（該檔 §0），故
# h06_* 內的 harness_*() 不依賴呼叫端先載入 helper；三種入口（tests/testthat.R、
# test_dir()、test_file()）同一個結果（A-43）。
source(testthat::test_path("harness-06.R"), local = environment())

# 模型的輸入：兩個母體全列（無抽樣）
analysis_frame <- harness_data("analysis")
ability_frame <- harness_data("ability")
# 退化 fixture 的底稿：完整清洗資料集（4,424 列；變異後母體仍須是 3,630）
clean_frame <- harness_data("full")

# 六列的獨立重算只做一次（六個 glm，確定性）；延後到第一次被呼叫時才算，
# 使重算失敗落在測試內而不是檔案層。
recomputed <- local({
  cached <- NULL
  function() {
    if (is.null(cached)) cached <<- h06_recompute(analysis_frame, ability_frame)
    cached
  }
})

flow_started <- Sys.time()

test_that("P1 六列的 (model, population) 配對集合等於契約的六個配對，且配對為唯一鍵", {
  published <- h06_table()

  expect_equal(nrow(published), 6L, label = "比較表為六列")
  expect_true(all(H06_COLUMNS %in% names(published)),
              label = sprintf("八個欄名齊備（實有：%s）", paste(names(published), collapse = ", ")))

  observed <- sort(paste(published$model, published$population, sep = "@"))
  expected <- sort(paste(H06_PAIRS$model, H06_PAIRS$population, sep = "@"))
  expect_identical(observed, expected, label = "配對集合等於六個配對（財務三欄出現兩次）")

  expect_equal(anyDuplicated(paste(published$model, published$population)), 0L,
               label = "(model, population) 為唯一鍵：同一規格在兩個母體各一列")

  # 兩個母體不得被排成單一序列（REQ-F-F6-1 的失效形狀）：母體欄只能取兩個具名值
  expect_setequal(unique(as.character(published$population)), c("analysis", "ability"))
  expect_profile(published, populations = c("analysis", "ability"))
})

test_that("P2 逐列 n 與 population 相符，n 合計與 population_ledger.csv 及釘值三方一致", {
  published <- h06_table()

  for (i in seq_len(nrow(H06_PAIRS))) {
    row <- h06_pick(published, H06_PAIRS$model[i], H06_PAIRS$population[i])
    expect_equal(as.character(row$population), H06_PAIRS$population[i],
                 label = sprintf("%s＠%s 的 population", H06_PAIRS$model[i], H06_PAIRS$population[i]))
    expect_equal(as.numeric(row$n), as.numeric(H06_PAIRS$n[i]),
                 label = sprintf("%s＠%s 的 n", H06_PAIRS$model[i], H06_PAIRS$population[i]))
  }

  # 三個獨立來源：表、母體清冊、契約釘值
  analysis_rows <- published[as.character(published$population) == "analysis", , drop = FALSE]
  ability_rows <- published[as.character(published$population) == "ability", , drop = FALSE]
  expect_equal(unique(as.numeric(analysis_rows$n)), 3630, label = "analysis 四列的 n 皆 3,630")
  expect_equal(unique(as.numeric(ability_rows$n)), 2828, label = "ability 兩列的 n 皆 2,828")
  expect_equal(unique(as.numeric(analysis_rows$n)), h06_ledger_n("analysis"),
               label = "analysis 的 n = 清冊的 analysis n")
  expect_equal(unique(as.numeric(ability_rows$n)), h06_ledger_n("ability"),
               label = "ability 的 n = 清冊的 ability n")

  # 重算的 n 與表必須同值（重算在兩個母體上各取全列）
  model <- recomputed()
  for (i in seq_len(nrow(H06_PAIRS))) {
    expect_equal(as.numeric(h06_pick(model, H06_PAIRS$model[i], H06_PAIRS$population[i])$n),
                 as.numeric(H06_PAIRS$n[i]),
                 label = sprintf("重算的 n：%s＠%s", H06_PAIRS$model[i], H06_PAIRS$population[i]))
  }
})

test_that("P3 六個 R² 逐列在半個末位內等於報告值，且等於獨立重算（1e-9）", {
  published <- h06_table()
  model <- recomputed()

  # 報告值的來源：程式的 REPORTED_R2 六個字串。釘值與常數必須同值——有人改了
  # 常數（例如把 0.004952 寫成 0.0050）這一條就紅，不必等下游表對不上。
  from_source <- h06_reported_from_source()
  expect_identical(from_source, H06_REPORTED,
                   label = "程式的 REPORTED_R2 六字串等於測試端的釘值（A-46）")

  # 精度規則本身（A-40：末位即半個單位）：0.004952 → 5e-7、0.09577 → 5e-6、0.2227 → 5e-5
  expect_equal(h06_precision("0.004952")$tolerance, 5e-7, tolerance = 0, label = "六位小數的容差 5e-7")
  expect_equal(h06_precision("0.09577")$tolerance, 5e-6, tolerance = 0, label = "五位小數的容差 5e-6")
  expect_equal(h06_precision("0.2227")$tolerance, 5e-5, tolerance = 0, label = "四位小數的容差 5e-5")
  expect_equal(vapply(H06_REPORTED, function(txt) h06_precision(txt)$tolerance, numeric(1)),
               H06_TOLERANCE, tolerance = 0, label = "六個報告值各自的容差")

  gaps <- numeric(nrow(H06_PAIRS))
  ratios <- numeric(nrow(H06_PAIRS))
  for (i in seq_len(nrow(H06_PAIRS))) {
    label <- sprintf("%s＠%s", H06_PAIRS$model[i], H06_PAIRS$population[i])
    row <- h06_pick(published, H06_PAIRS$model[i], H06_PAIRS$population[i])
    recomputed_row <- h06_pick(model, H06_PAIRS$model[i], H06_PAIRS$population[i])
    text <- unname(H06_REPORTED[[H06_PAIRS$key[i]]])

    # (1) 表的值在報告值的最後一位上相等
    expect_true(h06_matches(as.numeric(row$mcfadden_r2), text), label = paste0(label, "：R² 在 ", text, " 的末位內"))
    # (2) 表的值等於測試端獨立重算的值
    expect_equal(as.numeric(row$mcfadden_r2), as.numeric(recomputed_row$mcfadden_r2),
                 tolerance = H06_REL_TOL, label = paste0(label, "：表值 = 獨立重算"))
    expect_true(isTRUE(recomputed_row$converged), label = paste0(label, "：重算的 glm 已收斂"))

    gaps[i] <- as.numeric(row$mcfadden_r2) - as.numeric(text)
    ratios[i] <- abs(gaps[i]) / h06_precision(text)$tolerance
  }

  # 每一個報告值都在容差內，且沒有一列是靠「剛好過」活著：最大的 ratio 仍在 1 以下，
  # 而最緊的一列是 ability_quartile（A-46 記錄的值：4.28e-6 對 5e-6）。
  expect_true(all(ratios <= 1), label = "六列的 |差| 皆在各自的半末位容差內")
  tightest <- which.max(ratios)
  expect_identical(H06_PAIRS$key[tightest], "ability_quartile",
                   label = "最緊的一列是 ability_quartile（再改寬一位就轉紅）")
  expect_lt(ratios[tightest], 1)
})

test_that("P4 年齡帶用四帶參數化（0.07557）；五帶為 0.08390，兩者不可混用", {
  published <- h06_table()
  row <- h06_pick(published, "age_band", "analysis")

  four <- h06_age_fit(analysis_frame, H06_AGE_BREAKS_MODEL, H06_AGE_LEVELS_MODEL)
  five <- h06_age_fit(analysis_frame, H06_AGE_BREAKS_AGEGROUP, H06_AGE_LEVELS_AGEGROUP)

  # 兩種參數化的人數切法不同（合計都是 3,630）：不是換標籤，是換分組
  expect_equal(as.numeric(four$n), as.numeric(H06_PIN_AGE_N_MODEL), label = "四帶人數 2654／355／403／218")
  expect_equal(as.numeric(five$n), as.numeric(H06_PIN_AGE_N_AGEGROUP), label = "五帶人數 1621／1033／355／403／218")
  expect_equal(sum(four$n), 3630, label = "四帶合計 3,630")
  expect_equal(sum(five$n), 3630, label = "五帶合計 3,630")

  # 表的那一列是四帶的值（與重算同值），不是五帶的值
  expect_equal(as.numeric(row$mcfadden_r2), as.numeric(four$fit$r2), tolerance = H06_REL_TOL,
               label = "age_band 列的 R² = 四帶重算")
  expect_true(h06_matches(as.numeric(row$mcfadden_r2), "0.07557"), label = "四帶值四位有效數字為 0.07557")

  # 五帶的值：四位有效數字 0.08390，且在報告值的末位規則下**不**等於 0.07557
  expect_identical(h06_sig(five$fit$r2), "0.08390", label = "五帶值四位有效數字為 0.08390")
  expect_false(h06_matches(as.numeric(five$fit$r2), "0.07557"),
               label = "五帶值不得被當成 0.07557（兩種參數化不可混用）")
  expect_gt(abs(as.numeric(five$fit$r2) - as.numeric(row$mcfadden_r2)), 5e-6,
            label = "四帶與五帶的差遠大於半末位容差")
})

test_that("P5 auc 逐列獨立重算（1e-9）；falsifier 逐列非空且引用表內欄名", {
  published <- h06_table()
  model <- recomputed()

  for (i in seq_len(nrow(H06_PAIRS))) {
    label <- sprintf("%s＠%s", H06_PAIRS$model[i], H06_PAIRS$population[i])
    row <- h06_pick(published, H06_PAIRS$model[i], H06_PAIRS$population[i])
    recomputed_row <- h06_pick(model, H06_PAIRS$model[i], H06_PAIRS$population[i])
    expect_equal(as.numeric(row$auc), as.numeric(recomputed_row$auc), tolerance = H06_REL_TOL,
                 label = paste0(label, "：auc = 獨立重算（秩式、同分平均秩）"))
    expect_true(as.numeric(row$auc) > 0.5, label = paste0(label, "：auc 未反向（> 0.5）"))
  }

  # status 全 ok：六列都配適成功且與報告值相符
  expect_identical(unique(as.character(published$status)), "ok", label = "六列 status 全為 ok")

  # falsifier：每列非空、不含 NA／TBD／N/A，且引用至少一個表內欄名（REQ-F-F6-2）
  falsifier <- as.character(published$falsifier)
  expect_false(anyNA(falsifier), label = "falsifier 無缺值")
  expect_true(all(nzchar(trimws(falsifier))), label = "falsifier 逐列非空")
  expect_false(any(grepl("^(NA|TBD|N/A)$", trimws(falsifier))), label = "falsifier 不是 NA／TBD／N/A 佔位")
  expect_true(all(grepl("mcfadden_r2|auc", falsifier)),
              label = "falsifier 逐列引用表內欄名（mcfadden_r2 或 auc）")

  # 機制句：每列非空且互不相同（六列不是同一句話的複本）
  mechanism <- as.character(published$mechanism)
  expect_true(all(nzchar(trimws(mechanism))), label = "mechanism 逐列非空")
  expect_equal(anyDuplicated(mechanism), 0L, label = "六個機制句互不相同")
})

test_that("P6 全 ok 時重跑重現同一張表，且已發佈的 model_comparison.csv 逐位元組不變", {
  published <- h06_table()
  published_path <- h06_published_path()
  sha_before <- h06_sha256(published_path)

  out_root <- harness_out_root()
  withr::defer(unlink(out_root, recursive = TRUE, force = TRUE))

  run <- h06_run(out_root)
  expect_identical(run$status, "ok", label = paste("重跑須成功；實得：", run$error))
  expect_true(run$table_written, label = "重跑寫出 model_comparison.csv")
  expect_lt(run$elapsed, H06_FLOW_LIMIT_SEC, label = "單流程在 120 秒上限內")
  expect_false(is.null(run$comparison), label = "腳本自身環境留有 comparison")

  fresh <- run$comparison
  expect_equal(nrow(fresh), 6L, label = "重跑的表仍為六列")
  expect_identical(as.character(fresh$model), as.character(published$model), label = "重跑的 model 欄逐列相同")
  expect_identical(as.character(fresh$population), as.character(published$population),
                   label = "重跑的 population 欄逐列相同")
  expect_identical(as.numeric(fresh$n), as.numeric(published$n), label = "重跑的 n 欄逐列相同")
  expect_equal(as.numeric(fresh$mcfadden_r2), as.numeric(published$mcfadden_r2), tolerance = 1e-12,
               label = "重跑的 mcfadden_r2 逐列相同（全精度）")
  expect_equal(as.numeric(fresh$auc), as.numeric(published$auc), tolerance = 1e-12,
               label = "重跑的 auc 逐列相同（全精度）")
  expect_identical(as.character(fresh$mechanism), as.character(published$mechanism),
                   label = "重跑的機制句逐字相同")
  expect_identical(as.character(fresh$falsifier), as.character(published$falsifier),
                   label = "重跑的否證條件逐字相同")
  expect_identical(as.character(fresh$status), rep("ok", 6L), label = "重跑的六列 status 全 ok")

  # 已發佈的表：指紋與內容都不變（被測程式的寫入一律落在暫存根）
  expect_identical(h06_sha256(published_path), sha_before, label = "已發佈的 model_comparison.csv sha256 不變")
  expect_identical(h06_table(), published, label = "已發佈的表內容不變")
})

test_that("P7 負向控制：REPORTED_R2 改一位 → 該列 mismatch、不被寫成 ok；還原後回到 ok", {
  published <- h06_table()
  published_path <- h06_published_path()
  sha_before <- h06_sha256(published_path)

  out_root <- harness_out_root()
  withr::defer(unlink(out_root, recursive = TRUE, force = TRUE))

  # (0) 原樣：六列 ok（負向控制的基準）
  pristine <- h06_run(out_root)
  expect_identical(pristine$status, "ok", label = paste("原樣重跑須成功；實得：", pristine$error))
  expect_identical(as.character(pristine$comparison$status), rep("ok", 6L), label = "原樣六列全 ok")

  # (1) 把 admission_quartile 的報告值改**最後一位**（0.004952 → 0.004953）：
  #     差 6.63e-7，大於半末位容差 5e-7。這是「不靠容差活著」的實測——只動一位就轉紅。
  tampered <- h06_run(out_root, reported = c(admission_quartile = "0.004953"))
  expect_identical(tampered$status, "ok", label = paste("注入後腳本仍跑完（mismatch 不是拒絕）；實得：", tampered$error))
  expect_false(is.null(tampered$comparison), label = "注入後仍寫出表")
  expect_true(tampered$table_written, label = "注入後表仍寫出（標 mismatch，不停止寫檔）")

  bad <- h06_pick(tampered$comparison, "admission_quartile", "ability")
  expect_identical(as.character(bad$status), "mismatch", label = "被改的那一列 status 轉 mismatch")
  expect_false(identical(as.character(bad$status), "ok"), label = "該列不得被寫成 ok")

  # 數值不被改寫：表裡仍是算出的值，不是報告的字串
  computed <- as.numeric(h06_pick(published, "admission_quartile", "ability")$mcfadden_r2)
  expect_equal(as.numeric(bad$mcfadden_r2), computed, tolerance = 1e-12,
               label = "mismatch 的那一列仍存算出的值（工具不自改報告、也不改算值）")
  gap <- as.numeric(bad$mcfadden_r2) - 0.004953
  expect_gt(abs(gap), 5e-7, label = "末位差 6.63e-7 越過半末位容差 5e-7")
  expect_lt(abs(gap), 2 * 5e-7, label = "差額不到兩個末位（只改一位，不是另一組規格）")

  # 其餘五列不受影響
  is_bad <- as.character(tampered$comparison$model) == "admission_quartile" &
    as.character(tampered$comparison$population) == "ability"
  others <- as.character(tampered$comparison$status)[!is_bad]
  expect_identical(others, rep("ok", 5L), label = "其餘五列仍為 ok")
  expect_equal(as.numeric(tampered$comparison$mcfadden_r2[!is_bad]),
               as.numeric(published$mcfadden_r2[!is_bad]), tolerance = 1e-12,
               label = "其餘五列的數值不變")

  # (2) 還原（同一份原始碼、同一個輸出根）→ 回到六列 ok，且與原樣重跑的表相同
  restored <- h06_run(out_root)
  expect_identical(restored$status, "ok", label = paste("還原後重跑須成功；實得：", restored$error))
  expect_identical(as.character(restored$comparison$status), rep("ok", 6L), label = "還原後六列回到 ok")
  expect_identical(restored$comparison, pristine$comparison, label = "還原後的表與原樣重跑逐欄相同")

  # 整個過程不碰已發佈的表
  expect_identical(h06_sha256(published_path), sha_before, label = "已發佈的 model_comparison.csv sha256 不變")
})

test_that("P8 年齡帶整欄為常數 → 該列 refuse:empty-denominator，其餘五列數值不變", {
  published <- h06_table()

  # 退化 fixture：年齡整欄設為 20（全落在 <25 一帶）→ 年齡帶因子只有一個水準，
  # glm 配不出對比 → 該列 refuse:empty-denominator。母體界線（3,630）與其餘欄不動，
  # 故分位表的重建核對仍會通過，四列照出。
  fixture <- clean_frame
  fixture[[H06_COL_AGE]] <- 20
  fixture_path <- h06_write_frame(fixture, file.path(harness_dir(), "constant_age.csv"))

  out_root <- harness_out_root()
  withr::defer(unlink(out_root, recursive = TRUE, force = TRUE))

  run <- h06_run(out_root, clean_path = fixture_path)
  expect_identical(run$status, "ok",
                   label = paste("退化 fixture 下腳本仍跑完（單列拒絕，不是整檔停止）；實得：", run$error))
  expect_false(is.null(run$comparison), label = "退化 fixture 下表仍寫出")

  degraded <- run$comparison
  expect_equal(nrow(degraded), 6L, label = "退化 fixture 下表仍為六列")

  age_row <- h06_pick(degraded, "age_band", "analysis")
  expect_identical(as.character(age_row$status), "refuse:empty-denominator",
                   label = "年齡帶那一列 refuse:empty-denominator")
  expect_true(is.na(as.numeric(age_row$mcfadden_r2)), label = "拒絕的那一列不填 R²（不是 0）")
  expect_true(is.na(as.numeric(age_row$auc)), label = "拒絕的那一列不填 auc")

  # 其餘五列的數值與 status 不動：拒絕是逐列的，不是整張表
  for (i in 2:6) {
    label <- sprintf("%s＠%s", H06_PAIRS$model[i], H06_PAIRS$population[i])
    row <- h06_pick(degraded, H06_PAIRS$model[i], H06_PAIRS$population[i])
    baseline <- h06_pick(published, H06_PAIRS$model[i], H06_PAIRS$population[i])
    expect_identical(as.character(row$status), "ok", label = paste0(label, "：其餘列仍為 ok"))
    expect_equal(as.numeric(row$mcfadden_r2), as.numeric(baseline$mcfadden_r2), tolerance = 1e-12,
                 label = paste0(label, "：R² 不變"))
    expect_equal(as.numeric(row$auc), as.numeric(baseline$auc), tolerance = 1e-12,
                 label = paste0(label, "：auc 不變"))
  }
})

test_that("預算：兩個母體全列、無抽樣、無隨機來源（seed 與收縮記 n/a）", {
  expect_equal(sum(H06_SAMPLE_ROWS), 6458, label = "兩個母體合計 3,630 + 2,828 列")
  expect_equal(nrow(analysis_frame), as.numeric(H06_SAMPLE_ROWS[1]), label = "分析母體全列 3,630")
  expect_equal(nrow(ability_frame), as.numeric(H06_SAMPLE_ROWS[2]), label = "能力母體全列 2,828")
  expect_match(H06_SEED_NOTE, "^n/a", label = "無隨機來源：seed 記 n/a")
  expect_match(H06_SHRINK_NOTE, "^n/a", label = "單點注入：收縮記 n/a")
  expect_equal(H06_FLOW_LIMIT_SEC, 120, label = "單流程上限 120 秒")
  expect_equal(H06_RETRIES, 0L, label = "重試 0 次")

  elapsed <- as.numeric(difftime(Sys.time(), flow_started, units = "secs"))
  expect_lt(elapsed, H06_FLOW_LIMIT_SEC, label = "本流程總耗時在單流程上限內")
})
