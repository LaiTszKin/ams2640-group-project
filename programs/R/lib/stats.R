# stats.R — 可重用的統計量
#
# 六個具名函式：prop_ci（比率與威爾遜區間）、fisher_2x2（精確檢定）、
# phi_2x2（關聯強度）、mcfadden_r2（解釋力）、auc_rank（秩式曲線下面積）、
# fmt_sig（四位有效數字的呈現）。分析腳本只 source 本檔取統計量，不自行實作
# （PRD §5）。
#
# 常數一律取自 00_setup.R（REQ-A-2）：本檔不寫死母體、呈現位數或信賴水準，
# 也不讀任何資料。可獨立 source；重複 source 為無操作。
#
# 異常輸入回具名類別而非 NaN：
#   "refuse:empty-denominator" — 分母為零，如 prop_ci(0, 0) 或空樣本
#   "refuse:single-class"      — 所需欄位只有一個類別，如 phi_2x2(10, 10, 0, 0)
# 兩者皆為長度一的 character（不是 list、不是 NaN），呼叫端以
# identical(x, "refuse:...") 判定後停止並記錄，不寫空表。
#
# 用法：source("programs/R/lib/stats.R")

source(file.path(here::here("programs/R/00_setup.R")))

## 1. 比例與其區間 ---------------------------------------------------------

# prop_ci(k, n, level)：k 次成功於 n 次試驗的比例與其威爾遜分數區間。
#
# 區間以 PropCIs 為底（scoreci 即威爾遜分數區間）。該套件的原始碼把上下界
# round(digits = 4)，與 D9「表存未格式化 double、捨入只在呈現層」相抵，故以
# 同一算式重算未捨入的界，並在此確認兩者只差在它那一次捨入（差的上界為
# 五位小數的一半）。回傳的 level 原樣帶出，供呼叫端寫入記錄。
#
# 回傳 list(lower, upper, estimate, level)；n 為零時回 "refuse:empty-denominator"。
prop_ci <- function(k, n, level = PROP_CI_LEVEL) {
  if (!is.numeric(k) || !is.numeric(n) || length(k) != 1L || length(n) != 1L) {
    stop("prop_ci：k 與 n 須為長度一的數值", call. = FALSE)
  }
  if (!is.numeric(level) || length(level) != 1L || is.na(level) || level <= 0 || level >= 1) {
    stop("prop_ci：level 須為 (0, 1) 內的長度一數值", call. = FALSE)
  }
  if (is.na(k) || is.na(n) || n < 0 || k < 0 || k > n) {
    stop("prop_ci：須滿足 0 <= k <= n", call. = FALSE)
  }
  if (n == 0) return("refuse:empty-denominator")

  phat <- k / n
  z <- stats::qnorm(1 - (1 - level) / 2)
  denom <- 1 + z^2 / n
  centre <- (phat + z^2 / (2 * n)) / denom
  half <- z / denom * sqrt(phat * (1 - phat) / n + z^2 / (4 * n^2))

  lower <- max(0, centre - half)
  upper <- min(1, centre + half)

  reference <- PropCIs::scoreci(k, n, level)$conf.int
  if (any(abs(c(lower, upper) - reference) > 5e-05)) {
    stop("prop_ci：PropCIs::scoreci 與威爾遜算式不一致", call. = FALSE)
  }

  list(lower = lower, upper = upper, estimate = phat, level = level)
}

## 2. 精確檢定 -------------------------------------------------------------

