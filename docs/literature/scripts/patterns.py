#!/usr/bin/env python3
"""sentence-pattern counter — 逐句語法要素統計

用法：python3 patterns.py <text-file> [--max-sentences N] [--json out.json]

輸入：純文字（可含檔首註記行，以 <!-- 或 # 開頭者會被略過）
輸出：JSON，含 corpus 統計與每個句式的 count / per_1000 / 範例句（最多 3 條）

設計原則：
- 句子切分以正則完成，先保護常見縮寫（et al., e.g., i.e., Fig., vs., U.S., pp., No.）
- 每個句式獨立計數；一句可同時命中多個句式（重疊是刻意保留，便於比較密度）
- 範例句一律回傳原文，不得改寫
"""
import json
import re
import sys

ABBR = ["et al", "e.g", "i.e", "Fig", "Figs", "vs", "U.S", "U.K", "pp", "No", "cf", "approx", "Dr", "Mr", "Ms", "St"]
SENT_END = re.compile(r"(?<=[.!?])[\"'”’)]*\s+(?=[A-Z0-9(\"“])")

def read_text(path):
    lines = []
    for ln in open(path, encoding="utf-8", errors="ignore"):
        if ln.startswith("<!--") or ln.startswith("# ") or ln.startswith("──"):
            continue
        lines.append(ln)
    return "".join(lines)

