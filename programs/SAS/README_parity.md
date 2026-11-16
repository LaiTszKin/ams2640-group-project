# README_parity — SAS 端對照程式（`05_parity.sas`）

這份文件說明 SAS 端對照程式的**上傳清單、執行順序、下載位置、十四個 cell_id 的定義與分組規則**。
對照的目的只有一個：R 與 SAS 在同一份清洗資料上給出相同答案（PRD F10、`REQ-F-F10-1` 前半）。

R 是數值權威。SAS 重算十四格、出兩張圖，數值匯出後由 `programs/R/90_parity.R` 逐格比對；
SAS 的數字不覆蓋 R 的表，兩者分屬 `output/parity/`（SAS 匯出）與 `output/tables/`（R 產出）兩個目錄（`REQ-A-6`、修訂 A-13）。

---

## 1. 產物清單與產地

| 檔案 | 產地 | 現在狀態 |
| --- | --- | --- |
| `programs/SAS/05_parity.sas` | 本機撰寫 | 已完成；**本機沒有 SAS，未在本地執行過** |
| `programs/SAS/README_parity.md` | 本機撰寫 | 本文件 |
| `output/parity/cell_map.csv` | 本機撰寫 | 已完成，十四列，機器可讀（SAS 重跑會產生同內容的第二份，見 §6） |
| `output/parity/sas_parity.csv` | **SAS Studio 匯出後放此** | 未在本地產生（本機無 SAS）；由 §3 執行後下載 |
| `output/parity/age_band_dropout.pdf` | **SAS Studio 匯出後放此** | 未在本地產生；由 §3 執行後下載 |
| `output/parity/ability_quartile_graduation.pdf` | **SAS Studio 匯出後放此** | 未在本地產生；由 §3 執行後下載 |

`cell_map.csv` 與 README 不依賴 SAS 執行，故現在就是完整的最終版；
`sas_parity.csv` 與兩張 PDF 必須由 SAS Studio 產生，本機不代工、也不以任何估算值代替。

---

## 2. 上傳清單（SAS Studio → `Files (Home)`，一次就好）

上傳到 ODA 的 **Files (Home)**，該目錄即 `/home/&sysuserid`（程式以 `&sysuserid` 組路徑，不寫死帳號）。

| 檔案 | 來源 | 必要性 |
| --- | --- | --- |
| `ams2640.sas7bdat` | `data/processed/` | 主格式（欄名已正規化為 ≤32 字元） |
| `ams2640.xpt` | `data/processed/` | 備援一（`proc cimport`） |
| `ams2640_clean.csv` | `data/processed/` | 備援二（`proc import`；欄名為原始問卷用語） |
| `05_parity.sas` | `programs/SAS/` | 本程式 |

三個資料檔**任一可用即可**：`05_parity.sas` 依 `sas7bdat → xpt → csv` 的順序嘗試，成功即停。
三個都放上去最省事；只放 `sas7bdat` 也能跑完。

`00_setup.sas` 與 `01`–`04` 號 SAS 程式**不在本專案內**（`programs/SAS/` 目前只有本程式），
因此 `05_parity.sas` **不 `%include` 任何其他檔案**：路徑、欄名、切點全部寫在檔內，
不對一個不存在的檔案留下依賴。若日後補上 `00_setup.sas`，本程式仍可獨立執行。

---

## 3. 執行順序

1. 登入 <https://welcome.oda.sas.com/> → **SAS Studio**。
2. 把 §2 的四個檔上傳到 **Files (Home)**。
3. 開 `05_parity.sas`，**整份執行一次**（Ctrl+E / Run）。
4. 看 log：
   - 應見 `NOTE: [05_parity] 載入 …`（實際來源）、`分析母體 n=…`、`必要欄齊備`；
   - 末尾十四列的 PROC PRINT 是十四格的值（`value` 以 `best32.` 顯示，不是四位）；
   - 圖的 PDF 會寫進 SAS 端的 `parity/` 目錄（`&sysuserid/parity/`）。
5. 把 SAS 端 `parity/` 目錄下的四個檔下載，放進專案的 `output/parity/`：

