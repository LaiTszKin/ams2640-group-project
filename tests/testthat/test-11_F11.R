# test-11_F11.R — F11（交付）的性質與斷言（V11，涵蓋 T13 的 seam programs/R/run_all.R）
#
# 判定表（抄自 T13 ＋ 修訂 A-15／A-26，逐條對應下面每個 test_that）：
#
# | 輸入                          | 前置                | 結果                                    | 拒絕類別                  | 後置                              |
# | spec 恰 28 列、四欄齊備        | 十張分析表皆有母體與 n | 28 列對照表，逐列帶 population 與 n     | —                        | number_map.csv 落地               |
# | spec 為 27（或 29）列          | 其餘不變            | 停止，寫明列數與契約 28                  | refuse:incomplete-spec   | number_map.csv 不落地             |
# | 任一分析表缺母體或 n           | spec 28 列          | 停止，寫明表名與缺欄                     | refuse:missing-profile   | number_map.csv 不落地             |
# | spec 的 source_row 指不到一列  | spec 28 列          | 停止，寫明該列與可用列鍵                 | refuse:missing-profile   | number_map.csv 不落地             |
#
# 性質（每條可證偽；括號為對應的 test_that）：
#   P1 spec 恰 28 列、key 不重複、四欄齊備（f11_spec_check 回 28）
#   P2 對照表每列帶 population 與 n，且 n 與已發佈表該列的 n 同值（三方一致）
#   P3 28 列覆蓋：對照表的 key 與 spec 的 key 一一對應、無多無少
#   P4 十張分析表皆自帶母體與 n；age_tests 以 n_a／n_b 表達
#   P5 負向控制一：27 列與 29 列皆 refuse:incomplete-spec
#   P6 負向控制二：28 列但 key 重複 → refuse:incomplete-spec；缺 source_row 欄亦同
#   P7 分析表缺 n → refuse:missing-profile，且 number_map.csv 不落地（暫存輸出根無此檔）
#   P8 spec 指不到一列（指錯列鍵／指到非分析表／指到 n 有兩欄的 age_tests）
#      → refuse:missing-profile
#   P9 負向控制三：表中值解析不到時 pass 記 NA，不得記成 TRUE
#   P10 拒絕時既有 number_map.csv 一個位元組都不變（寫檔是最後一步）
#
# 交付行為的端到端（E1–E3）需要 T13 的 run_all.R 與它寫出的 spec／number_map；T13
# 依賴 T12，而 T12 阻塞於 B2（缺 SAS 對照值）。故這三條今日以 skip 明示阻塞原因，
# 不以空跑冒充綠；入口就位後同一批斷言直接接手。

# harness-11.R 在載入時自行把 helper-harness.R 載進**自己的求值環境**（該檔 §0，
# 依 A-43：三個入口同綠，故不假設呼叫端先載 helper）。
source(testthat::test_path("harness-11.R"), local = FALSE)

# 模型的輸入：十張已發佈的分析表（經 harness_table()，A-36）與由它們造的 28 列 spec。
published <- f11_published_tables()
spec <- f11_fixture_spec(published)
profiles <- f11_profiles(published)
map <- f11_map(spec, published, resolve = f11_fixture_resolver(published))

flow_started <- Sys.time()

test_that("P1 spec 恰 28 列、四欄齊備、key 不重複", {
  checked <- f11_spec_check(spec)

  expect_equal(checked$rows, 28L, label = "spec 為 28 列")
  expect_identical(checked$keys, as.character(spec$number_key), label = "key 原序回傳")
  expect_equal(anyDuplicated(checked$keys), 0L, label = "28 個 key 互不相同")
  expect_true(all(H11_SPEC_COLUMNS %in% names(spec)), label = "四欄齊備")

  # key 不為空、來源位置不為空
  expect_false(anyNA(spec$number_key), label = "number_key 無缺值")
  expect_true(all(nzchar(trimws(as.character(spec$number_key)))), label = "number_key 非空字串")
  expect_true(all(nzchar(trimws(as.character(spec$source_table)))), label = "source_table 非空")
  expect_true(all(nzchar(trimws(as.character(spec$source_row)))), label = "source_row 非空")

  # fixture 的 28 列取自 7 張表，且每列都指到真實存在的一列
  expect_equal(length(unique(spec$source_table)), 7L, label = "fixture 取自 7 張分析表")
})

