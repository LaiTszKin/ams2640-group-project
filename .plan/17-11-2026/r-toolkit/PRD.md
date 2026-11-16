# PRD — r-toolkit

| Field | Value |
| --- | --- |
| Plan | `r-toolkit` — 依研究已定的八組分析，建立可重跑的 R 工具，R 為數值權威、SAS 為對照與視覺化 |
| Date | 2026-11-17 |
| Owner | Sunny（Lai Tsz Kin），AMS2640 組員；分析判準來自同日的討論紀錄 |
| Status | Draft |
| Source | `~/thoughts/財富、社會背景與能力對畢業率的影響/`（`summary.md`、`report.md`、`refine.md`、Q1–Q42）；`docs/AMS2640_Project_Guideline_2627S1 (3).doc` |
| Next | `pdd:decompose` |

**What this document is.** 這份文件寫的是工具要交付的行為：誰觸發、產出什麼、在什麼條件下拒絕、什麼情況絕不可發生。程式結構只出現在 §5，因為那份結構目前不存在，它就是交付物本身。

## 1. Business and problem

課程報告的每一個數字目前來自一次臨時核算：Python 腳本散落在討論過程中，沒有進入專案，也沒有進入版本控制。分母在討論中改過一次（4,424 改為 3,630），既有審核表仍停在舊分母；`report.md` 裡二十八個數字因此沒有可重跑的路徑。評分者看到的是數字，看不到數字的來源。

同時，本專案的 R 端目前無法執行：專案根目錄的啟動設定會載入版本管理環境的啟動腳本，而該環境尚未建立，任何 R 指令在專案根目錄下即刻失敗（2026-11-17 實測，訊息為版本環境的啟動檔找不到）。程式目錄、輸出目錄與版本環境目錄皆不存在，只有清洗後的舊資料集。

值得做這件事的理由是一條：報告裡的每個數字都能由一條指令重現，且 R 與 SAS 兩端在同一份資料上給出相同答案。這是課程指引對雙工具的要求，也是 `report.md` 能被檢查的條件。

## 2. Actors and objects

| Actor | Who it is | What it may do | What it is refused |
| --- | --- | --- | --- |
| 分析者 | 組員，在本機執行 | 建立母體、跑任一分析、重跑全部、比對兩端 | 寫入原始資料；以未鎖定的套件版本執行；覆寫未經確認的舊產物 |
| 評分者 | 課程導師 | 讀表、讀圖、讀執行記錄 | 執行工具（工具對它唯讀） |
| SAS 端 | 瀏覽器中的 SAS Studio | 讀取清洗後的資料集、重算四個關鍵數字、出圖 | 修改清洗後的資料集；以自身的數值覆蓋 R 的表 |
| 工具 | R 程式 | 讀原始資料、寫清洗資料與輸出 | 越過專案根目錄解析路徑；在缺套件時靜默繼續 |

- **Objects and quantities**：分析母體 — 人，3,630，界線為已畢業加已退學，不可逆（一旦入組不改）；能力母體 — 人，2,828，界線為第二學期成績大於零；比率 — 無單位，0 至 1，呈現取四位有效數字；計數 — 人，整數；phi — 無單位，−1 至 1；模型解釋力 — 無單位，0 至 1；表 — CSV，英文欄名，一表一分析；圖 — PDF，由 SAS 產；執行記錄 — 文字，附時間戳。

## 3. Business rules

| Operation | Precondition | Result | Must hold afterwards |
| --- | --- | --- | --- |
| 建立母體 | 原始資料的欄數為 37（36 變數加結果欄） | `apply` | 清洗資料集就位，母體 3,630 與能力母體 2,828 同時寫入清冊 |
| 建立母體 | 原始資料欄數與 37 不符 | `refuse:input-schema` | 無產物變動 |
| 跑任一分析 | 清洗資料集存在且晚於原始資料 | `apply` | 該分析的表格與記錄段落就位 |
| 跑任一分析 | 分析所需分母為零 | `refuse:empty-denominator` | 該分析不留空表，記錄寫明分母為零 |
| 跑任一分析 | 所需欄位的缺值數超出清冊登記 | `refuse:missing-profile` | 記錄寫明超出的欄位與筆數 |
| 比對兩端 | R 的表與 SAS 的對照值皆存在 | `apply` | 差異表就位，逐格標明通過與否 |
| 比對兩端 | 任一數字超出容差 | `refuse:parity` | 整體判定為不一致，並指出第一個不符的格子 |
| 寫任何檔案 | 目標在原始資料目錄內 | `refuse:readonly-target` | 寫入中止，原始資料的校驗值不變 |
| 執行任一分析 | 版本鎖定環境與鎖定檔不同步 | `refuse:unpinned-package` | 拒絕執行並列出不同步的套件 |

