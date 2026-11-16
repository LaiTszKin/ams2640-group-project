# test-02_F2.R — F2（母體）的模型與斷言（V02）
#
# Covers: T02（模型閘 G1 之後）。Requirement: REQ-F-F2-1（清冊九列、3,630 與 2,828）、
# REQ-F-F2-2（原始資料的校驗值前後相同）、REQ-F-F2-3（欄數或類別不符時清冊不更新）。
#
# 交界契約（REQ-A-7）：本檔只呼叫 helper-harness.R 的具名函式（harness_data／
# harness_dir／harness_out_root／harness_table／harness_seed／expect_rate_equal／
# expect_profile）與 harness-02.R 的入口。樣本、種子、暫存與輸出根一律由 helper 提供；
# 本檔不含 read.*／set.seed／tempdir。注入只在 harness_dir() 的暫存副本上做，
# 不改 data/raw，也不改 programs/。
#
# 每條性質都可證偽：釘值來自 T02 的判定表，拒絕分支以注入觸發，最後以「原始資料與
# data/processed 的指紋回到開跑前」收尾——拒絕分支一旦走到底就會覆寫 data/processed，
# 那一條因此同時是「沒有越線」的證據。

source(testthat::test_path("harness-02.R"), local = TRUE)

# 開跑前先取指紋：本檔最後一條斷言要比對的就是這兩個值。
f2_raw_sha_before <- f2_sha256(f2_raw_path())
f2_processed_before <- f2_processed_shas()

## 1. 清冊的九列 ----------------------------------------------------------

test_that("清冊九列：(population, metric) 逐列釘值", {
  ledger <- f2_ledger()

  expect_equal(nrow(ledger), nrow(F2_PINS))
  expect_identical(as.character(ledger$population), F2_PINS$population)
  expect_identical(as.character(ledger$metric), F2_PINS$metric)
  expect_equal(as.integer(ledger$n), F2_PINS$n)
  expect_equal(as.integer(ledger$value), F2_PINS$value)

  # 整欄相等之外再逐列唸一次：紅燈時要看得出是哪一個 (population, metric) 壞掉。
  for (i in seq_len(nrow(F2_PINS))) {
    expect_equal(
      as.integer(ledger$value[[i]]), F2_PINS$value[[i]],
      label = sprintf("第 %d 列 %s/%s 的值", i, F2_PINS$population[[i]], F2_PINS$metric[[i]])
    )
  }

  # §3 不變量：每一列自帶母體與 n，population 取三個具名值，n 為非負整數。
  expect_profile(ledger)
})

test_that("清冊的九個值與清洗資料集的重算逐列相等", {
  ledger <- f2_ledger()
  recomputed <- f2_populations()

  expect_identical(as.character(recomputed$metric), F2_PINS$metric)
  expect_equal(as.integer(recomputed$value), as.integer(ledger$value),
               label = "重算值與清冊值（同一列的兩個來源）")
})

## 2. analysis 與 ability 分屬兩列 -----------------------------------------

test_that("analysis 與 ability 分屬兩列；ability 為分析母體 ∩ 第二學期成績 > 0", {
  ledger <- f2_ledger()
  analysis_row <- ledger[ledger$population == "analysis" & ledger$metric == "analysis", , drop = FALSE]
  ability_row <- ledger[ledger$population == "ability" & ledger$metric == "ability", , drop = FALSE]

  expect_equal(nrow(analysis_row), 1L)
  expect_equal(nrow(ability_row), 1L)
  # 兩者是不同的列，不是同一個數字換名字
  expect_false(any(ledger$population == "analysis" & ledger$metric == "ability"))
  expect_false(any(ledger$population == "ability" & ledger$metric == "analysis"))

  # 交集事實：全樣本 3,554 人有第二學期成績，交集後 2,828 人，差額 726 人全為在讀者。
  basis <- f2_ability_basis()
  expect_equal(basis$scored_full, F2_SCORED_FULL_N, label = "全樣本上第二學期成績 > 0 的人數")
  expect_equal(basis$ability, F2_ABILITY_N, label = "能力母體（交集）")
  expect_equal(basis$gap, F2_SCORED_ANALYSIS_GAP, label = "差額")
  expect_identical(basis$outside_results, "Enrolled", label = "差額的結果類別")
  expect_equal(as.integer(ability_row$value), basis$ability)

  # 分析母體加上在讀者回到全樣本：3,630 + 794 = 4,424
  expect_equal(as.integer(analysis_row$value) + F2_ENROLLED_N, F2_TOTAL_N)
})

