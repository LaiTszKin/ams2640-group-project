# AMS2640 — 統計專案

UCI *Predict Students' Dropout and Academic Success* 的分析專案。
R 負責資料準備與相關審核，SAS 負責視覺化與正式推論檢定。

## 為什麼資料夾長這樣

專案邊界先劃清楚，後面所有爭議都少一半：

- **`data/raw/` 唯讀** —— 原始 CSV 永不修改。任何清洗都寫到 `data/processed/`。
- **`data/processed/`** —— 由 `programs/R/01_prep_data.R` 產生，可刪可重建。
- **`programs/R/` 與 `programs/SAS/`** —— 編號一一對應（`01` 對 `01`），
  看編號就知道流程走到哪。
- **`output/`** —— `figures/`（圖）、`tables/`（表）、`logs/`（執行記錄）。
  全部由程式產生，不手動編輯。
- **`docs/`** —— 課程指引等唯讀文件。

路徑一律經 `here::here()`，所以在專案根目錄（或它的子目錄）執行，結果與工作目錄無關，
不會出現 `setwd()`。注意 `here()` 本身在非專案環境**不會報錯**，會靜默退回 cwd——
`00_setup.R` 因此加了一道根目錄檢查，找不到 `AMS2640.Rproj` 就停。

## 目錄

```
.
├── AMS2640.Rproj              RStudio 專案檔（決定 here() 的根）
├── renv.lock                  套件版本鎖定
├── data/
│   ├── raw/data.csv           原始資料（唯讀，semicolon + BOM）
│   └── processed/             清洗後：.sas7bdat / .xpt / _clean.csv
├── programs/
│   ├── R/
│   │   ├── 00_setup.R         路徑、套件、共用常數（唯一來源）
│   │   ├── 01_prep_data.R     CSV → SAS 資料集
│   │   ├── 02_correlation_audit.R  相關審核（真 vs 偽）
│   │   └── run_all.R          單一入口
│   └── SAS/
│       ├── 00_setup.sas       路徑、formats、輸出資料夾
│       ├── 01_import_check.sas      匯入與資料品質檢查
│       ├── 02_viz.sas               SGPLOT，輸出 PDF
│       ├── 03_inference.sas         t 檢定、相關、迴歸、卡方
│       ├── 04_correlation_stratified.sas  CMH、Type 3、偏相關
│       └── tools/sasopen            複製程式到剪貼簿並開 SAS Studio
├── output/{figures,tables,logs}/
└── docs/                      課程指引
```

## R 端

```bash
Rscript programs/R/run_all.R
```

第一次在新機器上，先還原套件版本：

```r
renv::restore()
```

## SAS 端

**SAS 不是本機程式。** SAS Institute 只發行 Windows / Linux 版本，兩者都要 license，
macOS 沒有安裝包。免費且合法的路徑是 **SAS OnDemand for Academics（ODA）**，
在瀏覽器裡跑 SAS Studio。

### 一次性設定

1. <https://welcome.oda.sas.com/> → **Sign In** → 建立 SAS Profile（用學校 email）
2. 收驗證信、設密碼
3. 登入後點 **SAS Studio**

### 上傳（`Files (Home)`，一次就好）

```
ams2640.sas7bdat                 ← 來自 data/processed/
00_setup.sas                     ← 來自 programs/SAS/
01_import_check.sas
02_viz.sas
03_inference.sas
04_correlation_stratified.sas
```

之後每個程式貼進 Studio 執行即可。每個 `.sas` 開頭都會載入 `00_setup.sas`；
若沒上傳，會印 WARNING 並退回預設路徑，不會靜默失敗。

本機編輯、雲端執行：

```bash
programs/SAS/tools/sasopen programs/SAS/02_viz.sas
```

VS Code 的 `SAS.sas-lsp` 擴充只支援 Viya / SSH / IOM 連線，**不支援 ODA**，
所以它只負責語法高亮與診斷，執行一律在瀏覽器。

## 執行順序

| 步驟 | R | SAS | 產物 |
|---|---|---|---|
| 1 | `01_prep_data.R` | — | `data/processed/ams2640.sas7bdat` |
| 2 | `02_correlation_audit.R` | `01_import_check.sas` | 相關審核表、資料品質報告 |
| 3 | — | `02_viz.sas` | `output/figures/ams2640_viz.pdf` |
| 4 | — | `03_inference.sas` | 檢定結果 |
| 5 | — | `04_correlation_stratified.sas` | CMH、Type 3、偏相關 |

## 已知陷阱

- **SAS 不支援連續比較**：`0 <= x <= 20` 會被算成 `(0<=x)<=20`，恆真且不報錯。
  必須寫 `0 <= x and x <= 20`。
- **`haven::write_sas()` 會把 factor 壓成整數碼**，類別標籤消失。寫入前先
  `across(where(is.factor), as.character)`。
- **`&sysuserid` 只在 SAS 端有效**，本機 shell 是空字串。若 log 報
  `Physical file does not exist`，先 `%put &sysuserid;` 對照。
- **`pass1` / `pass2` 有 180 個 missing**（兩學期皆 0 註冊），不是 0。
- **原始 CSV 三個坑**：semicolon 分隔、UTF-8 BOM、欄名內藏 tab。
- **`.sas7bdat` 由 haven 產生**；若某個變數型別異常，退回同目錄的 `.xpt`
  （`proc cimport`）或 `ams2640_clean.csv`（`proc import`）。
- **ODA 免費額度** 5 GB，本專案用不到 2 MB；不要用無痕模式，session 會斷。
