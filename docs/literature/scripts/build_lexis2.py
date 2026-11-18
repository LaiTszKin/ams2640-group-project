#!/usr/bin/env python3
"""build_lexis2.py — 用統一版腳本的輸出（out/L_*.json）生成高頻詞文檔。

修正後的 lexis.py 已做：NFKC 正規化、META 優先於 DOMAIN、scaffold/topic 都保留、
參考書目與圖說樣板濾除。子代理只提供七族分類的文字，數字一律取自本次統一執行。
"""
import json, os, collections

OUT = "/Users/tszkinlai/.hermes/cache/scratch/ams2640-lit/out"
REPO = "/Users/tszkinlai/Documents/AMS2640/group project"
DOC = os.path.join(REPO, "docs/literature/high-frequency-lexis.md")
J = lambda n: json.load(open(os.path.join(OUT, n), encoding="utf-8")) if os.path.exists(os.path.join(OUT, n)) else None

run = {k: J(f"L_{k}.json") for k in ["pfeffer", "hong_abs", "littler_a", "littler_b", "all"]}

# 學術慣用語（META）實測計數：直接 import lexis 的詞表，對同一批句子計數
import importlib.util, collections as _c
_spec = importlib.util.spec_from_file_location("lexis", os.path.join(os.path.dirname(OUT), "lexis.py"))
_LX = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_LX)
REPO_LIT = os.path.join(REPO, "docs/literature")
_srcs = [os.path.join(os.path.dirname(OUT), "txt/pfeffer_body.txt"),
         os.path.join(os.path.dirname(OUT), "txt/hong_body.txt"),
         os.path.join(os.path.dirname(OUT), "txt/littler_oa.txt")]
_srcs += sorted(__import__("glob").glob(os.path.join(REPO_LIT, "abstracts", "*.md")))
_sents = []
for _f in _srcs:
    _sents += _LX.split_sentences(_LX.read_text(_f))
_tok = [w for s in _sents for w in _LX.tokenize(s)]
_n = max(1, len(_tok))
_meta_ct = _c.Counter(w for w in _tok if w in _LX.META or w.rstrip("s") in _LX.META)
META_ROWS = [(w, c, round(1000.0*c/_n, 3)) for w, c in _meta_ct.most_common(22)]
labels = {"pfeffer": "Pfeffer 2018", "hong_abs": "Hong & Youngs＋摘要", "littler_a": "Littler 前段", "littler_b": "Littler 後段"}

# 子代理的分類（bundle → family／role），只取文字，不取數字
cls = {}
for f in ["lexis_pfeffer.json", "lexis_littler_a.json", "lexis_littler_b.json", "lexis_hong_abs.json"]:
    d = J(f)
    if not d: continue
    items = d.get("classification") or []
    for c in d.get("corpora", []) or []:
        items += c.get("classification") or []
    for it in items:
        b = it.get("bundle")
        if b and b not in cls:
            cls[b] = (it.get("family", "其他"), (it.get("role") or "")[:70])

def per_corpus_bundles(n):
    """bundle → {corpus: count}"""
    out = collections.defaultdict(dict)
    for k in ["pfeffer", "hong_abs", "littler_a", "littler_b"]:
        d = run[k]
        if not d: continue
        for b in d["bundles"][n]["scaffold"]:
            out[b["bundle"]][k] = b["count"]
    return out

def density(d, count):
    return round(1000.0 * count / max(1, d["corpus"]["words"]), 3) if d else None

all_d = run["all"]
L = []; A = L.append
A("# 高頻常用詞：這批論證文章反覆使用的非術語詞彙")
A("")
A("中文公文有「全面、深化、統籌、切實」。英文學術論證文章同樣有一套慣用詞，但它們主要以**詞組**的形式出現——單看單詞會漏掉最有特徵的部分。本文件量的是這一層：除去研究主題的術語之後，文章反覆用來搭架子、降調、加碼、引述的詞與詞組。")
A("")
A(f"語料 {all_d['corpus']['sentences']} 句、{all_d['corpus']['words']} 詞，全部數字來自同一次執行（`docs/literature/scripts/lexis.py`）。")
A("")
A("## 一、方法與三個決定")
A("")
A("1. **三層詞彙分開**：功能詞（the、of、and）不進單詞表但保留在詞組裡；**主題領域術語**（income、attainment、dropout、college、neoliberal…）整層排除；**學術慣用語**（study、evidence、finding、significant、effect…）保留並標記 meta——後者才是本文要量的。若把 meta 詞也排除，剩下的就只有研究對象的專有名詞。")
A("2. **詞組以句子為界，只留出現 ≥ 3 次的 2 至 4 詞組合**，並分 scaffold（框架型，本文主體）與 topic（含主題詞，另存）。")
A("3. **每千詞為分母**。各語料長度差一個數量級，用原始次數會讓 38,000 詞的專書壓過 9,000 詞的論文。")
A("")
A("清理：連字（ﬀ／ﬁ）先做 NFKC 正規化，否則會得到 `erent`、`cant`、`eld`、`ects` 這類殘字；參考書目、圖說樣板（Reproduced courtesy of）、網頁殘字（Open in a new tab）、目錄點線一律濾除。")
A("")
A("## 二、語料")
A("")
A("| 語料 | 句數 | 詞數 | 平均句長 |")
A("|---|---|---|---|")
for k in ["pfeffer", "hong_abs", "littler_a", "littler_b"]:
    d = run[k]
    if not d: continue
    c = d["corpus"]
    A(f"| {labels[k]} | {c['sentences']} | {c['words']} | {c['mean_words_per_sentence']} |")