def split_sentences(text):
    t = text
    for i, a in enumerate(ABBR):
        t = t.replace(a + ".", a + "@@%d@@" % i)
    parts = SENT_END.split(t)
    for i, a in enumerate(ABBR):
        parts = [p.replace(a + "@@%d@@" % i, a + ".") for p in parts]
    out, seen = [], set()
    for p in parts:
        p = re.sub(r"\s+", " ", p).strip().replace("\x0c", " ")
        w = p.split()
        if len(w) < 6:                                   # 少於 6 詞者多為標題或殘片
            continue
        if re.match(r"^\d", p):                          # 頁碼／圖表編號開頭
            continue
        if re.match(r"^(?:Figure|Table|Fig\.|Plate|Source|Note)\b", p, re.I):
            continue
        if sum(ch.isdigit() for ch in p) > max(4, len(w) // 3):   # 表格殘片
            continue
        if p in seen:                                    # 重複的頁眉頁腳
            continue
        seen.add(p)
        out.append(p)
    return out

W = lambda s: s.split()

PATTERNS = [
    # (key, 中文名, 定義, 正則)
    ("passive_agentless", "被動句（無施事）",
     "be/get + 過去分詞，且句中無 by + 施事",
     r"\b(?:is|are|was|were|be|been|being|get|gets|got)\s+(?:\w+ly\s+)?(\w+ed|shown|given|made|taken|found|seen|held|drawn|known|built|used|done)\b"),
    ("passive_byagent", "被動句（帶 by 施事）",
     "被動結構 + by + 名詞短語",
     r"\b(?:is|are|was|were|be|been|being)\s+\w+(?:ed|en)\b[^.]{0,60}\bby\s+(?:the|a|an|their|his|her|its|our|these|those|students?|families|parents?|scholars?|researchers?|institutions?|[A-Z][a-z]+)\b"),
    ("copular", "SVC 系動詞句",
     "is/are/was/were/seems/remains/appears + 補語",
     r"\b(?:is|are|was|were|seems?|remains?|appears?|becomes?)\s+(?:a|an|the|not|more|less|also|still|however|thus|therefore|likely|unlikely|important|possible|clear|evident|consistent|necessary|difficult|unclear)\b"),
    ("existential", "存在句",
     "there is/are/there was/there has been",
     r"\bthere\s+(?:is|are|was|were|has\s+been|have\s+been|exists?|remains?)\b"),
    ("cleft", "分裂句／焦點句",
     "it is/was … that/who；what … is",
     r"\b(?:it\s+(?:is|was)\s+[^.]{0,60}\b(?:that|who|which)\b|what\s+\w+\s+(?:is|are|does)\b)"),
    ("conditional", "條件句",
     "if/unless/whether/were … to",
     r"\b(?:if|unless|whether|were\s+\w+\s+to)\b"),
    ("concessive", "讓步句",
     "although/though/while/even if/despite/in spite of",
     r"\b(?:although|though|while|whilst|even\s+if|even\s+though|despite|in\s+spite\s+of|notwithstanding)\b"),
    ("causal", "因果連結",
     "because/since/as a result/therefore/thus/hence/consequently",
     r"\b(?:because|since|as\s+a\s+result|therefore|thus|hence|consequently|accordingly|so\s+that)\b"),
    ("contrast", "對比連結",
     "whereas/rather than/in contrast/by comparison/on the other hand",
     r"\b(?:whereas|rather\s+than|in\s+contrast|by\s+comparison|on\s+the\s+other\s+hand|conversely|instead)\b"),
    ("relative", "關係子句",
     "which/that/who/whose/where 引導的修飾子句",
     r"\b(?:which|that|who|whom|whose|where)\s+\w+"),
    ("participle_phrase", "分詞短語",
     "句首或句中 -ing/-ed 短語作修飾",
     r"(?:^|,\s*)(\w+ing|\w+ed)\s+(?:the|a|an|this|these|those|its|their|his|her|our|some|many|most|few|all|both|such|more|less|by|in|from|to|with|for|as)\b"),
    ("nominal_subject", "名詞化主語（抽象名詞開句）",
     "句首為抽象名詞短語：The analysis / This finding / Evidence / Research / Data …",
     r"^(?:The|This|These|Such|Our|Their|Its|Recent|Previous|Prior|Existing|Growing|Widening|Research|Evidence|Data|Findings?|Results?|Studies|Scholars?|Analys[ie]s|Literature|Work|Policy|Inequality|Achievement|Attainment|Participation|Completion)\b[^.]{0,40}\b(?:shows?|suggests?|indicates?|finds?|reveals?|demonstrates?|argues?|documents?|confirms?|examines?|explores?|provides?|offers?|is|are|was|were|has|have|can|may|will)\b"),
    ("nominal_chain", "名詞串（N of N）",
     "of 串接兩層以上的名詞短語",
     r"\b\w+\s+of\s+(?:the\s+|a\s+|an\s+)?\w+\s+of\s+(?:the\s+|a\s+|an\s+)?\w+"),
    ("colon_expansion", "冒號展開",
     "冒號後列舉或解釋",
     r":\s"),
    ("dash_insert", "破折號插入",
     "em dash 或 en dash 插入語",
     r"—|–\s"),
    ("reporting_verb", "引述動詞",
     "argue/suggest/show/find/report/contend/claim/maintain/demonstrate/note/observe",
     r"\b(?:argues?|argued|suggests?|suggested|shows?|showed|shown|finds?|found|reports?|reported|contends?|contended|claims?|claimed|maintains?|maintained|demonstrates?|demonstrated|notes?|noted|observes?|observed|concludes?|concluded|proposes?|proposed)\b"),
    ("modal", "情態動詞",
     "may/might/can/could/should/must/would/ought",
     r"\b(?:may|might|can|could|should|must|would|ought)\b"),
    ("negation", "否定結構",
     "not/never/no/none/little/few/nor/without",
     r"\b(?:not|never|no|none|neither|nor|without|little|few|hardly|scarcely)\b"),
    ("quant_number", "數字與統計嵌入",
     "百分號、percent、n =、p <、倍數",
     r"\d+(?:\.\d+)?\s?(?:%|percent|percentage\s+points?)|\bn\s*=\s*\d|\bp\s*[<>=]\s*0?\.\d|\b\d+(?:\.\d+)?\s?(?:times|fold)\b"),
    ("compound_adj", "複合形容詞",
     "連字號複合修飾語（low-income, high-stakes, first-generation）",
     r"\b\w+-\w+(?:-\w+)?\b(?=\s+\w)"),
    ("fronted_adverb", "句首副詞／連接副詞",
     "However, Therefore, Moreover, In addition, Thus … 開句",
     r"^(?:However|Therefore|Thus|Moreover|Furthermore|Additionally|Consequently|Nevertheless|Nonetheless|Accordingly|Meanwhile|Instead|Similarly|Conversely|Importantly|Notably|Indeed|Overall|In\s+addition|In\s+contrast|By\s+contrast|On\s+the\s+other\s+hand|As\s+a\s+result|For\s+example|For\s+instance|In\s+particular)\b"),
    ("delexical_verb", "虛化動詞",
     "conduct/carry out/perform/provide/make use of/give rise to",
     r"\b(?:conduct(?:ed|s)?|carr(?:y|ies|ied)\s+out|perform(?:ed|s)?|provid(?:e|es|ed)|mak(?:e|es|ing)\s+use\s+of|giv(?:e|es|ing)\s+rise\s+to|tak(?:e|es|ing)\s+into\s+account)\b"),
    ("to_purpose", "不定式目的／評價",
     "to + 原形動詞（表目的或後置修飾）",
     r"\bto\s+(?:be|have|make|show|examine|explore|understand|address|reduce|increase|improve|ensure|provide|explain|test|assess|identify|measure|achieve|close)\b"),
    ("wh_clause", "wh-名詞子句",
     "how/what/why/whether 引導的子句作主語或賓語",
     r"\b(?:how|what|why|whether|where|when)\s+(?:the|a|an|this|these|it|they|students?|families|policy|social|class|wealth|income|education|educational)\b"),
    ("adjective_stacking", "形容詞堆疊（前置修飾 ≥2）",
     "名詞前兩個以上形容詞",
     r"\b(?:[\w-]+\s+){2}(?:social|economic|educational|academic|financial|structural|institutional|racial|ethnic|parental|family|class|income|wealth|higher|lower|public|private|elite|low|high)\b\s+\w+"),
    ("hedge", "模糊限制語",
     "may/might/possibly/likely/appear/suggest/tend/arguably/relatively",
     r"\b(?:possibly|likely|unlikely|appear(?:s|ed)?|suggest(?:s|ed)?|tend(?:s|ed)?|arguably|relatively|somewhat|largely|generally|often|typically|broadly)\b"),
    ("booster", "強化語",
     "clearly/indeed/particularly/significantly/substantially/strikingly/never",
     r"\b(?:clearly|indeed|particularly|significantly|substantially|strikingly|sharply|vastly|considerably|far\s+more|much\s+more|never|always|undoubtedly)\b"),
]

def count_patterns(sents):
    res = {}
    for key, zh, definition, rx in PATTERNS:
        cre = re.compile(rx, re.IGNORECASE | re.MULTILINE)
        hits = [s for s in sents if cre.search(s)]
        examples = hits[:3]
        res[key] = {"name": zh, "definition": definition, "count": len(hits),
                    "per_1000": round(1000.0 * len(hits) / max(1, len(sents)), 2),
                    "examples": examples}
    return res

def length_stats(sents):
    lens = [len(W(s)) for s in sents]
    if not lens:
        return {}
    lens_sorted = sorted(lens)
    def pct(p):
        k = max(0, min(len(lens_sorted) - 1, int(round(p / 100 * len(lens_sorted))) - 1))
        return lens_sorted[k]
    return {
        "sentences": len(lens),
        "words": sum(lens),
        "mean_words": round(sum(lens) / len(lens), 2),
        "median_words": pct(50),
        "p90_words": pct(90),
        "share_over_40w": round(100.0 * sum(1 for x in lens if x > 40) / len(lens), 2),
        "share_under_15w": round(100.0 * sum(1 for x in lens if x < 15) / len(lens), 2),
    }

def main():
    path = sys.argv[1]
    maxn = None
    out = None
    if "--max-sentences" in sys.argv:
        maxn = int(sys.argv[sys.argv.index("--max-sentences") + 1])
    start = 0
    if "--from" in sys.argv:
        start = int(sys.argv[sys.argv.index("--from") + 1])
    if "--to" in sys.argv:
        maxn = int(sys.argv[sys.argv.index("--to") + 1])
    if "--json" in sys.argv:
        out = sys.argv[sys.argv.index("--json") + 1]
    text = read_text(path)
    sents = split_sentences(text)
    sents = sents[start:maxn] if maxn else sents[start:]
    payload = {
        "file": path,
        "length": length_stats(sents),
        "patterns": count_patterns(sents),
    }
    js = json.dumps(payload, ensure_ascii=False, indent=1)
    if out:
        open(out, "w", encoding="utf-8").write(js)
        print("wrote", out, "| sentences:", payload["length"]["sentences"])
    else:
        print(js)

if __name__ == "__main__":
    main()
