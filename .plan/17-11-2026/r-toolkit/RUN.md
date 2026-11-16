# RUN — r-toolkit 執行台帳

| Field | Value |
| --- | --- |
| 契約 | `PRD.md`、`TASKS.md`、`tasks/`（只讀，除帶日期修訂） |
| 開始 | 2026-11-17T02:58（HKT） |
| 工作分支 | `main`（於第一個 worktree 建立前記錄；執行期間不再讀 `HEAD`） |
| 基線 commit | `5e695f7`，44 個檔案（`git init -b main` 後的第一個 commit） |
| 目前 HEAD | `8cefc31`（T01 合併後） |

## 0. 前置檢查（第 1 步）

| 檢查 | 結果 |
| --- | --- |
| DAG 無環 | 通過（邊集 DFS，無回邊） |
| 每個節點有任務檔 | 28 / 28 |
| 登記與任務檔一致（Class、Depends on、Owned） | 通過（逐任務比對，差集為空） |
| 兩閘可在圖上判定 | `G1` 由 `T01`／`T02`／`T03`／`T14` 餵入；`G2` 由 `T13`／`T14` 餵入 |
| 26 條 PRD 需求全數出現在 `TASKS.md` | 通過 |
| git 儲存庫 | 原本不存在；`.gitignore` 已在（2026-11-11）。已 `git init -b main` 並以 `5e695f7` 建基線。刪 `.git` 即回到原狀 |

## 1. 共用前置（第 2 步）

- **分支記錄**：`main`。執行期間若偵測到分支變更即停。
- **基線**：每個 worktree 自當時的 `main` HEAD 建立。第一波 `5e695f7`；第二波 `8cefc31`。
- **隔離**：worktree 置於 `~/.hermes/cache/scratch/pdd-r-toolkit/<task-id>`，不落於專案樹內。R 的共用產物是 `renv/library`（已被兩層 `.gitignore` 排除），每個 worktree 各自一份；同一波無兩個任務會寫 `renv.lock`。
- **主樹狀態**：乾淨。採「worktree 內 commit → `git merge --no-ff`」。
- **共用檔**：`renv.lock`、`00_setup.R` 由 `T01` 獨佔；`lib/stats.R` 由 `T03` 獨佔。

## 2. 派工台帳

| 波 | 任務 | 類別 | worktree | 基線 | 狀態 | commit | 備註 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `T01` | construction | `T01` | `5e695f7` | **已接受、已合併、worktree 已移除** | `109abb8`（merge `8cefc31`） | 驗收：delta 只在 owned（另 `renv/.gitignore` 為 renv 產物）；兩條自檢主代理重跑通過；主樹首次觸發還原 6.3 秒、52 套件 |
| 2 | `T02` | construction | `T02` | `8cefc31` | dispatched | — | 清冊九列固定表 |
| 2 | `T03` | construction | `T03` | `8cefc31` | dispatched | — | 六個具名函式 |

## 3. T01 驗收記錄（construction 類）

| 檢查 | 證據 |
| --- | --- |
| 目的可自真實入口觀察 | 主樹 `Rscript -e 'source("programs/R/00_setup.R"); c(ANALYSIS_N, ABILITY_N)'` → `[1] 3630 2828` |
| 版本環境同步 | `renv::status()$synchronized` → `TRUE`；訊息 `No issues found` |
| 還原分支可跑 | 主樹首次執行（無 library）→ `Successfully installed 52 packages`、`耗時 6.3 秒` |
| delta ⊆ owned | `git status -uall` 僅 `.Rprofile`、`renv.lock`、`programs/R/00_setup.R`、`renv/activate.R`、`renv/.gitignore`（末者為 renv 產生，byproduct） |
| 契約未被改寫 | 任務檔 sha256 `fc0754b3…376a5`、PRD `6a22c19e…`、TASKS `07c9578d…` 執行前後一致 |
| 記錄內容 | `output/logs/00_setup.log` 含 `r_version`、`package_count: 53`、`restore_elapsed_sec`、`synchronized: TRUE` |
| 常數數目 | 14 個（任務檔寫「十三項」，屬計數筆誤，見 `AMENDMENTS.md` A-28；行為不受影響） |

保留事項：`output/logs/*.log` 被專案既有 `.gitignore` 排除，記錄不進版控、每次執行重生；`renv/library` 亦然。此為 repo 自身政策，非任務缺陷。

## 4. 驗收準則（按類別）

| 類別 | 驗收看什麼 |
| --- | --- |
| construction | 目的可自真實入口觀察；delta ⊆ owned；受影響的既有套件與型別檢查仍綠 |
| verification A | 模型存在；性質在預算內跑過；反例已收縮並固定 |
| verification C | 變更前後皆綠，且注入一個違規必須轉紅 |

共同原則：subagent 的自報不是驗收；測了 0 個案例的 exit 0 不算綠；既有 oracle 不得被削弱；報告中的任何「實測 X」由主代理以同一指令重跑。

## 5. 阻斷清單（2026-11-17T04:05）

