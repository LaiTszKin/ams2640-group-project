# 05_models.R — 三層的解釋力比較（F6）
#
# 一張六列表：五個模型規格 × 兩個母體的配對，逐列給出解釋力（McFadden）、
# 曲線下面積（秩式）、機制句與否證條件。
#   ① 年齡帶＠3,630        ② 財務三欄＠3,630      ③ 財務三欄＠2,828
#   ④ 能力分位＠2,828      ⑤ 財務加能力＠2,828    ⑥ 入學成績分位＠2,828
#
# 年齡帶模型的參數化為四帶（AGE_BREAKS_MODEL，<25 併為一帶）：<25、25-29、
# 30-39、40+。五帶（AGE_BREAKS）得 0.0839，四帶才得 0.0756，兩者不可混用
# （PRD §4 F6、A-16）。切帶用 findInterval() 的左閉右開 [a, b)，與 03_age.R 同。
#
# 能力分位模型直接讀 <OUT_ROOT>/tables/ability_quartiles.csv 的分組（T06 的等量
# 切法），本檔不重切。該表是四列的彙總（population、quartile、n、graduation_rate），
# 不含個人層鍵，故個人歸屬以 T06 記載的同一個等量切法重建，並以該表的 n 與
# graduation_rate 逐組相等作為「同一分組」的證明；對不上即停手，不改切法。
# 讀輸出目錄是本檔的特例（PRD §5 分析腳本不讀輸出目錄；T07 步驟 4 明文要求讀此表）。
#
# 解釋力一律走 lib/stats.R 的 mcfadden_r2（ll_null 取虛無模型的對數似然，即
# -null.deviance/2），曲線下面積一律走 auc_rank（正類為 Dropout、分數為
# predict(type = "response")、同分取平均秩）；本檔不自行實作這兩者。
#
# 比對規則（A-23）：每列算出的解釋力與報告所載數字比對，四位有效數字上不同者
# 該列 status 為 mismatch，停止交付、交主代理裁決；本檔不自行改寫報告的數字。
# 比對精度取報告所寫的位數（0.0756 寫到小數四位即三位有效數字，0.2227 為四位），
# 判準是「把算出的值四捨五入到該位後相等」。以 fmt_sig 的字串相等會把 0.07557
# 與 0.0756 判成不同——報告沒有寫第四位，那不是差異。
#
# 用法（專案根目錄）：Rscript programs/R/05_models.R
# 產物：
#   <OUT_ROOT>/tables/model_comparison.csv   model、population、n、mcfadden_r2、
#                                            auc、mechanism、falsifier、status
#   <OUT_ROOT>/logs/05_models.log            收斂狀態、三欄欄名、年齡帶參數化、係數

## 0. 由 00_setup.R 取常數與共用統計量 ---------------------------------------

source(file.path(here::here("programs/R/00_setup.R")))
source(file.path(PROJ_ROOT, "programs/R/lib/stats.R"))

## 1. 路徑、欄名與固定形狀 -------------------------------------------------

CLEAN_PATH <- file.path(PROJ_ROOT, "data", "processed", "ams2640_clean.csv")
QUARTILE_PATH <- file.path(OUT_ROOT, "tables", "ability_quartiles.csv")
TABLE_PATH <- file.path(OUT_ROOT, "tables", "model_comparison.csv")
LOG_PATH <- file.path(OUT_ROOT, "logs", "05_models.log")

# 欄名以清洗資料集為準（01_prep_data.R 保留原始欄名，只把結果欄改名 target）
COL_RESULT <- "target"
COL_AGE <- "Age at enrollment"
COL_TUITION <- "Tuition fees up to date"
COL_DEBTOR <- "Debtor"
COL_SCHOLARSHIP <- "Scholarship holder"
COL_SEM2 <- "Curricular units 2nd sem (grade)"
COL_ADMISSION <- "Admission grade"

REQUIRED_COLS <- c(
  COL_RESULT, COL_AGE, COL_TUITION, COL_DEBTOR, COL_SCHOLARSHIP,
  COL_SEM2, COL_ADMISSION
)