test_that("P2 對照表每列帶 population 與 n，且與已發佈表該列的 n 同值", {
  expect_equal(nrow(map), 28L, label = "對照表為 28 列")
  expect_identical(names(map), H11_MAP_COLUMNS, label = "欄序即 T13 的八欄")

  # 每列都帶母體與 n（PRD §3 不變量）
  expect_false(anyNA(map$population), label = "population 無缺值")
  expect_true(all(as.character(map$population) %in% HARNESS_POPULATIONS),
              label = "population 取 full／analysis／ability")
  expect_false(anyNA(map$n), label = "n 無缺值")
  expect_true(all(map$n >= 0), label = "n 非負")
  expect_true(all(map$n == round(map$n)), label = "n 為整數")

  # 三方一致：spec 的來源 → 已發佈表該列 → 對照表該列。逐列檢查，逐一指名。
  for (i in seq_len(nrow(map))) {
    table <- as.character(map$source_table[i])
    frame <- published[[table]]
    keys <- f11_row_key(table, frame)
    hit <- which(keys == as.character(map$source_row[i]))
    expect_equal(length(hit), 1L, label = sprintf("第 %d 列的列鍵在 %s 中唯一", i, table))
    expect_equal(as.character(map$population[i]), as.character(frame$population[hit]),
                 label = sprintf("第 %d 列的 population 與 %s 同值", i, table))
    expect_equal(as.numeric(map$n[i]), as.numeric(frame$n[hit]),
                 label = sprintf("第 %d 列的 n 與 %s 該列同值", i, table))
  }

  # 母體不只一種：3,630 與 2,828 兩個母體都在對照表裡出現（V11 的 Budget）
  expect_setequal(unique(as.character(map$population)), c("analysis", "ability", "full"))
})

test_that("P3 28 列覆蓋：對照表的 key 與 spec 一一對應、無多無少", {
  expect_equal(nrow(map), nrow(spec), label = "列數與 spec 相同")
  expect_identical(map$number_key, as.character(spec$number_key), label = "key 與 spec 同序同值")
  expect_length(setdiff(map$number_key, spec$number_key), 0L)
  expect_length(setdiff(spec$number_key, map$number_key), 0L)
  expect_equal(sum(duplicated(map$number_key)), 0L, label = "每個 key 恰一列")

  # 換一個 spec 的列序，覆蓋關係仍成立（覆蓋不依賴列序）
  reordered <- spec[rev(seq_len(nrow(spec))), , drop = FALSE]
  map_reordered <- f11_map(reordered, published, resolve = f11_fixture_resolver(published))
  expect_setequal(map_reordered$number_key, map$number_key)
  expect_identical(map_reordered$number_key, as.character(reordered$number_key))
  expect_equal(map_reordered$n, rev(map$n), label = "n 隨列序重排，不隨原序")
})

test_that("P4 十張分析表皆自帶母體與 n（age_tests 以 n_a／n_b 表達）", {
  expect_length(setdiff(names(H11_PROFILE_COLUMNS), names(published)), 0L)
  expect_equal(length(published), 10L, label = "十張分析表皆在位")

  for (name in names(H11_PROFILE_COLUMNS)) {
    prof <- profiles[[name]]
    expect_true(is.data.frame(prof), label = sprintf("%s 有逐列 profile", name))
    expect_false(anyNA(prof$n), label = sprintf("%s 的 n 無缺值", name))
    expect_true(all(as.character(prof$population) %in% HARNESS_POPULATIONS),
                label = sprintf("%s 的 population 取三個具名值", name))
    # 單一 n 欄的表同時以 helper 的不變量斷言覆核（PRD §3）
    if (identical(setdiff(H11_PROFILE_COLUMNS[[name]], "population"), "n")) {
      expect_profile(published[[name]])
    } else {
      expect_identical(sort(unique(prof$n_role)), c("n_a", "n_b"),
                       label = sprintf("%s 的 n 以 n_a／n_b 兩欄表達", name))
    }
  }
})

test_that("P5 負向控制一：spec 為 27 或 29 列 → refuse:incomplete-spec", {
  short <- spec[-1L, , drop = FALSE]
  expect_equal(nrow(short), 27L)
  expect_error(f11_spec_check(short), "refuse:incomplete-spec", fixed = TRUE)
  expect_error(f11_spec_check(short), "27", fixed = TRUE)
  expect_error(f11_spec_check(short), "28", fixed = TRUE)

  long <- rbind(spec, spec[1L, , drop = FALSE])
  long$number_key[nrow(long)] <- "extra.key"
  expect_equal(nrow(long), 29L)
  expect_error(f11_spec_check(long), "refuse:incomplete-spec", fixed = TRUE)
  expect_error(f11_spec_check(long), "29", fixed = TRUE)

  # 交付路徑同樣在寫檔之前停下：兩個變異版 spec 都不產出 number_map.csv
  for (variant in list(short, long)) {
    root <- harness_out_root()
    tables_dir <- file.path(root, "tables")
    expect_error(f11_deliver(variant, tables_dir, published), "refuse:incomplete-spec", fixed = TRUE)
    expect_false(file.exists(f11_map_path(tables_dir)),
                 label = "spec 列數不符時 number_map.csv 不落地")
    unlink(root, recursive = TRUE, force = TRUE)
  }
})