# fisher_2x2(a, b, c, d)：以列序 [a b; c d] 組 2×2，回樣本勝算比 ad/bc 與
# 雙尾精確檢定的 p。fisher.test 的 estimate 是條件最大概似勝算比，與樣本
# 勝算比在格子小的時候不同，故勝算比自行由格子算出。
#
# 任一列或任一欄的邊際和為零時沒有勝算比可言，回 "refuse:empty-denominator"；
# 佔位空格（如 b = 0）不是零分母，勝算比為 0 或 Inf，照常回傳。
fisher_2x2 <- function(a, b, c, d) {
  cells <- c(a, b, c, d)
  if (!is.numeric(cells) || length(cells) != 4L) {
    stop("fisher_2x2：a、b、c、d 須為四個數值", call. = FALSE)
  }
  if (anyNA(cells) || any(cells < 0) || any(cells != round(cells))) {
    stop("fisher_2x2：四格須為非負整數", call. = FALSE)
  }

  tab <- matrix(cells, nrow = 2L, byrow = TRUE)
  if (any(rowSums(tab) == 0) || any(colSums(tab) == 0)) {
    return("refuse:empty-denominator")
  }

  # 邊際皆非零時 ad 與 bc 不會同時為零；bc 為零即勝算比無上界。
  # 兩個乘積同樣先轉 double：本母體的邊際下整數乘積仍在範圍內（a*d 的上界
  # 是母體半數的平方），但與 phi_2x2 共用一種運算型別，母體放大時不必再找
  # 第二次。
  numerator <- as.numeric(a) * as.numeric(d)
  denominator <- as.numeric(b) * as.numeric(c)
  odds_ratio <- if (denominator == 0) Inf else numerator / denominator

  test <- stats::fisher.test(tab, alternative = "two.sided")
  list(odds_ratio = odds_ratio, p_value = unname(test$p.value))
}

## 3. 關聯強度 -------------------------------------------------------------

# phi_2x2(a, b, c, d)：2×2 的 phi 係數，等於兩欄的皮爾森相關係數。
# 任一列或任一欄為空即只有一個類別，分母（邊際和的乘積）為零，
# 回 "refuse:single-class"。合法的稀疏格（如 phi_2x2(10, 0, 0, 10)）
# 回 1，不拒絕。
phi_2x2 <- function(a, b, c, d) {
  cells <- c(a, b, c, d)
  if (!is.numeric(cells) || length(cells) != 4L) {
    stop("phi_2x2：a、b、c、d 須為四個數值", call. = FALSE)
  }
  if (anyNA(cells) || any(cells < 0) || any(cells != round(cells))) {
    stop("phi_2x2：四格須為非負整數", call. = FALSE)
  }

  # 四格與邊際先轉 double：整數乘積在四格為四位數時就已超過整數上限
  # （2^31 - 1 ≈ 2.1e9），逐項相乘到第三項即溢位成 NA 並發出警告；double 的
  # 乘積在 2^53 以內仍逐位元精確，故轉型不改變任何合法輸入的結果，只是把
  # 溢位這條路封死。向量化的呼叫端（整數計數欄）曾因此拿到 NA，而同一組格
  # 以 double 傳入卻得正確值——兩種型別必須同值，見第 6 節的回歸檢查。
  a <- as.numeric(a)
  b <- as.numeric(b)
  c <- as.numeric(c)
  d <- as.numeric(d)

  rows <- c(a + b, c + d)
  cols <- c(a + c, b + d)
  if (rows[1] == 0 || rows[2] == 0 || cols[1] == 0 || cols[2] == 0) {
    return("refuse:single-class")
  }

  (a * d - b * c) / sqrt(rows[1] * rows[2] * cols[1] * cols[2])
}

## 4. 解釋力與曲線下面積 ---------------------------------------------------

# mcfadden_r2(ll_model, ll_null)：1 - ll_model / ll_null。
#
# ll_null 為零即結果只有一個類別（虛無模型的對數似然為零），回
# "refuse:single-class"。完全分離不在本函式判定：分離與否是配適的性質，
# 兩個對數似然不足以分辨，改由呼叫端在配適失敗時記錄。
mcfadden_r2 <- function(ll_model, ll_null) {
  if (!is.numeric(ll_model) || !is.numeric(ll_null) ||
      length(ll_model) != 1L || length(ll_null) != 1L) {
    stop("mcfadden_r2：ll_model 與 ll_null 須為長度一的數值", call. = FALSE)
  }
  if (is.na(ll_model) || is.na(ll_null)) {
    stop("mcfadden_r2：對數似然不得為 NA", call. = FALSE)
  }
  if (ll_null == 0) return("refuse:single-class")

  1 - ll_model / ll_null
}

