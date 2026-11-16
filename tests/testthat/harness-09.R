# harness-09.R — F9 相關審核 的預算、執行上限與入口（V09，verification A）
#
# 交界契約（REQ-A-7、A-1、A-25、A-43）：
#   * 樣本、種子、暫存與輸出根一律取自 `helper-harness.R`：本檔只呼叫 harness_data()、
#     harness_seed()、harness_dir()、harness_out_root()、harness_table()、
#     expect_rate_equal()、expect_profile()。
#   * 本檔不自行讀檔（已發佈的表一律 harness_table()）、不設種子（一律 harness_seed()）、
#     不自建暫存目錄（一律 harness_dir()／harness_out_root()），故 REQ-A-7 對 tests/ 的
#     三類禁令（自行讀表、自設種子、自建暫存）在本檔的命中數為 0。
#   * 本檔只決定預算、執行上限與入口；判定表的斷言在 `test-09_F9.R`，反例與
#     trace 在 `pins/09_F9.md`。
#
# 分節：
#   1. 預算與上限            2. 釘值（Properties 逐條落成常數）
#   3. 性質函式（回傳違反清單）4. 退化 fixture 與注入（只在暫存副本上做）
#   5. 執行入口
#
# 性質函式的契約：每個 `h09_violations_*()` 回一個**字元向量**；空向量＝該性質成立，
# 非空＝逐條寫出「實得 vs 釘值」。回字元而非直接斷言，是為了讓同一支性質能被
# mutant（測試檔第 8 節）再跑一次，用「mutant 必須非空」證明該性質會判紅。

## 0. 載入即載入測試台 -------------------------------------------------------

# 本檔所在目錄。順序很重要：被 source() 時，堆疊上指向 harness-09.R 的 ofile 才是
# 本檔的位置——process 的 `--file=` 可能是別的腳本（`Rscript tests/testthat.R`、
# `Rscript -e`），先看它會把目錄誤判成 `tests`。
h09_this_dir <- function() {
  frames <- sys.frames()
  for (i in rev(seq_along(frames))) {
    ofile <- frames[[i]]$ofile
    if (!is.null(ofile) && grepl("harness-09[.]R$", ofile)) {
      return(dirname(normalizePath(ofile, winslash = "/", mustWork = FALSE)))
    }
  }
  # 本檔被 Rscript 直接執行時沒有 source() 的 ofile，改由 --file= 定位。
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg) && grepl("harness-09[.]R$", file_arg[[1L]])) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[[1L]]), winslash = "/", mustWork = FALSE)))
  }
  # 兩者皆無（例如在 REPL 內 source 本檔）：自工作目錄與 tests/testthat 找本檔的鄰居。
  for (dir in c(getwd(), file.path(getwd(), "tests", "testthat"))) {
    if (file.exists(file.path(dir, "harness-09.R"))) {
      return(normalizePath(dir, winslash = "/", mustWork = FALSE))
    }
  }
  getwd()
}

# 載入時無條件載入 `helper-harness.R`，放進**本檔被求值的同一個環境**（A-43）：`h09_*`
# 的 closure 都在那個環境，故 `.harness_table_path()`／`harness_data()` 等一併解析得到。
# 三種入口因此一致：`tests/testthat.R`、`test_dir()`／`test_file()`、
# `Rscript tests/testthat/harness-09.R`。
if (!file.exists(file.path(h09_this_dir(), "helper-harness.R"))) {
  stop("找不到 helper-harness.R（應與 harness-09.R 同目錄）：", h09_this_dir(), call. = FALSE)
}
source(file.path(h09_this_dir(), "helper-harness.R"), local = TRUE)

## 1. 預算與上限 -----------------------------------------------------------