- **States and transitions**：環境 — 未還原 → 已還原 → 可執行；未還原狀態下令行即失敗，允許的移動只有「還原」。資料 — 原始 → 清洗 → 分析產物；原始往後不可移動。表 — 未產生 → 已產生 → 已比對 → 已接受；比對失敗的表回到「已產生」，記錄追加一筆。
- **Invariants**：每一張表都帶母體與 n，範圍為全部輸出表；比率以四位有效數字呈現，範圍為全部數值欄；畢業率恆等於已畢業除以「已畢業加已退學」，範圍為任何引用該率的句子；原始資料的校驗值恆不變，範圍為全部執行；同一份輸入重跑得到相同的表的內容，範圍為全部輸出。
- **Deliberately not encoded**：因果方向 — 資料在同代人身上記錄成績與結果，工具只出關聯量；十頁篇幅的取捨 — 屬撰稿決定，工具不判斷哪一層進正文。

## 4. Behaviour

### F1 在新機器上把工具還原到可執行

- **Who, and when it triggers**：分析者，第一次在該機器開啟專案，或換機器之後。
- **Happy path**：進入專案 → 執行還原 → 版本鎖定環境建立 → 套件版本與鎖定檔一致 → 一行自檢印出環境版本與套件數 → 可執行。
- **Refusal path**：鎖定檔缺漏或套件來源不可達時拒絕，類別 `refuse:unpinned-package`，分析者看到缺哪些套件、原始錯誤，下一步是接通來源再重跑。
- **Boundary behaviour**：環境已存在時重跑為無操作；鎖定檔比已安裝的新時，還原只補差額；套件版本比鎖定檔新時，以鎖定檔為準並在記錄中列出被降級的套件。
- **Must never happen**：專案根目錄的任何指令因為缺少啟動檔而失敗（2026-11-17 的實測狀態）；在版本不同步的情況下產出表。
- **Where it is visible**：執行記錄的第一段，含 R 版本、套件數、還原耗時。

### F2 建立分析母體

- **Who, and when it triggers**：分析者，在任何分析之前，且每次原始資料變動之後。
- **Happy path**：讀原始資料 → 修正分隔符、編碼與欄名（SAS 格式限 32 字元與 `[A-Za-z0-9_]`，對應表入記錄）→ 標記結果欄 → 寫出清洗資料集與 SAS 可讀格式 → 寫出母體清冊。清冊為長格式，`population` 取 `full`／`analysis`／`ability` 三個具名值，九列固定：總筆數、已畢業、已退學、在讀（母體 `full`）、分析母體、未登記修讀 180、第二學期零分 802、零分中退學 727、能力母體（修訂 A-21）。
- **Refusal path**：欄數與 37 不符時拒絕，類別 `refuse:input-schema`，清冊不更新；缺值超出登記時拒絕，類別 `refuse:missing-profile`。
- **Boundary behaviour**：結果為「在讀」的 794 人不進分析母體，但保留在清洗資料集中；兩個學期成績皆為零的 180 人不是零分，缺值登記須與零分分開；第二學期成績為零的 802 人中 727 人為退學者，該組不進能力母體。
- **Must never happen**：原始資料被寫入；以 4,424 為分母產出任一張表。
- **Where it is visible**：母體清冊與清洗資料集的檔案時間。

### F3 財富層的四格與關聯強度