# 財務三欄的編碼（T07 步驟 1）：欠繳、欠債、無獎學金，三者皆為「財務壓力較大」
# 的那一端為 1。學費欄是「已繳清」，故以 0 為欠繳；獎學金欄是「有」，故以 0 為無。
UNPAID_VALUE <- 0L
DEBTOR_VALUE <- 1L
SCHOLARSHIP_NONE_VALUE <- 0L
FINANCIAL_COLS <- c("tuition_unpaid", "debtor", "no_scholarship")

# 年齡帶標籤與能力分位的組名（表內具名值與清冊、T06 的表一致）
AGE_LEVELS <- c("<25", "25-29", "30-39", "40+")
QUARTILE_LEVELS <- paste0("q", seq_len(N_QUARTILES))

# 結果欄的退學值：正類即「退學」，取自 00_setup.R 的分析母體類別
DROPOUT <- "Dropout"

# 表內六列的模型鍵（英文鍵，與其他表的 verdict／status 同類）
MODEL_AGE <- "age_band"
MODEL_FIN <- "financial_three"
MODEL_ABILITY <- "ability_quartile"
MODEL_FIN_ABILITY <- "financial_plus_ability"
MODEL_ADMISSION <- "admission_quartile"

# 母體標籤（清冊與其他表同用 analysis／ability，PRD §3）
POPULATION_ANALYSIS <- "analysis"
POPULATION_ABILITY <- "ability"

# 報告所載的解釋力（A-23 的比對對象）。存字串而不存數值：末位就是比對精度，
# 數值會把「寫到第幾位」這件事洗掉。
REPORTED_R2 <- c(
  age_band              = "0.07557",
  financial_three       = "0.2227",
  financial_three_ability = "0.2011",
  ability_quartile      = "0.09577",
  financial_plus_ability = "0.2611",
  admission_quartile    = "0.004952"
)

## 2. 小工具 ---------------------------------------------------------------

stamp <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# 專案內的檔案以相對路徑呈現（記錄可讀；不寫死任何絕對路徑）
short_path <- function(path) {
  prefix <- paste0(PROJ_ROOT, "/")
  ifelse(startsWith(path, prefix), substring(path, nchar(prefix) + 1L), path)
}

# 先寫同目錄的暫存檔再改名，半途失敗不留半份表
atomic_write <- function(path, writer) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(pattern = paste0(".", basename(path), "-"), tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  writer(tmp)
  if (!file.rename(tmp, path)) {
    if (!file.copy(tmp, path, overwrite = TRUE)) {
      stop(sprintf("無法以原子替換寫入 %s", short_path(path)), call. = FALSE)
    }
  }
  invisible(path)
}

# 記錄一律追加一段；時間戳只在段首，段內列序固定
log_block <- function(lines) {
  dir.create(dirname(LOG_PATH), recursive = TRUE, showWarnings = FALSE)
  block <- c(sprintf("== 05_models %s ==", stamp()), lines, "")
  atomic_write(LOG_PATH, function(path) {
    previous <- if (file.exists(LOG_PATH)) readLines(LOG_PATH, warn = FALSE) else character()
    writeLines(c(previous, block), path, useBytes = TRUE)
  })
}

# 停手：先把理由寫進記錄，再停止；不改契約、不改報告的數字
halt <- function(status, reason, next_step) {
  log_block(c(
    sprintf("input: %s", short_path(CLEAN_PATH)),
    sprintf("status: %s", status),
    sprintf("reason: %s", reason),
    sprintf("next_step: %s", next_step),
    sprintf("table_untouched: %s", short_path(TABLE_PATH))
  ))
  stop(sprintf("%s\n- %s\n- 下一步：%s", status, reason, next_step), call. = FALSE)
}

