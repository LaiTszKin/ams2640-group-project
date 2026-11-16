## 專案啟動設定（R 只讀「工作目錄」的這一份；從子目錄啟動時不會讀到它）。
##
## renv/activate.R 是專案狀態，不是環境本體：library 缺件時 source 它只會警告，不會把
## 套件裝回來。所以守衛比對的是「renv/library 是否滿足 renv.lock」，不滿足就自行
## renv::restore()，換機器或新 clone 之後不必先手動 bootstrap，也不會因為缺啟動檔而
## 讓專案根目錄的任何 Rscript 失敗。

# 非互動的 restore 不應停下來等授權詢問。
options(renv.consent = TRUE)

local({
  project <- getwd()             # .Rprofile 以 cwd 為錨，專案根即 cwd
  activate <- file.path(project, "renv", "activate.R")
  lockfile <- file.path(project, "renv.lock")

  if (!file.exists(lockfile))
    stop("renv.lock 不存在，無法還原版本環境；請確認 clone 完整。", call. = FALSE)
  if (!requireNamespace("renv", quietly = TRUE))
    stop("renv 未安裝，無法還原版本環境：先 install.packages(\"renv\") 再重開。", call. = FALSE)

  library_dir <- renv::paths$library(project = project)

  # library 內每個套件的版本（DESCRIPTION 的 Version 欄）
  lib_versions <- function(path) {
    if (!dir.exists(path)) return(stats::setNames(character(), character()))
    pkgs <- list.dirs(path, full.names = FALSE, recursive = FALSE)
    pkgs <- pkgs[file.exists(file.path(path, pkgs, "DESCRIPTION"))]
    out <- vapply(pkgs, function(p) {
      dcf <- tryCatch(read.dcf(file.path(path, p, "DESCRIPTION")), error = function(e) NULL)
      if (is.null(dcf) || !"Version" %in% colnames(dcf)) NA_character_ else unname(dcf[1, "Version"])
    }, character(1), USE.NAMES = TRUE)
    stats::setNames(out, pkgs)
  }

  # 鎖定檔要求的版本
  locked_versions <- function() {
    records <- renv::lockfile_read(lockfile)$Packages
    out <- vapply(records, function(r) {
      v <- r$Version
      if (is.null(v)) NA_character_ else as.character(v)
    }, character(1), USE.NAMES = TRUE)
    stats::setNames(out, names(records))
  }

  # 缺件或缺版本差額（library 多出來的套件不算缺環境，交給 00_setup.R 的同步檢查）
  shortfall <- function(have, want) {
    absent <- setdiff(names(want), names(have))
    differ <- intersect(names(want), names(have))
    differ <- differ[is.na(have[differ]) | have[differ] != want[differ]]
    list(ok = length(absent) == 0L && length(differ) == 0L, absent = absent, differ = differ)
  }

  have <- lib_versions(library_dir)
  want <- locked_versions()

  # 還原前後的差集由 00_setup.R 寫入記錄（補件與降級清單），故先把還原前狀態交出去。
  Sys.setenv(
    RTOOLKIT_LIBRARY_BEFORE = if (length(have)) paste0(names(have), "=", have, collapse = ";") else ""
  )
  Sys.setenv(RTOOLKIT_RESTORE_ACTION = "none")
  Sys.setenv(RTOOLKIT_RESTORE_ELAPSED = "0")

  if (shortfall(have, want)$ok && file.exists(activate)) {
    source(activate)
    return(invisible(NULL))
  }

  # restore 會另起 R 子程序；子程序若也讀到這份設定，不該再觸發一次還原。
  if (identical(Sys.getenv("RTOOLKIT_PROFILE_BOOTSTRAP"), "1"))
    return(invisible(NULL))

  started <- Sys.time()
  Sys.setenv(RTOOLKIT_PROFILE_BOOTSTRAP = "1")
  on.exit(Sys.unsetenv("RTOOLKIT_PROFILE_BOOTSTRAP"), add = TRUE)

  # renv 1.3.1 的 restore() 只裝套件、不寫 activate.R，故先補上啟動腳本；
  # 用的是 renv 自己的 infrastructure 寫入器（與 renv::activate() 同一支），
  # 避免像 renv::activate() 那樣連 .Rprofile／.gitignore／.Rbuildignore 一起改寫。
  if (!file.exists(activate)) {
    write_activate <- get0(
      "renv_infrastructure_write_activate",
      envir = asNamespace("renv"),
      inherits = FALSE
    )
    if (is.function(write_activate)) write_activate(project)
  }

  # 讓專案 library 先上 .libPaths()，restore 才會裝進專案 library 而不是系統 library。
  if (file.exists(activate)) source(activate)

  message("[.Rprofile] 版本環境缺件，執行 renv::restore()")
  renv::restore(project = project, prompt = FALSE)

  after <- shortfall(lib_versions(library_dir), want)
  if (!after$ok) {
    stop(
      "refuse:unpinned-package — 還原後仍未滿足鎖定檔：",
      paste(c(after$absent, after$differ), collapse = ", "),
      call. = FALSE
    )
  }

  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  Sys.setenv(RTOOLKIT_RESTORE_ACTION = "restore")
  Sys.setenv(RTOOLKIT_RESTORE_ELAPSED = sprintf("%.1f", elapsed))
  message(sprintf("[.Rprofile] renv::restore() 完成，耗時 %.1f 秒", elapsed))
})
