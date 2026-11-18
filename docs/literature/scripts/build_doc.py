#!/usr/bin/env python3
"""彙總 subagent JSON → docs/literature/sentence-patterns.md（第二版）

分三類呈現，避免把「未審核」誤標為「不可用」：
  A. 已正式審核（80 句人工判讀，verification.json 有 precision）
  B. 關鍵詞型（字面詞表比對，未正式審核，我抽查 8 句未見系統性誤判）
  C. 不可用（已審核且 precision < 0.50）
"""
import json, os

OUT = "/Users/tszkinlai/.hermes/cache/scratch/ams2640-lit/out"
REPO = "/Users/tszkinlai/Documents/AMS2640/group project"
DOC = os.path.join(REPO, "docs/literature/sentence-patterns.md")
J = lambda n: json.load(open(os.path.join(OUT, n), encoding="utf-8"))

def pct_map(doc):
    if isinstance(doc["patterns"], dict):
        return dict(doc["patterns"])
    return {p["key"]: p for p in doc["patterns"]}

pfe = J("pfeffer_body.json"); pf = pct_map(pfe); pf_n = pfe["length"]["sentences"]
hon = J("hong_body.json");    hf = pct_map(hon); hf_n = hon["length"]["sentences"]
ab  = J("compare_ab.json")
abst = J("hong_abstracts.json")
abs_c = [c for c in abst["corpora"] if c.get("label") == "abstracts"][0]
abs_p = pct_map(abs_c); abs_n = abs_c["corpus"]["sentences"]
ver = J("verification.json")

lit_n = ab["A_body"]["sentences"] + ab["B_body"]["sentences"]
lit_per = {}
for seg in ("A_body", "B_body"):
    n = ab[seg]["sentences"]
    for t in ab[seg]["top"]:
        lit_per[t["key"]] = lit_per.get(t["key"], 0.0) + t["per_1000"] * n / 1000.0
lit_per = {k: round(v / lit_n * 1000, 2) for k, v in lit_per.items()}

prec = {p["key"]: p.get("precision") for p in ver["patterns"]}
hits = {p["key"]: p.get("hits_in_sample") for p in ver["patterns"]}
AUDITED = set(prec)

names = {}
for src in (pf, hf, abs_p):
    for k, v in src.items():
        if v.get("name"):
            names.setdefault(k, v["name"])
def nm(k): return names.get(k, k)

keys = sorted(set(list(pf) + list(hf) + list(abs_p) + list(lit_per)))
rows = {}
for k in keys:
    parts = [(pf_n, pf.get(k, {}).get("per_1000", 0.0)),
             (hf_n, hf.get(k, {}).get("per_1000", 0.0)),
             (lit_n, lit_per.get(k, 0.0)),
             (abs_n, abs_p.get(k, {}).get("per_1000", 0.0))]
    tot = sum(n for n, _ in parts)
    raw = sum(n * v / 1000.0 for n, v in parts) / tot * 1000
    rows[k] = {"key": k, "name": nm(k), "per_1000": round(raw, 2),
               "precision": prec.get(k), "hits": hits.get(k),
               "by": [round(raw, 2) and round(v, 2) for (n, v) in parts]}

audited_ok = sorted([r for r in rows.values() if r["precision"] and r["precision"] >= 0.80], key=lambda r: -r["per_1000"])
audited_mid = sorted([r for r in rows.values() if r["precision"] and 0.50 <= r["precision"] < 0.80], key=lambda r: -r["per_1000"])
audited_bad_all = sorted([r for r in rows.values() if r["precision"] and r["precision"] < 0.50], key=lambda r: -r["per_1000"])
# relative 有可用的下界估計（wh-關係詞），故另段處理，不列入不可用
audited_bad = [r for r in audited_bad_all if r["key"] != "relative"]
rel_row = [r for r in audited_bad_all if r["key"] == "relative"]
keyword = sorted([r for r in rows.values() if r["key"] not in AUDITED], key=lambda r: -r["per_1000"])

pf_l, hf_l, abs_l = pfe["length"], hon["length"], abs_c["corpus"]
lit_mean = round((ab["A_body"]["length"]["mean_words"] * ab["A_body"]["sentences"] +
                  ab["B_body"]["length"]["mean_words"] * ab["B_body"]["sentences"]) / lit_n, 2)
total_n = pf_n + hf_n + lit_n + abs_n

