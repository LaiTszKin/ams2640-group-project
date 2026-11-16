# T11 — SAS 端對照程式

| Field | Value |
| --- | --- |
| Task | `T11` |
| Class | `construction` |
| Requirement | `REQ-F-F10-1`（前半） |
| Depends on | T02、T04、T05、T06 |
| Seam | programs/SAS/05_parity.sas |
| Owned files | `programs/SAS/05_parity.sas`、`programs/SAS/README_parity.md`、`output/parity/cell_map.csv`、`output/parity/sas_parity.csv`、`output/parity/age_band_dropout.pdf`、`output/parity/ability_quartile_graduation.pdf` |
| Plan | `.plan/17-11-2026/r-toolkit/` |
| PRD | [`../PRD.md`](../PRD.md) |
| DAG | [`../TASKS.md`](../TASKS.md) |
| Status | work contract |

**Self-sufficiency**: 只讀本檔與 PRD 相關章節即可開工。DAG 與追溯在 `../TASKS.md`；兩者不一致時以本檔所引的 PRD 條文為準，並回報主代理裁決。

**Boundaries**: 只寫 `Owned files` 列出的檔案。不改 `../PRD.md`、`../TASKS.md`、同批其他任務的檔案。發現矛盾即停手回報。

**Class boundaries**: construction 不寫檢查、模型或基線；verification 不改生產檔案，一切注入只在暫存副本上做。

**Path base**: 以下路徑相對專案根目錄。

---

## Construction

- **Purpose**: SAS Studio 跑一次即在 `output/parity/` 產出十四列對照值、一份機器可讀的 cell_map 與兩張圖
- **Seam**: `programs/SAS/05_parity.sas` — 本任務建立的入口
- **Flow it feeds**: F10（兩端對照）的前半
- **Files owned**:
  - `programs/SAS/05_parity.sas` — 重算十四格並出兩張圖
  - `programs/SAS/README_parity.md` — 上傳清單、執行順序、十四個 cell_id 的說明
  - `output/parity/cell_map.csv` — `cell_id, table, column, row_key, value_type`，十四列，機器可讀；`row_key` 為 R 表該列的鍵值（如 `w_both`、`a_25_29`、`q3`）
  - `output/parity/sas_parity.csv` — `cell_id, indicator, group, value, n, value_type`，十四列
  - `output/parity/age_band_dropout.pdf` — 年齡帶退學率圖
  - `output/parity/ability_quartile_graduation.pdf` — 能力分位畢業率圖
- **Steps**:
  1. 載入清洗資料集（備援 xpt 與 csv）
  2. 十四格逐列寫定：`pop_analysis`（分析母體人數）；`w_only_unpaid`、`w_only_debt`、`w_both`、`w_neither`（四格退學率，格名與 T04 一致）；`a_lt20`、`a_20_24`、`a_25_29`、`a_30_39`、`a_40plus`（五帶退學率，標籤與 T05 一致）；`q1`、`q2`、`q3`、`q4`（四組畢業率，標籤與 T06 一致）
  3. 值以 `best32.` 匯出（未套用顯示格式，至少 15 位有效數字；SAS 對未格式化數值預設只給 BEST12，故須明確指定）；`value_type` 為 `count` 或 `rate`
  4. 分組規則寫進 README 並在程式內以註解標明：能力分位採**等量切分**（第二學期成績升冪、同分依原始列序、組寬 `floor(n/4)`、末組收餘，與 T06 同；不可用 PCTLDEF 預設分位數切點）；母體界線為 `Target in (Graduate, Dropout)`；四格以原欄定義 `tuition_unpaid = (Tuition fees up to date = 0)`、`debtor = (Debtor = 1)`，列序為兩者俱有、僅欠繳、僅欠債、皆無
  5. 出兩張圖至 `output/parity/`
  6. 同步寫出 `cell_map.csv`，欄位指向 R 端表名與欄名
- **Refusal**: `refuse:input-schema` — 資料集載入失敗時停止，印出嘗試過的每個路徑與 SAS 端錯誤原文
- **Boundaries**: SAS 只讀清洗資料集；匯出值不套顯示精度；對照值目錄與 `output/tables/` 分離；p 值不進對照集（十四格全為計數與比率）
- **Untouched**: 既有 01–04 號 SAS 程式不動；不改 R 端任何表

---

## Report format

完成後回報四項，缺一即視為未完成：

1. **Result** — construction：呼叫者現在看到什麼；verification A：走到哪些分支、用了多少預算、抓到什麼（trace、seed、最短序列）與**負向控制**的紅燈輸出；C：變更前後的通過與否、違規清單、門檻值與實測值（含掃描檔數）。
2. **實際建立或修改的檔案**，逐項對照 `Owned files`。
3. **偏離本檔之處與原因**；沒有則寫 `none`。
4. **在 owned files 內無法交付的部分**與其所需決定；verification 另附發現的生產缺陷與其 seam。

