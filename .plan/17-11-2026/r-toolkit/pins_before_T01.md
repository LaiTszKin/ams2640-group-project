# pins_before_T01 — 第 0 波凍結記錄

主代理產出，日期 2026-11-17T02:35（HKT）。此後唯讀；任何異動須新的帶日期修訂。

由 `V13` 第一階段抄入 `programs/R/checks/pins_baseline.txt`，不得以任務文字代替本檔。

## 環境列

| 件 | 現狀 | 消解條件 |
| --- | --- | --- |
| 版本環境目錄 `renv/` | 不存在 | 目錄存在，且 `renv::status()$synchronized` 為真 |
| `.Rprofile` | 僅一行 `source("renv/activate.R")`，無守衛；在專案根執行任何 `Rscript` 即刻失敗（實測錯誤：無法開啟檔案 `renv/activate.R`） | 改為有守衛的形式，缺 `activate.R` 時觸發還原 |

## 套件列

`renv.lock` 現有 31 個套件（`R6`、`bit`、`bit64`、`cli`、`clipr`、`cpp11`、`crayon`、`dplyr`、`forcats`、`generics`、`glue`、`haven`、`here`、`hms`、`lifecycle`、`magrittr`、`pillar`、`pkgconfig`、`prettyunits`、`progress`、`readr`、`renv`、`rlang`、`rprojroot`、`tibble`，其餘為其依賴）。

| 套件 | 現狀 | 消解條件 | 呼叫點 |
| --- | --- | --- | --- |
| `testthat` | 未登記、未安裝 | 登記於 `renv.lock` 且可 `requireNamespace` | `T14`、`V01`–`V11` |
| `PropCIs` | 未登記、未安裝 | 同上 | `T03` 的 `prop_ci` |
| `broom` | 未登記、未安裝 | 同上 | `T07` 的模型整理 |

`ggplot2` 不在本清單：依 `A-3`，圖由 SAS 產（PRD D11），R 端不出圖，故不進鎖定檔。

## 資料與其他

- `data/raw/data.csv` — 37 欄、4,424 列、分號分隔、UTF-8 BOM；sha256 `3ef126de5cefff26eb11fbb4237f1a1401cb64b488e2f1d598c23cedeb4c45ae`
- `data/processed/` — 三個舊產物存在，產生它們的 R 版本未知（PRD §10 未決項）
- `programs/`、`output/`、`tests/` — 皆不存在