H09_FLOW <- "F9 相關審核"
H09_SAMPLE <- "分析母體全列（harness_data(\"analysis\")，3630 列；逐欄一列，無抽樣）"
H09_SAMPLE_ROWS <- 3630L
# 收縮：本流程無隨機來源，收縮與種子皆記 n/a；上界照契約寫定（V09 Budget）。
H09_SHRINK_MAX_ITER <- 200L
H09_SHRINK_MAX_SEC <- 30
H09_SHRINK_NOTE <- "n/a（無隨機來源，無可收縮的輸入）"
H09_SEED_NOTE <- "本流程不消耗亂數，種子記 n/a"
# 上限：整個流程 120 秒；單一注入執行 60 秒（08_audit.R 在 3,630 列上重算 36 欄）。
H09_FLOW_LIMIT_SEC <- 120
H09_CHILD_LIMIT_SEC <- 60
H09_RETRIES <- 0L

## 2. 釘值 ----------------------------------------------------------------

# 表形狀與分母（PRD F9、REQ-F-F9-1；n 自 00_setup.R 的 ANALYSIS_N，本檔以資料重新表達）。
H09_TABLE <- "correlation_audit"
H09_POPULATION <- "analysis"
H09_N <- 3630L
H09_ROWS <- 36L
H09_COLUMNS <- c("population", "variable", "effect", "p_raw", "p_bh",
                 "keep", "verdict", "in_model", "n")

# 判詞的封閉詞彙：五類（PRD §4 F9、修訂 A-24／A-35）。
H09_VERDICTS <- c("definitional", "substantive", "weak", "noise", "ecological")
H09_VERDICT_COUNTS <- c(definitional = 4L, substantive = 4L, weak = 17L, noise = 8L, ecological = 3L)
H09_KEEP_VERDICTS <- c("definitional", "substantive")
H09_KEEP_N <- 8L
H09_IN_MODEL_N <- 4L

# 四個同代欄（以清洗資料集的實際欄名指稱，不用 pass1／avg_grade 短名）。
H09_DEFINITIONAL_COLS <- c(
  "Curricular units 1st sem (approved)",
  "Curricular units 2nd sem (approved)",
  "Curricular units 1st sem (grade)",
  "Curricular units 2nd sem (grade)"
)

# 三個以年份為單位的欄：判 ecological（每人共用一個年度值）。
H09_ECOLOGICAL_COLS <- c("Unemployment rate", "Inflation rate", "GDP")
# 可觀察形狀：各欄的不同值個數（PRD F8：九至十個值，故上界 10）。
H09_ECO_LEVELS <- c("Unemployment rate" = 10L, "Inflation rate" = 9L, "GDP" = 10L)
# 可觀察形狀：單一值最多由幾人共用（數百人共用一個值，個人層解讀不成立）。
H09_ECO_MAX_MULT <- c("Unemployment rate" = 452L, "Inflation rate" = 726L, "GDP" = 452L)

# 判為 substantive 的四欄（in_model 的同義集合）。
H09_IN_MODEL_VARS <- c("Application mode", "Course", "Tuition fees up to date", "Scholarship holder")

# 門檻（08_audit.R 的檔內常數；本檔抄入以釘住判詞規則）。
H09_EFFECT_MIN <- 0.30
H09_P_BH_MAX <- 0.05
H09_EFFECT_NOISE <- 0.10

# BH 重算的容差：表中 p_bh 與「以全部 p_raw、m = 表列數」重算的 BH 之相對差（A-24）。
H09_BH_REL_TOL <- 1e-12
# Bonferroni 負向控制：改用它校正後，至少這麼多列的 p_bh 不同（實測 34 列）。
H09_BONF_MISMATCH_MIN <- 20L

# 拒絕類別與腳本
H09_REFUSE_CATEGORY <- "refuse:input-schema"
H09_SCRIPT_REL <- file.path("programs", "R", "08_audit.R")

## 3. 性質函式 ------------------------------------------------------------

h09_note <- function(fmt, ...) sprintf(fmt, ...)

h09_num <- function(x) suppressWarnings(as.numeric(as.character(x)))

# 內部：逐元素為真的判斷（避免 any() 在 NA 上報錯）。
isTRUE_any <- function(x) !is.na(x) & x