test_that("P6 負向控制二：28 列但 key 重複或缺欄 → refuse:incomplete-spec", {
  dup <- spec
  dup$number_key[nrow(dup)] <- dup$number_key[1L]
  expect_equal(nrow(dup), 28L, label = "重複版仍是 28 列")
  expect_error(f11_spec_check(dup), "refuse:incomplete-spec", fixed = TRUE)
  expect_error(f11_spec_check(dup), "重複", fixed = TRUE)
  expect_error(f11_spec_check(dup), as.character(dup$number_key[1L]), fixed = TRUE)

  no_pos <- spec[, setdiff(names(spec), "source_row"), drop = FALSE]
  expect_equal(nrow(no_pos), 28L)
  expect_error(f11_spec_check(no_pos), "refuse:incomplete-spec", fixed = TRUE)
  expect_error(f11_spec_check(no_pos), "source_row", fixed = TRUE)

  blank_key <- spec
  blank_key$number_key[3L] <- "  "
  expect_error(f11_spec_check(blank_key), "refuse:incomplete-spec", fixed = TRUE)
})

test_that("P7 分析表缺 n → refuse:missing-profile，且 number_map.csv 不落地", {
  # 單一突變：拿掉 language_groups 的 n 欄
  broken <- published
  broken$language_groups$n <- NULL

  expect_error(f11_profiles(broken), "refuse:missing-profile", fixed = TRUE)
  expect_error(f11_profiles(broken), "language_groups", fixed = TRUE)
  expect_error(f11_profiles(broken), "n", fixed = TRUE)

  root <- harness_out_root()
  tables_dir <- file.path(root, "tables")
  expect_error(f11_deliver(spec, tables_dir, broken), "refuse:missing-profile", fixed = TRUE)

  # 後置：暫存輸出根裡沒有 number_map.csv（不是「先寫再刪」）
  expect_false(file.exists(f11_map_path(tables_dir)),
               label = "拒絕時 number_map.csv 不落地")
  expect_equal(length(list.files(tables_dir)), 0L, label = "拒絕時輸出根目錄仍為空")
  unlink(root, recursive = TRUE, force = TRUE)

  # population 缺值與未具名值同樣屬 missing-profile
  no_pop <- published
  no_pop$age_bands$population[1L] <- NA_character_
  expect_error(f11_profiles(no_pop), "refuse:missing-profile", fixed = TRUE)

  rogue_pop <- published
  rogue_pop$wealth_four_cell$population <- "everyone"
  expect_error(f11_profiles(rogue_pop), "refuse:missing-profile", fixed = TRUE)
  expect_error(f11_profiles(rogue_pop), "everyone", fixed = TRUE)

  # 缺整張表亦同
  missing_table <- published[setdiff(names(published), "macro_values")]
  expect_error(f11_profiles(missing_table), "refuse:missing-profile", fixed = TRUE)
  expect_error(f11_profiles(missing_table), "macro_values", fixed = TRUE)
})

test_that("P8 spec 指不到唯一一列 → refuse:missing-profile（指錯列／非分析表／n 有兩欄）", {
  # (1) 列鍵指錯
  wrong <- spec
  wrong$source_row[2L] <- "no_such_row"
  expect_error(f11_map(wrong, published), "refuse:missing-profile", fixed = TRUE)
  expect_error(f11_map(wrong, published), "no_such_row", fixed = TRUE)

  # (2) 指到非分析表（母體清冊有 population 與 n，但不是分析表）
  off_list <- spec
  off_list$source_table[1L] <- "population_ledger"
  off_list$source_row[1L] <- "analysis"
  expect_error(f11_map(off_list, published), "refuse:missing-profile", fixed = TRUE)
  expect_error(f11_map(off_list, published), "population_ledger", fixed = TRUE)

  # (3) 指到 n 有兩欄的 age_tests：單一 n 欄無從決定，拒絕而非自行挑一個
  two_n <- spec
  two_n$source_table[3L] <- "age_tests"
  two_n$source_row[3L] <- f11_row_key("age_tests", published$age_tests)[1L]
  expect_error(f11_map(two_n, published), "refuse:missing-profile", fixed = TRUE)
  expect_error(f11_map(two_n, published), "n_a", fixed = TRUE)
  expect_error(f11_map(two_n, published), "n_b", fixed = TRUE)

  # 拒絕時同樣不寫檔
  root <- harness_out_root()
  tables_dir <- file.path(root, "tables")
  expect_error(f11_deliver(wrong, tables_dir, published), "refuse:missing-profile", fixed = TRUE)
  expect_false(file.exists(f11_map_path(tables_dir)))
  unlink(root, recursive = TRUE, force = TRUE)
})