```
sas_parity.csv
cell_map.csv                      ← 與本機那份內容相同；下載後可直接覆蓋，或保留本機版本
age_band_dropout.pdf
ability_quartile_graduation.pdf
```

6. 回到本機跑 R 端比對：`Rscript programs/R/90_parity.R`（T12）。
   逐格結果寫入 `output/tables/parity_diff.csv`；任一格超出容差即以 `refuse:parity` 結束（結束碼 3）。

程式會自行建立 SAS 端的 `parity/` 目錄（`options dlcreatedir`），不必先手動建。

---

## 4. 十四個 cell_id

`row_key` 是 **R 表該列的鍵值**，即 R 表鍵欄裡的字面值（`age_bands.csv` 的 `band` 欄存的就是 `<20`…`40+`；
`cell_id` 的 `a_lt20` 一類是對照用的短名，不是 R 表裡的值）。`population_ledger.csv` 的列由
`(population, metric) = (analysis, analysis)` 選定，`row_key` 記的是 `metric` 值。

| # | cell_id | R 表 | 欄 | row_key | value_type | 意思 | 分母 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `pop_analysis` | `population_ledger.csv` | `value` | `analysis` | `count` | 分析母體人數 | — |
| 2 | `w_both` | `wealth_four_cell.csv` | `dropout_rate` | `w_both` | `rate` | 兩者俱有（欠繳＋欠債） | 該格人數 |
| 3 | `w_only_unpaid` | `wealth_four_cell.csv` | `dropout_rate` | `w_only_unpaid` | `rate` | 僅欠繳 | 該格人數 |
| 4 | `w_only_debt` | `wealth_four_cell.csv` | `dropout_rate` | `w_only_debt` | `rate` | 僅欠債 | 該格人數 |
| 5 | `w_neither` | `wealth_four_cell.csv` | `dropout_rate` | `w_neither` | `rate` | 皆無 | 該格人數 |
| 6 | `a_lt20` | `age_bands.csv` | `dropout_rate` | `<20` | `rate` | 未滿 20 歲 | 該帶人數 |
| 7 | `a_20_24` | `age_bands.csv` | `dropout_rate` | `20-24` | `rate` | 20–24 歲 | 該帶人數 |
| 8 | `a_25_29` | `age_bands.csv` | `dropout_rate` | `25-29` | `rate` | 25–29 歲 | 該帶人數 |
| 9 | `a_30_39` | `age_bands.csv` | `dropout_rate` | `30-39` | `rate` | 30–39 歲 | 該帶人數 |
| 10 | `a_40plus` | `age_bands.csv` | `dropout_rate` | `40+` | `rate` | 40 歲以上（含 40） | 該帶人數 |
| 11 | `q1` | `ability_quartiles.csv` | `graduation_rate` | `q1` | `rate` | 第二學期成績最低的四分之一 | 該組人數 |
| 12 | `q2` | `ability_quartiles.csv` | `graduation_rate` | `q2` | `rate` | 第二四分位 | 該組人數 |
| 13 | `q3` | `ability_quartiles.csv` | `graduation_rate` | `q3` | `rate` | 第三四分位 | 該組人數 |
| 14 | `q4` | `ability_quartiles.csv` | `graduation_rate` | `q4` | `rate` | 第二學期成績最高的四分之一 | 該組人數 |

`sas_parity.csv` 的欄位為 `cell_id, indicator, group, value, n, value_type`：
`indicator` 為 `pop_analysis`／`dropout_rate`／`graduation_rate`；`group` 等於 `row_key`；
`n` 為該格人數；`value` 為該格的值（`count` 為人數，`rate` 為 0–1 的比率）。

---

## 5. 分組規則（與 R 端逐條對齊；改動即兩端不可比）

### 5.1 分析母體界線

`target in ("Graduate", "Dropout")`。結果為在讀（`Enrolled`）的列不進母體，但仍留在清洗資料集裡。
母體人數**不寫死**：程式由資料算出（2026-11-17 的清洗資料集為 3,630）。

### 5.2 四格：原欄編碼與列序