# 等量切組：與 04_ability.R（T06）同一個切法——成績升冪、order(method = "radix")
# 穩定排序（同分依清洗資料集原始列序）、組寬 floor(n / groups)、餘數全收末組。
# 本檔只用它重建能力分位的個人歸屬（該表不含個人層鍵）與切入學成績分位。
equal_split <- function(score, groups) {
  n <- length(score)
  placement <- order(score, method = "radix")
  width <- n %/% groups
  membership <- integer(n)
  for (g in seq_len(groups - 1L)) {
    membership[placement[((g - 1L) * width + 1L):(g * width)]] <- g
  }
  membership[placement[((groups - 1L) * width + 1L):n]] <- groups
  membership
}

# 報告數字的比對精度：末位即半個單位（"0.0756" → 5e-05），並要求該位不超過
# SIG_DIGITS 位有效數字。回傳 list(tolerance, significant_digits)。
reported_precision <- function(text) {
  decimals <- nchar(sub("^[^.]*\\.?", "", text))
  significant <- nchar(gsub("[^1-9]", "", sub("^0+\\.?0*", "", text)))
  if (significant > SIG_DIGITS) {
    stop(sprintf("報告值 %s 寫到 %d 位有效數字，超過位數政策（%d）",
                 text, significant, SIG_DIGITS), call. = FALSE)
  }
  list(tolerance = 0.5 * 10^(-decimals), significant_digits = significant)
}

## 3. 讀清洗資料集 ---------------------------------------------------------

if (!file.exists(CLEAN_PATH)) {
  halt("stopped:missing-input",
       sprintf("找不到清洗資料集 %s", short_path(CLEAN_PATH)),
       "先執行 programs/R/01_prep_data.R 產生清洗資料集後重跑。")
}

clean <- utils::read.csv(CLEAN_PATH, check.names = FALSE, stringsAsFactors = FALSE)
missing_cols <- setdiff(REQUIRED_COLS, names(clean))
if (length(missing_cols)) {
  halt("stopped:input-schema",
       sprintf("清洗資料集缺欄：%s", paste(missing_cols, collapse = " | ")),
       "確認清洗資料集是契約界定的那一份後重跑。")
}

result <- as.character(clean[[COL_RESULT]])
# 正類為退學：當期已退學者才有結果可言；在讀（Enrolled）不進分析母體
dropout <- result == DROPOUT
in_analysis <- result %in% ANALYSIS_RESULTS
in_ability <- in_analysis & clean[[COL_SEM2]] > ABILITY_MIN_SCORE

analysis_n <- sum(in_analysis)
ability_n <- sum(in_ability)

## 4. 三個預測變數的編碼 ---------------------------------------------------

# 財務三欄：欠繳、欠債、無獎學金（欄名以清洗資料集為準，編碼寫入記錄）
unpaid <- as.integer(clean[[COL_TUITION]] == UNPAID_VALUE)
debtor <- as.integer(clean[[COL_DEBTOR]] == DEBTOR_VALUE)
no_scholarship <- as.integer(clean[[COL_SCHOLARSHIP]] == SCHOLARSHIP_NONE_VALUE)

# 年齡四帶：findInterval 的左閉右開 [a, b)；<25、25-29、30-39、40+
age_band_index <- findInterval(clean[[COL_AGE]], AGE_BREAKS_MODEL)
age_band <- factor(AGE_LEVELS[age_band_index + 1L], levels = AGE_LEVELS)

## 5. 能力分位：讀 T06 的分組並核對 ---------------------------------------
#    （讀輸出目錄屬本檔特例，見檔頭；對不上即停手）

if (!file.exists(QUARTILE_PATH)) {
  halt("stopped:missing-input",
       sprintf("找不到能力分位表 %s（由 04_ability.R 產出）", short_path(QUARTILE_PATH)),
       "先執行 Rscript programs/R/04_ability.R 後重跑。")
}