test_that("P9 負向控制三：解析不到的表值記 NA，不得記成 pass = TRUE", {
  # (1) 沒有解析器：table_value 與 pass 皆 NA——「無從解析」不等於「通過」
  blind <- f11_map(spec, published)
  expect_true(all(is.na(blind$table_value)), label = "無解析器時 table_value 為 NA")
  expect_true(all(is.na(blind$pass)), label = "無解析器時 pass 為 NA")
  expect_false(any(blind$pass %in% TRUE), label = "無從解析不得記成 TRUE")

  # (2) 有解析器但值不符：pass 為 FALSE，且不是 NA（可判定就要判定）
  drift <- function(spec_row, tbls) f11_fixture_resolver(tbls)(spec_row, tbls) + 1
  off <- f11_map(spec, published, resolve = drift)
  expect_false(anyNA(off$pass), label = "解析得到值時 pass 不為 NA")
  expect_false(any(off$pass), label = "整列偏移 1 之後無一列通過")
  expect_true(all(abs(off$table_value - as.numeric(spec$value)) > 0.5), label = "偏差大於半個末位")

  # (3) 正向：與 spec 同值的解析器使 28 列全通過（否則上面的反面錨可能是恆假）
  expect_false(anyNA(map$pass), label = "parse 得到值時 pass 不為 NA")
  expect_true(all(map$pass), label = "與 spec 同值時 28 列全數通過")

  # (4) 半個末位（A-40）：0.0756 寫成四位小數，0.07557 仍算相等
  expect_true(f11_value_equal(0.07557, "0.0756"))
  expect_false(f11_value_equal(0.0758, "0.0756"))
  expect_true(f11_value_equal(3630, "3630"), label = "計數零差")
  expect_false(f11_value_equal(3629, "3630"), label = "計數差 1 即不相等")
})

test_that("P10 交付寫檔：happy path 落地 28 列；拒絕時既有檔一個位元組都不變", {
  root <- harness_out_root()
  tables_dir <- file.path(root, "tables")
  withr::defer(unlink(root, recursive = TRUE, force = TRUE))

  delivered <- f11_deliver(spec, tables_dir, published, resolve = f11_fixture_resolver(published))
  expect_identical(delivered$status, "apply")
  expect_equal(delivered$rows, 28L)
  expect_true(file.exists(f11_map_path(tables_dir)), label = "happy path 寫出 number_map.csv")

  # 讀回的檔案與記憶體中的內容一致（交付的事實，不只是函式的回傳值）
  reread <- f11_read_map(tables_dir)
  expect_equal(nrow(reread), 28L, label = "落地的檔為 28 列")
  expect_identical(names(reread), H11_MAP_COLUMNS, label = "落地的檔為 T13 的八欄")
  expect_identical(as.character(reread$number_key), as.character(spec$number_key))
  expect_equal(as.numeric(reread$n), map$n, label = "落地的 n 與模型一致")
  expect_true(all(as.character(reread$population) %in% HARNESS_POPULATIONS))

  # 既有檔在拒絕分支下不被改寫：寫入是最後一步，故連開檔都不會發生
  sentinel <- charToRaw("number_key,spec_value\ndo_not_touch,0\n")
  writeBin(sentinel, f11_map_path(tables_dir))
  broken <- published
  broken$age_bands$n <- NULL
  expect_error(f11_deliver(spec, tables_dir, broken), "refuse:missing-profile", fixed = TRUE)
  after <- readBin(f11_map_path(tables_dir), "raw", n = length(sentinel))
  expect_identical(after, sentinel, label = "拒絕後既有 number_map.csv 逐位元組不變")
})

