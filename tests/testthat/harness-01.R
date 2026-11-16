# harness-01.R — F1（環境還原）的預算、執行上限與入口
#
# 本檔只做三件事：① 宣告 F1 的預算與具名指令；② 把「執行 00_setup.R 的暫存副本」
# 與「讀 00_setup.log」包成少數具名函式；③ 提供斷言輔助。樣本、種子與暫存目錄
# 一律取自 `helper-harness.R`（REQ-A-7）：副本建在 `harness_dir()` 內、輸出根由
# `harness_out_root()` 提供，本檔不自行造暫存目錄、不寫入專案的 `output/`。
#
# 邊界：一切注入（改寫鎖定檔、刪記錄欄、缺啟動檔）只在 `harness_dir()` 的副本上做，
# 真實樹的 `.Rprofile`、`renv.lock`、`programs/R/` 與 `output/` 不動。

## 1. 預算與具名指令 -------------------------------------------------------

# 種子值取自測試台（A-2）。F1 無隨機來源，故種子與收縮步數在報告中記 n/a，
# 值只作記錄，不驅動任何行為。
F1_SEED <- HARNESS_SEED
F1_SEED_NOTE <- "n/a：F1 無隨機來源"
F1_SHRINK_MAX <- 200L     # 收縮上界（n/a：同上）
F1_SHRINK_SEC <- 30        # 收縮秒數上界（n/a：同上）
F1_LIMIT_SEC <- 600        # 單流程上限（A-2：含套件安裝）

# T01 步驟 5 的具名自檢指令：一行、專案根目錄、印出兩個母體常數。
F1_CHECK_EXPR <- 'source("programs/R/00_setup.R"); c(ANALYSIS_N, ABILITY_N)'

# 釘值（PRD D2／D4）。斷言同時要求「正整數」與「等於釘值」：前者是 F1 的性質，
# 後者把 F1 綁回 T01 的閘 G1，避免還原成功卻匯出錯的常數。
F1_PINNED <- c(ANALYSIS_N = 3630L, ABILITY_N = 2828L)

# 副本的組成（V01 性質二逐字列出）。`AMS2640.Rproj` 是 `here::here()` 與
# `00_setup.R` 的根標記，少了它副本在第一步就停，與「缺版本環境」無關——
# 故它是副本的必要成員，不算額外注入。
F1_COPY_REQUIRED <- c(
  ".Rprofile", "AMS2640.Rproj", "renv.lock", "renv/activate.R", "programs/R/00_setup.R"
)

# 記錄的必備三欄（PRD §4 F1「可見面」）。
F1_LOG_FIELDS <- c("r_version", "package_count", "restore_elapsed_sec")

## 2. 執行：一律以子程序跑被測入口 -----------------------------------------

f1_rscript <- function() file.path(R.home("bin"), "Rscript")

# 子程序的環境：F1 的場景是「新機器」，故**不繼承**測試 session 的任何變數，以
# `env -i` 起一個只有下列項目的環境。被測程式碼把空字串視同未設，故 RTOOLKIT_* 給空值。
#
# 這一條是必要的，不是潔癖：測試 session 自己就是一個 renv session，它把
# `RENV_PROJECT` 與 `R_LIBS_USER` 指向真實樹的 library。子程序若繼承，renv 會把
# 「專案」解讀成真實樹——還原因此裝進真實樹（已滿足，於是一個都不裝），副本的
# library 仍是空的，守衛在還原後的差額檢查以 refuse:unpinned-package 停下；
# 另一種繼承組合會讓 renv 失去套件快取，改從原始碼編譯 52 個套件（實測逾 400 秒）。
# R 需要的 HOME／PATH／TMPDIR／LANG 由呼叫端的現值帶入；專案狀態一個不帶。
f1_env <- function(out_root = NULL) {
  vars <- c(
    HOME = Sys.getenv("HOME"),
    PATH = Sys.getenv("PATH"),
    TMPDIR = Sys.getenv("TMPDIR"),
    LANG = Sys.getenv("LANG"),
    RTOOLKIT_OUT_ROOT = if (is.null(out_root)) "" else out_root,
    RTOOLKIT_SETUP_LOGGED = "",
    RTOOLKIT_PROFILE_BOOTSTRAP = "",
    RTOOLKIT_RESTORE_ACTION = "",
    RTOOLKIT_RESTORE_ELAPSED = "",
    RTOOLKIT_LIBRARY_BEFORE = ""
  )
  paste0(names(vars), "=", vars)
}

# 在 `dir` 內跑一次具名指令。回 status（逾時為 124）、合併後的輸出（stderr 併入，
# 拒絕訊息因此在同一串）與該次執行寫入的輸出根。
f1_run <- function(dir, expr = F1_CHECK_EXPR, out_root = NULL, limit = F1_LIMIT_SEC) {
  out <- suppressWarnings(withr::with_dir(dir, system2(
    "/usr/bin/env",
    args = c("-i", f1_env(out_root), f1_rscript(), "-e", shQuote(expr)),
    stdout = TRUE,
    stderr = TRUE,
    timeout = limit
  )))
  status <- attr(out, "status")
  list(
    dir = dir,
    status = if (is.null(status)) 0L else as.integer(status),
    output = as.character(out),
    out_root = if (is.null(out_root)) file.path(dir, "output") else out_root,
    limit = limit
  )
}

