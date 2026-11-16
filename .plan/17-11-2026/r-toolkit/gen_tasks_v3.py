#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""第三版生成器：併入第二輪稽核修訂（A-10 至 A-17）與六項實算釘值。"""
import os, io

PLAN = os.path.dirname(os.path.abspath(__file__))
TASKS_DIR = os.path.join(PLAN, "tasks")
os.makedirs(TASKS_DIR, exist_ok=True)
SEED = "20261117"

def header(t):
    deps = "、".join(t["deps"]) if t["deps"] else "—"
    return f"""# {t['id']} — {t['title']}

| Field | Value |
| --- | --- |
| Task | `{t['id']}` |
| Class | `{t['cls']}` |
| Requirement | {t['req']} |
| Depends on | {deps} |
| {'Seam' if t['cls'] != 'verification' else 'Flow'} | {t.get('seam') or t.get('flow')} |
| Owned files | {t['owned']} |
| Plan | `.plan/17-11-2026/r-toolkit/` |
| PRD | [`../PRD.md`](../PRD.md) |
| DAG | [`../TASKS.md`](../TASKS.md) |
| Status | work contract |

**Self-sufficiency**: 只讀本檔與 PRD 相關章節即可開工。DAG 與追溯在 `../TASKS.md`；兩者不一致時以本檔所引的 PRD 條文為準，並回報主代理裁決。

**Boundaries**: 只寫 `Owned files` 列出的檔案。不改 `../PRD.md`、`../TASKS.md`、同批其他任務的檔案。發現矛盾即停手回報。

**Class boundaries**: construction 不寫檢查、模型或基線；verification 不改生產檔案，一切注入只在暫存副本上做。

**Path base**: 以下路徑相對專案根目錄。

---
"""

def body(t):
    out = []
    if t["cls"] == "construction":
        out += ["## Construction\n", f"- **Purpose**: {t['purpose']}",
                f"- **Seam**: `{t['seam']}` — 本任務建立的入口",
                f"- **Flow it feeds**: {t['flow']}", "- **Files owned**:"]
        out += [f"  - `{f[0]}` — {f[1]}" for f in t["files"]]
        out.append("- **Steps**:")
        out += [f"  {i}. {s}" for i, s in enumerate(t["steps"], 1)]
        out += [f"- **Refusal**: {t['refusal']}", f"- **Boundaries**: {t['boundaries']}",
                f"- **Untouched**: {t['untouched']}"]
    else:
        out += ["## Verification\n", f"- **Flow**: {t['flow']}", f"- **Covers**: {t['covers']}",
                f"- **Shape**: {t['shape']}", "- **Files owned**:"]
        out += [f"  - `{f[0]}` — {f[1]}" for f in t["files"]]
        if t.get("rules"):
            out.append("- **Rule（逐字抄自 PRD §6.2）**:")
            out += [f"  - {r}" for r in t["rules"]]
        out.append("- **Steps**:")
        out += [f"  {i}. {s}" for i, s in enumerate(t["steps"], 1)]
        if t.get("properties"):
            out.append("- **Properties（每條可證偽，含拒絕分支與負向控制）**:")
            out += [f"  - {p}" for p in t["properties"]]
        out.append(f"- **Budget**: {t['budget']}")
    out.append("""
---

## Report format

完成後回報四項，缺一即視為未完成：

1. **Result** — construction：呼叫者現在看到什麼；verification A：走到哪些分支、用了多少預算、抓到什麼（trace、seed、最短序列）與**負向控制**的紅燈輸出；C：變更前後的通過與否、違規清單、門檻值與實測值（含掃描檔數）。
2. **實際建立或修改的檔案**，逐項對照 `Owned files`。
3. **偏離本檔之處與原因**；沒有則寫 `none`。
4. **在 owned files 內無法交付的部分**與其所需決定；verification 另附發現的生產缺陷與其 seam。
""")
    return "\n".join(out)

def render(t):
    return header(t) + "\n" + body(t) + "\n"