quartile_table <- utils::read.csv(QUARTILE_PATH, check.names = FALSE, stringsAsFactors = FALSE)
needed_quartile_cols <- c("population", "quartile", "n", "graduation_rate")
missing_quartile_cols <- setdiff(needed_quartile_cols, names(quartile_table))
if (length(missing_quartile_cols) || nrow(quartile_table) != N_QUARTILES) {
  halt("stopped:input-schema",
       sprintf("能力分位表須有 %s 四欄、%d 列；實得 %d 欄、%d 列",
               paste(needed_quartile_cols, collapse = "/"), N_QUARTILES,
               ncol(quartile_table), nrow(quartile_table)),
       "確認 04_ability.R 產出的分位表是契約界定的那一份後重跑。")
}
if (!identical(sort(quartile_table$quartile), sort(QUARTILE_LEVELS)) ||
    !all(quartile_table$population == POPULATION_ABILITY)) {
  halt("stopped:input-schema",
       "能力分位表的 population 或 quartile 值與本檔的組名不符",
       "確認 04_ability.R 產出的分位表是契約界定的那一份後重跑。")
}

# 個人歸屬：同一等量切法重建；以該表的 n 與 graduation_rate 證明是同一分組
ability_quartile <- rep(NA_integer_, nrow(clean))
ability_quartile[in_ability] <- equal_split(clean[[COL_SEM2]][in_ability], N_QUARTILES)

rebuilt_n <- tabulate(ability_quartile[in_ability], nbins = N_QUARTILES)
rebuilt_rate <- vapply(
  seq_len(N_QUARTILES),
  function(g) mean(dropout[in_ability][ability_quartile[in_ability] == g]),
  numeric(1)
)
table_n <- as.integer(quartile_table$n[order(match(quartile_table$quartile, QUARTILE_LEVELS))])
table_rate <- as.numeric(quartile_table$graduation_rate[
  order(match(quartile_table$quartile, QUARTILE_LEVELS))
])
# 分位表的 graduation_rate 是畢業率；本檔的正類是退學，故比對 1 - 退學率
rate_gap <- max(abs((1 - rebuilt_rate) - table_rate))
if (!identical(rebuilt_n, table_n) || rate_gap > PARITY_TOL) {
  halt("stopped:quartile-mismatch",
       sprintf("以 T06 的等量切法重建的分組與 %s 不一致：人數 %s 對 %s、退學率最大差 %.3g",
               short_path(QUARTILE_PATH),
               paste(rebuilt_n, collapse = "/"), paste(table_n, collapse = "/"), rate_gap),
       "由主代理裁決分位表與切法何者為準；本檔不改切法、不改分位表。")
}

# 入學成績分位：等量切四組、在能力母體（2,828）上排名
admission_quartile <- rep(NA_integer_, nrow(clean))
admission_quartile[in_ability] <- equal_split(clean[[COL_ADMISSION]][in_ability], N_QUARTILES)

## 6. 六列的配適 -----------------------------------------------------------

# 每列的預測項一律以欄名向量組成，避免在公式字串裡拼路徑或數字。
# 預測項：財務三欄與分位組皆為 0/1 與因子，無截距以外的常數。
FINANCIAL_TERMS <- FINANCIAL_COLS
AGE_TERMS <- "age_band"
QUARTILE_TERM <- "ability_band"
ADMISSION_TERM <- "admission_band"

# 分析用的資料框：只帶本檔用到的欄，母體以列索引切
model_data <- data.frame(
  dropout = as.integer(dropout),
  tuition_unpaid = unpaid,
  debtor = debtor,
  no_scholarship = no_scholarship,
  age_band = age_band,
  ability_band = factor(QUARTILE_LEVELS[ability_quartile], levels = QUARTILE_LEVELS),
  admission_band = factor(QUARTILE_LEVELS[admission_quartile], levels = QUARTILE_LEVELS),
  stringsAsFactors = FALSE
)