# 內部：p 向量的比較。expected 為 0 時用絕對差，其餘用相對差。
h09_p_diff <- function(actual, expected, rel_tol) {
  bad <- is.na(actual) | is.na(expected) |
    (expected > 0 & abs(actual - expected) / expected > rel_tol) |
    (expected == 0 & abs(actual - expected) > 0)
  bad
}

# 3.1 形狀、母體、n、封閉詞彙、判詞分佈。
h09_violations_shape <- function(tbl, analysis = NULL) {
  out <- character()
  if (!is.data.frame(tbl)) return("審核表不是資料框")
  if (!identical(names(tbl), H09_COLUMNS)) {
    return(h09_note("欄序為 %s，釘值 %s",
                    paste(names(tbl), collapse = ","), paste(H09_COLUMNS, collapse = ",")))
  }
  if (nrow(tbl) != H09_ROWS) {
    out <- c(out, h09_note("表為 %d 列，釘值 %d 列（36 個變數一欄一列）", nrow(tbl), H09_ROWS))
  }
  if (!all(as.character(tbl$population) == H09_POPULATION)) {
    out <- c(out, h09_note("population 欄為 %s，釘值 %s",
                           paste(unique(as.character(tbl$population)), collapse = "/"), H09_POPULATION))
  }
  n <- h09_num(tbl$n)
  if (anyNA(n) || any(n != round(n))) {
    out <- c(out, "n 欄不是整數計數")
  } else if (any(n != H09_N)) {
    out <- c(out, h09_note("n 欄有 %d 列不等於 %d（實得 %s）", sum(n != H09_N), H09_N,
                           paste(unique(n), collapse = "/")))
  }
  variable <- as.character(tbl$variable)
  if (anyNA(variable) || anyDuplicated(variable)) {
    out <- c(out, "variable 欄含缺值或重複欄名")
  }
  if (!is.null(analysis)) {
    expected_vars <- setdiff(names(analysis), "target")
    if (length(expected_vars) != H09_ROWS || !setequal(variable, expected_vars)) {
      out <- c(out, h09_note("variable 集合與清洗資料集的 %d 個變數不符（表 %d 列；差集：%s）",
                             length(expected_vars), length(variable),
                             paste(setdiff(expected_vars, variable), collapse = ", ")))
    }
  }
  verdict <- as.character(tbl$verdict)
  outside <- setdiff(unique(verdict), H09_VERDICTS)
  if (length(outside)) {
    out <- c(out, h09_note("verdict 出現封閉詞彙外的值：%s（詞彙 %s）",
                           paste(outside, collapse = "/"), paste(H09_VERDICTS, collapse = "/")))
  } else {
    counts <- as.integer(table(factor(verdict, levels = H09_VERDICTS)))
    if (!identical(counts, unname(H09_VERDICT_COUNTS))) {
      out <- c(out, h09_note("判詞分佈為 %s，釘值 %s",
                             paste(sprintf("%s=%d", H09_VERDICTS, counts), collapse = " "),
                             paste(sprintf("%s=%d", H09_VERDICTS, unname(H09_VERDICT_COUNTS)), collapse = " ")))
    }
  }
  effect <- h09_num(tbl$effect)
  p_raw <- h09_num(tbl$p_raw)
  p_bh <- h09_num(tbl$p_bh)
  if (anyNA(effect) || anyNA(p_raw) || anyNA(p_bh)) {
    out <- c(out, "effect／p_raw／p_bh 含缺值")
  } else {
    if (any(abs(effect) > 1)) out <- c(out, "效果量超出 [-1, 1]")
    if (any(p_raw < 0 | p_raw > 1)) out <- c(out, "p_raw 超出 [0, 1]")
    if (any(p_bh < 0 | p_bh > 1)) out <- c(out, "p_bh 超出 [0, 1]")
  }
  if (!is.logical(tbl$keep) || !is.logical(tbl$in_model)) {
    out <- c(out, "keep／in_model 不是邏輯欄（TRUE/FALSE）")
  }
  out
}