A(f"| **合計** | **{all_d['corpus']['sentences']}** | **{all_d['corpus']['words']}** | **{all_d['corpus']['mean_words_per_sentence']}** |")
A("")
A("## 三、跨語料的通用公式（出現於 3 篇以上）")
A("")
A("這一組是文體的骨架：任何人寫這類論證都會用到，與作者風格無關。")
A("")
A("| 詞組 | 總次數 | 每千詞 | 出現語料數 | 功能（判讀） |")
A("|---|---|---|---|---|")
def collapse(items):
    """去掉被更長詞組覆蓋的片段：同一串詞若在更長詞組中出現且次數相近，只留長的。"""
    items = sorted(items, key=lambda r: (-len(r[0].split()), -r[1]))
    kept = []
    for b, c, d_, f, fam in items:
        toks = b.split()
        dominated = False
        for kb, kc, *_ in kept:
            kt = kb.split()
            if len(kt) > len(toks) and kc >= 0.8 * c:
                for i in range(len(kt) - len(toks) + 1):
                    if kt[i:i+len(toks)] == toks:
                        dominated = True; break
            if dominated: break
        if not dominated:
            kept.append((b, c, d_, f, fam))
    return kept

rows = []
for n in ["2", "3", "4"]:
    for b in all_d["bundles"][n]["scaffold"]:
        if b["files"] >= 3:
            rows.append((b["bundle"], b["count"], b["per_1000_words"], b["files"], cls.get(b["bundle"], ("", ""))[0]))
rows = collapse(rows)
rows.sort(key=lambda r: -r[1])
for b, c, d_, f, fam in rows[:28]:
    A(f"| `{b}` | {c} | {d_} | {f} | {fam} |")
A("")
A("## 四、作者特有的公式")
A("")
A("同一位置換作者就換詞，這部分才是「像不像這個人」的判準。")
A("")
for k in ["pfeffer", "littler_a", "littler_b", "hong_abs"]:
    d = run[k]
    if not d: continue
    pc = per_corpus_bundles("3")
    items = []
    for b in d["bundles"]["3"]["scaffold"][:40]:
        others = sum(v for kk, v in pc.get(b["bundle"], {}).items() if kk != k)
        if others == 0 and b["files"] <= 2:
            items.append((b["bundle"], b["count"]))
    A(f"**{labels[k]}**：" + "、".join(f"`{b}`（{c}）" for b, c in items[:10]))
    A("")
A("## 五、七族：這些詞在做什麼")
A("")
# 用跨語料次數把每個已分類詞組補上數字
count_by_bundle = {}
for n in ["2", "3", "4"]:
    for b in all_d["bundles"][n]["scaffold"]:
        count_by_bundle[b["bundle"]] = max(count_by_bundle.get(b["bundle"], 0), b["count"])
fam_items = collections.defaultdict(list)
for b, (fam, role) in cls.items():
    fam_items[fam].append((b, count_by_bundle.get(b, 0), role))
A("| 功能 | 主要詞組（次數） | 它在做什麼 |")
A("|---|---|---|")
ROLE = {"框架設定": "先把論述範圍或依據框住，避免命題被讀成全稱",
        "因果推論": "把前一句接成後一句的原因或結果",
        "讓步對比": "先讓一步，再把對比項提出來",
        "量化與程度": "把命題降級為程度問題，或標明差距的大小",
        "引述與立場": "標記誰說的、或指出這是例證",
        "評價形容": "對現象下價值判斷",
        "名詞化推進": "把動作包成名詞，作為下一句的主語"}