# 一列 = 一個（模型規格 × 母體）配對；population 與 n 逐列自帶（REQ-F-F6-1）
SPECS <- list(
  list(
    key = MODEL_AGE, reported = "age_band", population = POPULATION_ANALYSIS,
    rows = which(in_analysis), terms = AGE_TERMS,
    mechanism = "年齡帶是入學時的家庭生命階段代理：較年長者多為在職進修，退學的機會成本與可支配時間不同，故帶效應以非單調的方式出現在退學上。",
    falsifier = "若在財務三欄之上加入年齡帶後 mcfadden_r2 的增幅在四位有效數字上為零，或四帶之間的退學率差消失，則本列的「年齡帶有獨立解釋力」被否證。"
  ),
  list(
    key = MODEL_FIN, reported = "financial_three", population = POPULATION_ANALYSIS,
    rows = which(in_analysis), terms = FINANCIAL_TERMS,
    mechanism = "欠繳、欠債、無獎學金描述同一條財務壓力：繳不出學費的人被迫離校，故財務三欄的解釋力應高於年齡帶，且三個係數同向（皆提高退學）。",
    falsifier = "若本列的 mcfadden_r2 不高於年齡帶那一列，或三欄中任一係數的方向與「財務壓力提高退學」相反，則本列的機制被否證。"
  ),
  list(
    key = MODEL_FIN, reported = "financial_three_ability", population = POPULATION_ABILITY,
    rows = which(in_ability), terms = FINANCIAL_TERMS,
    mechanism = "同一個財務三欄在 2,828 上重配：剔除第二學期零分者已移走一部分最直接的財務退學路徑，故同一規格的 mcfadden_r2 應低於 3,630 上的那一列。",
    falsifier = "若本列的 mcfadden_r2 不低於 3,630 上同一規格那一列，則「剔除零分者移走了財務退學路徑」的讀法被否證。"
  ),
  list(
    key = MODEL_ABILITY, reported = "ability_quartile", population = POPULATION_ABILITY,
    rows = which(in_ability), terms = QUARTILE_TERM,
    mechanism = "能力分位由第二學期成績切出，是同期在校表現：成績低者被當、失去學分而退學，故與退學同向；但這是同期伴隨，不是入學前的能力。",
    falsifier = "若以第一學期分位取代第二學期分位後 mcfadden_r2 不下降，或本列的 mcfadden_r2 高於同母體的財務三欄，則「同期成績而非先前能力」的讀法被否證。"
  ),
  list(
    key = MODEL_FIN_ABILITY, reported = "financial_plus_ability", population = POPULATION_ABILITY,
    rows = which(in_ability), terms = c(FINANCIAL_TERMS, QUARTILE_TERM),
    mechanism = "財務先行、能力同期：兩者相加的解釋力高於任一單獨規格，說明「繳不出錢」與「讀不下去」是兩條部分獨立的路徑，而非同一件事的兩種說法。",
    falsifier = "若在財務三欄之上加入能力分位、或在能力分位之上加入財務三欄後 mcfadden_r2 的增幅為零或負，則本列的「兩條路徑部分獨立」被否證。"
  ),
  list(
    key = MODEL_ADMISSION, reported = "admission_quartile", population = POPULATION_ABILITY,
    rows = which(in_ability), terms = ADMISSION_TERM,
    mechanism = "入學成績分位是入學前的學術準備，離退學的時點最遠：它若有解釋力，應遠小於同期的能力分位，故本列是「入學前資訊幾乎不含退學資訊」的量度。",
    falsifier = "若本列的 mcfadden_r2 不低於同母體的能力分位，或本列的 auc 低於 0.5（方向反轉），則「入學前成績幾乎不含退學資訊」被否證。"
  )
)

