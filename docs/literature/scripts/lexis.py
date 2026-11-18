#!/usr/bin/env python3
"""lexis.py — 高頻「常用詞」與慣用詞組統計（領域術語以外）

用法：
  python3 lexis.py --files a.txt b.txt [--label NAME] [--from N --to M] [--json out.json] [--top 40]

輸出 JSON：
  corpus      : 句數、詞數
  content     : 去掉功能詞與領域術語後的高頻詞（每千詞、出現於幾個語料）
  bundles     : 2/3/4 詞的慣用詞組（每千詞、出現在幾篇）
  stance      : hedges/boosters/connectives/評述形容詞/first-person 的計數
  nominalisation : -tion/-ment/-ity/-ness/-ance/-ence 結尾的詞密度
  domain_hits : 被排除的領域詞（供審核員檢查排除清單是否誤殺通用詞）

設計原則：一個腳本跑全部語料；詞組不跨句；所有比率以「每千詞」為分母。
"""
import argparse, json, re, sys, os, unicodedata

WORD = re.compile(r"(?<![0-9A-Za-z])[A-Za-z][A-Za-z'’\-]*")
SENT_SPLIT = re.compile(r"(?<=[.!?])[\"'”’)]*\s+(?=[A-Z0-9(\"“])")
ABBR = ["et al", "e.g", "i.e", "Fig", "Figs", "vs", "U.S", "U.K", "pp", "No", "cf", "approx", "Dr", "Mr", "Ms", "St", "p"]

STOP = set("""a about above after again against all also am an and any are as at be because been before being below
between both but by can could did do does doing down during each few for from further had has have having he her here
hers herself him himself his how i if in into is it its itself just me more most my myself no nor not now of off on once
only or other ought our ours ourselves out over own same she should so some such than that the their theirs them
themselves then there these they this those through to too under until up very was we were what when where which while
who whom why will with would you your yours yourself yourselves may might must shall upon within without across among
around because been being ever never always often still yet thus hence therefore however moreover furthermore
additionally consequently nevertheless nonetheless accordingly meanwhile instead similarly conversely importantly notably
indeed overall particularly significantly substantially clearly largely generally typically relatively somewhat
much many little less least well back even first second third one two three four five six seven eight nine ten
per cent percent among toward towards whether both either neither another other others such given whether""".split())

# 主題領域術語（教育／不平等研究）——要排除，否則表格只是在列研究對象
DOMAIN = set("""income wealth wealthy education educational attainment dropout dropouts graduation graduate graduates
college colleges university universities student students family families parental parents parent ses socioeconomic
class classes inequality inequalities equality gap gaps completion degree degrees tuition fee fees financial finance
aid scholarship scholarships enrollment enrolment enrol enrol enrolled higher achievement academic institution
institutions institutional school schools
neoliberal media women discourse political culture merit capitalism mumpreneur ladder
neoliberalism racialisation racialization entrepreneur entrepreneurial schooling policy policies cohort cohorts trend trends assets asset debt
debtor credential credentials mobility meritocracy meritocratic credential social economic background backgrounds
disparit disparities disadvantage disadvantaged advantage advantaged earnings wage wages labour labor market
occupational occupation occupations race racial ethnic ethnicity gender immigration immigrant inequality
persistence retention transfer admission admissions curriculum curricular semester semesters semester's grade grades
minority minorities poverty poor rich wealthier poorer low-income high-income white black hispanic asian
first-generation undergraduate undergraduates graduate postgraduate secondary primary tertiary k-12
capital cultural embodied institutionalized worth net points recession texas chicago accountability testing
test tests rate rates distribution effect effects decrease children child adults adult
high-stakes stakes quintile quintiles scores score teachers teacher classroom classrooms social
access points higher increases
united states american america britain british uk us usa europe european portugal portuguese spain spanish
income-based wealth-based attainment-based""".split())

# 學術慣用語（meta）：這些是「文體常用詞」，要保留並另列，正是公文那類詞的對應物
META = set("""study studies research researcher researchers finding findings result results evidence analysis
analyses analytic model models framework mechanism mechanisms process processes factor factors effect effects role
approach approaches perspective context data sample samples survey surveys measure measures estimate estimates
primary secondary tertiary
assess assessment examine examines examined explore explores explored investigate show shows showed shown find finds
found indicate indicates indicated suggest suggests suggested argue argues argued claim claims claimed report reports
reported observe observes observed document documents documented note notes noted conclude concludes concluded propose
proposes proposed consistent inconsistent robust significant insignificant strong weak large small substantial
considerable pattern patterns association associations relationship relationships difference differences change changes
increase decrease decline trend trends account accounts explain explains explanation implication implications
limitation limitations contribution contribution""".split())