# 3.2 四個同代欄：verdict 為 definitional、in_model 為 FALSE、keep 為 TRUE；
#     且 definitional 恰好是這四欄（不多不少）。
h09_violations_definitional <- function(tbl) {
  out <- character()
  if (!is.data.frame(tbl) || !all(c("variable", "verdict", "in_model", "keep") %in% names(tbl))) {
    return("審核表缺 variable／verdict／in_model／keep 欄")
  }
  variable <- as.character(tbl$variable)
  absent <- setdiff(H09_DEFINITIONAL_COLS, variable)
  if (length(absent)) {
    return(h09_note("表內缺同代欄：%s", paste(absent, collapse = ", ")))
  }
  idx <- match(H09_DEFINITIONAL_COLS, variable)
  wrong <- H09_DEFINITIONAL_COLS[as.character(tbl$verdict[idx]) != "definitional"]
  if (length(wrong)) {
    out <- c(out, h09_note("同代欄未判 definitional：%s", paste(wrong, collapse = ", ")))
  }
  modelled <- H09_DEFINITIONAL_COLS[isTRUE_any(tbl$in_model[idx])]
  if (length(modelled)) {
    out <- c(out, h09_note("同代欄被標進模型（in_model 應為 FALSE）：%s", paste(modelled, collapse = ", ")))
  }
  kept <- H09_DEFINITIONAL_COLS[!isTRUE_any(tbl$keep[idx])]
  if (length(kept)) {
    out <- c(out, h09_note("同代欄未保留（keep 應為 TRUE）：%s", paste(kept, collapse = ", ")))
  }
  flagged <- variable[as.character(tbl$verdict) == "definitional"]
  if (!setequal(flagged, H09_DEFINITIONAL_COLS) || length(flagged) != length(H09_DEFINITIONAL_COLS)) {
    out <- c(out, h09_note("判為 definitional 的欄為 %s，釘值恰為四個同代欄 %s",
                           paste(flagged, collapse = ", "),
                           paste(H09_DEFINITIONAL_COLS, collapse = ", ")))
  }
  out
}

# 3.3 BH：以表中**全部** p_raw、m = 表列數重算，逐列相對差 ≤ 1e-12。
#     method 可換成 bonferroni 作負向控制（此時必須有違反）。
h09_violations_bh <- function(tbl, method = "BH", rel_tol = H09_BH_REL_TOL) {
  out <- character()
  if (!is.data.frame(tbl) || !all(c("p_raw", "p_bh") %in% names(tbl))) {
    return("審核表缺 p_raw／p_bh 欄")
  }
  p_raw <- h09_num(tbl$p_raw)
  p_bh <- h09_num(tbl$p_bh)
  if (anyNA(p_raw) || anyNA(p_bh)) return("p_raw／p_bh 含缺值，無法重算")
  expected <- stats::p.adjust(p_raw, method = method)
  bad <- h09_p_diff(p_bh, expected, rel_tol)
  if (any(bad)) {
    i <- which(bad)[seq_len(min(3L, sum(bad)))]
    out <- c(out, h09_note("%s 重算有 %d 列不符（容差 %.0e）；首幾列：%s",
                           method, sum(bad), rel_tol,
                           paste(sprintf("%s 表=%s 重算=%s", as.character(tbl$variable)[i],
                                         format(p_bh[i], digits = 6), format(expected[i], digits = 6)),
                                 collapse = "；")))
  }
  out
}

# 3.4 家族大小被釘住：重算用的是表列數（36），不是舊版固定 6 個 p 值（A-24）。
#     若表的 p_bh 恰等於「只用前 6 列 p_raw 做 BH」的結果，這條性質判紅。
h09_violations_bh_family <- function(tbl, family = 6L) {
  out <- character()
  if (!is.data.frame(tbl) || !all(c("p_raw", "p_bh") %in% names(tbl))) {
    return("審核表缺 p_raw／p_bh 欄")
  }
  if (nrow(tbl) != H09_ROWS) {
    out <- c(out, h09_note("表為 %d 列，家族大小應為 %d", nrow(tbl), H09_ROWS))
  }
  if (nrow(tbl) < family) return(out)
  wrong <- stats::p.adjust(h09_num(tbl$p_raw)[seq_len(family)], method = "BH")
  same <- !h09_p_diff(h09_num(tbl$p_bh)[seq_len(family)], wrong, H09_BH_REL_TOL)
  if (all(same)) {
    out <- c(out, h09_note("前 %d 列的 p_bh 等於「只用這 %d 個 p_raw」的 BH：家族大小被縮成 %d（舊版缺陷）",
                           family, family, family))
  }
  out
}