test_that("預算：兩個母體全列、無抽樣、無隨機來源、單流程上限 600 秒", {
  budget <- f11_budget()

  expect_equal(as.numeric(budget$rows[["analysis"]]), nrow(harness_data("analysis")),
               label = "分析母體全列")
  expect_equal(as.numeric(budget$rows[["ability"]]), nrow(harness_data("ability")),
               label = "能力母體全列")
  expect_equal(as.numeric(budget$rows[["analysis"]]), 3630, label = "分析母體 3,630")
  expect_equal(as.numeric(budget$rows[["ability"]]), 2828, label = "能力母體 2,828")
  expect_match(budget$seed, "^n/a", label = "無隨機來源：seed 記 n/a")
  expect_match(budget$shrink, "^n/a", label = "fixture 為有限枚舉：收縮記 n/a")
  expect_equal(budget$flow_seconds, 600, label = "單流程上限 600 秒")
  expect_equal(budget$retries, 0L, label = "重試 0 次")

  elapsed <- as.numeric(difftime(Sys.time(), flow_started, units = "secs"))
  expect_lt(elapsed, budget$flow_seconds, label = "本流程總耗時在上限內")
  # fixture 的列數上限：4+5+4+5+6+3+1 = 28（枚舉無隨機，故無「找不到」的可能）
  expect_equal(sum(F11_FIXTURE_PLAN$take), 28L, label = "fixture 取列計畫合計 28")
})

## 交付行為的端到端（需 T13；今日阻塞於 B2）--------------------------------

test_that("E1 單一入口以子程序跑完全部，結束碼 0，記錄含耗時與套件版本", {
  program <- tryCatch(f11_program_path(), error = function(e) NA_character_)
  if (is.na(program) || !file.exists(program)) {
    skip(paste(
      "阻塞 B2：programs/R/run_all.R（T13）未建——T13 依賴 T12，T12 缺 SAS 對照值",
      "（output/parity/ 只有 cell_map.csv）。本流程今日只判定模型骨架（P1–P10）。"
    ))
  }
  root <- harness_out_root()
  withr::defer(unlink(root, recursive = TRUE, force = TRUE))
  run <- f11_run(root)
  expect_equal(run$status, 0L, label = "結束碼為 0")
  expect_lt(run$elapsed, f11_budget()$flow_seconds, label = "單流程在上限內")
  expect_true(file.exists(run$map), label = "number_map.csv 落地")
  facts <- f11_log_facts(root)
  expect_true(facts$has_version, label = "記錄含 R 版本")
  expect_true(facts$has_elapsed, label = "記錄含每步耗時")
  expect_true(facts$has_timestamp, label = "記錄含時間戳")
  m <- f11_read_map(file.path(root, "tables"))
  expect_equal(nrow(m), 28L, label = "28 列")
  expect_false(anyNA(m$pass), label = "每列都解析得到表值")
})

test_that("E2 已發佈 spec 為 28 列，且對照表覆蓋其每個 number_key", {
  spec_path <- tryCatch(f11_spec_path(), error = function(e) NA_character_)
  if (is.na(spec_path) || !file.exists(spec_path)) {
    skip(paste(
      "阻塞 B2：output/tables/number_map_spec.csv（T13 的 owned 產物）尚未落地——",
      "T13 卡在 T12（缺 SAS 對照值）。今日 28 列覆蓋只能以模型 fixture 判定（P1–P3）。"
    ))
  }
  published_spec <- utils::read.table(spec_path, sep = ",", header = TRUE,
                                      check.names = FALSE, stringsAsFactors = FALSE)
  checked <- f11_spec_check(published_spec)
  expect_equal(checked$rows, 28L, label = "已發佈 spec 為 28 列")
  expect_equal(anyDuplicated(checked$keys), 0L, label = "key 不重複")
  expect_length(setdiff(checked$keys, as.character(published_spec$number_key)), 0L)
})

test_that("E3 已發佈 number_map.csv 為 28 列，逐列帶 population 與 n", {
  tables_dir <- file.path(f11_project_root(), "output", "tables")
  if (!file.exists(f11_map_path(tables_dir))) {
    skip(paste(
      "阻塞 B2：output/tables/number_map.csv 需 programs/R/run_all.R（T13）產出，",
      "而 T13 卡在 T12（缺 SAS 對照值）。今日以模型 P2／P10 判定同一批性質。"
    ))
  }
  m <- f11_read_map(tables_dir)
  expect_equal(nrow(m), 28L, label = "28 列")
  expect_profile(m)
  expect_false(anyNA(m$n), label = "每列帶 n")
  expect_identical(names(m), H11_MAP_COLUMNS, label = "八欄")
})