# 取出 `c(ANALYSIS_N, ABILITY_N)` 的兩值。其他行（還原訊息、套件清單）不參與。
f1_parse_pair <- function(output) {
  hit <- grep("^\\[1\\]\\s+-?[0-9]+\\s+-?[0-9]+\\s*$", output, value = TRUE)
  if (!length(hit)) return(integer())
  as.integer(strsplit(trimws(sub("^\\[1\\]\\s+", "", hit[[1L]])), "\\s+")[[1L]])
}

## 3. 暫存副本 -------------------------------------------------------------

# 專案根：由測試台解析（向上找 `AMS2640.Rproj`），本檔不重寫尋找邏輯、不讀 marker 以外
# 的任何檔案。性質一以此為工作目錄，性質二至六以它為副本的來源。
f1_project_root <- function() .harness_project_root()

# 副本＝F1 的前置狀態：專案狀態（.Rprofile、activate.R、鎖定檔、入口）在，
# 版本環境本體不在（`renv/library` 存在但沒有任何套件）。
#   drop     從副本的鎖定檔移除一個套件（性質三的注入）
#   lockfile FALSE 表示副本不含鎖定檔（`.Rprofile` 的前置拒絕）
f1_copy <- function(drop = NULL, lockfile = TRUE) {
  root <- .harness_project_root()
  dir <- harness_dir()
  file.copy(file.path(root, c(".Rprofile", "AMS2640.Rproj")), dir, overwrite = TRUE)
  if (lockfile) file.copy(file.path(root, "renv.lock"), dir, overwrite = TRUE)
  dir.create(file.path(dir, "renv"), showWarnings = FALSE)
  file.copy(file.path(root, "renv", "activate.R"), file.path(dir, "renv"), overwrite = TRUE)
  # 空 library：契約對「缺版本環境」的定義之一（`renv/library` 為空）。
  dir.create(file.path(dir, "renv", "library"), showWarnings = FALSE)
  dir.create(file.path(dir, "programs", "R"), recursive = TRUE, showWarnings = FALSE)
  file.copy(
    file.path(root, "programs", "R", "00_setup.R"),
    file.path(dir, "programs", "R"),
    overwrite = TRUE
  )
  if (!is.null(drop)) f1_drop_from_lockfile(file.path(dir, "renv.lock"), drop)

  present <- file.exists(file.path(dir, F1_COPY_REQUIRED))
  names(present) <- F1_COPY_REQUIRED
  list(
    dir = dir,
    drop = drop,
    lockfile = lockfile,
    files = present,
    library_pkgs = f1_library_packages(dir),
    profile_guarded = f1_profile_is_guarded(dir)
  )
}

# 副本 library 內真的裝了哪些套件（以 DESCRIPTION 為憑）。
f1_library_packages <- function(dir) {
  lib <- file.path(dir, "renv", "library")
  if (!dir.exists(lib)) return(character())
  descs <- list.files(lib, pattern = "^DESCRIPTION$", recursive = TRUE, full.names = TRUE)
  sort(unique(basename(dirname(descs))))
}

# `.Rprofile` 是否為守衛版：必須自己判斷 library 狀態並呼叫還原，而不是只 source
# `activate.R`（renv 的 activate 腳本不含還原呼叫）。
f1_profile_is_guarded <- function(dir) {
  path <- file.path(dir, ".Rprofile")
  if (!file.exists(path)) return(FALSE)
  text <- paste(readLines(path, warn = FALSE), collapse = "\n")
  all(vapply(
    c("renv::restore", "RTOOLKIT_RESTORE_ACTION"),
    function(token) grepl(token, text, fixed = TRUE),
    logical(1)
  ))
}

# 從鎖定檔移除一個套件：用 00_setup.R 自己也用的 renv API，避免手改 JSON 走樣。
f1_drop_from_lockfile <- function(path, pkg) {
  lock <- renv::lockfile_read(path)
  if (is.null(lock$Packages[[pkg]])) {
    stop("副本的鎖定檔沒有 ", pkg, "，無法造「缺套件」的注入。", call. = FALSE)
  }
  lock$Packages[[pkg]] <- NULL
  renv::lockfile_write(lock, project = dirname(path))
  if (pkg %in% names(renv::lockfile_read(path)$Packages)) {
    stop("無法從 ", path, " 移除 ", pkg, "：寫回後仍在。", call. = FALSE)
  }
  invisible(pkg)
}

## 4. 記錄 ----------------------------------------------------------------

f1_log_path <- function(out_root) file.path(out_root, "logs", "00_setup.log")

f1_read_log <- function(out_root) {
  path <- f1_log_path(out_root)
  if (!file.exists(path)) return(character())
  readLines(path, warn = FALSE)
}