C = [
 dict(id="T01", cls="construction", title="環境還原與共用常數",
   req="`REQ-F-F1-1`、`REQ-A-2`、`REQ-A-4`（三者皆由本任務交付，`V12`／`V13` 判定）", deps=[],
   seam="programs/R/00_setup.R",
   owned="`.Rprofile`、`programs/R/00_setup.R`、`renv/activate.R`、`renv.lock`、`output/logs/00_setup.log`",
   files=[(".Rprofile", "改為有守衛的啟動：`renv/activate.R` 存在則 source，否則呼叫 `renv::restore()` 產生它"),
          ("programs/R/00_setup.R", "路徑根、母體界線、年齡切點、分位數、容差、呈現常數、套件檢查"),
          ("renv/activate.R", "由 renv 產生的啟動腳本"),
          ("renv.lock", "新增 testthat、PropCIs、broom 後的快照；本專案唯一寫者"),
          ("output/logs/00_setup.log", "R 版本、套件數、還原耗時、降級與補件清單")],
   purpose="在專案根目錄執行一行指令，環境即還原至可執行，並在 `00_setup.log` 留下一段含 R 版本、套件數與耗時的自檢記錄",
   flow="F1（環境還原）",
   steps=["把 `.Rprofile` 改為有守衛的形式：`renv/activate.R` 缺席**或** `renv/library` 為空時呼叫 `renv::restore()`。renv 的 activate 腳本本身不含還原呼叫（實測 `renv::load()` 對空 library 只警告），故守衛須自行判斷 library 狀態",
          "新增三類套件並在報告列出呼叫點：`testthat`（T14 與 V01–V11）、`PropCIs`（T03 的威爾遜區間）、`broom`（T07 的模型整理）。`ggplot2` 不進鎖定檔（D11 圖由 SAS 產）",
          "在 `00_setup.R` 匯出下列十三項具名常數，並逐一註明用途：`PROJ_ROOT`、`OUT_ROOT`（輸出基底，預設 `file.path(PROJ_ROOT, \"output\")`，可由環境變數 `RTOOLKIT_OUT_ROOT` 覆寫；表在 `file.path(OUT_ROOT, \"tables\")`、記錄在 `file.path(OUT_ROOT, \"logs\")`）、`ANALYSIS_N`（3,630）、`ABILITY_N`（2,828）、`PROP_CI_LEVEL`（0.95）、`ANALYSIS_RESULTS`（已畢業與已退學兩個類別值）、`ABILITY_MIN_SCORE`（能力母體門檻）、`AGE_BREAKS`（20／25／30／40）、`AGE_BREAKS_MODEL`（<25 合併的四帶，供 T07 重現 0.0756）、`N_QUARTILES`、`PARITY_TOL`、`SIG_DIGITS`、`MISSING_PROFILE`（整數純量，預設 `0L`；量法為清洗後 NA 儲存格的總數，不含「未登記修讀」的列；T02 的拒絕門檻）、`RETIRED_ANALYSIS_N`（已退役分母 4,424，註明等於分析母體加在讀人數）",
          "加入同步檢查：版本環境與鎖定檔不同步、或程式引用未登記的套件時停止並列出",
          "以具名指令自檢並寫入記錄：`Rscript -e 'source(\"programs/R/00_setup.R\"); c(ANALYSIS_N, ABILITY_N)'`、`Rscript -e 'renv::status()$synchronized'`",
          "確認路徑一律由 `PROJ_ROOT` 導出；在子目錄執行時只保證路徑正確"],
   refusal="`refuse:unpinned-package` — 列出不同步或未登記的套件，程式停止且不產生任何表",
   boundaries="**缺版本環境**的定義為「`renv/library` 不存在、為空或缺件」；`activate.R` 隨專案保存，其存在與否不構成缺環境。環境已存在時重跑為無操作；鎖定檔較新時只補差額；已安裝較新時以鎖定檔為準並記降級清單",
   untouched="`data/raw/` 與 `data/processed/` 不動；`00_setup.R` 不引用 `lib/` 的任何符號"),
 dict(id="T02", cls="construction", title="分析母體與清洗資料集",
   req="`REQ-F-F2-1`、`REQ-F-F2-2`、`REQ-F-F2-3`", deps=["T01"],
   seam="programs/R/01_prep_data.R",
   owned="`programs/R/01_prep_data.R`、`data/processed/ams2640_clean.csv`、`data/processed/ams2640.sas7bdat`、`data/processed/ams2640.xpt`、`output/tables/population_ledger.csv`、`output/logs/01_prep.log`",
   files=[("programs/R/01_prep_data.R", "讀原始資料、清洗、寫三種格式、寫母體清冊"),
          ("data/processed/ams2640_clean.csv", "清洗後文字格式"),
          ("data/processed/ams2640.sas7bdat", "SAS 可讀格式（factor 先轉字元）"),
          ("data/processed/ams2640.xpt", "SAS 備援格式"),
          ("output/tables/population_ledger.csv", "長格式 `population, metric, n, value`；每列自帶母體與 n"),
          ("output/logs/01_prep.log", "缺值登記、新舊檔案時間、拒絕理由與下一步")],
   purpose="一條指令產出清洗資料集與母體清冊，清冊逐列帶母體、指標、n 與值，並在記錄留下新舊時間",
   flow="F2（建立分析母體）",
   steps=["讀原始資料，處理分號、BOM 與欄名內的定位字元",
          "檢查欄數為 37 且結果欄只含三個既知類別，否則拒絕並回報差異",
          "定義能力母體為**分析母體與第二學期成績大於零的交集**；全樣本上滿足該條件者 3,554 人，交集後 2,828 人，差額 726 人全為在讀者",
          "寫清冊。`population` 欄取三個具名值之一：`full`、`analysis`、`ability`。九列固定為：(`full`, `total`, n=4,424, 4,424)、(`full`, `graduate`, 4,424, 2,209)、(`full`, `dropout`, 4,424, 1,421)、(`full`, `enrolled`, 4,424, 794)、(`analysis`, `analysis`, 3,630, 3,630)、(`analysis`, `no_registration_rows`, 3,630, 180)、(`analysis`, `zero_score_sem2`, 3,630, 802)、(`analysis`, `zero_score_sem2_dropout`, 3,630, 727)、(`ability`, `ability`, 2,828, 2,828)。`n` 欄為該列母體總數，`value` 為該指標的值",
          "寫三種資料格式。SAS 格式有三項硬限制：欄名須 ≤ 32 字元且僅 `[A-Za-z0-9_]`（原欄名含空格、括號、斜線且 10 個超長，實測兩種格式皆寫不出），故先做欄名正規化並把 `原名 → 新名` 對應逐項寫入 `01_prep.log`；factor 先轉字元；結果欄改名為 `target`。記錄另記新舊檔案的修改時間",
          "在寫入前確認目標路徑不在原始資料目錄內"],
   refusal="`refuse:input-schema`（欄數或類別不符）、`refuse:missing-profile`（缺值總數超出 `00_setup.R` 的 `MISSING_PROFILE`）、`refuse:readonly-target`（目標落在原始資料目錄）",
   boundaries="在讀的 794 人留在清洗資料集但不進分析母體；180 列為兩學期 `enrolled` 皆 0（未登記修讀），與第二學期成績為 0 的 802 人分列登記；半途失敗以原子替換避免半份資料集",
   untouched="`data/raw/data.csv` 只讀；其 sha256 3ef126de5cefff26eb11fbb4237f1a1401cb64b488e2f1d598c23cedeb4c45ae 執行前後必須相同"),
 dict(id="T03", cls="construction", title="共用統計量",
   req="支撐 `REQ-F-F3-1` 至 `REQ-F-F9-1`；並受 `REQ-A-2` 約束（不得自定義常數），接受由 `V12` 判定", deps=["T01"],
   seam="programs/R/lib/stats.R",
   owned="`programs/R/lib/stats.R`",
   files=[("programs/R/lib/stats.R", "六個具名函式：`prop_ci`、`fisher_2x2`、`phi_2x2`、`mcfadden_r2`、`auc_rank`、`fmt_sig`")],
   purpose="source 之後六個具名函式可用；`prop_ci(0,0)` 回 `refuse:empty-denominator`、`phi_2x2` 對單一類別回 `refuse:single-class`、`mcfadden_r2(0,0)` 回 `refuse:single-class`（完全分離不在本函式判定，見修訂 A-29）",
   flow="支撐 F3 至 F9 的計算",
   steps=["檔首以 `source(file.path(here::here(\"programs/R/00_setup.R\")))` 取得常數。不得引用尚未定義的符號（`PROJ_ROOT` 正是 00_setup 的產物），不得在檔內寫死位數或母體；重複 source 00_setup 須為幂等",
          "`prop_ci(k, n, level = PROP_CI_LEVEL)`：威爾遜區間，以 `PropCIs` 為底；零分母回具名類別。信賴水準只自 `PROP_CI_LEVEL` 取，不在函式內寫死",
          "`fisher_2x2(a, b, c, d)`：雙尾，回 odds ratio 與 p",
          "`phi_2x2(a, b, c, d)`：單一類別回 `refuse:single-class`",
          "`mcfadden_r2(ll_model, ll_null)`：`ll_null` 為 0（單一結果類別）時回 `refuse:single-class`；完全分離不在本函式判定（分離是配適的性質，兩個對數似然不足以判定），改由 T07 在配適失敗時以 `refuse:empty-denominator` 記錄；`auc_rank(score, y)`：秩式 AUC，同分以平均秩",
          "`fmt_sig(x, digits = SIG_DIGITS)`：計數一律整數；四位有效數字只在呈現層",
          "自檢三段各一行：`prop_ci(0,0)` 回 `refuse:empty-denominator`、`phi_2x2(10,10,0,0)` 回 `refuse:single-class`（合法 2×2 如 `phi_2x2(10,0,0,10)` 回數值 1）、`mcfadden_r2(0,0)` 回 `refuse:single-class`"],
   refusal="`refuse:empty-denominator`、`refuse:single-class` — 回傳具名類別，呼叫端據此停止並記錄",
   boundaries="零分母與單一類別各回一個具名結果；本檔不讀任何資料、不印任何表",
   untouched="`00_setup.R` 的常數不動；本檔不 `source` 任何編號腳本"),
 dict(id="T04", cls="construction", title="財富層的四格與關聯強度",
   req="`REQ-F-F3-1`（分母與 share 的定義以修訂 A-10 為準）", deps=["T02", "T03"],
   seam="programs/R/02_wealth.R",
   owned="`programs/R/02_wealth.R`、`output/tables/wealth_four_cell.csv`、`output/logs/02_wealth.log`",
   files=[("programs/R/02_wealth.R", "四格計數、各格退學率、各格 share、phi"),
          ("output/tables/wealth_four_cell.csv", "`population`、`cell`、`n`、`dropout_rate`、`share`、`phi`"),
          ("output/logs/02_wealth.log", "執行記錄與母體")],
   purpose="一張四格表，每格自帶人數、該格退學率與 share，並附 phi",
   flow="F3（財富層）",
   steps=["編碼定為 `tuition_unpaid = (學費是否繳清 == 0)`、`debtor = (是否欠債 == 1)`；未指定此編碼時 phi 的符號不定",
          "四格以固定列序輸出：兩者俱有、僅欠繳、僅欠債、皆無。此序與 report 展示的 95.13／93.08／51.87／29.32 一一對應（95.13 屬兩者俱有 226 人，不是僅欠繳的 260 人）",
          "以**該格人數**為分母計算 `dropout_rate`；另以分析母體為分母計算 `share`（四格 share 相加為 1，容差 1e-4，因四位有效數字呈現）",
          "以同一 2×2（欠繳=1、欠債=1）計算 phi",
          "寫表：`population` 欄逐列填 `analysis`，`n` 欄為該格人數；不另寫首列註記"],
   refusal="`refuse:empty-denominator` — 任一格為空時寫明空格位置並停止，且不覆寫既有表",
   boundaries="四格 n 合計等於分析母體；share 四格合計為 1（容差 1e-4）；以欠債作入口的版本只在記錄留一行對照，不入表",
   untouched="不寫其他分析的檔案；不改 `lib/`；不寫入母體人數的字面量（母體自 `00_setup.R` 與 `population_ledger.csv` 取）"),
 dict(id="T05", cls="construction", title="年齡帶與婚配分層",
   req="`REQ-F-F4-1`、`REQ-F-F4-2`、`REQ-F-F4-3`（拒絕語義以修訂 A-11 為準）", deps=["T02", "T03"],
   seam="programs/R/03_age.R",
   owned="`programs/R/03_age.R`、`output/tables/age_bands.csv`、`output/tables/age_tests.csv`、`output/tables/marriage_strata.csv`、`output/logs/03_age.log`",
   files=[("programs/R/03_age.R", "五帶切分、兩帶檢定、婚配分層"),
          ("output/tables/age_bands.csv", "`population`、`band`、`n`、`share`、`dropout_rate`、`unpaid_rate`"),
          ("output/tables/age_tests.csv", "`population`、`test`、`group_a`、`n_a`、`group_b`、`n_b`、`odds_ratio`、`p_value`、`tail`、`status`"),
          ("output/tables/marriage_strata.csv", "`population`、`band`、`married_n`、`married_rate`、`single_n`、`single_rate`、`n`、`p_value`、`status`"),
          ("output/logs/03_age.log", "執行記錄與婚配映射")],
   purpose="三張表同時給出五帶概況、兩個關鍵檢定、以及逐帶的婚配分層，且小帶的處理逐列可讀",
   flow="F4（社會背景：年齡與婚配）",
   steps=["帶的定義為**左閉右開** `[a, b)`：`<20`、`20–24`、`25–29`、`30–39`、`40+`（最後一帶為 `[40, ∞)`），切點取自 `AGE_BREAKS`；不得使用 `cut()` 的預設右閉（右閉會得 2080／646／326／379／199，與釘值不符）",
          "計算各帶人數、share、退學率、欠繳率",
          "對 25–29 與 40+ 兩帶的退學率與欠繳率各做一次雙尾精確檢定",
          "婚配映射定為 **已婚 = marital_status 2；單身 = 其餘（1、3、4、5、6）**，並寫入記錄。此映射是釘值 0.0245／0.1301 得以重現的唯一讀法；若改用「單身 = 1」該兩值為 0.0024／0.0571",
          "逐帶依序判定，三分支互斥：① 帶內已婚或單身人數為零 → `refuse:empty-denominator`，整支停止且三張表皆不產生；② 任一格人數 < 30 → 入表，`p_value` 留空、`status` 填 `insufficient_n`；③ 其餘各做一次雙尾精確檢定"],
   refusal="`refuse:empty-denominator` — 僅在帶內已婚或單身人數為零時觸發，整支停止；小帶（任一格 < 30）不拒絕，入表並標 `insufficient_n`",
   boundaries="`40+` 含 40；檢定一律雙尾；三分支的優先序為零格 → 小帶 → 檢定；每張表逐列帶 `population`",
   untouched="不把婚姻狀況寫成機制；不把宏觀三欄升為主效應；不寫入年齡帶或母體的字面量"),
 dict(id="T06", cls="construction", title="能力分位與兩期追蹤",
   req="`REQ-F-F5-1`、`REQ-F-F5-2`", deps=["T02", "T03"],
   seam="programs/R/04_ability.R",
   owned="`programs/R/04_ability.R`、`output/tables/ability_quartiles.csv`、`output/tables/ability_transitions.csv`、`output/logs/04_ability.log`",
   files=[("programs/R/04_ability.R", "剔除零成績、等量切四組、計算畢業率、兩期移動表"),
          ("output/tables/ability_quartiles.csv", "`population`、`quartile`、`n`、`graduation_rate`"),
          ("output/tables/ability_transitions.csv", "寬表：`population`、`from_sem1`（取值 `q1`–`q4` 與 `missing_sem1`）、`to_q1`、`to_q2`、`to_q3`、`to_q4`、`n`；共 5 列"),
          ("output/logs/04_ability.log", "執行記錄、切分方法、被剔除人數")],
   purpose="一張分位表與一張 5×4 移動表，四組各 707 人，且移動表列合計回到能力母體",
   flow="F5（能力）",
   steps=["自清洗資料集取能力母體（分析母體 ∩ 第二學期成績 > 0）",
          "**等量切四組**：以第二學期成績排序（`order(..., method=\"radix\")`，同分依清洗資料集原始列序），取 `floor(n/4)` 為組寬、末組收餘。等量切法得 707／707／707／707；分位數切點法得 707／739／680／702，與釘值不符，故不得使用 `quantile()` 切點",
          "計算各組畢業率並寫入 `quartile`、`n`、`graduation_rate`",
          "建移動表：第一學期以同一等量切法在**有第一學期成績的 2,802 人**上切四組（700／700／700／702，同分依原始列序），不得用 `quantile()` 切點；缺第一學期成績者 26 人單列 `missing_sem1`。欄為第二學期的四組",
          "寫表並在兩張表都帶 `population` 欄；記錄切分方法與被剔除人數"],
   refusal="`refuse:empty-denominator` — 剔除後母體為零時停止且不覆寫既有表",
   boundaries="入學前成績另計；第二學期成績為零者不入本表（他們本在能力母體之外）；5×4 的列合計等於能力母體",
   untouched="不改母體定義；不引入名次式追蹤；檔內不得出現母體數字字面量"),
 dict(id="T07", cls="construction", title="三層解釋力比較",
   req="`REQ-F-F6-1`、`REQ-F-F6-2`", deps=["T02", "T03", "T06"],
   seam="programs/R/05_models.R",
   owned="`programs/R/05_models.R`、`output/tables/model_comparison.csv`、`output/logs/05_models.log`",
   files=[("programs/R/05_models.R", "五個模型規格、六列配適"),
          ("output/tables/model_comparison.csv", "`model`、`population`、`n`、`mcfadden_r2`、`auc`、`mechanism`、`falsifier`、`status`"),
          ("output/logs/05_models.log", "收斂狀態、三欄欄名、年齡帶參數化")],
   purpose="一張六列表，每列一個（模型規格 × 母體）配對，帶解釋力、曲線下面積、機制句與否證條件",
   flow="F6（解釋力比較）",
   steps=["財務三欄定為 `tuition_unpaid`、`debtor`、`no_scholarship`（欄名以清洗資料集為準，寫入記錄）",
          "年齡帶模型使用 `AGE_BREAKS_MODEL`（四帶：<25、25–29、30–39、40+）。五帶切法得 0.0839，四帶才得 0.0756，兩者不可混用",
          "配適六列：①年齡帶＠3,630 ②財務三欄＠3,630 ③財務三欄＠2,828 ④能力分位＠2,828 ⑤財務加能力＠2,828 ⑥入學成績分位＠2,828。入學成績分位以 `Admission grade` 等量切四組、在 2,828 上排名",
          "能力分位模型直接讀 `ability_quartiles.csv` 的分組（即 T06 的等量切法），不在本檔重切；解釋力用 `mcfadden_r2`、AUC 用 `auc_rank`（正類為 Dropout、分數為 `predict(type = \"response\")`、同分平均秩）；模型整理以 `broom` 輸出",
          "每列填 `population` 與 `n`，並附機制句與否證條件；同母體的列連續排列。**若任一列算出的解釋力與報告所載數字在四位有效數字上不同，該列 `status` 填 `mismatch` 並停止交付**，由主代理裁決是改模型規格還是改報告數字——不得自行改寫報告",
          "記錄每個模型的收斂狀態；不收斂者該列 `status` 填 `refuse:empty-denominator`（廣義）"],
   refusal="`refuse:empty-denominator`（廣義：樣本不足以配適）— 該列 `status` 寫入類別並在記錄寫明模型名，其餘列照出",
   boundaries="不同母體的分數不以單一序列排序；能力的解釋力註明量度為同期成績；入學成績分位註明為入學前成績",
   untouched="不改分位與母體定義；不做因果推論；不自行實作 AUC"),
 dict(id="T08", cls="construction", title="語言文化的小樣本材料",
   req="`REQ-F-F7-1`", deps=["T02", "T03"],
   seam="programs/R/06_language.R",
   owned="`programs/R/06_language.R`、`output/tables/language_groups.csv`、`output/logs/06_language.log`",
   files=[("programs/R/06_language.R", "國籍→語言圈對應、分組計數、區間、檢定、檢定力"),
          ("output/tables/language_groups.csv", "`population`、`group`、`n_members`（含在讀）、`n`（退學率分母）、`dropout_rate`、`ci_low`、`ci_high`、`p_vs_local`、`required_per_group`；`population` 逐列填 `full`，本地僅作對照不佔列"),
          ("output/logs/06_language.log", "逐值國籍對應與三圈人數")],
   purpose="一張表給出各語言圈的人數、可比較人數、退學率、區間與所需樣本量，供局限一節引用",
   flow="F7（語言文化）",
   steps=["取非本地國籍者，保留本地作對照",
          "國籍代碼→語言圈對應（依 UCI data dictionary 的國名）寫定並逐值記入 log：葡語＝21 安哥拉、22 佛得角、24 幾內亞比紹、25 莫桑比克、26 聖多美、41 巴西；西語＝6 西班牙、101 墨西哥、108 古巴、109 哥倫比亞；其餘歸其他。三圈人數為 74／17／19",
          "各圈算 `n_members`（含在讀）、`n`（僅畢業與退學）、`dropout_rate`；`n < 10` 者只出計數",
          "對**西語圈**與本地做雙尾精確檢定（不是「最大一組」：最大組是葡語圈，與本地同語不作跨語比較）",
          "`required_per_group` 以 α = 0.05 雙尾、power = 0.8 與觀察到的差距計算",
          "寫表並在記錄寫明可比較總數（86）與三圈人數"],
   refusal="`refuse:empty-denominator` — 某圈 `n` 為零時該圈列 n=0 並在記錄寫明，不中止；`n < 10` 者入表、`dropout_rate` 與區間留空",
   boundaries="葡語圈與本地同語，`p_vs_local` 留空；在讀者計入 `n_members` 但不入 `n`；對齊點為西語圈 `n_members` 17、`n` 11、退學率 54.55%、p 0.3586、每組約 165 人",
   untouched="不寫結論句；只產局限材料（結論已撤回）"),
 dict(id="T09", cls="construction", title="宏觀三欄的值域與角色",
   req="`REQ-F-F8-1`", deps=["T02", "T03"],
   seam="programs/R/07_macro.R",
   owned="`programs/R/07_macro.R`、`output/tables/macro_values.csv`、`output/logs/07_macro.log`",
   files=[("programs/R/07_macro.R", "年度區塊、逐值計數、角色標記"),
          ("output/tables/macro_values.csv", "`population`、`variable`、`value`、`year`、`year_inferred`、`n`、`role`"),
          ("output/logs/07_macro.log", "十個年度三元組與其人數")],
   purpose="一張逐值表，每列帶母體、值、年份、人數與角色；表長 30 列（三欄 × 十個年度）",
   flow="F8（宏觀環境）",
   steps=["以 (`Unemployment rate`, `Inflation rate`, `GDP`) 三元組建立年度區塊。資料無年份欄，**列序不含年份資訊**（相鄰列的宏觀值隨機交替），故不得以列序推定；十個三元組各對應一個年度，`year` 依 `year_inferred = TRUE` 標記",
          "逐 (variable, year) 計數；`Inflation rate` 的值 1.4 出現在兩個年度，故其列數為 10 而非 9，全表為 30 列",
          "檢查：不同值數量為 Unemployment 10、Inflation 9、GDP 10，寫入記錄；某欄不同值多於人數的十分之一時拒絕",
          "`role` 欄一律填 `control`；`population` 欄一律填 `analysis`",
          "寫表與記錄，記錄含十個三元組及其 n"],
   refusal="`refuse:input-schema` — 某欄不同值多於人數的十分之一時停止且不覆寫表",
   boundaries="同一數值可跨年（inflation 1.4）；每列帶 n，n 合計等於分析母體",
   untouched="不改清洗資料；不作主效應估計"),
 dict(id="T10", cls="construction", title="相關審核表",
   req="`REQ-F-F9-1`", deps=["T02", "T03"],
   seam="programs/R/08_audit.R",
   owned="`programs/R/08_audit.R`、`output/tables/correlation_audit.csv`、`output/tables/correlation_audit.txt`、`output/logs/08_audit.log`",
   files=[("programs/R/08_audit.R", "逐欄效果量、BH 校正、判詞、in_model 標記"),
          ("output/tables/correlation_audit.csv", "`population`、`variable`、`effect`、`p_raw`、`p_bh`、`keep`、`verdict`、`in_model`、`n`"),
          ("output/tables/correlation_audit.txt", "同內容可讀版"),
          ("output/logs/08_audit.log", "門檻值、分母來源、舊版分母的來歷")],
   purpose="一張審核表在分析母體上重算，逐列帶判詞、校正後 p 與 `in_model`，並記錄舊版分母的來歷",
   flow="F9（相關審核）",
   steps=["取分析母體；n 自 `00_setup.R` 常數與清冊取，檔內不寫字面量",
          "逐欄計算效果量：連續欄用相關係數，類別欄用變異數分析式效果量",
          "以 BH 法校正；門檻寫在檔內常數並印入記錄：`EFFECT_MIN = 0.30`、`P_BH_MAX = 0.05`、`EFFECT_NOISE = 0.10`",
          "判詞四類：`definitional`（與結果同代的 `pass1`／`pass2`／`avg_grade`）、`substantive`（效果量 ≥ 0.30 且 `p_bh` < 0.05）、`noise`（效果量 < 0.10）、`ecological`（以年份為單位的三欄）",
          "`keep` 為 `definitional` 或 `substantive`；`in_model` 僅對 `substantive` 且非同代欄為 TRUE",
          "記錄寫明舊版分母為 `RETIRED_ANALYSIS_N`（4,424，等於分析母體加在讀），磁碟上無舊表可覆蓋"],
   refusal="`refuse:input-schema` — 分母與母體清冊不符時拒絕發佈",
   boundaries="與結果同代的欄標 `definitional` 且 `in_model = FALSE`；以年份為單位的欄標 `ecological`；每列帶 population 與 n",
   untouched="不動清洗資料；不改 `lib/`；不寫入母體數字字面量"),
 dict(id="T11", cls="construction", title="SAS 端對照程式",
   req="`REQ-F-F10-1`（前半）", deps=["T02", "T04", "T05", "T06"],
   seam="programs/SAS/05_parity.sas",
   owned="`programs/SAS/05_parity.sas`、`programs/SAS/README_parity.md`、`output/parity/cell_map.csv`、`output/parity/sas_parity.csv`、`output/parity/age_band_dropout.pdf`、`output/parity/ability_quartile_graduation.pdf`",
   files=[("programs/SAS/05_parity.sas", "重算十四格並出兩張圖"),
          ("programs/SAS/README_parity.md", "上傳清單、執行順序、十四個 cell_id 的說明"),
          ("output/parity/cell_map.csv", "`cell_id, table, column, row_key, value_type`，十四列，機器可讀；`row_key` 為 R 表該列的鍵值（如 `w_both`、`a_25_29`、`q3`）"),
          ("output/parity/sas_parity.csv", "`cell_id, indicator, group, value, n, value_type`，十四列"),
          ("output/parity/age_band_dropout.pdf", "年齡帶退學率圖"),
          ("output/parity/ability_quartile_graduation.pdf", "能力分位畢業率圖")],
   purpose="SAS Studio 跑一次即在 `output/parity/` 產出十四列對照值、一份機器可讀的 cell_map 與兩張圖",
   flow="F10（兩端對照）的前半",
   steps=["載入清洗資料集（備援 xpt 與 csv）",
          "十四格逐列寫定：`pop_analysis`（分析母體人數）；`w_only_unpaid`、`w_only_debt`、`w_both`、`w_neither`（四格退學率，格名與 T04 一致）；`a_lt20`、`a_20_24`、`a_25_29`、`a_30_39`、`a_40plus`（五帶退學率，標籤與 T05 一致）；`q1`、`q2`、`q3`、`q4`（四組畢業率，標籤與 T06 一致）",
          "值以 `best32.` 匯出（未套用顯示格式，至少 15 位有效數字；SAS 對未格式化數值預設只給 BEST12，故須明確指定）；`value_type` 為 `count` 或 `rate`",
          "分組規則寫進 README 並在程式內以註解標明：能力分位採**等量切分**（第二學期成績升冪、同分依原始列序、組寬 `floor(n/4)`、末組收餘，與 T06 同；不可用 PCTLDEF 預設分位數切點）；母體界線為 `Target in (Graduate, Dropout)`；四格以原欄定義 `tuition_unpaid = (Tuition fees up to date = 0)`、`debtor = (Debtor = 1)`，列序為兩者俱有、僅欠繳、僅欠債、皆無",
          "出兩張圖至 `output/parity/`",
          "同步寫出 `cell_map.csv`，欄位指向 R 端表名與欄名"],
   refusal="`refuse:input-schema` — 資料集載入失敗時停止，印出嘗試過的每個路徑與 SAS 端錯誤原文",
   boundaries="SAS 只讀清洗資料集；匯出值不套顯示精度；對照值目錄與 `output/tables/` 分離；p 值不進對照集（十四格全為計數與比率）",
   untouched="既有 01–04 號 SAS 程式不動；不改 R 端任何表"),
 dict(id="T12", cls="construction", title="兩端差異表",
   req="`REQ-F-F10-1`（後半）、`REQ-F-F10-2`；`REQ-A-6`（檢查式以修訂 A-13 為準）",
   deps=["T02", "T04", "T05", "T06", "T11"],
   seam="programs/R/90_parity.R",
   owned="`programs/R/90_parity.R`、`output/tables/parity_diff.csv`、`output/logs/90_parity.log`",
   files=[("programs/R/90_parity.R", "讀 cell_map、母體清冊與 R 表，逐格比對；含路徑清單常數"),
          ("output/tables/parity_diff.csv", "`cell_id, indicator, group, r_value, sas_value, n, value_type, diff, tolerance, pass`"),
          ("output/logs/90_parity.log", "整體判定、第一個不符的 cell_id、讀寫路徑清單")],
   purpose="一張差異表逐格標明兩端是否一致，並在任一格超出容差時以 `refuse:parity` 結束",
   flow="F10（兩端對照）的後半",
   steps=["在檔首以兩個具名常數落路徑清單：`PARITY_READ_PATHS`（`output/parity/cell_map.csv`、`output/parity/sas_parity.csv`、`output/tables/population_ledger.csv`、`output/tables/wealth_four_cell.csv`、`output/tables/age_bands.csv`、`output/tables/ability_quartiles.csv`）與 `PARITY_WRITE_PATHS`（`output/tables/parity_diff.csv`、`output/logs/90_parity.log`）。兩者交集須為空（`REQ-A-6`）",
          "讀母體清冊的選取器固定為 (population = `analysis`, metric = `analysis`)，取 `value` 欄；十四個 cell_id 由 `cell_map.csv` 對應到 R 表與欄",
          "核對 `sas_parity.csv` 的 cell_id 集合**等於** `cell_map.csv` 的十四個（無重複、無未知），否則以 `refuse:input-schema` 停止",
          "逐格比對：`count` 要求零差；`rate` 以 `diff = abs(r_value - sas_value) / abs(r_value)` 計算，`pass = diff <= PARITY_TOL`（1e-9，對未格式化 double）",
          "以 `cell_map.csv` 的列序為固定鍵序寫表（不依 locale 字串排序），使「第一個不符」有唯一定義",
          "結束碼：全格通過 → `quit(status = 0)`；存在不符 → 寫 log 後 `quit(status = 3)`；對照值或缺檔 → `quit(status = 1)`"],
   refusal="`refuse:parity`（結束碼 3，不中止交付鏈）、`refuse:input-schema`（cell_id 集合不符，結束碼 1）",
   boundaries="容差為計數零差、比率相對差 1e-9；本任務不寫 R 端其他表；結束碼 3 代表「已判定為不一致但流程可繼續」",
   untouched="不覆寫 R 端的分析表；不改 SAS 匯出檔"),
 dict(id="T13", cls="construction", title="單一入口與數字對照表",
   req="`REQ-F-F11-1`、`REQ-F-F11-2`", deps=["T04","T05","T06","T07","T08","T09","T10","T11","T12"],
   seam="programs/R/run_all.R",
   owned="`programs/R/run_all.R`、`output/tables/number_map_spec.csv`、`output/tables/number_map.csv`、`output/logs/run_all.log`",
   files=[("programs/R/run_all.R", "以子程序逐支呼叫各步驟、結尾檢查與產出對照表"),
          ("output/tables/number_map_spec.csv", "`number_key, value, source_table, source_row`；28 列，抄自報告"),
          ("output/tables/number_map.csv", "`number_key, spec_value, table_value, source_table, source_row, population, n, pass`"),
          ("output/logs/run_all.log", "每步耗時、套件版本、執行時間、parity 判定")],
   purpose="一條指令跑完全部步驟並產出 28 列的數字對照表，且每列帶母體與 n",
   flow="F11（交付）",
   steps=["以子程序逐支執行，清單固定為九支且依序：`01_prep_data.R`、`02_wealth.R`、`03_age.R`、`04_ability.R`、`05_models.R`、`06_language.R`、`07_macro.R`、`08_audit.R`、`90_parity.R`（不含 `00_setup.R` 與 `run_all.R` 自身）。以 `system2(file.path(R.home(\"bin\"), \"Rscript\"), c(\"programs/R/<name>\"))` 呼叫，逐一檢查結束碼。**不得以 `source()` 呼叫**：`REQ-A-3` 的檢查式會把它計為橫向引用",
          "結束碼 3（`refuse:parity`）記入 log 後繼續；其餘非零即停止並指出步驟",
          "結尾依檔案與欄位對照逐表檢查母體與 n（`age_tests` 取 `population`、`n_a`、`n_b`；`marriage_strata` 取 `population`、`n`；`ability_transitions` 取 `population`、`n`），其餘九張：`wealth_four_cell`、`age_bands`、`age_tests`、`marriage_strata`、`ability_quartiles`、`ability_transitions`、`model_comparison`、`language_groups`、`macro_values`、`correlation_audit`。對照表與數字對照表本身不在此列",
          "`number_map_spec.csv` 逐列抄自報告的 28 個數字，於首次執行前寫定並置唯讀；路徑一律自 `PROJ_ROOT` 解析（不隨輸出根變動），不得由 `output/tables/` 回填。列數不等於 28 或缺任一 key 時以 `refuse:incomplete-spec` 停止。本檔為輸入，不列入「兩次執行皆產出」的檔案清單",
          "逐列比對 spec 與表中值，產出 `number_map.csv`",
          "記錄寫明 R 版本、套件版本、執行時間"],
   refusal="`refuse:missing-profile`（分析表缺母體或 n，且不產出 number_map.csv）、`refuse:incomplete-spec`（spec 列數不符）",
   boundaries="重跑兩次得相同的表；記錄附時間戳，表本身不附；`refuse:parity` 不中止交付流程；本入口讀 `output/tables` 的既有表屬預期行為（PRD §5 已列例外）",
   untouched="不改任何分析腳本；不重寫 `lib/`；不刪除既有輸出"),
 dict(id="T14", cls="construction", title="測試台（共用樣本、種子與暫存）",
   req="`REQ-A-7`（接受由 `V12` 判定）", deps=["T01", "T02"],
   seam="tests/testthat/helper-harness.R",
   owned="`tests/testthat/helper-harness.R`、`tests/testthat.R`",
   files=[("tests/testthat/helper-harness.R", "四個具名函式與兩個斷言輔助；`HARNESS_SEED` 常數"),
          ("tests/testthat.R", "測試入口")],
   purpose="呼叫 `testthat::test_local()` 時，任一測試檔可自 `harness_data()`／`harness_seed()`／`harness_dir()`／`harness_out_root()` 取得全量資料、固定種子、獨立暫存目錄與可覆寫的輸出根",
   flow="支撐 V01 至 V11 的建模",
   steps=["`HARNESS_SEED <- 20261117L`；`harness_seed()` 以 `set.seed(HARNESS_SEED)` 就位後回傳。<br/>**更正（第三輪）**：起因是把「怕撞 `REQ-A-7` 的掃描」當成理由而禁用 `set.seed`，但該掃描本來就排除 `helper-harness.R`，禁令因此錯誤。故本檔使用 `set.seed`，測試檔仍只呼叫 `harness_seed()`",
          "`harness_data(population, mutator = NULL)`：population 取 `full`／`analysis`／`ability`，回全量資料框，不抽樣；給 `mutator` 時把變異後的資料寫入 `harness_dir()` 並回該路徑（供退化 fixture）。另 `harness_table(name)` 集中讀取 `output/tables/` 的一張表並檢查欄名，供 V02–V11 使用——測試檔本身不得出現 `read.csv`／`read_csv`",
          "`harness_dir()`：每次呼叫回一個獨立暫存目錄，測試結束後清除",
          "`harness_out_root()`：以 `tempfile()` 建一個空的輸出根並回傳路徑，**不自動清除**，由呼叫者負責刪除；本檔可被 testthat 以外的 R 程序 `source()` 載入而不需 testthat 就位",
          "`expect_rate_equal()`、`expect_profile()`：比率容差比較、表含母體與 n",
          "檔首寫明交界契約：`harness-0N.R` 只可呼叫上述函式，不得讀檔、不得自設種子、不得自建暫存"],
   refusal="`refuse:input-missing` — 清洗資料集缺席時停止，訊息寫明缺哪個檔、應先執行哪個任務",
   boundaries="樣本為全量兩個母體；種子固定 20261117；暫存目錄每次執行獨立；輸出根預設為空",
   untouched="不寫生產程式；不改 `lib/`；不寫入 `output/`"),
]