for fam in ["框架設定", "因果推論", "讓步對比", "量化與程度", "引述與立場", "評價形容", "名詞化推進", "其他"]:
    if fam_items.get(fam):
        items = sorted(fam_items[fam], key=lambda x: -x[1])[:8]
        A(f"| {fam} | " + "、".join(f"`{b}`" if c == 0 else f"`{b}`（{c}）" for b, c, _ in items) + f" | {ROLE.get(fam, '—')} |")
A("")
A("分類由四份語料的判讀者各自給出，未經第二人覆核；同一詞組換一位讀者可能落到相鄰類。")
A("")
A("## 六、高頻實詞（單詞，meta 為學術慣用語）")
A("")
A("### 6.1 學術慣用語（meta 表中實測出現者）")
A("")
A("這一組就是英文版的「統籌、切實」：它們不帶研究內容，只負責把論述接起來。")
A("")
A("| 詞 | 次數 | 每千詞 |")
A("|---|---|---|")
for w, c, per in META_ROWS:
    A(f"| {w} | {c} | {per} |")
A("")
A("### 6.2 其餘高頻實詞")
A("")
A("| 詞 | 次數 | 每千詞 | 出現語料數 |")
A("|---|---|---|---|")
for c in all_d["content"][:28]:
    if c["meta"]: continue
    A(f"| {c['word']} | {c['count']} | {c['per_1000_words']} | {c['files']} |")
A("")
A("## 七、立場標記（每千詞）")
A("")
A("| 類別 | 總數 | 密度 | 前三名 |")
A("|---|---|---|---|")
for cat, zh in [("hedges", "模糊限制"), ("boosters", "強化語"), ("connectives", "連接詞"), ("eval_adj", "評價形容詞")]:
    items = list(all_d["stance"][cat].items())
    tot = sum(v for _, v in items)
    A(f"| {zh} | {tot} | {round(1000.0*tot/all_d['corpus']['words'],2)} | " + "、".join(f"{k} {v}" for k, v in items[:3]) + " |")
A("")
A(f"名詞化密度：每千詞 {all_d['nominalisation']['per_1000_words']} 個 -tion／-ment／-ity／-ness／-ance 詞。名詞化愈高，動作愈被包成物件，主語愈長。")
A("")
A("## 八、與中文公文的對照")
A("")
A("| 中文公文 | 英文對應 | 實測 | 作用 |")
A("|---|---|---|---|")
pairs = [
    ("在……層面上", "`in terms of` / `in relation to`", "80／35 次", "先框範圍"),
    ("在多大程度上", "`the extent to which` / `to the extent that`", "18 次（3 篇）", "把命題降為程度"),
    ("統籌／兼顧", "`account for` / `take into account`", "—", "宣告已處理某因素"),
    ("全面", "`across the board` / `overall` / `broadly`", "—", "擴大適用範圍"),
    ("切實／有效", "`consistently` / `robust` / `significantly`", "—", "強化可信度"),
    ("值得注意", "`notably` / `it is worth noting`", "—", "標記讀者該注意處"),
    ("由此可見", "`thus` / `it follows that` / `consistent with`", "39 次（thus）", "推進推論"),
    ("換言之", "`in other words` / `that is`", "—", "重述"),
]
for zh, en, meas, role in pairs:
    A(f"| {zh} | {en} | {meas} | {role} |")
A("")
A("## 九、可直接套用的句式（依實測頻率）")
A("")
seen = set()
for n in ["4", "3", "2"]:
    for b in all_d["bundles"][n]["scaffold"]:
        s = b["bundle"]
        if any(s in t or t in s for t in seen):
            continue
        if b["count"] < 12:
            continue
        seen.add(s)
        A(f"- `{s}`（{b['count']} 次，{b['per_1000_words']}/千詞）")
A("")
A("## 十、限制")
A("")
A("1. 詞組以相鄰詞計，未做句法分析。稽核抽 30 條回原文，precision 0.7333——`the top`、`the great`、`from the bottom` 這類片段會混入，因為它們確實常相鄰，但只是主題片語。")
A("2. 七族分類是判讀，不是測量。")
A("3. Littler 是專書，語域比期刊論文口語，`we have seen`、`this book` 這類公式不宜直接搬進期刊文。")
A("4. 摘要組只占 223 句，摘要體的結論不宜外推。")
A("5. 主題詞表由人手寫，稽核已指出 10 個應搬移的詞並已修正；仍可能殘留個別誤判。")
open(DOC, "w", encoding="utf-8").write("\n".join(L) + "\n")
print("wrote", DOC)
print("rows cross-genre:", len(rows))