# 3.5 三個以年份為單位的欄：verdict 為 ecological、keep 與 in_model 皆 FALSE；
#     且 ecological 恰好是這三欄。另驗可觀察形狀：值域 ≤ 10 個、單值由數百人共用。
h09_violations_ecological <- function(tbl, analysis = NULL) {
  out <- character()
  if (!is.data.frame(tbl) || !all(c("variable", "verdict", "keep", "in_model") %in% names(tbl))) {
    return("審核表缺 variable／verdict／keep／in_model 欄")
  }
  variable <- as.character(tbl$variable)
  absent <- setdiff(H09_ECOLOGICAL_COLS, variable)
  if (length(absent)) {
    return(h09_note("表內缺生態欄：%s", paste(absent, collapse = ", ")))
  }
  idx <- match(H09_ECOLOGICAL_COLS, variable)
  wrong <- H09_ECOLOGICAL_COLS[as.character(tbl$verdict[idx]) != "ecological"]
  if (length(wrong)) {
    out <- c(out, h09_note("以年份為單位的欄未判 ecological：%s", paste(wrong, collapse = ", ")))
  }
  kept <- H09_ECOLOGICAL_COLS[isTRUE_any(tbl$keep[idx])]
  if (length(kept)) {
    out <- c(out, h09_note("生態欄被保留（keep 應為 FALSE）：%s", paste(kept, collapse = ", ")))
  }
  modelled <- H09_ECOLOGICAL_COLS[isTRUE_any(tbl$in_model[idx])]
  if (length(modelled)) {
    out <- c(out, h09_note("生態欄被標進模型（in_model 應為 FALSE）：%s", paste(modelled, collapse = ", ")))
  }
  flagged <- variable[as.character(tbl$verdict) == "ecological"]
  if (!setequal(flagged, H09_ECOLOGICAL_COLS) || length(flagged) != length(H09_ECOLOGICAL_COLS)) {
    out <- c(out, h09_note("判為 ecological 的欄為 %s，釘值恰為三欄 %s",
                           paste(flagged, collapse = ", "), paste(H09_ECOLOGICAL_COLS, collapse = ", ")))
  }
  if (!is.null(analysis)) {
    levels_obs <- vapply(H09_ECOLOGICAL_COLS, function(v) {
      if (!v %in% names(analysis)) return(NA_integer_)
      length(unique(analysis[[v]]))
    }, integer(1))
    mult_obs <- vapply(H09_ECOLOGICAL_COLS, function(v) {
      if (!v %in% names(analysis)) return(NA_integer_)
      as.integer(max(table(analysis[[v]])))
    }, integer(1))
    if (anyNA(levels_obs)) {
      out <- c(out, h09_note("分析母體缺生態欄：%s",
                             paste(H09_ECOLOGICAL_COLS[is.na(levels_obs)], collapse = ", ")))
    } else {
      if (!identical(unname(levels_obs), unname(H09_ECO_LEVELS))) {
        out <- c(out, h09_note("生態欄的不同值個數為 %s，釘值 %s（以年份為單位：九至十個值）",
                               paste(levels_obs, collapse = "/"), paste(H09_ECO_LEVELS, collapse = "/")))
      }
      if (!identical(unname(mult_obs), unname(H09_ECO_MAX_MULT))) {
        out <- c(out, h09_note("生態欄的單值最大共用數為 %s，釘值 %s（數百人共用一個年度值）",
                               paste(mult_obs, collapse = "/"), paste(H09_ECO_MAX_MULT, collapse = "/")))
      }
    }
  }
  out
}