- **Who, and when it triggers**：分析者，需要家境那一節的數字時。
- **Happy path**：以「學費是否繳清」與「是否欠債」交叉 → 四格計數 → 各格退學率 → 兩欄的 phi → 寫表。
- **Refusal path**：任一格為空時拒絕，類別 `refuse:empty-denominator`，記錄寫明空格的位置。
- **Boundary behaviour**：欠繳為入口、欠債為輔助，兩者同時出現時計入「兩者俱有」；各格退學率以**該格人數**為分母，另設 share 欄以分析母體為分母（四格 share 相加為 1）。四格列序為兩者俱有、僅欠繳、僅欠債、皆無，與本節展示的四個率一一對應（修訂 A-22）。
- **Must never happen**：以欠債作為家境的唯一入口；把某格退學率寫成佔全樣本的比例（欠繳 486 人中退學 457 人 = 94.03%，分母是格內人數）。
- **Where it is visible**：家境一節的表格，四格分別為 95.13%、93.08%、51.87%、29.32%，phi 0.4349（2026-11-17 實算，母體 3,630）。

### F4 社會背景：年齡帶與婚配

- **Who, and when it triggers**：分析者，需要年齡那一節的數字時。
- **Happy path**：切五個年齡帶 → 各帶人數、退學率、欠繳率 → 25–29 與 40 歲以上兩帶的退學率與欠繳率各做一次精確檢定 → 以婚姻狀況分層，逐帶做已婚對單身的精確檢定 → 寫表。
- **Refusal path**：帶內已婚或單身人數為零時拒絕，類別 `refuse:empty-denominator`；任一格人數低於 30 的帶列入表、p 值留空並標 `insufficient_n`，不拒絕（修訂 A-11）。
- **Boundary behaviour**：帶的切點為 20、25、30、40；40 歲以上含 40；檢定為雙尾；控制變數（失業率、通脹率、GDP）以輔助身分進入，不作主效應。
- **Must never happen**：把婚姻狀況當作年齡層的機制（已由 Q36 排除）；把宏觀三欄升為主效應（已由 Q37 排除）。
- **Where it is visible**：年齡一節的表格與兩個檢定的 p 值：25–29 對 40 以上的欠繳率 p = 0.4987、退學率 p = 0.0088；30–39 已婚對單身 p = 0.0245、40 以上 p = 0.1301。

### F5 能力：分位表與兩期追蹤

- **Who, and when it triggers**：分析者，需要能力那一節的數字時。
- **Happy path**：剔除該期成績為零者 → 依第二學期成績切四分位 → 各組人數與畢業率 → 以同一批人比較第一與第二學期的組別移動 → 寫表。
- **Refusal path**：剔除後分母為零時拒絕，類別 `refuse:empty-denominator`。
- **Boundary behaviour**：四組每組 707 人、母體 2,828；入學前成績另計，不與在校成績混在同一組；同一人在兩期可以換組。
- **Must never happen**：含零分者計算分位（該切法把首尾差由 37.48 個百分點放大到 77.96）；以名次而非人以追蹤。
- **Where it is visible**：能力一節的四格，畢業率依序 51.77%、76.94%、83.88%、89.25%。

### F6 三層的解釋力比較

- **Who, and when it triggers**：分析者，需要「主導」那一句時。
- **Happy path**：配適六列（五個模型規格 × 兩個母體：年齡帶＠3,630、財務三欄＠3,630、財務三欄＠2,828、能力分位＠2,828、財務加能力＠2,828、入學成績分位＠2,828）→ 記錄解釋力與曲線下面積 → 寫比較表 → 附每層的機制句與否證條件（修訂 A-16）。年齡帶模型採四帶參數化（小於 25 併為一帶），0.0756 以此重現；五帶為 0.0839。
- **Refusal path**：模型不收斂時拒絕，類別 `refuse:empty-denominator` 的廣義形（樣本不足以配適），記錄寫明是哪一個模型。
- **Boundary behaviour**：比較在同一母體上進行；能力與財務的並置以 2,828 為母體，年齡帶以 3,630；兩者不同母體時表內分別標明，不作單一排序。
- **Must never happen**：把同代人（同期成績）的相關讀成前因；以欄位數多寡代替解釋力。
- **Where it is visible**：解釋力比較表。三個錨值由本規格可重現：年齡帶 0.0756（四帶參數化）、財務三欄 0.2227（2,828 上 0.2011）；能力分位 0.0947、財務加能力 0.2607、入學成績 0.0092 依賴分位切法與分箱規格，於工具重算後以「四位有效數字與表中值相等」驗收，**若與報告所載不同則標 `mismatch` 交主代理裁決，不自行改寫報告**（修訂 A-23）。