HEDGES = ["may", "might", "could", "suggest", "suggests", "suggested", "appear", "appears", "likely", "unlikely",
          "possibly", "perhaps", "seem", "seems", "tend", "tends", "arguably", "relatively", "somewhat", "largely",
          "often", "typically", "generally", "broadly", "approximately", "about"]
BOOSTERS = ["clearly", "indeed", "particularly", "significantly", "substantially", "strikingly", "sharply", "vastly",
            "considerably", "undoubtedly", "certainly", "always", "never", "far", "much", "highly", "strongly",
            "crucial", "essential", "fundamental", "central", "key", "critical", "important", "remarkable"]
CONNECTIVES = ["however", "therefore", "thus", "hence", "moreover", "furthermore", "nevertheless", "nonetheless",
               "consequently", "accordingly", "meanwhile", "instead", "similarly", "conversely", "whereas",
               "although", "though", "while", "because", "since", "so", "yet", "also", "besides", "overall",
               "in addition", "in contrast", "by contrast", "on the other hand", "as a result", "for example",
               "for instance", "in particular", "in other words", "that is", "in short", "in sum"]
EVAL_ADJ = ["important", "significant", "crucial", "central", "key", "critical", "essential", "fundamental",
            "remarkable", "striking", "clear", "evident", "consistent", "substantial", "considerable", "marked",
            "pronounced", "persistent", "growing", "widening", "rising", "declining", "unequal", "uneven", "sharp"]

def read_text(path):
    out = []
    for ln in open(path, encoding="utf-8", errors="ignore"):
        if ln.startswith("<!--") or ln.startswith("# ") or ln.startswith("──"):
            continue
        out.append(ln)
    txt = "".join(out)
    for lig, rep in [("\ufb00","ff"),("\ufb01","fi"),("\ufb02","fl"),("\ufb03","ffi"),("\ufb04","ffl")]:
        txt = txt.replace(lig, rep)
    return unicodedata.normalize("NFKC", txt)