## 3. SAS 兩式的讀回 ------------------------------------------------------

test_that("SAS 兩式以 haven 讀回：4,424 × 37，結果欄為字元且類別集合為三值", {
  for (fmt in c("sas", "xpt")) {
    data <- f2_sas(fmt)

    expect_equal(dim(data), c(F2_TOTAL_N, F2_EXPECTED_COLS), label = paste0(fmt, " 的維度"))
    expect_true(F2_RESULT_COL %in% names(data), label = paste0(fmt, " 含結果欄 target"))
    expect_true(is.character(data[[F2_RESULT_COL]]),
                label = paste0(fmt, " 的結果欄為字元（不是數值碼或 factor）"))
    expect_setequal(unique(as.character(data[[F2_RESULT_COL]])), F2_RESULTS)
  }

  # 兩式是同一份資料的兩個容器：欄名逐字相同，列數相同
  expect_identical(names(f2_sas("sas")), names(f2_sas("xpt")))
})

## 4. 原始資料的校驗值 ----------------------------------------------------

test_that("原始資料的 sha256 等於釘值（REQ-F-F2-2）", {
  expect_identical(f2_sha256(f2_raw_path()), F2_RAW_SHA256)
  expect_identical(f2_raw_sha_before, F2_RAW_SHA256)
})

## 5. 預算 ----------------------------------------------------------------

test_that("預算：三個母體全列、無隨機來源、重試 0 次", {
  budget <- f2_budget()

  expect_equal(unname(budget$rows), c(F2_TOTAL_N, F2_ANALYSIS_N, F2_ABILITY_N))
  expect_identical(budget$seed, "n/a（無隨機來源；harness_seed() 未被呼叫）")
  expect_identical(budget$retries, 0L)
  expect_equal(budget$flow_seconds, F2_FLOW_SECONDS)
})

## 6. 拒絕分支（注入只在暫存副本上）---------------------------------------

test_that("輸出根指進原始資料目錄 → refuse:readonly-target，副本逐位元組不變", {
  # 原始資料形狀的暫存副本；把它的目錄當輸出根，等於「把輸出根指向 data/raw」。
  fixture <- f2_raw_fixture()
  raw_dir <- dirname(fixture)
  withr::defer(unlink(raw_dir, recursive = TRUE, force = TRUE))

  files_before <- sort(list.files(raw_dir, recursive = TRUE, all.files = TRUE))
  fixture_sha_before <- f2_sha256(fixture)

  result <- f2_run(fixture, raw_dir)

  expect_false(identical(result$status, 0L), label = "結束碼非 0")
  expect_true(f2_refused(result, "readonly-target"), label = "拒絕類別")
  # 拒絕的後置：原始資料未變動，目錄裡也沒有留下任何產物（含 00_setup 的交棒記錄）
  expect_identical(f2_sha256(fixture), fixture_sha_before, label = "原始資料副本的 sha256")
  expect_identical(sort(list.files(raw_dir, recursive = TRUE, all.files = TRUE)), files_before,
                   label = "原始資料目錄的檔案清單")
  expect_false(file.exists(result$table), label = "暫存根上沒有清冊")
  expect_lt(result$elapsed, F2_FLOW_SECONDS)
})

# 上面那條注入的是「輸出根＝副本目錄本身」，故 `dir.create(recursive = TRUE)` 的殘留會以
# 「多一個子目錄」的形式出現在同一個列舉裡。A-48 補的兩條測的是另一種形狀：輸出根是 raw
# 下**尚未存在**的目標（子目錄、或經符號連結指進去的路徑）。這兩條不以「目錄裡有沒有多
# 檔案」收尾，而以「被保護目錄的列舉前後逐行相同」與「該子目錄根本不存在」收尾——只驗
# 有沒有寫檔，會漏掉建目錄這一類殘留。

