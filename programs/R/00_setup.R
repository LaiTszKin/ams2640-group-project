# 00_setup.R — 專案唯一的設定來源
#
# 本檔持有路徑根、母體界線、年齡切點、分位數、容差、呈現常數與套件檢查
# （REQ-A-2、REQ-A-4）。分析腳本只 source 本檔取常數，不自行寫出這些數字，
# 也不寫死 output/ 下的字面路徑；所有寫入路徑一律由 OUT_ROOT 導出。
#
# 用法：source("programs/R/00_setup.R")，之後下列常數即在 global env 可用；
# 重複 source 為無操作（常數值相同、同一個 R session 只寫一段記錄）。

## 1. 路徑根 ---------------------------------------------------------------

# here() 由 AMS2640.Rproj 決定根，從專案子目錄執行也指回根目錄。
# 非專案目錄時 here() 會靜默退回 cwd（README 記錄的陷阱），故檢查標記檔。
PROJ_ROOT <- here::here()
if (!file.exists(file.path(PROJ_ROOT, "AMS2640.Rproj"))) {
  stop(
    "找不到專案根目錄：here() 未解析到含 AMS2640.Rproj 的目錄（目前為 ",
    PROJ_ROOT, "）；請在專案或其子目錄下執行。",
    call. = FALSE
  )
}

# 輸出基底：表在 file.path(OUT_ROOT, "tables")、記錄在 file.path(OUT_ROOT, "logs")。
# RTOOLKIT_OUT_ROOT 讓測試與可重建檢查把輸出導到暫存根，不動 output/。
OUT_ROOT <- Sys.getenv("RTOOLKIT_OUT_ROOT", unset = "")
if (!nzchar(OUT_ROOT)) OUT_ROOT <- file.path(PROJ_ROOT, "output")

# .Rprofile 只在專案根被 R 讀取；從子目錄 source 本檔時，這裡自行把版本環境載入，
# 讓套件與路徑兩者都與工作目錄無關（REQ-A-1：不靠 setwd）。
# 用 renv::load(project=) 而非 source(activate.R)：activate.R 以 cwd 認定專案，
# 在子目錄會被解讀成子目錄自己是一個專案。
if (!renv::paths$library(project = PROJ_ROOT) %in% .libPaths()) {
  suppressMessages(renv::load(project = PROJ_ROOT))
}

## 2. 母體界線 -------------------------------------------------------------

# 分析母體人數：已畢業加已退學，不可逆（PRD D2）。結果為在讀者不進分析母體。
ANALYSIS_N <- 3630L

# 能力母體人數：分析母體與第二學期成績大於 ABILITY_MIN_SCORE 的交集（PRD D4）。
ABILITY_N <- 2828L

# 結果欄入分析母體的兩個類別值（第三類 Enrolled 只留在清洗資料集）。
ANALYSIS_RESULTS <- c("Graduate", "Dropout")

# 能力母體門檻：第二學期成績須嚴格大於此值；零分是「無成績」，不是低能力。
ABILITY_MIN_SCORE <- 0

# 已退役分母 4,424 = 分析母體 3,630 + 在讀 794；任何表都不得再以它為分母。
RETIRED_ANALYSIS_N <- 4424L

## 3. 年齡與能力切點 -------------------------------------------------------

# 年齡帶切點，左閉右開 [a, b)：<20、20-24、25-29、30-39、40+（最後一帶為 [40, ∞)）。
# 不得用 cut() 的預設右閉：右閉得 2080/646/326/379/199，與釘值不符。
AGE_BREAKS <- c(20, 25, 30, 40)

# 模型用的四帶參數化（<25 併為一帶）：<25、25-29、30-39、40+，供 T07 重現 0.0756；
# 五帶切法得 0.0839，兩種參數化不可混用。
AGE_BREAKS_MODEL <- c(25, 30, 40)

# 能力分位數：依第二學期成績切四分位，四組各 707 人。
N_QUARTILES <- 4L

## 4. 統計與呈現 -----------------------------------------------------------

# 比例的信賴水準：lib 的威爾遜區間（prop_ci）預設值，函式內不寫死。
PROP_CI_LEVEL <- 0.95

# 兩端容差：計數零差；比率與 p 值的相對差上限，對未格式化的 double 比對（PRD D10）。
PARITY_TOL <- 1e-9

# 呈現位數：比率與解釋力取四位有效數字，計數取整數（PRD D9）；只作用在呈現層。
SIG_DIGITS <- 4L