# 配適一列：收斂失敗或解釋力無法定義時回具名狀態，數值留 NA，其餘列照出
fit_spec <- function(spec) {
  dat <- model_data[spec$rows, , drop = FALSE]
  formula <- stats::as.formula(paste("dropout ~", paste(spec$terms, collapse = " + ")))
  fit <- tryCatch(
    stats::glm(formula, data = dat, family = stats::binomial()),
    error = function(e) e
  )
  if (inherits(fit, "error") || !isTRUE(fit$converged)) {
    return(list(
      status = "refuse:empty-denominator", r2 = NA_real_, auc = NA_real_,
      n = nrow(dat), converged = FALSE, fit = NULL,
      reason = if (inherits(fit, "error")) conditionMessage(fit) else "glm 未收斂"
    ))
  }

  # 虛無模型即僅有截距的模型，其對數似然為 -null.deviance / 2
  ll_model <- as.numeric(stats::logLik(fit))
  ll_null <- -fit$null.deviance / 2
  r2 <- mcfadden_r2(ll_model, ll_null)
  if (is.character(r2)) {
    return(list(
      status = r2, r2 = NA_real_, auc = NA_real_, n = nrow(dat),
      converged = TRUE, fit = fit, ll_model = ll_model, ll_null = ll_null,
      reason = "解釋力無法定義（虛無模型的對數似然為零）"
    ))
  }

  # 分數為預測的退學機率（type = "response"），正類為退學
  score <- stats::predict(fit, type = "response")
  auc <- auc_rank(score, dat$dropout == 1L)
  if (is.character(auc)) {
    return(list(
      status = auc, r2 = r2, auc = NA_real_, n = nrow(dat),
      converged = TRUE, fit = fit, ll_model = ll_model, ll_null = ll_null,
      reason = "曲線下面積無法定義（只有一個類別）"
    ))
  }

  list(
    status = "ok", r2 = r2, auc = auc, n = nrow(dat), converged = TRUE, fit = fit,
    ll_model = ll_model, ll_null = ll_null, deviance = fit$deviance,
    null_deviance = fit$null.deviance, reason = NA_character_
  )
}

fits <- lapply(SPECS, fit_spec)

## 7. 解釋力與報告值的比對 ------------------------------------------------

# 報告所載的解釋力逐列比對；不同者標 mismatch，不自行改寫（A-23）
comparisons <- Map(function(spec, fit) {
  text <- unname(REPORTED_R2[[spec$reported]])
  if (is.na(text)) {
    stop(sprintf("報告值表缺 %s 的條目", spec$reported), call. = FALSE)
  }
  precision <- reported_precision(text)
  reported <- as.numeric(text)
  if (!is.finite(fit$r2)) {
    return(list(reported = reported, text = text, gap = NA_real_,
                tolerance = precision$tolerance, match = NA,
                status = fit$status))
  }
  gap <- fit$r2 - reported
  list(
    reported = reported, text = text, gap = gap,
    tolerance = precision$tolerance,
    match = abs(gap) <= precision$tolerance,
    status = if (abs(gap) <= precision$tolerance) "ok" else "mismatch"
  )
}, SPECS, fits)

# 一列的 status：配適成功且與報告相符才是 ok
row_status <- vapply(seq_along(SPECS), function(i) {
  if (!identical(fits[[i]]$status, "ok")) fits[[i]]$status else comparisons[[i]]$status
}, character(1))

mismatch_index <- which(row_status == "mismatch")

## 8. 寫表 -----------------------------------------------------------------

comparison <- data.frame(
  model = vapply(SPECS, `[[`, character(1), "key"),
  population = vapply(SPECS, `[[`, character(1), "population"),
  n = vapply(fits, function(f) as.integer(f$n), integer(1)),
  mcfadden_r2 = vapply(fits, function(f) as.numeric(f$r2), numeric(1)),
  auc = vapply(fits, function(f) as.numeric(f$auc), numeric(1)),
  mechanism = vapply(SPECS, `[[`, character(1), "mechanism"),
  falsifier = vapply(SPECS, `[[`, character(1), "falsifier"),
  status = row_status,
  stringsAsFactors = FALSE
)

atomic_write(TABLE_PATH, function(path) readr::write_csv(comparison, path))

## 9. 記錄 -----------------------------------------------------------------