### F7 語言文化：小樣本的界線

- **Who, and when it triggers**：分析者，需要局限那一節的數字時。
- **Happy path**：取非本地國籍者 → 按語言圈分組（葡語 74、西語 17、其他 19）→ 各組人數與退學率 → 對**西語圈**與本地比對（最大組為葡語圈，與本地同語不作跨語比較），給精確檢定與區間 → 計算驗出該差距所需的每組人數 → 寫表（修訂 A-18）。
- **Refusal path**：任一組人數低於 10 時拒絕出率，類別 `refuse:empty-denominator`，只出計數。
- **Boundary behaviour**：非本地國籍共 110 人，可比較者 86 人；葡語圈與本地同語，不作跨語比較；檢定力以八成計算。
- **Must never happen**：以 110 人的分組差異下結論（結論已於 Q31 撤回，工具只出局限材料）。
- **Where it is visible**：局限一節的表格，含西語圈 11 人、退學率 54.55%、p = 0.3586、每組約需 165 人。

### F8 宏觀三欄的角色

- **Who, and when it triggers**：分析者，需要控制變數那一段時。
- **Happy path**：以三欄三元組建立十個年度區塊（資料無年份欄，列序不含年份資訊）→ 逐 (variable, year) 計數 → 寫逐值表 → 標明以控制變數身分進入模型（修訂 A-17）。inflation 的值 1.4 跨兩個年度，故全表 30 列而非 29。
- **Refusal path**：某欄的不同值多於人數的十分之一時拒絕標為宏觀，類別 `refuse:input-schema`。
- **Boundary behaviour**：三欄各只有九至十個值，每個值由數百人共用。
- **Must never happen**：以年份為單位的變數承擔主效應的結論句。
- **Where it is visible**：值域表與模型表中的控制變數列。

### F9 相關審核：真效果與假效果

- **Who, and when it triggers**：分析者，需要「哪些欄位值得進模型」時。
- **Happy path**：逐欄計算效果量 → BH 校正 → 依規則判為定義性、實質、弱、噪音或生態謬誤五類（弱＝效果量 0.10 至 0.30，保留為否）→ 寫審核表（修訂 A-24）。
- **Refusal path**：分母與正文不同的表不得發佈，類別 `refuse:input-schema`；既有審核表停在 4,424，重跑後須為 3,630。
- **Boundary behaviour**：類別欄用變異數分析式的效果量，連續欄用相關係數；校正後的保留判定以效果量與校正後 p 值並用；以年份為單位的欄另標生態謬誤。
- **Must never happen**：同一份報告出現兩個分母；把通過科目數當作獨立解釋變數（與結果同代）。
- **Where it is visible**：審核表與其判詞欄，n 欄為 3,630。

### F10 SAS 端的對照與視覺化

- **Who, and when it triggers**：分析者，R 端全部完成後。
- **Happy path**：上傳清洗資料集與對照程式 → SAS 重算四個關鍵數字（分析母體人數、四格退學率、年齡帶退學率、能力分位畢業率）→ 出圖 → 匯出對照值 → R 端比對 → 寫差異表。
- **Refusal path**：任一數字超出容差時，整體判定為不一致，類別 `refuse:parity`，並指出第一個不符的格子。
- **Boundary behaviour**：容差為計數零差、比率與 p 值的相對差 1e-9；SAS 端只讀清洗資料集；圖由 SAS 產，R 端不重複出圖。
- **Must never happen**：兩端數字不一致而報告照用；SAS 的數值覆蓋 R 的表。
- **Where it is visible**：差異表與 SAS 的執行記錄。

### F11 交付與引用對照

- **Who, and when it triggers**：分析者，交稿前。
- **Happy path**：單一入口跑完全部 → 檢查每張表的母體與 n → 產生數字對照表（`report.md` 的每個數字對應到哪張表哪一列）→ 記錄寫明執行時間與套件版本。
- **Refusal path**：任一表缺母體或 n 時拒絕交付，類別 `refuse:missing-profile`。
- **Boundary behaviour**：重跑兩次得到相同的表；記錄附時間戳，表本身不附。
- **Must never happen**：報告引用的數字在表中找不到。
- **Where it is visible**：對照表與執行記錄。