# auc_rank(score, y)：秩式曲線下面積，同分取平均秩。
#
# y 為正類標記，須為 logical 或 0/1 數值（正類為 TRUE 或 1），長度與 score
# 相同；標記不由此處猜測，避免因字串排序悄悄換掉正類。樣本為空回
# "refuse:empty-denominator"，只有一個類別回 "refuse:single-class"。
# 算式為 Mann–Whitney 形式：正類的平均秩和減去其自身可配對數，除以正負類
# 配對數。
auc_rank <- function(score, y) {
  if (!is.numeric(score)) {
    stop("auc_rank：score 須為數值", call. = FALSE)
  }
  n <- length(score)
  if (length(y) != n) {
    stop("auc_rank：score 與 y 的長度須相同", call. = FALSE)
  }
  if (is.logical(y)) {
    positive <- y
  } else if (is.numeric(y) && all(y %in% c(0, 1))) {
    positive <- y == 1
  } else {
    stop("auc_rank：y 須為 logical 或 0/1 數值（正類為 TRUE 或 1）", call. = FALSE)
  }
  if (anyNA(score) || anyNA(positive)) {
    stop("auc_rank：score 與 y 不得含 NA", call. = FALSE)
  }
  if (n == 0L) return("refuse:empty-denominator")

  n_pos <- sum(positive)
  n_neg <- n - n_pos
  if (n_pos == 0L || n_neg == 0L) return("refuse:single-class")

  ranks <- rank(score, ties.method = "average")
  (sum(ranks[positive]) - n_pos * (n_pos + 1) / 2) / (n_pos * n_neg)
}

## 5. 呈現 ---------------------------------------------------------------

# fmt_sig(x, digits)：以 digits 位有效數字把數字轉成字串，計數一律整數。
# 只在呈現層呼叫；表與記錄存的是未格式化的 double（D9）。
#
# 整數值的數（含計數）輸出無小數點，故計數不會出現小數；其餘取 digits 位
# 有效數字並保留尾隨零（0.6930 寫成四位，不是三位），極小或極大者用科學記號。
# 具名類別（"refuse:..." 字串）原樣帶出，讓拒絕能落進表格的同一欄；NA 回
# NA_character_。可接受向量，回傳同長度的 character。
fmt_sig <- function(x, digits = SIG_DIGITS) {
  if (is.character(x)) return(x)
  if (!is.numeric(x)) {
    stop("fmt_sig：x 須為數值或具名類別的字串", call. = FALSE)
  }
  if (!is.numeric(digits) || length(digits) != 1L || is.na(digits) || digits < 1) {
    stop("fmt_sig：digits 須為 >= 1 的長度一數值", call. = FALSE)
  }

  template <- paste0("%#.", as.integer(digits), "g")
  vapply(x, function(value) {
    if (is.na(value)) return(NA_character_)
    if (!is.finite(value)) return(format(value, trim = TRUE))
    if (value == round(value)) return(sprintf("%.0f", value))
    sprintf(template, value)
  }, character(1))
}

## 6. 整數輸入的回歸檢查 ---------------------------------------------------

# 同一組四格因型別而有兩種結果，是這個檔案最難在呼叫端察覺的失效：整數四格
# 回 NA（第 3 節的乘積溢位），double 四格回數值，而 NA 仍是 numeric，呼叫端
# 無法以型別分辨。以下在 source 時比對兩組真實四格的兩種型別，不一致即停止
# ——寧可載入時失敗，也不讓下游以 NA 寫出表。
#
# 兩組四格皆為分析母體的四格分割，其中 226/260/187/2957 即
# output/tables/wealth_four_cell.csv 的四格。檢查只做純算術，無狀態、無輸出，
# 重複 source 的結果相同。
local({
  for (cells in list(c(457L, 29L, 964L, 2180L), c(226L, 260L, 187L, 2957L))) {
    from_integer <- do.call(phi_2x2, as.list(cells))
    from_double <- do.call(phi_2x2, as.list(as.numeric(cells)))
    if (!identical(from_integer, from_double)) {
      stop(sprintf("phi_2x2：整數四格 %s 回 %s，double 回 %s（整數乘積溢位）",
                   paste(cells, collapse = "/"),
                   format(from_integer), format(from_double)),
           call. = FALSE)
    }
  }
})