# 每個模型的配適摘要：n、對數似然、解釋力、面積、收斂狀態
fit_lines <- vapply(seq_along(SPECS), function(i) {
  fit <- fits[[i]]
  spec <- SPECS[[i]]
  if (!identical(fit$status, "ok") && !isTRUE(fit$converged)) {
    return(sprintf(
      "model_rows: model=%s population=%s n=%d converged=%s status=%s reason=%s",
      spec$key, spec$population, fit$n, fit$converged, fit$status, fit$reason
    ))
  }
  sprintf(
    "model_rows: model=%s population=%s n=%d converged=%s ll_model=%s ll_null=%s null_deviance=%s mcfadden_r2=%s r2_fmt=%s auc=%s status=%s",
    spec$key, spec$population, fit$n, fit$converged,
    format(fit$ll_model, digits = 15), format(fit$ll_null, digits = 15),
    format(fit$null_deviance, digits = 15),
    format(fit$r2, digits = 15), fmt_sig(fit$r2), fmt_sig(fit$auc), row_status[i]
  )
}, character(1))

# 係數逐項（broom 的整理，寫入記錄；不入表）
tidy_lines <- unlist(lapply(seq_along(SPECS), function(i) {
  fit <- fits[[i]]$fit
  if (is.null(fit)) {
    return(sprintf("coefficients: model=%s population=%s unavailable（未配適成功）",
                   SPECS[[i]]$key, SPECS[[i]]$population))
  }
  tidy <- broom::tidy(fit)
  header <- sprintf("coefficients: model=%s population=%s", SPECS[[i]]$key, SPECS[[i]]$population)
  rows <- sprintf(
    "  term=%s estimate=%s std_error=%s statistic=%s p_value=%s",
    tidy$term, fmt_sig(tidy$estimate), fmt_sig(tidy$std.error),
    fmt_sig(tidy$statistic), fmt_sig(tidy$p.value)
  )
  c(header, rows)
}), use.names = FALSE)

# 比對結果逐列（四位有效數字的比較與差異）
compare_lines <- vapply(seq_along(SPECS), function(i) {
  fit <- fits[[i]]
  cmp <- comparisons[[i]]
  if (is.na(cmp$match)) {
    return(sprintf(
      "compare: model=%s population=%s computed=%s reported=%s match=NA status=%s",
      SPECS[[i]]$key, SPECS[[i]]$population, fmt_sig(fit$r2), cmp$text, row_status[i]
    ))
  }
  sprintf(
    "compare: model=%s population=%s computed=%s reported=%s diff=%s tolerance=%s match=%s status=%s",
    SPECS[[i]]$key, SPECS[[i]]$population, fmt_sig(fit$r2), cmp$text,
    fmt_sig(cmp$gap), format(cmp$tolerance, scientific = TRUE),
    cmp$match, row_status[i]
  )
}, character(1))

mismatch_lines <- if (!length(mismatch_index)) {
  "mismatch: none"
} else {
  c(
    sprintf("mismatch: %d 列與報告所載不同（四位有效數字），交主代理裁決，本檔不改報告的數字",
            length(mismatch_index)),
    vapply(mismatch_index, function(i) {
      sprintf("  - %s＠%s：算得 %s，報告 %s（差 %s，容差 %s）",
              SPECS[[i]]$key, SPECS[[i]]$population,
              fmt_sig(fits[[i]]$r2), comparisons[[i]]$text,
              fmt_sig(comparisons[[i]]$gap),
              format(comparisons[[i]]$tolerance, scientific = TRUE))
    }, character(1))
  )
}