VA = [
 ("V01","F1 環境還原","T01","`REQ-F-F1-1`",
  ["專案根目錄 `Rscript -e 'source(\"programs/R/00_setup.R\"); c(ANALYSIS_N, ABILITY_N)'` 成功結束（常數為正整數）",
   "在暫存副本執行同一指令：副本含 `.Rprofile`（已是守衛版）、`renv/activate.R`、`renv.lock`、`programs/R/00_setup.R`，且 `renv/library` 為空；斷言 `00_setup.log` 記錄一次還原並成功結束（此即 renv 真正會 bootstrap 的狀態；若 activate 腳本本身不含還原，守衛須自行判斷 library 為空）",
   "鎖定檔缺套件時以 `refuse:unpinned-package` 停止，`00_setup.log` 寫明缺哪一個",
   "`00_setup.log` 含 R 版本、套件數、還原耗時三欄；刪掉其中一欄後斷言轉紅（負向控制）",
   "已還原狀態重跑：記錄追加一段且套件數不變（無操作）"]),
 ("V02","F2 母體","T02","`REQ-F-F2-1`, `REQ-F-F2-2`, `REQ-F-F2-3`",
  ["清冊逐 (population, metric) 釘值：total 4,424、graduate 2,209、dropout 1,421、enrolled 794、analysis 3,630、ability 2,828、missing_no_registration 180、zero_score_sem2 802、zero_score_sem2_dropout 727",
   "analysis 與 ability 分屬兩列；ability 為分析母體與第二學期成績 > 0 的交集（全樣本上為 3,554，差額 726 為在讀者）",
   "以 haven 讀回 `.sas7bdat` 與 `.xpt`：列數 4,424、欄數 37、結果欄為字元且類別集合等於三個既知值",
   "`data/raw/data.csv` 的 sha256 等於 3ef126de5cefff26eb11fbb4237f1a1401cb64b488e2f1d598c23cedeb4c45ae",
   "把輸出根指向 `data/raw` 時以 `refuse:readonly-target` 停止（以暫存副本驗證，不碰真實原始資料）",
   "欄數改為 36 或結果欄出現第四類時以 `refuse:input-schema` 停止，且清冊 sha256 不變",
   "缺值總數超過 `MISSING_PROFILE` 時以 `refuse:missing-profile` 停止，記錄寫出欄位與筆數"]),
 ("V03","F3 財富層","T04","`REQ-F-F3-1`",
  ["四格 n 合計等於分析母體；`share` 四格合計為 1（容差 1e-4）",
   "`dropout_rate` 依固定列序為 0.9513、0.9308、0.5187、0.2932（四位有效數字後相等）",
   "phi 等於 +0.4349（容差 1e-3，四位有效數字）；編碼定為 `欠繳=1`、`欠債=1`",
   "整列或整欄互換後 phi 變號且絕對值不變（負向控制一）；對角互換後 phi 不變（負向控制二）",
   "餵入空格時以 `refuse:empty-denominator` 停止，且 `wealth_four_cell.csv` 的 sha256 不變"]),
 ("V04","F4 年齡層","T05","`REQ-F-F4-1`, `REQ-F-F4-2`, `REQ-F-F4-3`",
  ["五帶齊備，n 為 1,621／1,033／355／403／218，合計 3,630；`share` 合計 1（容差 1e-4）",
   "`dropout_rate` 欄：25–29 為 0.6930、40+ 為 0.5826；`unpaid_rate` 欄：25–29 為 0.2789、40+ 為 0.2523",
   "兩項檢定為雙尾：退學率 p 0.008781、欠繳率 p 0.4987（四位有效數字後相等）",
   "婚配映射為已婚 = 2、單身 = 其餘；30–39 的 p 為 0.02455、40+ 為 0.1301（四位有效數字後相等）。另釘四格：30–39 已婚 153／單身 250、40+ 已婚 115／單身 103；負向控制改以「單身 = 1」重跑，p 須變為 0.0024／0.0571",
   "任一格 < 30 的帶入表、`p_value` 為空、`status` 為 `insufficient_n`，且不判失敗",
   "帶內已婚或單身為零時以 `refuse:empty-denominator` 停止，三張表的 sha256 皆不變"]),
 ("V05","F5 能力層","T06","`REQ-F-F5-1`, `REQ-F-F5-2`",
  ["四組各 707 人、母體 2,828；畢業率為 0.5177、0.7694、0.8388、0.8925（四位有效數字後相等）",
   "以分位數切點法重算時組數為 707／739／680／702，與本表不符（證明切法被釘住）",
   "移動表為 5 列 × 4 欄共 20 格；缺第一學期成績列合計等於 26，其四個分格為 13／7／3／3；對角線 396／285／313／477",
   "四個 quartile 列合計等於 2,802，四個 quartile 欄各等於 707",
   "剔除後母體為零時以 `refuse:empty-denominator` 停止，且 `ability_quartiles.csv` 與 `ability_transitions.csv` 的 sha256 皆不變"]),
 ("V06","F6 模型比較","T07","`REQ-F-F6-1`, `REQ-F-F6-2`",
  ["表為六列；(model, population) 配對集合等於 {年齡帶＠3,630、財務三欄＠3,630、財務三欄＠2,828、能力分位＠2,828、財務加能力＠2,828、入學成績分位＠2,828}",
   "`mcfadden_r2` 欄：三個已實算可重現的錨值為年齡帶 0.0756（四帶參數化；五帶為 0.0839）、財務三欄＠3,630 0.2227、財務三欄＠2,828 0.2011（四位有效數字後相等）。能力分位與財務加能力的值依附於 T06 的等量切法，入學成績分位依附於 T07 的分箱規格，三者一律以「重算後四位有效數字等於表中值」驗收，且若與報告所載數字不同，T07 的 `status` 為 `mismatch`、不自行改寫",
   "`auc` 以 `auc_rank` 對同一分數與結果獨立重算，逐列與表值相對差 ≤ 1e-9（不使用未經規格記錄的錨值；報告所載 0.6525／0.7444 的產生規格未記錄，故只作為 `mismatch` 的比對對象，不作釘值）",
   "`falsifier` 欄每列非空且不含 `NA`／`TBD`／`N/A`，並引用至少一個表內欄名",
   "強制一個模型不收斂時該列 `status` 為 `refuse:empty-denominator`，其餘五列數值不變"]),
 ("V07","F7 語言文化","T08","`REQ-F-F7-1`",
  ["以全量 4,424 列（`harness_data(\"full\")`）為樣本時，三圈 `n_members` 為 74／17／19、合計 110；分析母體上的 `n` 合計 86",
   "西語圈 `n` 11、`dropout_rate` 0.5455、`p_vs_local` 0.3586（四位有效數字後相等）",
   "西語圈區間兩端在 [0,1]、包含 0.5455，且等於以 6/11 計的威爾遜區間（相對差 1e-3）",
   "`required_per_group` 以西語圈為 165±10；輸入明列 α = 0.05 雙尾、power = 0.8",
   "任一組 1 ≤ n < 10 時該列 `dropout_rate` 為 NA、其餘組照出；某圈 n = 0 時該圈列 n=0 且記錄寫明，不中止",
   "葡語圈 `p_vs_local` 為空（同語，不作跨語比較）"]),
 ("V08","F8 宏觀","T09","`REQ-F-F8-1`",
  ["表長 30 列；`variable` 不同值數為 10／9／10，`population` 全為 `analysis`",
   "每個 value 的 n 合計等於該值在分析母體的人數（inflation 1.4 的兩列相加為 726）",
   "`year` 每列非 NA；`year_inferred` 為真時 `07_macro.log` 含十個三元組；互換兩列的 year 後斷言轉紅（負向控制）",
   "`role` 全為 `control`",
   "某欄不同值多於人數的十分之一時以 `refuse:input-schema` 停止且表不被覆寫"]),
 ("V09","F9 審核表","T10","`REQ-F-F9-1`",
  ["n 等於分析母體常數；每列 `verdict` 屬四類封閉詞彙",
   "`pass1`、`pass2`、`avg_grade` 三欄的 `in_model` 為 FALSE；`verdict` 為 `definitional`",
   "`p_bh` 以表中全部 `p_raw`（m = 表列數）依列序重算 BH，與表中相對差 1e-12；改以 Bonferroni 校正後斷言轉紅（負向控制）",
   "以年份為單位的三欄 `verdict` 為 `ecological`",
   "母體清冊分母與常數不符時以 `refuse:input-schema` 停止且不寫表"]),
 ("V10","F10 兩端對照","T12","`REQ-F-F10-1`, `REQ-F-F10-2`",
  ["`parity_diff.csv` 的 cell_id 集合等於 `cell_map.csv` 的十四個，且`cell_map.csv` 與 `sas_parity.csv` 的集合相等（無重複、無未知）",
   "全格在容差內時結束碼為 0；任一格超出時結束碼為 3 且 log 含 `refuse:parity` 與該 cell_id",
   "鍵序為 `cell_map.csv` 的列序，不依 locale 字串排序；「第一個不符」即該序下首個 `pass = FALSE` 的列",
   "「第一個不符」在兩個以上不符時指向登錄序最前者（以 fixture 造兩格不符驗證）",
   "容差兩側（不落在不可表示的邊界上）：相對差為 `0.5 × PARITY_TOL` 的格通過、為 `2 × PARITY_TOL` 的格不通過",
   "`sas_parity.csv` 缺席時結束碼為 1 且 log 列出預期路徑",
   "兩個 PDF 存在且大小 > 0"]),
 ("V11","F11 交付","T13","`REQ-F-F11-1`, `REQ-F-F11-2`",
  ["單一入口以子程序執行全部分析，結束碼為 0，記錄含每步耗時與套件版本",
   "`number_map.csv` 為 28 列，逐列覆蓋 spec 的每個 `number_key`，且每列帶 `population` 與 `n`",
   "任一分析表缺母體或 n 時以 `refuse:missing-profile` 停止，且 `number_map.csv` 不落地（以暫存輸出根斷言無此檔）",
   "spec 列數改為 27 時以 `refuse:incomplete-spec` 停止（負向控制）",
   "兩次執行的逐檔 sha256 比較交由 `V14` 判定（A-8／A-9），本任務只斷言交付行為：28 列覆蓋、母體與 n 齊備、拒絕分支"]),
]

