# test-01_F1.R — F1（環境還原）的模型：REQ-F-F1-1
#
# 判定表逐條落地（T01 的 seam 為 `programs/R/00_setup.R` 與守衛版 `.Rprofile`）：
#
#   性質  輸入／前置                                  結果（拒絕類別）               後置
#   P1    專案根目錄、版本環境已在                    退出碼 0、兩常數為正整數        記錄一段、status: ok
#   P2    副本：守衛版 .Rprofile、activate.R、鎖定檔、  自行還原、退出碼 0              記錄一段 restore
#         入口齊、`renv/library` 為空
#   P3    副本：鎖定檔缺一個套件                      退出碼 1（refuse:unpinned-     記錄一段 refuse、
#                                                    package）                      不產生表
#   P4    一次真實還原的記錄                          三欄齊且形狀正確                刪任一欄→斷言轉假
#   P5    已還原副本再跑一次                          退出碼 0、無操作                記錄追加一段、
#                                                                                   套件數不變
#   P6    副本缺鎖定檔                                啟動守衛即停止、退出碼非 0      不寫記錄
#
# 樣本、種子、暫存與輸出根全部取自 `helper-harness.R` 與 `harness-01.R`（REQ-A-7）；
# 一切注入都在 `harness_dir()` 的副本上做，真實樹的 `output/`、`programs/` 不動。

# 本流程的入口與預算：`harness-0N.R` 不是 testthat 的 helper 慣例檔名（helper 只載入
# `helper-*.R`），故由測試檔顯式載入，路徑以測試台解析、不靠工作目錄。
source(testthat::test_path("harness-01.R"), local = TRUE)

test_that("F1-P1 專案根目錄的具名指令成功結束，兩個母體常數為正整數", {
  out_root <- f1_out_root() # 被測程式碼寫記錄的位置導到暫存根，不動專案 output/
  run <- f1_run(f1_project_root(), out_root = out_root)

  expect_identical(
    run$status, 0L,
    label = sprintf("退出碼為 0（實得 %d；單流程上限 %d 秒）", run$status, run$limit)
  )

  values <- f1_parse_pair(run$output)
  expect_length(values, 2L)
  expect_true(
    length(values) == 2L && all(values > 0L),
    label = sprintf("ANALYSIS_N 與 ABILITY_N 皆為正整數（實得：%s）", paste(values, collapse = " / "))
  )
  # 還原成功不等於常數正確：把 F1 綁回 T01 的閘 G1。
  expect_identical(
    values, unname(F1_PINNED),
    label = sprintf("常數等於釘值 %s", paste(F1_PINNED, collapse = " / "))
  )

  sections <- f1_sections(f1_read_log(out_root))
  expect_identical(length(sections), 1L, label = "這次執行寫了恰好一段記錄")
  if (length(sections)) f1_assert_ok_section(sections[[1L]])
})

test_that("F1-P2 副本缺版本環境時自行還原，記錄一段並成功結束", {
  probe <- f1_restore_probe()
  copy <- probe$copy

  # 前置：副本的樣子就是「專案狀態在、版本環境本體不在」。
  expect_true(
    all(copy$files),
    label = sprintf(
      "副本齊備（缺：%s）", paste(names(copy$files)[!copy$files], collapse = "、")
    )
  )
  expect_true(
    copy$profile_guarded,
    label = "副本的 .Rprofile 為守衛版（自行判斷 library 並呼叫還原，不只 source activate.R）"
  )
  expect_identical(
    length(copy$library_pkgs), 0L,
    label = sprintf("副本的 renv/library 為空（實裝：%s）", paste(copy$library_pkgs, collapse = "、"))
  )

  # 結果：一個 R 指令把環境拉回來並成功結束。
  expect_identical(
    probe$run$status, 0L,
    label = sprintf("副本內退出碼為 0（實得 %d；上限 %d 秒）", probe$run$status, probe$run$limit)
  )

  # 後置：記錄一段，且那一段說自己真的還原過。
  sections <- probe$sections
  expect_identical(length(sections), 1L, label = "這次執行寫了恰好一段記錄")
  if (length(sections)) {
    section <- sections[[1L]]
    f1_assert_log_fields(section)
    expect_identical(
      f1_field(section, "restore_action"), "restore",
      label = "記錄的 restore_action 為 restore（真的還原過，不是只載入）"
    )
    elapsed <- suppressWarnings(as.numeric(f1_field_or_empty(section, "restore_elapsed_sec")))
    expect_true(
      is.finite(elapsed) && elapsed > 0,
      label = sprintf("還原耗時為正（實得 %s 秒）", f1_field_or_empty(section, "restore_elapsed_sec"))
    )
    # 還原後 library 不再是空的，且專案呼叫的套件真的在其中——否則「成功結束」
    # 與「環境可用」是兩件事。
    installed <- f1_library_packages(copy$dir)
    expected_pkgs <- c("renv", "here", "testthat", "PropCIs", "broom")
    expect_true(
      all(expected_pkgs %in% installed),
      label = sprintf(
        "還原後 library 裝了 %d 個套件，含 %s（缺：%s）",
        length(installed), paste(expected_pkgs, collapse = "、"),
        paste(setdiff(expected_pkgs, installed), collapse = "、")
      )
    )
    f1_assert_ok_section(section)
  }
})