- `unpaid`（欠繳）= `tuition_uptodate = 0`，即「學費是否繳清」原欄為 0；
- `indebt`（欠債）= `debtor = 1`，即 `Debtor` 原欄為 1；
- 任一欄缺值時該列不進任何一格（與 R 端 `NA` 不入格一致）。

列序固定為 **兩者俱有 → 僅欠繳 → 僅欠債 → 皆無**（`w_both`、`w_only_unpaid`、`w_only_debt`、`w_neither`），
與報告家境一節展示的四個率一一對應（修訂 A-22）。`unpaid = 1` 與 `debtor = 1` 同時成立者屬第一格，
不由欠債另立一格。各格退學率的分母是**該格人數**，不是全母體（修訂 A-5／A-10）。

以此編碼讀同一份資料，phi 為 +0.4349；改以「繳清 = 1」讀會得 −0.4349，故編碼寫死在程式裡。

### 5.3 年齡帶：切點與左右閉

切點 20、25、30、40，帶為**左閉右開** `[a, b)`，最後一帶 `[40, ∞)`：

| 帶 | 條件 | 標籤 |
| --- | --- | --- |
| `a_lt20` | `age_enrol < 20` | `<20` |
| `a_20_24` | `20 <= age_enrol < 25` | `20-24` |
| `a_25_29` | `25 <= age_enrol < 30` | `25-29` |
| `a_30_39` | `30 <= age_enrol < 40` | `30-39` |
| `a_40plus` | `age_enrol >= 40` | `40+` |

SAS 不支援連續比較：`20 <= x < 25` 會被算成 `(20<=x) < 25`，恆真且不報錯，故一律寫成
`20 <= x and x < 25`（專案 README 的已知陷阱）。右閉的讀法會把邊界值歸到下一帶的左端，得到另一組人數，
與 R 端的切法不符（修訂 A-11）。

### 5.4 能力分位：等量切分（不是分位數切點）

1. 能力母體 = 分析母體 ∩ `cu2_grade > 0`（第二學期零分是「無成績」，不是低能力，PRD D4）。
2. 依 `cu2_grade` **升冪**排序；**同分者依原始列序**（程式以 `rownum` 為第二排序鍵，即 `proc sort by cu2_grade rownum`，
   等同 R 端 `order(..., method = "radix")` 的穩定排序）。
3. 組寬 `w = floor(n/4)`：排序後第 1…w 人為 `q1`、第 w+1…2w 為 `q2`、第 2w+1…3w 為 `q3`，
   **末組收餘數**（第 3w+1…n 為 `q4`）。
4. **不得用 `PROC RANK` 或 `PCTLDEF` 的分位數切點**：切點法在此資料上切出不同的組寬與不同的畢業率，
   首尾差會被放大。十四格不接受「差不多」的答案（T06、`REQ-F-F5-1`）。

以 2026-11-17 的清洗資料集：能力母體 2,828 人、`w = 707`、四組各 707 人。

### 5.5 比率的算法

退學率 = 該格內 `target = "Dropout"` 的人數 ÷ 該格人數；畢業率 = 該組內 `target = "Graduate"` 的人數 ÷ 該組人數。
兩者都是「格內／組內」分母，不是全母體。

---

## 6. 精度與匯出

- 值以 `best32.` 匯出：**不套用任何顯示格式、不四捨五入到四位**，故 CSV 內是 15 位以上有效數字
  （例如 `0.9513274336283186…`）。這是 `REQ-F-F10-1` 能用相對差 1e-9 比對的前提（修訂 A-19）：
  若表只存四位，容差就退化成字串相等；若加了顯示格式，SAS 預設的 BEST12 會直接吃掉精度。
- CSV 以 `catx` 組行、`$VARYING.` 寫定長輸出，避免 PUT 把字元欄補空白到宣告長度。
- `n` 為整數人數。
- 容差（`90_parity.R` 判）：**計數零差、比率相對差 1e-9**，對未格式化的 double 比對。
- 對照集**不含 p 值**：十四格全是計數與比率（`D10`、修訂 A-19）。
- 檔名與欄序固定：`sas_parity.csv` 為 `cell_id,indicator,group,value,n,value_type`；
  `cell_map.csv` 為 `cell_id,table,column,row_key,value_type`。兩者皆十四列、無表頭以外的雜訊。