# 3.6 keep 與 in_model 的規則：keep ⇔ verdict ∈ {definitional, substantive}；
#     in_model ⇔ substantive（且必然非同代、非生態）；兩者計數 8 與 4。
h09_violations_flags <- function(tbl) {
  out <- character()
  if (!is.data.frame(tbl) || !all(c("variable", "verdict", "keep", "in_model") %in% names(tbl))) {
    return("審核表缺 variable／verdict／keep／in_model 欄")
  }
  verdict <- as.character(tbl$verdict)
  keep <- isTRUE_any(tbl$keep)
  in_model <- isTRUE_any(tbl$in_model)
  expected_keep <- verdict %in% H09_KEEP_VERDICTS
  if (!identical(keep, expected_keep)) {
    bad <- as.character(tbl$variable)[keep != expected_keep]
    out <- c(out, h09_note("keep 與判詞規則不符（keep ⇔ definitional|substantive）：%s",
                           paste(bad, collapse = ", ")))
  }
  expected_model <- verdict == "substantive"
  if (!identical(in_model, expected_model)) {
    bad <- as.character(tbl$variable)[in_model != expected_model]
    out <- c(out, h09_note("in_model 與判詞規則不符（in_model ⇔ substantive）：%s",
                           paste(bad, collapse = ", ")))
  }
  if (sum(keep) != H09_KEEP_N) {
    out <- c(out, h09_note("keep 為 %d 欄，釘值 %d", sum(keep), H09_KEEP_N))
  }
  if (sum(in_model) != H09_IN_MODEL_N) {
    out <- c(out, h09_note("in_model 為 %d 欄，釘值 %d", sum(in_model), H09_IN_MODEL_N))
  }
  modelled <- as.character(tbl$variable)[in_model]
  if (!setequal(modelled, H09_IN_MODEL_VARS)) {
    out <- c(out, h09_note("in_model 的欄為 %s，釘值 %s",
                           paste(modelled, collapse = ", "), paste(H09_IN_MODEL_VARS, collapse = ", ")))
  }
  # 判詞門檻的自洽：substantive 必達 EFFECT_MIN 且 p_bh < P_BH_MAX；noise 必低於 EFFECT_NOISE。
  effect <- abs(h09_num(tbl$effect))
  p_bh <- h09_num(tbl$p_bh)
  sub_ok <- verdict != "substantive" | (effect >= H09_EFFECT_MIN & p_bh < H09_P_BH_MAX)
  if (any(!sub_ok, na.rm = TRUE)) {
    out <- c(out, h09_note("substantive 未同時滿足 |effect| ≥ %.2f 與 p_bh < %.2f：%s",
                           H09_EFFECT_MIN, H09_P_BH_MAX,
                           paste(as.character(tbl$variable)[which(!sub_ok)], collapse = ", ")))
  }
  noise_ok <- verdict != "noise" | effect < H09_EFFECT_NOISE
  if (any(!noise_ok, na.rm = TRUE)) {
    out <- c(out, h09_note("noise 的效果量未低於 %.2f：%s", H09_EFFECT_NOISE,
                           paste(as.character(tbl$variable)[which(!noise_ok)], collapse = ", ")))
  }
  out
}

## 4. 退化 fixture 與注入（只在暫存副本上做） ------------------------------

# 4.1 清洗資料集形狀的 fixture：資料來自 harness_data()，寫到 harness_dir()。
#     欄名與順序不動（08_audit.R 以 target 欄切母體）。
h09_clean_fixture <- function(dir, mutate, population = "full") {
  frame <- harness_data(population)
  mutated <- mutate(frame)
  if (!is.data.frame(mutated)) stop("mutate 必須回傳資料框", call. = FALSE)
  if (!identical(names(mutated), names(frame))) {
    stop("mutate 不得改動欄名（fixture 需保持清洗資料集的形狀）", call. = FALSE)
  }
  path <- file.path(dir, "f9_fixture_clean.csv")
  readr::write_csv(mutated, path)
  path
}