def vtasks():
    out = []
    CAP = {"V01": 600, "V11": 600}
    SAMPLE = {"V01": "無資料列（僅環境與記錄）", "V02": "3,630 與 2,828 兩母體全列",
              "V05": "2,828 全列", "V06": "3,630 與 2,828 全列", "V07": "3,630 全列（含非本地 110、可比較 86）",
              "V11": "3,630 與 2,828 各全列一次"}
    for vid, flow, covers, reqs, props in VA:
        n = vid[1:]; slug = flow.split()[0]
        out.append(dict(
            id=vid, cls="verification", title=f"{flow} 的模型",
            req=reqs, deps=[covers, "T14", "G1"], flow=flow,
            covers=f"`{covers}`（模型閘 `G1` 之後）",
            shape="`A modelling` — 判定表轉成可證偽性質，含每個拒絕分支與負向控制",
            owned=f"`tests/testthat/test-{n}_{slug}.R`、`tests/testthat/harness-{n}.R`、`tests/testthat/pins/{n}_{slug}.md`",
            files=[(f"tests/testthat/test-{n}_{slug}.R", "性質與斷言"),
                   (f"tests/testthat/harness-{n}.R", "本流程的預算、執行上限與入口；樣本、種子、暫存與輸出根一律取自 `helper-harness.R`"),
                   (f"tests/testthat/pins/{n}_{slug}.md", "反例的 trace、seed、最短序列")],
            properties=props,
            steps=["讀已落地的 seam，逐條抄出判定表（輸入、前置、結果、拒絕類別、後置）",
                   "為每條性質寫斷言，含上列的拒絕分支；退化 fixture 一律在 `harness_dir()` 的暫存副本上造，不改 `output/`、不改 `programs/`",
                   "以測試台取得樣本、種子與暫存；執行，失敗時收縮並記下最短序列",
                   "把反例寫入 `pins/`；另指名一條被改錯的斷言做負向控制，確認測試會紅",
                   "報告附 trace、seed、收縮步數與負向控制的紅燈輸出"],
            budget=f"樣本：{SAMPLE.get(vid, '3,630 全列')}；無抽樣；種子 {SEED}（由 `helper-harness.R` 提供）；收縮上界 200 次且 30 秒；單流程上限 {CAP.get(vid, 120)} 秒；重試 0 次；種子與收縮在無隨機來源的流程上記 `n/a`"))
    return out