test_that("輸出根為原始資料目錄下尚未存在的子目錄 → refuse:readonly-target，且拒絕後未建出它", {
  fixture <- f2_raw_fixture()
  raw_dir <- dirname(fixture)
  withr::defer(unlink(raw_dir, recursive = TRUE, force = TRUE))

  target <- file.path(raw_dir, "sub")
  # 起點先釘住：若 sub 事先存在，後面的 expect_false() 就恆假，這條注入證明不了任何事。
  expect_false(dir.exists(target), label = "注入前 raw 下的 sub 不存在")
  files_before <- sort(list.files(raw_dir, all.files = TRUE))

  result <- f2_run(fixture, target, allow_absent_out_root = TRUE)

  expect_false(identical(result$status, 0L), label = "結束碼非 0")
  expect_true(f2_refused(result, "readonly-target"), label = "拒絕類別")
  # 拒絕的後置（A-48 的第二段）：00_setup.R 的 dir.create(OUT_ROOT/logs) 若跑在守衛之前，
  # 這裡就會長出 sub（連同 sub/logs、sub/tables），即使一個檔案都沒寫。
  expect_false(dir.exists(target), label = "拒絕後 raw 下的 sub 未被建立")
  expect_identical(sort(list.files(raw_dir, all.files = TRUE)), files_before,
                   label = "原始資料目錄的列舉（含 all.files）")
  expect_false(file.exists(result$table), label = "子目錄上沒有清冊")
  expect_lt(result$elapsed, F2_FLOW_SECONDS)
})

test_that("輸出根經符號連結指進原始資料目錄 → refuse:readonly-target，且列舉逐行相同", {
  fixture <- f2_raw_fixture()
  raw_dir <- dirname(fixture)
  link_root <- harness_dir()
  withr::defer(unlink(raw_dir, recursive = TRUE, force = TRUE))
  withr::defer(unlink(link_root, recursive = TRUE, force = TRUE))

  # 連結放在另一個暫存目錄裡，指回原始資料副本的目錄：out_root 的字面拼法不含 raw_dir，
  # 只有解開連結之後才落在裡面。判定若只比字串，這條就會走到底。
  link <- file.path(link_root, "raw_link")
  expect_true(file.symlink(raw_dir, link), label = "符號連結已建立（否則本條測不到東西）")

  files_before <- sort(list.files(raw_dir, all.files = TRUE))
  # 拒絕訊息印的是**實體**目錄（§0 先解連結再比），故比對時也取實體路徑：
  # macOS 的 TMPDIR 是 /var → /private/var，字面拼法與實體拼法不同。
  raw_dir_real <- normalizePath(raw_dir, winslash = "/", mustWork = TRUE)
  result <- f2_run(fixture, file.path(link, "tables"), allow_absent_out_root = TRUE)

  expect_false(identical(result$status, 0L), label = "結束碼非 0")
  expect_true(f2_refused(result, "readonly-target"), label = "拒絕類別")
  expect_true(any(grepl(raw_dir_real, result$output, fixed = TRUE)),
              label = "拒絕訊息指名實體路徑（不是連結的拼法）")
  # 拒絕的後置：經連結寫入＝寫進 raw 本身，故列舉的任何一項變化（含 .DS_Store、空目錄）
  # 都算越線。
  expect_identical(sort(list.files(raw_dir, all.files = TRUE)), files_before,
                   label = "原始資料目錄的列舉（含 all.files）")
  expect_false(dir.exists(file.path(link, "logs")), label = "經連結的 logs 未被建立")
  expect_false(file.exists(result$table), label = "經連結的路徑上沒有清冊")
  expect_lt(result$elapsed, F2_FLOW_SECONDS)
})