# 4.2 母體清冊的 fixture：08_audit.R 只查 population=analysis、metric=analysis 那一列，
#     故最小清冊（表頭 + 一列）足以驅動分母核對，無須讀入已發佈的清冊。
h09_ledger_fixture <- function(dir, n, value) {
  path <- file.path(dir, "f9_fixture_ledger.csv")
  writeLines(c("population,metric,n,value",
               sprintf("analysis,analysis,%d,%d", as.integer(n), as.integer(value))),
             path, useBytes = TRUE)
  path
}

# 4.3 暫存輸出根：由測試台建根（RTOOLKIT_OUT_ROOT 指到它），再放一份母體清冊進去
#     （08_audit.R 自 OUT_ROOT/tables 讀清冊；A-34 的例外）。
h09_out_root_with_ledger <- function() {
  root <- harness_out_root()
  ledger <- .harness_table_path("population_ledger")
  if (!file.exists(ledger)) {
    stop("refuse:input-missing\n- 缺母體清冊 ", .harness_short(ledger), call. = FALSE)
  }
  if (!file.copy(ledger, file.path(root, "tables"), overwrite = TRUE)) {
    stop("無法把母體清冊複製進暫存輸出根：", root, call. = FALSE)
  }
  root
}

# 4.4 執行 08_audit.R（生產檔不動）：以環境變數換輸入與輸出根，在獨立環境 source。
#     時間上限由 setTimeLimit 收緊；重試次數固定 0（H09_RETRIES）。
h09_run_audit <- function(clean_path, out_root) {
  script <- file.path(h09_project_root(), H09_SCRIPT_REL)
  if (!file.exists(script)) stop("找不到 ", H09_SCRIPT_REL, "：F9 的 seam 不在預期位置", call. = FALSE)
  prior_clean <- Sys.getenv("RTOOLKIT_CLEAN_PATH", unset = "")
  prior_root <- Sys.getenv("RTOOLKIT_OUT_ROOT", unset = "")
  on.exit({
    if (nzchar(prior_clean)) Sys.setenv(RTOOLKIT_CLEAN_PATH = prior_clean) else Sys.unsetenv("RTOOLKIT_CLEAN_PATH")
    if (nzchar(prior_root)) Sys.setenv(RTOOLKIT_OUT_ROOT = prior_root) else Sys.unsetenv("RTOOLKIT_OUT_ROOT")
    setTimeLimit(elapsed = Inf, transient = TRUE)
  }, add = TRUE)

  Sys.setenv(RTOOLKIT_CLEAN_PATH = clean_path)
  Sys.setenv(RTOOLKIT_OUT_ROOT = out_root)
  # 08_audit.R 以相對路徑 source("programs/R/lib/stats.R")，用法記載為「專案根目錄」；
  # 測試在 tests/testthat 下執行時 wd 不是根，故這裡把被測腳本放回它記載的執行位置
  # （setwd 在測試端，不在 programs/R，REQ-A-1 的掃描域不受影響）。
  prior_wd <- getwd()
  on.exit(setwd(prior_wd), add = TRUE)
  setwd(h09_project_root())
  started <- Sys.time()
  setTimeLimit(elapsed = H09_CHILD_LIMIT_SEC, transient = TRUE)
  env <- new.env(parent = globalenv())
  error <- tryCatch({
    sys.source(script, envir = env)
    NULL
  }, error = function(e) e)
  message_text <- if (is.null(error)) "" else conditionMessage(error)
  outcome <- if (is.null(error)) "ok" else if (grepl(H09_REFUSE_CATEGORY, message_text, fixed = TRUE)) "refuse" else "error"
  list(
    outcome = outcome,
    message = message_text,
    elapsed = as.numeric(difftime(Sys.time(), started, units = "secs")),
    retries = H09_RETRIES,
    out_root = out_root
  )
}