VC = [
 dict(id="V12", cls="verification", title="結構規則檢查",
   req="`REQ-A-1`、`REQ-A-2`、`REQ-A-3`、`REQ-A-6`、`REQ-A-7`（五條同工具，合併為一個檢查腳本，先此聲明）",
   deps=["G2"], flow="結構規則（`programs/R/`、`tests/`）",
   covers="`T01`–`T14` 的結構",
   shape="`C architecture check` — 五條規則逐條通過與否，附掃描檔數",
   owned="`programs/R/checks/check_structure.R`、`programs/R/checks/patterns.txt`、`programs/R/checks/structure_baseline.txt`",
   files=[("programs/R/checks/check_structure.R", "五條規則的檢查腳本，逐條印掃描檔數與命中數"),
          ("programs/R/checks/patterns.txt", "各條規則的搜尋樣式（非 .R，避免自指）"),
          ("programs/R/checks/structure_baseline.txt", "掃描域、排除清單、核准字號、每條規則的基線命中數")],
   rules=["`REQ-A-1`：`grep -rn \"setwd(\" programs/R | wc -l` 為 0，且 `grep -rn \"/Users/\" programs/R | wc -l` 為 0",
          "`REQ-A-2`：`grep -rn -E \"\\b(3630|2828|4424)\\b\" programs/R --include=*.R | grep -v 00_setup | wc -l` 為 0；年齡切點與分位數以同一方式檢查（樣式 `\\b(20|25|30|40)\\b` 與 `0\\.25`，限 `programs/R/` 非 00_setup）",
          "`REQ-A-3`：`grep -rn \"source(\" programs/R | grep -v -E \"(00_setup|lib/)\" | wc -l` 為 0",
          "`REQ-A-6`：`90_parity.R` 的 `PARITY_READ_PATHS` 與 `PARITY_WRITE_PATHS` 兩清單交集為空",
          "`REQ-A-7`：`grep -rn -E \"(read_csv|read\\.csv|set\\.seed|tempdir)\\(\" tests --include=*.R | grep -v 'tests/testthat/helper-harness\\.R:' | wc -l` 為 0"],
   steps=["五條原文與樣式抄入 `patterns.txt`（以 PRD 的位元組為準，不重複轉義）；腳本以讀取該檔實作，不在 .R 內嵌樣式",
          "排除清單只含 `patterns.txt` 與 `structure_baseline.txt` 兩檔；`check_structure.R` 留在掃描域內（它不含樣式字面）。此排除須主代理帶日期核准，核准字號寫入基線檔",
          "逐條印掃描檔數與命中數；檔數為 0 判「不可判定」，不得算通過",
          "負向控制全部在暫存副本上做：複製 `programs/` 與 `tests/` 到 `harness_dir()`，注入違規檔，把掃描根指向副本，逐條要求轉紅；副本用完刪除，真實樹不動",
          "在全部建構接受後執行一次；`programs/SAS/` 不在任一條 `REQ-A` 的 Scope 內，不掃"],
   properties=["五條規則全綠，且每條掃描檔數 ≥ 1（`A-6` 另加：兩個路徑清單長度各 ≥ 1）",
               "副本注入 `setwd(` 的暫存檔後 `REQ-A-1` 轉紅",
               "副本 `00_setup.R` 以外改寫一個母體常數後 `REQ-A-2` 轉紅",
               "副本某編號腳本加一行 `source(\"04_ability.R\")` 後 `REQ-A-3` 轉紅",
               "副本 `90_parity.R` 的寫入清單加入 `output/parity/x.csv` 後 `REQ-A-6` 轉紅",
               "副本 `tests/` 內加 `set.seed(1)` 後 `REQ-A-7` 轉紅；真實樹的 `harness-0N.R` 不被誤判"],
   budget="門檻全部為零命中；掃描域 `programs/R/`、`tests/`；每條掃描檔數 ≥ 1；執行上限 30 秒"),
 dict(id="V13", cls="verification", title="套件同步檢查",
   req="`REQ-A-4`", deps=["G2"], flow="套件環境與鎖定檔一致",
   covers="`T01` 的鎖定檔與全部引用套件的腳本；受保護的變更是 `T01`",
   shape="`C architecture check` — 兩階段：凍結現狀（主代理於 T01 開工前記錄），再要求同步為真",
   owned="`programs/R/checks/check_pins.R`、`programs/R/checks/pins_baseline.txt`",
   files=[("programs/R/checks/check_pins.R", "同步狀態與實際使用套件的比對"),
          ("programs/R/checks/pins_baseline.txt", "第一階段的凍結內容；由本任務寫入一次後唯讀")],
   steps=["第一階段：抄入 `.plan/17-11-2026/r-toolkit/pins_before_T01.md`（由主代理於第 0 波產出，內容含日期與逐列一件）。該檔缺席或無日期時判「不可判定」並停止，不得以任務文字代替",
          "基線分兩節：環境列（`renv/` 存在、`renv::status()$synchronized` 為真）與套件列（逐套件名；今日缺 `testthat`、`PropCIs`、`broom`）",
          "第二階段：在 `T01` 接受後執行，要求環境列為真、套件列每名可 `requireNamespace` 且出現在 `renv.lock`",
          "負向控制：在暫存副本複製一份 `05_models.R` 並加入 `library(nonexistentpkg)`，把該副本列入比對，要求轉紅；真實樹不動",
          "清單異動須主代理帶日期修訂"],
   properties=["環境列消解：`renv::status()$synchronized` 為真",
               "套件列逐列消解：每個凍結套件名可 `requireNamespace` 且出現在 `renv.lock`",
               "消解列數等於凍結列數（環境列 2：`renv/` 與 `.Rprofile`；套件列 3；共 5）",
               "副本加入 `library(nonexistentpkg)` 後轉紅（負向控制）"],
   budget="門檻：環境列為真、未登記套件數為零、未消解列數為零；執行上限 60 秒"),
 dict(id="V14", cls="verification", title="輸出可重建檢查",
   req="`REQ-A-5`", deps=["G2"], flow="同一輸入重跑得到相同的表",
   covers="`run_all.R` 在兩個獨立輸出根產出的 `output/tables/` CSV（不判定入口本身；`output/` 對本檢查唯讀）",
   shape="`C architecture check` — 兩次獨立執行互比，逐檔 sha256；與 `V11` 的分工：結構事實歸本任務，交付行為歸 `V11`",
   owned="`programs/R/checks/check_reproducible.R`、`programs/R/checks/repro_baseline.txt`、`programs/R/checks/repro_config.txt`",
   files=[("programs/R/checks/check_reproducible.R", "`--make-baseline` 與 `--compare` 兩個模式"),
          ("programs/R/checks/repro_baseline.txt", "run1 的 14 個 sha256；寫定後 chmod a-w"),
          ("programs/R/checks/repro_config.txt", "凍結的 14 個檔名清單與時間戳欄黑名單")],
   steps=["`repro_config.txt` 於首跑前由 TASKS.md 登記的十三個 CSV 檔名抄入（排除 `number_map_spec.csv`，它是首跑前的唯讀輸入而非產物）並置唯讀；同時寫入時間戳欄黑名單（`^timestamp$|^generated_at$|^run_time$|^ts$`）",
          "`--make-baseline`：以 `RTOOLKIT_OUT_ROOT` 指向 `harness_out_root()` 的 run1 根，跑一次 `run_all.R`，取 14 檔 sha256 寫入基線並置唯讀；基線已存在時以 `refuse:baseline-exists` 停止",
          "`--compare`：以另一個空根跑第二次，逐檔比對 sha256、檔名集合與檔數；不符時指出檔名排序後第一筆",
          "檢查每檔欄名與黑名單交集為空；印出命中欄",
          "負向控制：在 run2 的副本注入一個時間欄，要求 sha256 分支與欄名分支分別轉紅；`output/` 全程唯讀"],
   properties=["兩次執行的檔名集合等於 `repro_config.txt` 的 14 個，檔數為 14",
               "逐檔 sha256 相同（`shasum -a 256`，位元組比對，不假定編碼）",
               "欄名與黑名單交集為空",
               "注入時間欄後兩個分支分別轉紅（負向控制）"],
   budget="門檻：檔數等於 14、檔名集合相等、逐檔 sha256 相同；範圍為兩個暫存輸出根下的 `tables/*.csv`；`output/` 不參與；兩次執行合計上限 600 秒"),
]