test_that("欄數改為 36 → refuse:input-schema，清冊 sha256 不變（REQ-F-F2-3）", {
  full <- harness_data("full")
  expect_equal(ncol(full), F2_EXPECTED_COLS)

  out_root <- harness_out_root()
  withr::defer(unlink(out_root, recursive = TRUE, force = TRUE))
  ledger_sha_before <- f2_sha256(f2_published_ledger_path())

  # 少一欄：36 個變數加結果欄的契約不成立
  fixture <- f2_raw_fixture(function(frame) {
    frame[, setdiff(names(frame), "Unemployment rate"), drop = FALSE]
  })
  result <- f2_run(fixture, out_root)

  expect_false(identical(result$status, 0L), label = "結束碼非 0")
  expect_true(f2_refused(result, "input-schema"), label = "拒絕類別")
  expect_true(any(grepl("欄數為 36", result$output, fixed = TRUE)),
              label = "拒絕訊息指名實測欄數")
  expect_false(file.exists(result$table), label = "暫存根上沒有清冊")
  expect_identical(f2_sha256(f2_published_ledger_path()), ledger_sha_before,
                   label = "專案清冊的 sha256")
})

test_that("結果欄出現第四類 → refuse:input-schema，清冊 sha256 不變（REQ-F-F2-3）", {
  out_root <- harness_out_root()
  withr::defer(unlink(out_root, recursive = TRUE, force = TRUE))
  ledger_sha_before <- f2_sha256(f2_published_ledger_path())

  fixture <- f2_raw_fixture(function(frame) {
    frame[[F2_RESULT_COL]][1L] <- "Withdrawn"   # 第四類：不在 Graduate／Dropout／Enrolled 之內
    frame
  })
  result <- f2_run(fixture, out_root)

  expect_false(identical(result$status, 0L), label = "結束碼非 0")
  expect_true(f2_refused(result, "input-schema"), label = "拒絕類別")
  expect_true(any(grepl("Withdrawn", result$output, fixed = TRUE)),
              label = "拒絕訊息指名多出的類別")
  expect_false(file.exists(result$table), label = "暫存根上沒有清冊")
  expect_identical(f2_sha256(f2_published_ledger_path()), ledger_sha_before,
                   label = "專案清冊的 sha256")
})

test_that("缺值超出 MISSING_PROFILE → refuse:missing-profile，記錄寫出欄位與筆數", {
  out_root <- harness_out_root()
  withr::defer(unlink(out_root, recursive = TRUE, force = TRUE))
  ledger_sha_before <- f2_sha256(f2_published_ledger_path())

  # 一個缺值儲存格，落在「未登記修讀」之外的一列（兩學期 enrolled 皆 0 的 180 列不計入缺值）
  fixture <- f2_raw_fixture(function(frame) {
    registered <- which(frame[[F2_ENROLLED_COLS[[1]]]] != 0)
    expect_true(length(registered) > 0L)
    frame[["Unemployment rate"]][registered[[1]]] <- NA
    frame
  })
  result <- f2_run(fixture, out_root)

  expect_false(identical(result$status, 0L), label = "結束碼非 0")
  expect_true(f2_refused(result, "missing-profile"), label = "拒絕類別")
  expect_true(any(grepl("Unemployment rate=1", result$output, fixed = TRUE)),
              label = "記錄寫出超限的欄位與筆數")
  expect_true(file.exists(result$log), label = "拒絕理由已寫入記錄")
  expect_false(file.exists(result$table), label = "暫存根上沒有清冊")
  expect_identical(f2_sha256(f2_published_ledger_path()), ledger_sha_before,
                   label = "專案清冊的 sha256")
})

## 7. 收尾：拒絕分支沒有越線 ----------------------------------------------

test_that("收尾：原始資料與 data/processed 的指紋與開跑前相同", {
  expect_identical(f2_sha256(f2_raw_path()), f2_raw_sha_before)
  expect_identical(f2_processed_shas(), f2_processed_before)
})

## 8. 負向控制 ------------------------------------------------------------

test_that("負向控制：把 total 釘成 4,425 的斷言必須紅", {
  ledger <- f2_ledger()
  total <- as.integer(ledger$value[as.character(ledger$metric) == "total"])

  # 紅燈本體：同一條斷言換上錯誤的釘值時，必須失敗。expect_failure() 綠 = 該斷言會紅。
  expect_failure(
    expect_equal(total, 4425L, label = "（負向控制）total 的錯誤釘值"),
    label = "把 total 釘成 4,425 時 expect_equal() 會失敗"
  )
  # 同一個數字用正確的釘值再走一次，證明上一條不是因為別的原因而紅。
  expect_equal(total, F2_PINS$value[[1]])
  expect_equal(total, 4424L)
})
