#!/usr/bin/env Rscript
# tests/testthat.R — 測試入口
#
# 用法：在專案根目錄（或任何位置）執行 `Rscript tests/testthat.R`。
# 樣本、種子、暫存與輸出根一律由 `tests/testthat/helper-harness.R` 提供；
# 任何測試檔不得自行讀檔、自設種子或自建暫存目錄（REQ-A-7）。
#
# 入口選哪一個 runner：`testthat::test_local()` 需要套件根（DESCRIPTION），
# 本專案不是 R 套件，故今日走等價的 `testthat::test_dir()`；兩者都載入同一個
# helper 並把工作目錄設在 tests/testthat，測試台的行為相同。專案日後加上
# DESCRIPTION 時，上面那一支即自動接手，契約所寫的 test_local() 隨即可用。

root <- local({
  # 入口檔自身的位置決定專案根：--file= 由 Rscript 提供，互動 source 時退回工作目錄。
  entry <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  start <- if (length(entry)) dirname(sub("^--file=", "", entry[[1]])) else getwd()
  normalizePath(file.path(start, ".."), winslash = "/", mustWork = FALSE)
})

# 測試台自我檢查（A-36）：先 harness_out_root() 再 harness_table() 必須仍讀到
# PROJ_ROOT/output/tables 的已發佈表，且專案的 output/ 未被寫入。這條回歸若成立，
# 在入口就以 status 1 停下，不讓測試跑起來才發現「取根與讀表互斥」。
source(file.path(root, "tests", "testthat", "helper-harness.R"))
self_check <- harness_self_check()
message(sprintf(
  "harness 自我檢查通過：out_root→table 仍讀 %s（%d 列），暫存根的同名誘餌表未被讀取",
  sub(paste0(root, "/"), "", self_check$table, fixed = TRUE), self_check$rows
))

results <- if (file.exists(file.path(root, "DESCRIPTION"))) {
  testthat::test_local(path = root, reporter = "summary")
} else {
  # 零個測試檔不算綠：明確停下並指名原因，不讓 exit 0 冒充「跑過了」。
  if (!length(list.files(file.path(root, "tests", "testthat"), pattern = "^test.*[.][Rr]$"))) {
    stop(
      "tests/testthat 尚無 test-*.R：測試台已就位，測試檔由驗證任務（V01–V11）交付；",
      "本次沒有任何測試被執行。",
      call. = FALSE
    )
  }
  testthat::test_dir(file.path(root, "tests", "testthat"), reporter = "summary")
}

summary_df <- as.data.frame(results)
if (nrow(summary_df) && (any(summary_df$failed > 0L) || any(summary_df$error))) {
  quit(save = "no", status = 1L)
}