tasks = C + vtasks() + VC
for t in tasks:
    t["file"] = f"{t['id']}-{t['title'].replace(' ', '-')}.md"
    with io.open(os.path.join(TASKS_DIR, t["file"]), "w", encoding="utf-8") as fh:
        fh.write(render(t))

byid = {t["id"]: t for t in tasks}
byid["G1"] = dict(id="G1", deps=["T01","T02","T03","T14"])
byid["G2"] = dict(id="G2", deps=["T13","T14"])
memo = {}
def depth(tid):
    if tid in memo: return memo[tid]
    d = 1 if not byid[tid]["deps"] else 1 + max(depth(p) for p in byid[tid]["deps"])
    memo[tid] = d
    return d
waves = {}
for tid in [t["id"] for t in tasks] + ["G1","G2"]:
    waves.setdefault(depth(tid), []).append(tid)
print("waves:")
for w in sorted(waves):
    print(f"  w{w}: {' '.join(sorted(waves[w]))}")
print("max:", max(waves), "tasks:", len(tasks))

TRACE_F = [
 ("REQ-F-F1-1","T01","`00_setup.R`","V01"),("REQ-F-F2-1","T02","`01_prep_data.R`","V02"),
 ("REQ-F-F2-2","T02","`01_prep_data.R` 的寫入前檢查","V02"),("REQ-F-F2-3","T02","`01_prep_data.R` 的欄數檢查","V02"),
 ("REQ-F-F3-1","T04","`02_wealth.R`","V03"),("REQ-F-F4-1","T05","`03_age.R`","V04"),
 ("REQ-F-F4-2","T05","`03_age.R` 的檢定段","V04"),("REQ-F-F4-3","T05","`03_age.R` 的分層段","V04"),
 ("REQ-F-F5-1","T06","`04_ability.R`","V05"),("REQ-F-F5-2","T06","`04_ability.R` 的移動表","V05"),
 ("REQ-F-F6-1","T07","`05_models.R`","V06"),("REQ-F-F6-2","T07","`05_models.R` 的條件欄","V06"),
 ("REQ-F-F7-1","T08","`06_language.R`","V07"),("REQ-F-F8-1","T09","`07_macro.R`","V08"),
 ("REQ-F-F9-1","T10","`08_audit.R`","V09"),("REQ-F-F10-1","T11、T12","`05_parity.sas` 與 `90_parity.R`","V10"),
 ("REQ-F-F10-2","T12","`90_parity.R` 的判定段","V10"),("REQ-F-F11-1","T13","`run_all.R`","V11"),
 ("REQ-F-F11-2","T13","`run_all.R` 的兩次執行","V11"),
]
TRACE_A = [
 ("REQ-A-1","—（建構即遵守）","`programs/R/` 全部 R 檔","V12"),
 ("REQ-A-2","T01","`00_setup.R` 的常數","V12"),
 ("REQ-A-3","—（建構即遵守）","`programs/R/` 編號腳本","V12"),
 ("REQ-A-4","T01","`renv.lock` 與 `00_setup.R` 的檢查段","V13"),
 ("REQ-A-5","T13","`output/tables/` 全部 CSV","V14"),
 ("REQ-A-6","T12","`PARITY_READ_PATHS` 與 `PARITY_WRITE_PATHS`","V12"),
 ("REQ-A-7","T14","`tests/testthat/helper-harness.R`","V12"),
]