## 5. Architecture

- **Module boundaries and responsibilities**：`programs/R/` 一個編號一個分析步驟，編號與 `programs/SAS/` 一一對應；`programs/R/00_setup.R` 唯一持有路徑、母體界線、年齡切點、分位數、容差與套件檢查；`programs/R/lib/` 持有可重用的統計量（比率與其區間、精確檢定、phi、解釋力與曲線下面積、四位有效數字的呈現）；`programs/R/run_all.R` 為單一入口；`programs/R/90_parity.R` 讀既有輸出表與 SAS 對照值，並寫出 `parity_diff.csv` 與其記錄（修訂 A-15）。`programs/R/run_all.R` 為交付入口，可讀 `output/tables` 的既有表以檢查母體與 n，其餘編號腳本不得讀取輸出目錄。`tests/testthat/helper-harness.R` 為測試端唯一共用設施，持有樣本、種子、暫存目錄與斷言輔助；任何測試檔自行讀資料或設種子即違反 `REQ-A-7`。分析腳本不得讀取輸出目錄，`lib/` 不得讀取任何資料。
- **Dependency direction**：分析腳本 → `lib/` → `00_setup.R`；`run_all.R` → 各分析腳本；`90_parity.R` → 輸出目錄與對照值。`lib/` 不依賴任何編號腳本；編號腳本之間互不 `source`。
- **Public surface**：`00_setup.R` 匯出的十三項常數（`PROJ_ROOT`、`OUT_ROOT`、`ANALYSIS_N`、`ABILITY_N`、`PROP_CI_LEVEL`、`ANALYSIS_RESULTS`、`ABILITY_MIN_SCORE`、`AGE_BREAKS`、`AGE_BREAKS_MODEL`、`N_QUARTILES`、`PARITY_TOL`、`SIG_DIGITS`、`MISSING_PROFILE`、`RETIRED_ANALYSIS_N`）。`OUT_ROOT` 為輸出基底（預設 `PROJ_ROOT/output`），可由 `RTOOLKIT_OUT_ROOT` 覆寫；全部寫入路徑自它導出（修訂 A-20）；`lib/` 匯出的**六個**函式（`prop_ci`、`fisher_2x2`、`phi_2x2`、`mcfadden_r2`、`auc_rank`、`fmt_sig`）。其餘皆為內部（修訂 A-14）。
- **Layers / partitions and cycles**：三層（設定、統計量、分析），只允許由上往下依賴；編號腳本之間的橫向引用為禁止依賴。
- **Performance (if involved)**：不涉及。全部計算在 3,630 列上進行，單次全跑以分鐘計。
- **Structure left alone this time**：`programs/SAS/` 的既有編號配置與 `tools/sasopen` 維持原樣，因為 SAS 端本次只做對照與出圖；`data/processed/` 的舊產物不刪，由 F2 覆蓋並在記錄中留下新舊時間。

## 6. Requirements

### 6.1 Functional requirements

#### REQ-F-F1-1 專案根目錄下的任一 R 指令能在缺版本環境時自行還原並成功結束

- **From rule**：§3「建立母體」之前的前置狀態，F1 的 happy path
- **Failure shape**：分析者在新機器上執行任一分析，取得版本環境的啟動檔找不到的錯誤（2026-11-17 的現狀）

#### REQ-F-F2-1 清洗資料集與母體清冊在同一指令下產生，且清冊記載 3,630 與 2,828

- **From rule**：F2 happy path；§3 不變量「每張表帶母體與 n」
- **Failure shape**：報告的家境表以 4,424 為分母，與正文的 3,630 並列於同一份文件

#### REQ-F-F2-2 原始資料的校驗值在全部執行前後相同

- **From rule**：§3 `refuse:readonly-target`；F2 must-never
- **Failure shape**：評分者比對原始檔的修改時間，發現分析過程中寫入

#### REQ-F-F2-3 欄數不為 37 或結果欄類別改變時，清冊不更新並指出差異

- **From rule**：§3 `refuse:input-schema`
- **Failure shape**：換一份資料後表照出，但分母已不是研究界定的那一群

#### REQ-F-F3-1 四格退學率以分析母體為分母，並輸出 phi