log_block(c(
  sprintf("r_version: %s", R.version.string),
  sprintf("proj_root: %s", PROJ_ROOT),
  sprintf("out_root: %s", OUT_ROOT),
  sprintf("input: %s", short_path(CLEAN_PATH)),
  sprintf("input_rows: %d", nrow(clean)),
  sprintf("population: %s %d（結果欄為 %s）", POPULATION_ANALYSIS, analysis_n,
          paste(ANALYSIS_RESULTS, collapse = "/")),
  sprintf("population: %s %d（分析母體 ∩ %s > %s）", POPULATION_ABILITY, ability_n,
          COL_SEM2, format(ABILITY_MIN_SCORE)),
  sprintf("financial_columns: %s = (%s == %d)、%s = (%s == %d)、%s = (%s == %d)",
          FINANCIAL_COLS[1], COL_TUITION, UNPAID_VALUE,
          FINANCIAL_COLS[2], COL_DEBTOR, DEBTOR_VALUE,
          FINANCIAL_COLS[3], COL_SCHOLARSHIP, SCHOLARSHIP_NONE_VALUE),
  sprintf("financial_marginals: %s", paste(sprintf(
    "%s=%d", FINANCIAL_COLS,
    c(sum(unpaid[in_analysis]), sum(debtor[in_analysis]), sum(no_scholarship[in_analysis]))
  ), collapse = "、")),
  sprintf("age_band_parameterization: AGE_BREAKS_MODEL = c(%s) → 四帶 %s（findInterval 的左閉右開 [a, b)）",
          paste(AGE_BREAKS_MODEL, collapse = ", "), paste(AGE_LEVELS, collapse = "、")),
  sprintf("age_band_n: %s（%d 帶，合計 %d 人）",
          paste(tabulate(age_band_index[in_analysis] + 1L, nbins = length(AGE_LEVELS)),
                collapse = "/"), length(AGE_LEVELS), analysis_n),
  "age_band_note: 五帶參數化（AGE_BREAKS）得 0.0839，與四帶的 0.0756 不可混用；本檔一律用四帶",
  sprintf("ability_quartile_source: %s（T06 的等量切法；本檔不重切）", short_path(QUARTILE_PATH)),
  "ability_quartile_note: 該表為四列彙總、無個人層鍵；個人歸屬以同一等量切法重建，並以表的 n 與 graduation_rate 逐組核對",
  sprintf("ability_quartile_n: %s（分位表 %s；重建 %s）",
          paste(rebuilt_n, collapse = "/"), paste(table_n, collapse = "/"),
          paste(rebuilt_n, collapse = "/")),
  sprintf("ability_quartile_rate_gap: %.3g（1 - graduation_rate 對重建的退學率，容差 %s）",
          rate_gap, format(PARITY_TOL, scientific = TRUE)),
  sprintf("admission_quartile_binning: %s 等量切四組、在 %d 人上排名（組寬 707，末組收餘）",
          COL_ADMISSION, ability_n),
  sprintf("admission_quartile_n: %s",
          paste(tabulate(admission_quartile[in_ability], nbins = N_QUARTILES), collapse = "/")),
  sprintf("positive_class: %s（分數為 predict(type = \"response\")，AUC 由 auc_rank 以同分平均秩計算）",
          DROPOUT),
  sprintf("row_order: 同母體連續排列 — %s", paste(comparison$population, collapse = "/")),
  fit_lines,
  tidy_lines,
  compare_lines,
  mismatch_lines,
  "value_scale: mcfadden_r2 與 auc 皆為 0 至 1 的無單位量；表存未格式化 double（D9）",
  "table_precision: 四位有效數字只在記錄與呈現層，表存全精度",
  sprintf("product: %s rows=%d cols=%d", short_path(TABLE_PATH), nrow(comparison), ncol(comparison)),
  if (length(mismatch_index)) "status: mismatch（停止交付，待主代理裁決規格或報告數字）" else "status: ok",
  if (length(mismatch_index)) {
    "next_step: 回報差異清單；由主代理裁決改模型規格或改報告數字，本檔不自行改寫"
  } else {
    "next_step: F6 的比較表完成"
  }
))

cat(sprintf("05_models: 六列（分析母體 %d、能力母體 %d）\n", analysis_n, ability_n))
for (i in seq_along(SPECS)) {
  cat(sprintf(
    "05_models: %-22s %-9s n=%4d  mcfadden_r2=%s  auc=%s  status=%s\n",
    SPECS[[i]]$key, SPECS[[i]]$population, comparison$n[i],
    fmt_sig(comparison$mcfadden_r2[i]), fmt_sig(comparison$auc[i]), comparison$status[i]
  ))
}
if (length(mismatch_index)) {
  cat(sprintf("05_models: %d 列與報告所載不同（四位有效數字），已標 mismatch，待裁決\n",
              length(mismatch_index)))
}
cat(sprintf("05_models: 表 %s、記錄 %s\n", short_path(TABLE_PATH), short_path(LOG_PATH)))