## 5. 資料品質 -------------------------------------------------------------

# 清洗後 NA 儲存格總數上限，不含「未登記修讀」的 180 列（兩學期皆 0 是 0，不是缺值）。
# 超出即 refuse:missing-profile（T02 的拒絕門檻）。
MISSING_PROFILE <- 0L

## 6. 套件同步檢查與自檢記錄 -----------------------------------------------

# 本專案會呼叫的套件：testthat（T14 與 V01–V11 的測試台）、PropCIs（T03 的威爾遜
# 區間）、broom（T07 的模型整理），其餘為既有的資料處理與路徑套件。
# 未登記於 renv.lock 或未安裝即 refuse:unpinned-package，且不產生任何表。
local({
  # renv 以靜態掃描決定鎖定檔該收哪些套件，故這裡的 requireNamespace() 寫成字面呼叫；
  # 寫成 vapply(required, requireNamespace, ...) 掃不到，鎖定檔會缺件、status 轉假。
  available <- c(
    renv     = requireNamespace("renv", quietly = TRUE),
    here     = requireNamespace("here", quietly = TRUE),
    dplyr    = requireNamespace("dplyr", quietly = TRUE),
    readr    = requireNamespace("readr", quietly = TRUE),
    haven    = requireNamespace("haven", quietly = TRUE),
    testthat = requireNamespace("testthat", quietly = TRUE),
    PropCIs  = requireNamespace("PropCIs", quietly = TRUE),
    broom    = requireNamespace("broom", quietly = TRUE)
  )
  required <- names(available)
  lockfile <- file.path(PROJ_ROOT, "renv.lock")
  log_file <- file.path(OUT_ROOT, "logs", "00_setup.log")

  # 某個 library 內的套件版本（讀 DESCRIPTION 的 Version）
  library_versions <- function(path) {
    if (!dir.exists(path)) return(stats::setNames(character(), character()))
    pkgs <- list.dirs(path, full.names = FALSE, recursive = FALSE)
    pkgs <- pkgs[file.exists(file.path(path, pkgs, "DESCRIPTION"))]
    out <- vapply(pkgs, function(p) {
      dcf <- tryCatch(read.dcf(file.path(path, p, "DESCRIPTION")), error = function(e) NULL)
      if (is.null(dcf) || !"Version" %in% colnames(dcf)) NA_character_ else unname(dcf[1, "Version"])
    }, character(1), USE.NAMES = TRUE)
    stats::setNames(out, pkgs)
  }

  installed <- library_versions(renv::paths$library(project = PROJ_ROOT))

  # 還原前的狀態由 .Rprofile 交棒，格式 pkg=ver;pkg=ver
  before <- local({
    text <- Sys.getenv("RTOOLKIT_LIBRARY_BEFORE", unset = "")
    if (!nzchar(text)) return(stats::setNames(character(), character()))
    pairs <- strsplit(text, ";", fixed = TRUE)[[1]]
    stats::setNames(sub("^[^=]*=", "", pairs), sub("=.*$", "", pairs))
  })
  before <- before[nzchar(names(before))]

  # 只有真的跑過 renv::restore() 才有所謂的補件／降級；否則交棒狀態不完整，
  # 差集會把所有套件誤報成「補件」。
  restored <- identical(Sys.getenv("RTOOLKIT_RESTORE_ACTION", unset = "none"), "restore")
  added <- if (restored) setdiff(names(installed), names(before)) else character()
  removed <- if (restored) setdiff(names(before), names(installed)) else character()
  shared <- if (restored) intersect(names(before), names(installed)) else character()
  downgraded <- shared[vapply(shared, function(p) {
    isTRUE(tryCatch(
      utils::package_version(before[[p]]) > utils::package_version(installed[[p]]),
      error = function(e) FALSE
    ))
  }, logical(1))]

  # 鎖定檔登記的套件與版本
  locked <- local({
    if (!file.exists(lockfile)) return(stats::setNames(character(), character()))
    records <- renv::lockfile_read(lockfile)$Packages
    out <- vapply(records, function(r) {
      if (is.null(r$Version)) NA_character_ else as.character(r$Version)
    }, character(1), USE.NAMES = TRUE)
    stats::setNames(out, names(records))
  })

  base_packages <- rownames(utils::installed.packages(priority = "base"))
  unregistered_required <- setdiff(required, names(locked))
  not_installed <- required[!available]

  # 程式引用但未登記的套件：掃 library()／require()／requireNamespace()／pkg::
  unregistered <- local({
    files <- list.files(
      file.path(PROJ_ROOT, "programs", "R"),
      pattern = "[.]R$", recursive = TRUE, full.names = TRUE
    )
    if (!length(files)) return(character())
    text <- unlist(lapply(files, readLines, warn = FALSE), use.names = FALSE)
    text <- sub("#.*$", "", text)               # 註解裡的舉例不是引用
    via_ns <- sub("::$", "", unlist(regmatches(text, gregexpr("[A-Za-z][A-Za-z0-9.]*::", text))))
    via_call <- sub(
      "^[^(]*\\([\"']?", "",
      unlist(regmatches(
        text,
        gregexpr("[^$[:alnum:]_.](library|require|requireNamespace)\\([\"']?[A-Za-z][A-Za-z0-9.]*", text)
      ))
    )
    referenced <- setdiff(unique(c(via_ns, via_call)), base_packages)
    setdiff(referenced, names(locked))
  })

  # renv 自己的判定；輸出吞掉，拒絕時才由本檔列清單
  status <- tryCatch(
    {
      utils::capture.output(st <- suppressMessages(renv::status(project = PROJ_ROOT)))
      st
    },
    error = function(e) NULL
  )
  synchronized <- isTRUE(status$synchronized)
  # 只列鎖定檔或專案 library 兩側真的有的套件，renv 視野中的 base/recommended 不列
  out_of_sync <- if (synchronized || is.null(status)) {
    character()
  } else {
    setdiff(
      intersect(
        unique(c(names(status$library$Packages), names(status$lockfile$Packages))),
        union(names(locked), names(installed))
      ),
      base_packages
    )
  }
  out_of_sync_text <- if (!length(out_of_sync)) {
    ""
  } else {
    paste0(
      "：", paste(utils::head(out_of_sync, 10L), collapse = ", "),
      if (length(out_of_sync) > 10L) sprintf(" 等 %d 個", length(out_of_sync)) else ""
    )
  }

  problems <- c(
    if (length(unregistered_required))
      sprintf("鎖定檔未登記本專案會呼叫的套件：%s", paste(unregistered_required, collapse = ", ")),
    if (length(not_installed))
      sprintf("套件未安裝：%s", paste(not_installed, collapse = ", ")),
    if (length(unregistered))
      sprintf("程式引用但鎖定檔未登記：%s", paste(unregistered, collapse = ", ")),
    if (!synchronized && !is.null(status))
      sprintf("版本環境與 renv.lock 不同步%s", out_of_sync_text)
  )

  # 記錄：R 版本、套件數、還原耗時、補件與降級清單（F1 的可見面）
  if (!identical(Sys.getenv("RTOOLKIT_SETUP_LOGGED"), "1")) {
    dir.create(dirname(log_file), recursive = TRUE, showWarnings = FALSE)
    lines <- c(
      sprintf("== 00_setup %s ==", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
      sprintf("r_version: %s", R.version.string),
      sprintf("package_count: %d", length(locked)),
      sprintf("installed_packages: %d", length(installed)),
      sprintf("restore_action: %s", Sys.getenv("RTOOLKIT_RESTORE_ACTION", unset = "none")),
      sprintf("restore_elapsed_sec: %s", Sys.getenv("RTOOLKIT_RESTORE_ELAPSED", unset = "0")),
      sprintf("added_on_restore: %s", if (length(added)) paste(added, collapse = ", ") else "none"),
      sprintf("downgraded_on_restore: %s", if (length(downgraded)) paste(downgraded, collapse = ", ") else "none"),
      sprintf("removed_on_restore: %s", if (length(removed)) paste(removed, collapse = ", ") else "none"),
      sprintf("synchronized: %s", synchronized),
      sprintf("proj_root: %s", PROJ_ROOT),
      sprintf("out_root: %s", OUT_ROOT),
      if (length(problems)) {
        c("status: refuse:unpinned-package", paste0("- ", problems))
      } else {
        "status: ok"
      },
      ""
    )
    cat(paste0(lines, collapse = "\n"), file = log_file, append = TRUE, sep = "")
    Sys.setenv(RTOOLKIT_SETUP_LOGGED = "1")
  }

  if (length(problems)) {
    stop(
      paste0("refuse:unpinned-package\n- ", paste(problems, collapse = "\n- ")),
      call. = FALSE
    )
  }

  invisible(TRUE)
})