- **From rule**：F3 happy path；§2 物件 phi 的界線；修訂 A-10 定各格分母為格內人數，另設 share 欄
- **Failure shape**：四格率的加總被當成 100%（該和應為 0.3915），或 share 欄四格相加不等於 1

#### REQ-F-F4-1 五個年齡帶的人數、退學率、欠繳率在同一次輸出中齊備

- **From rule**：F4 happy path
- **Failure shape**：年齡一節的曲線缺一段，或某帶的分母取自另一母體

#### REQ-F-F4-2 25–29 與 40 以上兩帶的兩項檢定各自給出雙尾 p 值

- **From rule**：F4 happy path；Q41 的核算
- **Failure shape**：年齡一節只能說「接近」或「不同」，讀者無從檢查

#### REQ-F-F4-3 婚姻分層逐帶給出已婚與單身的退學率與 p 值

- **From rule**：F4 happy path；Q36 的判定（婚姻不作機制）
- **Failure shape**：報告把婚姻狀況寫成家庭負擔的證據，而表格顯示 30 歲以上已婚者的退學率較低

#### REQ-F-F5-1 能力分位以第二學期成績為準，剔除零成績者，四組各 707 人

- **From rule**：F5 happy path；§2 能力母體 2,828
- **Failure shape**：能力一節的首尾差為 77.96 個百分點，較剔除零分者高一倍

#### REQ-F-F5-2 兩期之間以同一批人追蹤，輸出組別移動的計數

- **From rule**：F5 happy path；Q34 的判定
- **Failure shape**：曲線呈名次流動，而報告聲稱觀察的是同一批人的變化

#### REQ-F-F6-1 四個模型在同一張表上給出解釋力與曲線下面積，並標明各自的母體

- **From rule**：F6 happy path；§3 不變量「每張表帶母體與 n」
- **Failure shape**：比較表把 3,630 與 2,828 的解釋力排成單一序列

#### REQ-F-F6-2 每一層的解釋力列附一條否證條件

- **From rule**：§3 判準（Q38 的三條並用）
- **Failure shape**：讀者無法指出什麼觀察會推翻「主導」那一句

#### REQ-F-F7-1 非本地國籍的分組只出計數與率，並附檢定力所需的每組人數

- **From rule**：F7 happy path；Q31 的撤回
- **Failure shape**：局限一節被讀成支持語言隔閡的結論

#### REQ-F-F8-1 宏觀三欄輸出不同值數量與其年份對應，並標為控制變數

- **From rule**：F8 happy path；Q37 的判定
- **Failure shape**：模型表把以年份為單位的欄與個人層欄並列比較係數

#### REQ-F-F9-1 審核表在 3,630 上重算，並保留判詞欄

- **From rule**：F9 happy path；Q24 的判定
- **Failure shape**：報告附錄的審核表與正文分母不同，n 欄為 4,424

#### REQ-F-F10-1 SAS 端四個關鍵數字與 R 端逐格比對，差異在容差內

- **From rule**：F10 happy path；§3 `refuse:parity`
- **Failure shape**：課程要求雙工具，而兩端數字不同且無人察覺

#### REQ-F-F10-2 比對失敗時整體判定為不一致，並指出第一個不符的格子

- **From rule**：§3 `refuse:parity` 的後置條件
- **Failure shape**：差異表列出十格不符，讀者不知道哪一格先壞

#### REQ-F-F11-1 單一入口跑完全部，並產生報告數字與表格位置的對照

- **From rule**：F11 happy path
- **Failure shape**：交稿前發現某個數字出自一次性的核算，表裡找不到

#### REQ-F-F11-2 同一輸入連跑兩次，產生的表逐位元組相同

- **From rule**：§3 不變量「重跑得到相同的表」
- **Failure shape**：兩次跑的比率在第四位有效數字上不同，讀者無從判斷哪一次為準

### 6.2 Architectural requirements

#### REQ-A-1 專案內沒有任何以工作目錄為前提的絕對路徑或目錄切換

- **Scope**：`programs/R/` 下全部 R 檔案
- **Violation shape**：出現 `setwd(` 或在字串中寫死使用者家目錄的路徑
- **How it is checked**：`grep -rn "setwd(" programs/R | wc -l` 為 0，且 `grep -rn "/Users/" programs/R | wc -l` 為 0；今日基線同為 0（尚無 R 檔），故採絕對形式