L = []; A = L.append
A("# 句式頻率：同型論證文章的語法統計")
A("")
A(f"語料為 `docs/literature/` 內可統計的九篇英文文獻，清理後共 **{total_n} 個正文句**：Pfeffer & Killewald (2018) 論文、Littler (2017) 專書正文、Hong & Youngs (2008) 論文、六篇付費牆文章摘要。IRP 政策簡報因四欄版面在轉文字時交錯，句界無法還原，未納入統計。統計以 27 條正則逐句比對；另派一名審核員抽 80 句人工判讀，算出其中 8 條結構型正則的精確度。下表因此分三類：已審核、關鍵詞型（未正式審核）、不可用。")
A("")
A("## 一、語料與清理")
A("")
A("| 語料 | 正文句數 | 詞數 | 平均句長（詞） | 40 詞以上占比 | 清理 |")
A("|---|---|---|---|---|---|")
A(f"| Pfeffer 2018（Demography 55(3)） | {pf_n} | {pf_l['words']} | {pf_l['mean_words']} | {pf_l['share_over_40w']}% | 移除圖說與黏連的章節標題 |")
A(f"| Hong & Youngs 2008（EPAA 16(17)） | {hf_n} | {hf_l['words']} | {hf_l['mean_words']} | {hf_l['share_over_40w']}% | 截去參考書目、作者名錄、編委名單（原檔 70,189 字元，正文止於 53,607） |")
A(f"| Littler 2017（Routledge，專書） | {lit_n} | — | {lit_mean} | 22.3%（兩段平均） | 逐段剝除章末註釋與參考書目（占 15.01%） |")
A(f"| 六篇期刊摘要 | {abs_n} | — | {abs_l.get('mean_words')} | — | 只取摘要本體 |")
A("")
A("清理是必要的一步：未清理時 Hong & Youngs 約 22.5% 的句子是書目與名錄，會同時拉低平均句長並污染每一個頻率。")
A("")
A("## 二、已正式審核：可直接引用（精確度 ≥ 0.80）")
A("")
A("| 句式 | 每千句 | 精確度 | 審核樣本命中 |")
A("|---|---|---|---|")
for r in audited_ok:
    A(f"| {r['name']} | {r['per_1000']} | {r['precision']:.4g} | {r['hits']} |")
A("")
A("審核方式：以固定種子抽 80 句，逐句人工判讀該句式是否成立，再與腳本命中比對；precision = 人工判真數 ÷ 腳本命中數。")
A("")
A("## 三、已正式審核：方向可信、數值偏寬（0.50 ≤ 精確度 < 0.80）")
A("")
A("| 句式 | 每千句 | 精確度 | 校正後每千句 | 誤判來源 |")
A("|---|---|---|---|---|")
why = {"relative": "把 that 引導的內容子句與指示詞 that 一併計入",
       "reporting_verb": "動詞與名詞同形（claim、shows）及分詞形式未分辨",
       "compound_adj": "把作者姓氏（Ziol-Guest）與普通連字詞（run-up）計入",
       "nominal_subject": "開放式字元距把非抽象名詞的主語收進來"}
for r in audited_mid:
    A(f"| {r['name']} | {r['per_1000']} | {r['precision']:.4g} | {round(r['per_1000']*r['precision'],2)} | {why.get(r['key'],'—')} |")
A("")
A("這兩條可以用來說「常見」，但不能拿原始數字當精確值；校正後欄才是可引用的估計。")
A("")
A("## 四、已正式審核：不可引用（精確度 < 0.50）")
A("")
A("| 句式 | 每千句 | 精確度 | 問題 |")
A("|---|---|---|---|")
bad_why = {"adjective_stacking": "命中 39 句中僅 1 句成立；正則只要求「兩個詞 + 白名單形容詞」",
           "colon_expansion": "只認冒號字元，未判斷冒號後是否為列舉或解釋",
           "passive_agentless": ""}
for r in audited_bad:
    A(f"| {r['name']} | {r['per_1000']} | {r['precision']:.4g} | {bad_why.get(r['key'],'—')} |")
A("")
A("## 四之二、關係子句：原始值偏高，改用下界")
A("")
if rel_row:
    r = rel_row[0]
    A(f"關係子句的原始命中為每千句 {r['per_1000']}，但審核發現其中約半數的 `that` 其實是引述動詞後的內容子句（precision {r['precision']:.4g}）。改用只計 wh-關係詞（which／who／whom／whose／where）的收緊正則重算：Pfeffer 為每千句 143.4（39／272 句）、Hong & Youngs 為 122.5（24／196 句）。這是關係子句的下界，`that` 引導的限定性關係子句未計入。")
A("")
A("實務上的意思是：`which／who` 引導的關係子句每千句約 120 至 145 次，是可靠的密度；`that` 引導者無法用字面正則與內容子句分開，須以句法分析處理。")
A("")
A("## 五、關鍵詞型句式（未正式審核）")
A("")
A("以下十九條以字面詞表比對，誤判風險主要在詞性歧義。我對其中七條（情態、否定、句首副詞、系動詞、條件、因果、對比）各抽查 8 句，未見系統性誤判；其餘十二條未抽查。數字供排序參考，不宜當精確值。")
A("")
A("| 句式 | 每千句 | 抽查 |")
A("|---|---|---|")
CHECKED = {"modal", "negation", "fronted_adverb", "copular", "conditional", "causal", "contrast"}
for r in keyword:
    A(f"| {r['name']} | {r['per_1000']} | {'8 句，未見誤判' if r['key'] in CHECKED else '未抽查'} |")