- `05_parity.sas` 也會在 SAS 端寫一份 `cell_map.csv`（與本機那份內容相同），
  使「跑一次即得十四格＋cell_map＋兩張圖」在同一支程式內成立；下載後與本機版本核對即可。

---

## 7. 拒絕

| 情況 | 類別 | 行為 |
| --- | --- | --- |
| 三個資料檔皆不可讀，或載入後缺必要欄（`target`、`debtor`、`tuition_uptodate`、`age_enrol`、`cu2_grade`） | `refuse:input-schema` | log 印出**嘗試過的每個路徑與 SAS 端錯誤原文**（`&syserrortext`）以及 `work.raw` 現有欄清單，**不寫任何產物** |
| 任一格分母為零 | `refuse:empty-denominator` | 印出為零的 `cell_id`，**不寫任何產物**（PRD §3、F3） |

拒絕時不產生 `sas_parity.csv`、`cell_map.csv` 或任何圖；已存在的舊檔不會被覆蓋成半份。

---

## 8. 兩張圖

| 檔案 | 內容 | 軸 |
| --- | --- | --- |
| `age_band_dropout.pdf` | 五帶退學率長條圖，帶序固定為 `<20`、`20-24`、`25-29`、`30-39`、`40+` | y = 退學率 0–1，格上標四位小數 |
| `ability_quartile_graduation.pdf` | 四組畢業率長條圖，組序 `q1`–`q4`（`q1` 為最低成績） | y = 畢業率 0–1，格上標四位小數 |

標題內的 n 由資料算出（`&POP_N`、`&ABILITY_N`），不寫死在程式裡。圖由 SAS 產、R 不出圖（PRD D11）。

---

## 9. 人工核對用的預期值（R 端 2026-11-17 現值，非 SAS 輸出）

下表是**R 端現值**，只供上傳後肉眼核對；權威判定仍由 `90_parity.R` 逐格比對。
若 SAS 的值與此表不同，先查 §5 的四條分組規則（切法、左右閉、列序、編碼），再看 log 的 `n`。

| cell_id | n | value |
| --- | --- | --- |
| `pop_analysis` | 3630 | 3630 |
| `w_both` | 226 | 0.9513274336283186 |
| `w_only_unpaid` | 260 | 0.9307692307692308 |
| `w_only_debt` | 187 | 0.5187165775401069 |
| `w_neither` | 2957 | 0.2932025701724721 |
| `a_lt20` | 1621 | 0.2523133867982727 |
| `a_20_24` | 1033 | 0.3688286544046467 |
| `a_25_29` | 355 | 0.6929577464788732 |
| `a_30_39` | 403 | 0.6401985111662531 |
| `a_40plus` | 218 | 0.5825688073394495 |
| `q1` | 707 | 0.5176803394625177 |
| `q2` | 707 | 0.7694483734087695 |
| `q3` | 707 | 0.8387553041018387 |
| `q4` | 707 | 0.8925035360678925 |

---

## 10. 已知限制

- **本機沒有 SAS。** `05_parity.sas` 的產物（`sas_parity.csv` 與兩張 PDF）只能在 SAS Studio 上產生，
  目前尚未產生，因此 `output/parity/` 只有 `cell_map.csv` 這一個由本機產生的檔案。
  在 SAS 端跑完並下載之前，`90_parity.R` 會以「對照值缺席」結束（結束碼 1），這是預期行為。
- 程式的分組邏輯已在本機以資料逐條重演核對（十四格的 n 與比率與 R 表逐位相同），
  但 **SAS 語法本身未經 SAS 執行驗證**；第一次在 ODA 執行時，先確認 log 無 ERROR、十四列齊備再下載。
- ODA 的 session 有時限、閒置會斷；不要用無痕模式，額度 5 GB、本專案用不到 2 MB。