#### REQ-A-2 母體界線、年齡切點、分位數與容差只在一處定義

- **Scope**：`programs/R/` 下除 `00_setup.R` 以外的全部檔案
- **Violation shape**：某個分析腳本自行寫出 3630、2828、20、40、0.25，或寫死 `output/tables` 一類字面路徑而不經 `OUT_ROOT`（修訂 A-20），或以 `0.25` 之類的常數切分位
- **How it is checked**：`grep -rn -E "\b(3630|2828|4424)\b" programs/R --include=*.R | grep -v 00_setup | wc -l` 為 0，年齡切點與分位數以同一方式檢查；今日基線不適用（無檔案），採絕對形式

#### REQ-A-3 分析腳本之間沒有橫向引用

- **Scope**：`programs/R/` 下編號開頭的腳本
- **Violation shape**：`03_` 開頭的腳本 `source()` 另一個編號腳本
- **How it is checked**：`grep -rn "source(" programs/R | grep -v -E "(00_setup|lib/)" | wc -l` 為 0

#### REQ-A-4 套件環境與鎖定檔一致才允許產出

- **Scope**：`renv.lock` 與 `programs/R/` 的全部執行入口
- **Violation shape**：鎖定檔未更新而程式引用了新套件；或版本環境不存在而程式仍執行
- **How it is checked**：`Rscript -e 'renv::status()$synchronized'` 回傳真，且 `00_setup.R` 在啟動時檢查並在假時停止。今日基線為假（`renv/` 目錄不存在，鎖定檔 31 個套件中缺 testthat、PropCIs、broom；ggplot2 依修訂 A-3 不進鎖定檔），本計劃的範圍是把基線修至真（修訂 A-12）

#### REQ-A-5 輸出可重建：同一輸入重跑得到相同的表

- **Scope**：`output/tables/` 下全部 CSV
- **Violation shape**：表內含時間戳或亂序的列，兩次執行的校驗值不同
- **How it is checked**：`shasum -a 256 output/tables/*.csv` 在兩次全跑後相同；今日無基線，首跑即建立基線

#### REQ-A-6 已發佈的 SAS 對照值與 R 的表分屬兩個目錄，互不覆寫

- **Scope**：`output/tables/` 與 SAS 匯出的對照值所在目錄
- **Violation shape**：SAS 的數值檔與 R 的同名表落在同一個路徑
- **How it is checked**：`90_parity.R` 內的兩個具名常數 `PARITY_READ_PATHS` 與 `PARITY_WRITE_PATHS` 所列路徑取交集為空（修訂 A-13：原文的 grep 子句對一個必須寫 `output/tables/` 的腳本必然命中，已撤）

#### REQ-A-7 測試的樣本、種子與暫存目錄只由一個測試台提供

- **Scope**：`tests/` 下全部測試檔
- **Violation shape**：某個測試檔自行讀資料、自行設種子或自行建立暫存目錄
- **How it is checked**：`grep -rn -E "(read_csv|read\.csv|set\.seed|tempdir)\(" tests --include=*.R | grep -v helper-harness | wc -l` 為 0；今日基線為 0（測試目錄尚不存在），採絕對形式

## 7. Decisions