| # | 阻斷 | 任務 | 證據 | 需要誰 |
| --- | --- | --- | --- | --- |
| ~~B1~~ | **已解決（Q43：改報告）**：報告三數改為 0.0958／0.2611／0.0050；`REPORTED_R2` 待同步 | `T07`（已接受，三列 `mismatch`）、`V06` | `model_comparison.csv`：0.0958／0.2611／0.0050；`report.md`：0.0947／0.2607／0.0092 | 使用者：改報告，或保留並另立重算任務 |
| B2 | `sas_parity.csv` 與兩張 PDF 需在 SAS ODA 執行後下載 | `T12`、`V10` | `output/parity/` 只有 `cell_map.csv`；本機無 SAS | 使用者：跑 `programs/SAS/05_parity.sas` 並把三個產物放進 `output/parity/` |

B1 已由使用者裁決（`qa.md` Q43：「改報告」）。B2 仍待使用者執行 SAS。`G2` 因為 `T13`（依賴 `T12`）未完成而未關閉，三條 C 檢查因此不可派工。

## 6. 收尾檢查（第 7 步，尚未到）

- [x] 每批：worktree 內 commit → `merge --no-ff` → 主樹重跑驗證 → 移除 worktree → prune → 刪分支
- [ ] 執行結束時 `git worktree list` 只剩主樹
- [ ] `git branch --list 'pdd/*'` 為空
- [ ] worktree 建立數 = 移除數 + 保留數
- [ ] 無 push、tag、deploy

## 7. 接受清單（截至 2026-11-17T04:40）

| 任務 | 類別 | 狀態 | 證據 |
| --- | --- | --- | --- |
| T01 | construction | 接受、已合併 | `109abb8`；主樹首次還原 6.3 秒／52 套件 |
| T02 | construction | 接受、已合併 | 清冊九列；raw sha 不變；SAS 兩式讀回 4,424×37 |
| T03 | construction | 接受、已合併 | 六函式；後由 T03b 修整數溢位 |
| T04 | construction | 接受、已合併 | 四格 226/260/187/2957、phi 0.4349 |
| T05 | construction | 接受、已合併 | 五帶、婚配 p 0.02455/0.1301 |
| T06 | construction | 接受、已合併 | 707×4、移動表對角 396/285/313/477 |
| T07 | construction | 接受、已合併 | 六列；三列 `mismatch`（見 B1） |
| T08 | construction | 接受、已合併 | 74/17/19；西語圈 p 0.3586 |
| T09 | construction | 接受、已合併 | 30 列；10/9/10 |
| T10 | construction | 接受、已合併 | 36 列；五類判詞 |
| T11 | construction | 接受、已合併 | `05_parity.sas`、`cell_map.csv` 十四列；SAS 產物待 B2 |
| T14 | construction | 接受、已合併 | 測試台；`harness_table` 已解耦 |
| V01–V05 | verification A | 接受、已合併 | 43 個 test、主樹 runner 連跑兩次 exit 0 |

退回／未完成：`V04b`、`V05b`（harness 需自行載入 helper，A-42）在跑；`V07`–`V09`、`V11` 可派未派；`V06` 卡 B1；`V10`、`T12`、`T13` 卡 B2；`V12`–`V14` 卡 `G2`。

### 一次無法複現的紅燈（記錄，不當缺陷）

2026-11-17T04:10 一支背景批次在五個 worktree 上跑測試，回報 `V01 exit=1`。當時正值合併、worktree 正在被移除（其餘四個 worktree 已被刪，`cd` 失敗）。在主樹穩定後重跑 `test_file("test-01_F1.R")` 得 6 tests、0 failed、0 error、exit 0；全套 runner 連跑兩次亦 exit 0，兩次輸出只差暫存路徑。判定為併發狀態下的暫態，非測試缺陷；若日後重現，觸發條件是「worktree 同時被移除」。

## 8. 驗收準則（A-43 之後）

任何驗證任務必須三種入口同綠才算接受：① `Rscript tests/testthat.R`；② `testthat::test_dir("tests/testthat")`；③ 逐檔 `testthat::test_file()`。單一入口的綠燈不算證據。

## 9. 最終狀態（2026-11-17T04:50）

`main` 上十個測試檔、95 個 test、0 failed、0 error、3 skipped（全在 `F11`，因 `run_all.R` 未建立而由 B2 造成）。

| 檔 | tests | fail | err | skip |
| --- | --- | --- | --- | --- |
| test-01_F1.R | 6 | 0 | 0 | 0 |
| test-02_F2.R | 12 | 0 | 0 | 0 |
| test-03_F3.R | 8 | 0 | 0 | 0 |
| test-04_F4.R | 8 | 0 | 0 | 0 |
| test-05_F5.R | 9 | 0 | 0 | 0 |
| test-07_F7.R | 11 | 0 | 0 | 0 |
| test-08_F8.R | 7 | 0 | 0 | 0 |
| test-09_F9.R | 11 | 0 | 0 | 0 |
| test-06_F6.R | 9 | 0 | 0 | 0 |
| test-11_F11.R | 14 | 0 | 0 | 3 |

已完成 23 個任務：T01–T11、T14、T07b（建構與修復）與 V01–V09、V11（模型）。B1 已由 Q43／Q44 結案。
未完成：V10／T12／T13（B2，需 SAS）、V12–V14（卡 `G2`）、以及 A-44 的 S1／S3 兩個應另立的建構任務。