A("")
A("## 六、逐來源對照（每千句，未校正）")
A("")
A("| 句式 | Pfeffer | Hong & Youngs | Littler | 摘要 |")
A("|---|---|---|---|---|")
for r in audited_ok + audited_mid:
    A(f"| {r['name']} | " + " | ".join(str(x) for x in r["by"]) + " |")
A("")
A("## 七、句首與引述動詞（原文特徵，不經正則）")
A("")
A("- **Pfeffer**：report 20、observe 18、document 17、show 15、find 10；句首 `I begin by`、`As a result`、`In line with`、`In sum, then`、`Prior research on`。")
A("- **Littler 前段**：argue 42、suggest 18、put（it）17、write 14；句首 `In the UK`、`In other words`。")
A("- **Littler 後段**：argue 34、show 25、write 22、point out 14；句首 `At the same`、`It is a`、`As we saw`。")
A("- **六篇摘要**：名詞化主語＋引述動詞開句（`This study shows`、`These findings suggest`），句短而公式化。")
A("")
A("## 八、十個可複用的句式模板")
A("")
A("模板由上述結果歸納，方括號為可替換成分；括號內的數字是該結構在語料中的每千句密度。")
A("")
A("| # | 模板 | 結構 | 密度／千句 |")
A("|---|---|---|---|")
tpl = [
 ("This [finding] shows that [claim], [constraint].", "名詞化主語＋引述動詞（摘要體）", "名詞化主語 305.6（摘要）"),
 ("[X] is associated with [Y], whereas [Z] remains [state].", "系動詞＋對比連結", f"對比 {rows['contrast']['per_1000']}"),
 ("Prior research on [topic] has focused chiefly on [A], leaving [B] unexamined.", "句首介詞短語＋現在完成式", f"句首副詞／介詞 {rows['fronted_adverb']['per_1000']}"),
 ("The analysis is based on [data], which [property].", "被動＋wh-關係子句", f"被動 {rows['passive_agentless']['per_1000']}；關係子句（wh 下界）143.4／122.5"),
 ("Evidence from [setting] indicates that [claim]; the same pattern appears in [second setting].", "引述動詞＋分號並置", f"引述動詞 {rows['reporting_verb']['per_1000']}"),
 ("If [condition], then [consequence], a test that [falsifier].", "條件句＋同位語", f"條件 {rows['conditional']['per_1000']}"),
 ("Low-[noun] students are [verb-ed] in [institution], and the gap [verb]s with [variable].", "複合形容詞＋被動", f"複合形容詞 {rows['compound_adj']['per_1000']}"),
 ("Three mechanisms account for [outcome]: first, [M1]; second, [M2]; third, [M3].", "冒號列舉", "Littler 後段 263.3"),
 ("This is not a claim about [X]; it is a claim about [Y].", "否定＋重述", f"否定 {rows['negation']['per_1000']}"),
 ("[Author] (year) argues that [claim], a reading that [evaluation].", "引述動詞＋同位語評價", f"argue（Littler）32.31"),
]
for i, (t, s, d) in enumerate(tpl, 1):
    A(f"| {i} | {t} | {s} | {d} |")
A("")
A("## 九、三條寫作判準（由數據反推）")
A("")
A(f"1. **句長**：Pfeffer 平均 {pf_l['mean_words']} 詞、40 詞以上占 {pf_l['share_over_40w']}%；Hong & Youngs 平均 {hf_l['mean_words']} 詞、40 詞以上占 {hf_l['share_over_40w']}%；六篇摘要平均 {abs_l.get('mean_words')} 詞。長文可容許 30 詞上下的句子，40 詞以上宜壓在 20% 以下（Littler 正文兩段為 22.3% 與 20.67%）。")
A(f"2. **被動**：無施事被動每千句 Pfeffer {rows['passive_agentless']['by'][0]}、Hong & Youngs {rows['passive_agentless']['by'][1]}、Littler {rows['passive_agentless']['by'][2]}（校正後約乘以 0.846）。被動集中在資料與方法句；論證句用主動，主體才不會消失。")
A("3. **冒號**：Littler 後段每千句 263.3、前段 212.3，是「先立命題、再列證據」的標記。你的每段若走 A→B→C→D，冒號是最省字的接合點。")
A("")
A("## 十、可重跑的部分")
A("")
A("- 腳本：`~/.hermes/cache/scratch/ams2640-lit/patterns.py`（27 條正則，支援 `--from/--to` 切片）")
A("- 各語料輸出：`~/.hermes/cache/scratch/ams2640-lit/out/*.json`；正則審核：`out/verification.json`")
A("- 修好正則後重跑 `build_doc.py` 即可更新本文件全部數字。")

open(DOC, "w", encoding="utf-8").write("\n".join(L) + "\n")
print("wrote", DOC, "| sentences", total_n,
      "| audited_ok", len(audited_ok), "mid", len(audited_mid), "bad", len(audited_bad), "keyword", len(keyword))