- **D1 誰是權威**：R 產出全部八組分析，SAS 只做對照與視覺化。Rejected: 維持 R 做準備、SAS 做推論的分工 — 兩邊各做一半會使同一數字沒有單一來源，比對失去基準。
- **D2 分析母體**：3,630（已畢業 2,209、已退學 1,421）。Rejected: 4,424 全樣本 — 在讀者的結果未定，把它們算成非畢業會讓畢業率隨收集時點漂移。
- **D3 家境的入口**：以「學費是否繳清」為主，欠債為輔。Rejected: 以欠債為主 — 欠繳兩格的差距為 2.05 個百分點，欠債兩格為 22.55 個百分點，欠繳更貼近「繳不起」。
- **D4 能力母體**：第二學期成績大於零者，2,828。Rejected: 含零分 — 首尾差由 37.48 放大到 77.96 個百分點，把「無成績」讀成「低能力」。
- **D5 追蹤單位**：同一批人，兩期可換組。Rejected: 按名次 — 名次流動描述的是分布，不是同一批人的變化。
- **D6 宏觀三欄的角色**：控制變數。Rejected: 主效應 — 三欄各只有九至十個值，作主效應等於以年份為單位下個人結論。
- **D7 語言文化的處理**：機制保留、結論撤回，只出局限材料。Rejected: 保留結論 — 最大一組 11 人，p = 0.3586，八成檢定力每組需約 165 人。
- **D8 套件政策**：可新增並更新鎖定檔（繪圖、模型整理、比例區間三類）。成本是評分環境需先還原；Rejected: 只用既有 31 個包 — 區間與模型整理需自行實作，實作本身成為新的錯誤來源。
- **D9 呈現精度**：輸出表存未格式化的 double；比率與解釋力在**呈現層**取四位有效數字，計數取整數。Rejected: 表中只存四位 — 會使 1e-9 的兩端容差退化成字串相等（修訂 A-19）。
- **D10 兩端容差**：計數零差；比率相對差 1e-9（對未格式化 double）。對照集為十四格計數與比率，**不含 p 值**（修訂 A-19）。Rejected: 以畫面所見的四位數字比對 — 掩蓋真實差異。
- **D11 圖的產地**：SAS 出圖，R 不出圖。Rejected: 兩端各自出圖 — 課程要求雙工具，重複出圖只增加不一致的面。

## 8. External interface

| Surface | Who uses it | What they see | What they see on error |
| --- | --- | --- | --- |
| 單一入口指令 | 分析者 | 各步驟的完成訊息與耗時 | 拒絕類別、涉及的欄位或格子、下一步 |
| 輸出表 | 評分者、組員 | 英文欄名、母體與 n、四位有效數字 | 缺表時記錄說明拒絕原因 |
| 執行記錄 | 分析者、評分者 | R 版本、套件數、每步耗時、還原清單 | 錯誤原文與被中止的步驟 |
| 差異表 | 分析者 | 逐格通過與否，第一個不符的格子 | 整體判定為不一致 |
| SAS 產生的圖 | 評分者 | 年齡帶退學率、能力分位畢業率 | SAS 端的記錄訊息 |

## 9. Non-goals

- **N1** 報告正文的寫作與十頁取捨 — 屬撰稿決定，正文已完成於 `report.md`，取捨仍未定（S09）。
- **N2** 因果推論 — 資料在同代人身上記錄成績與結果，工具只出關聯量。
- **N3** SAS 端的推論重寫 — 本次 SAS 只做對照與出圖，舊有推論程式不動。
- **N4** 討論期間的 Python 核算 — 那些腳本留在討論目錄，不進專案、不入版本控制。
- **N5** 資料的重新收集或外部資料的併入 — 原始資料固定。

## 10. Open questions and risks

- **Open**：新增的三類套件在 R 4.6.1 上可安裝且與鎖定檔相容 — 以一次安裝並 `renv::snapshot()` 後 `renv::status()` 為真來關閉 — 影響 REQ-A-4。CRAN 於 2026-11-17 可達（回應 200）。
- **Open**：SAS OnDemand 的免費額度與 session 時限是否容得下四個對照程式 — 以一次完整上傳與執行關閉 — 影響 REQ-F-F10-1。
- **Open**：清洗後的舊資料集由哪一個 R 版本產生，未知 — 以 F2 重跑後比對缺值登記關閉 — 影響 REQ-F-F2-1。
- **Risk**：評分環境無網路時無法還原套件 — 影響 F1 — 緩解為把版本環境的套件本體隨專案交付，或在有網路的機器上先還原。
- **Risk**：SAS 與 R 對精確檢定的定義差異（雙尾的計算方式）造成 p 值在容差外 — 影響 REQ-F-F10-1 — 緩解為對照表只比對計數與比率，p 值另列並註明方法。

## 11. Handover

- Defaulted decisions：D10 的容差以相對差 1e-9 起算，於第一次比對後可調整（defaulted — vetoable until work starts）；D11 圖由 SAS 產，沿用專案 README 的既有分工（defaulted）。
- Chosen next skill：`pdd:decompose` — 十一條流程與六條架構規則，屬多行為加架構的變更。
- A later change enters as a new decision, dated, with the id it supersedes.