def tasks_md():
    L = ["```mermaid", "flowchart TD", '  subgraph C["Construction"]']
    L += [f'    {t["id"]}["{t["id"]} construction · {t["title"]}"]' for t in tasks if t["cls"] == "construction"]
    L += ["  end", '  subgraph V["Verification A（模型）"]']
    L += [f'    {t["id"]}["{t["id"]} verification A · {t["title"]}"]' for t in tasks if t["cls"] == "verification" and t["id"] in [v[0] for v in VA]]
    L += ["  end", '  subgraph K["Verification C（架構檢查）"]']
    L += [f'    {t["id"]}["{t["id"]} verification C · {t["title"]}"]' for t in tasks if t["cls"] == "verification" and t["id"] in [v["id"] for v in VC]]
    L += ["  end", '  G1{"模型閘 G1"}', '  G2{"守衛閘 G2 · C 檢查"}']
    for t in tasks:
        for d in t["deps"]:
            L.append(f"  {d} --> {t['id']}")
    for d in ["T01","T02","T03","T14"]:
        L.append(f"  {d} --> G1")
    for d in ["T13","T14"]:
        L.append(f"  {d} --> G2")
    L.append("```")

    reg = ["| Task | Class | Title | Depends on | Files owned | REQs | Seam / flow | File |", "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for t in tasks:
        deps = "、".join(f"`{d}`" for d in t["deps"]) or "—"
        seam = t.get("seam") or t["flow"].split("（")[0]
        reg.append(f"| `{t['id']}` | {t['cls']} | {t['title']} | {deps} | {t['owned']} | {t['req']} | {seam} | [`tasks/{t['file']}`](tasks/{t['file']}) |")

    tr = ["| REQ | Kind | Construction task | Seam | Verification task | Migration / removal |", "| --- | --- | --- | --- | --- | --- |"]
    tr += [f"| `{r}` | functional | `{tsk}` | {seam} | `{v}`（modelling） | — |" for r, tsk, seam, v in TRACE_F]
    tr += [f"| `{r}` | architectural | {('`'+tsk+'`') if tsk.startswith('T') else tsk} | {seam} | `{v}`（architecture check） | — |" for r, tsk, seam, v in TRACE_A]

    notes = {1:"設定先行",2:"資料與共用統計量",3:"八個分析與測試台",4:"模型閘關閉、SAS 對照程式",
             5:"差異表與十一個流程模型",6:"交付入口與對照模型",7:"守衛閘關閉、交付模型",8:"三條架構檢查"}
    wv = ["| Wave | Tasks | 說明 |", "| --- | --- | --- |"]
    for w in sorted(waves):
        wv.append(f"| {w} | {' '.join('`'+x+'`' for x in sorted(waves[w]))} | {notes.get(w,'')} |")

    return f"""# TASKS — r-toolkit

| Field | Value |
| --- | --- |
| PRD | [`PRD.md`](PRD.md) |
| Date | 2026-11-17（三輪稽核修訂後 v4） |
| Status | working contract |
| Workflow | 四類 → 模型閘 / 守衛閘 → 派工 |
| Task files | `tasks/<id>-<title>.md`，一任務一檔 |
| Scope audit | 三輪共 30 位稽核員、257 條回報；修訂 A-1 至 A-27 見 `AMENDMENTS.md` |

`TASKS.md` 是指引層：DAG、任務登記、需求追溯、閘門與派工順序。任務本文在各目的檔案裡。一檔一寫者。

## 1. Class register

| Class | Count | Flow / path covered |
| --- | --- | --- |
| construction | 14 | F1、F2、共用統計量、F3–F11、測試台 |
| verification A | 11 | F1–F11 各一個模型 |
| verification C | 3 | `REQ-A-1/2/3/6/7` 合併、`REQ-A-4`、`REQ-A-5` |
| migration | 0 | 無（greenfield） |
| removal | 0 | 無 |

## 2. DAG

{chr(10).join(L)}

`A --> B` 表示 B 依賴 A。閘門節點無擁有者、無檔案。

**Greenfield 的三處偏離。** 一，本計劃無 migration 與 removal，守衛閘沒有「先於變更」的物件，`G2` 的意義為「全部建構完成後，三條架構檢查開跑」。二，`REQ-A-4` 今日已被違反，`V13` 寫成兩階段：凍結清單由主代理於 `T01` 開工前產出 `pins_before_T01.md`（第 0 波），之後唯讀。三，`REQ-A-5` 今日無基線，`V14` 以兩次獨立執行互比取代前後互比。

## 3. Task register

{chr(10).join(reg)}

## 4. Task files

一任務一檔，本文不重述。

## 5. Requirement trace

{chr(10).join(tr)}

十九條 `REQ-F` 各有一個建構任務與一個模型；七條 `REQ-A` 各有一條架構檢查（`V12` 合併五條同工具規則，已聲明）。

## 6. Gates and dispatch

**模型閘 `G1`**：A 類驗證在涵蓋的建構任務全部被接受後開跑。
**守衛閘 `G2`**：三條 C 檢查在最後一個建構任務（含 `T14`）之後執行。

**分波**

{chr(10).join(wv)}

關鍵路徑：`T01` → `T02` → `T04` → `T11` → `T12` → `T13` → `G2` → `V12`，長度 8。最寬的一層為第 5 波（十個驗證任務並行）。

## 7. Coupling exceptions

| Task | Why it is not one unit | Compensation |
| --- | --- | --- |
| `T11` + `T12` | 同一份對照值契約的兩端 | 契約寫在 `cell_map.csv`（機器可讀），`T12` 依賴 `T11` |
| `V12` | 五條架構規則同工具 | 一個檢查腳本，逐條輸出，門檻皆為零命中 |

## 8. Scope audit

| 輪 | 回報 | 去重 | 採納 | 駁回 |
| --- | --- | --- | --- | --- |
| 一 | 90 | 69 | 68 | 1（`T03` 的重分類） |
| 二 | 103 | 62 | 61 | 1（`T01` 常數模組切分） |
| 三 | 64 | 55 | 52 | 3（列序迎合、兩組錨值改釘） |

修訂編號 A-1 至 A-27，逐條見 `AMENDMENTS.md`。第三輪之後停止稽核，理由記在該檔的「停止稽核的判斷」一節：剩下的發現集中在「每一格用哪個數字驗收」，寫一支分析腳本比再跑十個稽核員更快收斂。

## 9. Review checklist

- [x] 每條 PRD 需求被覆蓋，每個任務追溯到 `REQ-F` 或 `REQ-A`；
- [x] 每條 `REQ-A` 有 C 類驗證任務；
- [x] 每個任務的類別與檔案內容相符；
- [x] 每個檔案恰有一個寫者；
- [x] 無 migration 與 removal；
- [x] 每條流程恰有一個模型檔與一個 harness 入口；
- [x] DAG 無環、兩閘皆畫、驗證節點掛在閘下；
- [x] 登記的依賴欄等於 DAG 的邊；
- [x] 任務檔不含測試、模型、基線或約束腳本；
- [x] 未以數量配額切分；
- [x] 每條發現有處置。
"""

with io.open(os.path.join(PLAN, "TASKS.md"), "w", encoding="utf-8") as fh:
    fh.write(tasks_md())
print("TASKS.md written")