# 4.5 sha256：優先 shasum -a 256（macOS），其次 sha256sum（Linux）；兩者皆無則回 NA。
h09_sha256 <- function(paths) {
  tool <- Sys.which(c("shasum", "sha256sum"))
  tool <- tool[nzchar(tool)]
  if (!length(tool)) return(stats::setNames(rep(NA_character_, length(paths)), paths))
  args <- if (grepl("sha256sum$", tool[[1]])) shQuote(paths) else c("-a", "256", shQuote(paths))
  out <- suppressWarnings(system2(tool[[1]], args, stdout = TRUE, stderr = FALSE))
  hex <- sub("^([0-9a-fA-F]{64})\\b.*$", "\\1", out)
  if (length(hex) != length(paths)) return(stats::setNames(rep(NA_character_, length(paths)), paths))
  stats::setNames(hex, paths)
}

# 4.6 已發佈產物的路徑；由測試台解析（A-36 的分家），本檔不自組。
h09_published_paths <- function() {
  if (!exists(".harness_table_path", mode = "function")) {
    stop("harness-09.R 需要先載入 helper-harness.R（.harness_table_path() 由它提供）", call. = FALSE)
  }
  c(
    csv = .harness_table_path(H09_TABLE),
    txt = sub("[.]csv$", ".txt", .harness_table_path(H09_TABLE))
  )
}

# 4.7 負向控制計數：改用別種校正後有幾列的 p_bh 不同（實測 Bonferroni 21 列）。
h09_mismatch_count <- function(tbl, method = "bonferroni") {
  expected <- stats::p.adjust(h09_num(tbl$p_raw), method = method)
  sum(h09_p_diff(h09_num(tbl$p_bh), expected, H09_BH_REL_TOL))
}

## 5. 執行入口 -------------------------------------------------------------

h09_project_root <- function() {
  if (exists(".harness_project_root", mode = "function")) return(.harness_project_root())
  getwd()
}

# h09_this_dir() 定義於第 0 節：載入時就要用到它來定位 helper-harness.R。

h09_script_mode <- function() {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  length(file_arg) == 1L && identical(basename(sub("^--file=", "", file_arg[[1L]])), "harness-09.R")
}

# 入口：印預算 → 跑本流程的測試檔 → 檢查總耗時不超過 120 秒。
h09_entry <- function(reporter = "summary") {
  dir <- h09_this_dir()
  seed <- harness_seed()
  cat(sprintf(
    "harness-09: flow=%s\n  sample=%s\n  seed=%d（%s）\n  shrink=%s（上界 %d 次／%d 秒）\n  limit=%d 秒；retries=%d\n",
    H09_FLOW, H09_SAMPLE, seed, H09_SEED_NOTE, H09_SHRINK_NOTE,
    H09_SHRINK_MAX_ITER, H09_SHRINK_MAX_SEC, H09_FLOW_LIMIT_SEC, H09_RETRIES
  ))
  started <- Sys.time()
  results <- testthat::test_file(file.path(dir, "test-09_F9.R"), reporter = reporter)
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  assertions <- sum(vapply(results, function(r) length(r$results), integer(1)))
  cat(sprintf("harness-09: %s 秒（上限 %d 秒）；斷言 %d 條\n", sprintf("%.2f", elapsed),
              H09_FLOW_LIMIT_SEC, assertions))
  if (elapsed > H09_FLOW_LIMIT_SEC) {
    stop(sprintf("F9 測試超過單流程上限：%.2f 秒 > %d 秒", elapsed, H09_FLOW_LIMIT_SEC), call. = FALSE)
  }
  frame <- as.data.frame(results)
  red <- if (nrow(frame)) sum(frame$failed) + sum(as.integer(frame$error)) else 0L
  if (red > 0L) {
    cat(sprintf("harness-09: %d 條斷言判紅\n", red))
    if (h09_script_mode()) quit(save = "no", status = 1L) else stop("F9 有斷言判紅", call. = FALSE)
  }
  invisible(results)
}

# 自動入口：僅在「以 Rscript 直接執行本檔」且不是由本檔自己的入口再入時觸發。
# 入口會 source 測試檔，測試檔又會 source 本檔——沒有這個守衛就會遞迴。
if (h09_script_mode() && !isTRUE(getOption("harness09.entry.running"))) {
  options(harness09.entry.running = TRUE)
  on.exit(options(harness09.entry.running = NULL), add = TRUE)
  h09_entry()
}