# 一段＝以 `== 00_setup <時間> ==` 開頭到下一段之前。每次執行寫一段，
# 「追加一段」與「無操作」因此都以段數判定。
f1_sections <- function(lines) {
  starts <- grep("^== 00_setup ", lines)
  if (!length(starts)) return(list())
  ends <- c(starts[-1L] - 1L, length(lines))
  lapply(seq_along(starts), function(i) lines[starts[[i]]:ends[[i]]])
}

f1_field <- function(section, key) {
  hit <- grep(paste0("^", key, ": "), section, value = TRUE)
  if (!length(hit)) return(NA_character_)
  sub(paste0("^", key, ": "), "", hit[[1L]])
}

f1_field_or_empty <- function(section, key) {
  value <- f1_field(section, key)
  if (length(value) != 1L || is.na(value)) "" else value
}

f1_bullets <- function(section) grep("^- ", section, value = TRUE)

# 負向控制用：拿掉一欄，其餘不動。斷言必須因此轉紅。
f1_drop_field <- function(section, key) section[!grepl(paste0("^", key, ":"), section)]

# 負向控制用：把某個字串換成遮罩，形狀不變、指名的那個值不見。
f1_mask <- function(lines, pattern, replacement = "<masked>") {
  sub(pattern, replacement, lines)
}

## 5. 斷言輔助 -----------------------------------------------------------

# 三欄的值。缺欄回空字串，讓「有沒有那一欄」與「值對不對」共用同一個取法。
f1_log_field_values <- function(section) {
  vapply(F1_LOG_FIELDS, function(key) f1_field_or_empty(section, key), character(1))
}

# 三欄都在。負向控制在外的預測點：拿掉任一欄必須轉假。
f1_log_fields_complete <- function(section) all(nzchar(f1_log_field_values(section)))

# 三欄的形狀都對：R 版本字串、非負整數、非負秒數。
# 比「有沒有那一欄」嚴格：`restore_elapsed_sec: ` 空值算缺（性質四的第二類反例）。
f1_log_fields_shaped <- function(section) {
  values <- f1_log_field_values(section)
  all(c(
    grepl("^R version [0-9]+[.][0-9]+", values[["r_version"]]),
    grepl("^[0-9]+$", values[["package_count"]]),
    grepl("^[0-9]+([.][0-9]+)?$", values[["restore_elapsed_sec"]])
  ))
}

f1_assert_log_fields <- function(section) {
  values <- f1_log_field_values(section)
  testthat::expect_true(
    f1_log_fields_complete(section),
    label = sprintf(
      "記錄含 %s 三欄（實得：%s）",
      paste(F1_LOG_FIELDS, collapse = "／"),
      if (any(nzchar(values))) paste(names(values)[nzchar(values)], collapse = "、") else "無"
    )
  )
  testthat::expect_true(
    f1_log_fields_shaped(section),
    label = sprintf(
      "三欄形狀正確（r_version=%s／package_count=%s／restore_elapsed_sec=%s）",
      dQuote(values[["r_version"]]), dQuote(values[["package_count"]]),
      dQuote(values[["restore_elapsed_sec"]])
    )
  )
  invisible(f1_log_fields_complete(section) && f1_log_fields_shaped(section))
}

# 記錄一段必須是成功結束、且指名成功。拒絕段的 status 為 refuse:*，同一條斷言轉紅。
f1_assert_ok_section <- function(section) {
  status <- f1_field_or_empty(section, "status")
  testthat::expect_identical(status, "ok", label = sprintf("記錄的 status 為 ok（實得：%s）", status))
  invisible(identical(status, "ok"))
}

## 6. 取根與清理 ---------------------------------------------------------

# F1 需要在「專案根目錄」跑一次具名指令（性質一）。被測程式碼會寫記錄，故記錄導到
# 暫存根：`harness_out_root()` 決定寫入位置，測試結束時還原環境變數並刪根。
f1_out_root <- function(env = parent.frame()) {
  prior <- Sys.getenv("RTOOLKIT_OUT_ROOT", unset = "")
  root <- harness_out_root()
  withr::defer(
    {
      if (nzchar(prior)) Sys.setenv(RTOOLKIT_OUT_ROOT = prior) else Sys.unsetenv("RTOOLKIT_OUT_ROOT")
      unlink(root, recursive = TRUE, force = TRUE)
    },
    envir = env
  )
  root
}

## 7. 共用探針：一次還原，兩個性質共用 -----------------------------------

# 性質二與性質四都要「一次真實還原的副本與記錄」。探針只跑一次並記在 session 內，
# 兩個性質共用同一份證據，避免各自重複付一次套件安裝（單流程上限 600 秒）。
F1_STATE <- new.env(parent = emptyenv())
F1_STATE$probe <- NULL

f1_restore_probe <- function() {
  if (!is.null(F1_STATE$probe)) return(F1_STATE$probe)
  copy <- f1_copy()
  run <- f1_run(copy$dir)
  F1_STATE$probe <- list(
    copy = copy,
    run = run,
    sections = f1_sections(f1_read_log(run$out_root))
  )
  F1_STATE$probe
}