def split_sentences(text):
    t = text
    for i, a in enumerate(ABBR):
        t = t.replace(a + ".", a + "@@%d@@" % i)
    parts = SENT_SPLIT.split(t)
    for i, a in enumerate(ABBR):
        parts = [p.replace(a + "@@%d@@" % i, a + ".") for p in parts]
    keep = []
    for p in parts:
        p = re.sub(r"\s+", " ", p).strip().replace("\x0c", " ")
        w = p.split()
        if len(w) < 6:
            continue
        if re.match(r"^\d", p) or re.match(r"^(?:Figure|Table|Fig\.|Plate|Source|Note)\b", p, re.I):
            continue
        if sum(ch.isdigit() for ch in p) > max(4, len(w)//3):
            continue
        if re.search(r"(\bdoi\b|https?://|\.\.\.\.|\bpp?\.\s*\d|Reproduced courtesy|Open in a new tab|Press, \d{4})", p):
            continue
        if re.match(r"^[A-Z][a-z]+,\s+[A-Z]\.", p) or re.match(r"^[A-Z][a-z]+\s+[A-Z][a-z]+,", p):
            continue
        # 非英語殘片（Hong & Youngs 檔內含西班牙文摘要）
        if sum(1 for x in w if x.lower().strip(",.;:") in {"de","la","el","en","los","las","por","para","con","una","del","que","y"}) >= 3:
            continue
        keep.append(p)
    return keep

def is_domain(tok):
    """主題詞才算領域詞；META（學術慣用語）即使同時列在 DOMAIN 也保留。"""
    if tok in META or tok.rstrip("s") in META:
        return False
    return tok in DOMAIN or tok.rstrip("s") in DOMAIN

def tokenize(s):
    return [w.lower() for w in WORD.findall(s)]

def analyse(files, top=40, lo=None, hi=None, min_count=3):
    ARTIFACT = re.compile(r"^[a-z]$|\d|^(?:et|al|e|g|pp|cf|vs|ie|eg|st)$")
    sents, per_file_tokens = [], {}
    for f in files:
        ss = split_sentences(read_text(f))
        if lo is not None or hi is not None:
            ss = ss[(lo or 0):(hi if hi is not None else len(ss))]
        sents += [(os.path.basename(f), s) for s in ss]
        per_file_tokens[os.path.basename(f)] = sum(len(tokenize(s)) for s in ss)

    toks = [(f, w) for f, s in sents for w in tokenize(s)]
    n_tok = len(toks)
    word_count = {}
    word_files = {}
    domain_count = {}
    for f, w in toks:
        word_count[w] = word_count.get(w, 0) + 1
        word_files.setdefault(w, set()).add(f)
        if is_domain(w):
            domain_count[w] = domain_count.get(w, 0) + 1

    content = []
    for w, c in word_count.items():
        if len(w) < 3 or w in STOP or is_domain(w) or w.isdigit() or ARTIFACT.match(w):
            continue
        content.append({"word": w, "count": c, "per_1000_words": round(1000.0*c/n_tok, 3),
                        "files": len(word_files[w]), "meta": (w in META) or (w.rstrip("s") in META)})
    content.sort(key=lambda x: (-x["count"], x["word"]))
    content = [x for x in content if x["count"] >= 3][:top]

    bundles = {}
    for n in (2, 3, 4):
        cnt, files_of, ex = {}, {}, {}
        for f, s in sents:
            ws = tokenize(s)
            for i in range(len(ws) - n + 1):
                g = ws[i:i+n]
                if all(w in STOP for w in g):
                    continue
                key = " ".join(g)
                cnt[key] = cnt.get(key, 0) + 1
                files_of.setdefault(key, set()).add(f)
                ex.setdefault(key, s)
        rows = [{"bundle": k, "count": v, "per_1000_words": round(1000.0*v/n_tok, 3),
                 "files": len(files_of[k]), "example": ex[k],
                 "kind": "topic" if any(is_domain(w) for w in k.split()) else "scaffold"}
                for k, v in cnt.items() if v >= min_count and not ARTIFACT.search(k.split()[0])]
        rows.sort(key=lambda x: (-x["count"], x["bundle"]))
        bundles[n] = {"scaffold": [r for r in rows if r["kind"] == "scaffold"][:top],
                      "topic": [r for r in rows if r["kind"] == "topic"][:top]}

    text_l = [s.lower() for _, s in sents]
    stance = {}
    for name, lst in [("hedges", HEDGES), ("boosters", BOOSTERS), ("connectives", CONNECTIVES), ("eval_adj", EVAL_ADJ)]:
        d = {}
        for term in lst:
            c = sum(len(re.findall(r"\b" + re.escape(term) + r"\b", t)) for t in text_l)
            if c:
                d[term] = c
        stance[name] = dict(sorted(d.items(), key=lambda kv: -kv[1]))

    nom = {}
    for w, c in word_count.items():
        if re.search(r"(tion|ment|ity|ness|ance|ence)s?$", w) and len(w) > 6:
            nom[w] = c
    nom_tokens = sum(nom.values())

    return {
        "files": [os.path.basename(f) for f in files],
        "corpus": {"sentences": len(sents), "words": n_tok,
                   "per_file_words": per_file_tokens,
                   "mean_words_per_sentence": round(n_tok/max(1, len(sents)), 2)},
        "content": content,
        "bundles": bundles, "min_count": min_count,
        "stance": stance,
        "nominalisation": {"tokens": nom_tokens, "per_1000_words": round(1000.0*nom_tokens/n_tok, 2),
                           "top": dict(sorted(nom.items(), key=lambda kv: -kv[1])[:20])},
        "domain_hits": dict(sorted(domain_count.items(), key=lambda kv: -kv[1])[:40]),
    }

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--files", nargs="+", required=True)
    ap.add_argument("--from", dest="lo", type=int, default=None)
    ap.add_argument("--to", dest="hi", type=int, default=None)
    ap.add_argument("--top", type=int, default=40)
    ap.add_argument("--min-count", dest="min_count", type=int, default=3,
                    help="詞組最低出現次數（小語料，例如六篇摘要合併，可設 2）")
    ap.add_argument("--json", default=None)
    a = ap.parse_args()
    res = analyse(a.files, top=a.top, lo=a.lo, hi=a.hi, min_count=a.min_count)
    js = json.dumps(res, ensure_ascii=False, indent=1)
    if a.json:
        open(a.json, "w", encoding="utf-8").write(js)
        print("wrote", a.json, "| sentences", res["corpus"]["sentences"], "| words", res["corpus"]["words"])
    else:
        print(js)

if __name__ == "__main__":
    main()