test_that("F1-P4 記錄含 R 版本、套件數、還原耗時；刪掉任一欄後斷言轉假（負向控制）", {
  probe <- f1_restore_probe()
  if (!length(probe$sections)) {
    expect_true(FALSE, label = "探針的一次還原留下了一段記錄（沒有記錄則無從檢查三欄）")
    return(invisible(NULL))
  }
  section <- probe$sections[[1L]]

  # 正向：三欄齊、形狀正確。
  f1_assert_log_fields(section)

  # 負向控制一：逐欄刪除，同一個判定必須轉假。
  for (key in F1_LOG_FIELDS) {
    expect_false(
      f1_log_fields_complete(f1_drop_field(section, key)),
      label = sprintf("刪掉 %s 一欄後「三欄齊備」轉假", key)
    )
  }

  # 負向控制二：欄在但值空。弱斷言（只看欄名是否存在）會放過這種記錄。
  blanked <- f1_mask(section, "^restore_elapsed_sec: .*$", "restore_elapsed_sec: ")
  expect_true(
    any(grepl("^restore_elapsed_sec:", blanked)),
    label = "空值反例仍保留欄名（證明它只刪值、不刪欄）"
  )
  expect_false(
    f1_log_fields_shaped(blanked),
    label = "耗時欄有欄名但無值時「形狀正確」轉假"
  )
})

test_that("F1-P5 已還原狀態重跑：記錄追加一段、套件數不變、無操作", {
  probe <- f1_restore_probe()
  copy <- probe$copy
  before <- probe$sections

  rerun <- f1_run(copy$dir)
  expect_identical(
    rerun$status, 0L,
    label = sprintf("重跑退出碼為 0（實得 %d）", rerun$status)
  )

  after <- f1_sections(f1_read_log(rerun$out_root))
  expect_identical(
    length(after), length(before) + 1L,
    label = sprintf("記錄由 %d 段增為 %d 段（追加，不改寫）", length(before), length(after))
  )

  if (length(before) && length(after) > length(before)) {
    first <- before[[1L]]
    last <- after[[length(after)]]
    expect_identical(
      f1_field(last, "package_count"), f1_field(first, "package_count"),
      label = sprintf(
        "套件數不變（首次 %s、重跑 %s）",
        f1_field(first, "package_count"), f1_field(last, "package_count")
      )
    )
    expect_identical(
      f1_field(last, "restore_action"), "none",
      label = "重跑不再還原（restore_action 為 none）"
    )
    expect_identical(
      f1_field(last, "added_on_restore"), "none",
      label = "重跑沒有補件（added_on_restore 為 none）"
    )
    f1_assert_log_fields(last)
    f1_assert_ok_section(last)
  }
})

test_that("F1-P6 副本缺鎖定檔時啟動守衛即停止，且不寫記錄", {
  copy <- f1_copy(lockfile = FALSE)
  expect_false(copy$files[["renv.lock"]], label = "副本確實沒有 renv.lock（前置）")

  run <- f1_run(copy$dir)
  expect_false(run$status == 0L, label = sprintf("退出碼非 0（實得 %d）", run$status))
  expect_true(
    any(grepl("renv.lock 不存在", run$output, fixed = TRUE)),
    label = "訊息說出缺的是鎖定檔，而不是安裝失敗"
  )
  expect_identical(
    length(f1_sections(f1_read_log(run$out_root))), 0L,
    label = "停止發生在入口之前，故沒有寫任何記錄段"
  )
})

test_that("F1-P3 鎖定檔缺套件時以 refuse:unpinned-package 停止，記錄寫明缺哪一個", {
  copy <- f1_copy(drop = "PropCIs")
  run <- f1_run(copy$dir)

  expect_identical(
    run$status, 1L,
    label = sprintf("退出碼為 1（實得 %d）", run$status)
  )
  expect_true(
    any(grepl("refuse:unpinned-package", run$output, fixed = TRUE)),
    label = "錯誤類別為 refuse:unpinned-package"
  )
  expect_true(
    any(grepl("PropCIs", run$output, fixed = TRUE)),
    label = "訊息指名缺的是 PropCIs"
  )

  sections <- f1_sections(f1_read_log(run$out_root))
  expect_identical(length(sections), 1L, label = "拒絕也留下恰好一段記錄")
  if (length(sections)) {
    section <- sections[[1L]]
    expect_identical(
      f1_field(section, "status"), "refuse:unpinned-package",
      label = "記錄的 status 為 refuse:unpinned-package"
    )
    bullets <- f1_bullets(section)
    expect_true(
      any(grepl("PropCIs", bullets, fixed = TRUE)),
      label = sprintf("記錄的拒絕清單指名 PropCIs（清單：%s）", paste(bullets, collapse = " ／ "))
    )
    # 負向控制：把清單裡的名字遮掉，同一條判定轉假。
    expect_false(
      any(grepl("PropCIs", f1_mask(bullets, "PropCIs"), fixed = TRUE)),
      label = "清單未指名時「寫明缺哪一個」轉假"
    )
  }

  # 後置：拒絕時不產生任何表（PRD F1 的 Postcondition）。
  expect_false(
    dir.exists(file.path(run$out_root, "tables")),
    label = sprintf("拒絕後沒有 %s", file.path(basename(run$out_root), "tables"))
  )
})
