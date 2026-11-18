# 翻譯標準與句式轉換

本文件定兩件事：英文學術術語譯成中文的**標準**，以及英文常用句式轉成中文句子的**程序**。`glossary.md` 是詞條清單，本文件是規則；詞條有爭議時以規則裁決。

---

# 甲部　英文學術術語的中譯標準

## A1　單義雙向

一個英文術語只對應一個中文詞，一個中文詞只回譯成同一個英文術語。出現同義異形，即為錯字，不是風格。

判準：任取一句，把中文回譯，若得到與原文不同的英文詞，該譯法不成立。

## A2　首見附原文，之後只用中文

格式：中文（English）。第二次起不再附註，也不用雙語並列。英文稿相反：首見不附中文。

例外：欄位名、程式名、統計符號終身保留原文，見 A5。

## A3　詞性對應

名詞譯名詞，動詞譯動詞，形容詞譯形容詞。英文用名詞化（nominalisation），中文優先還原為動詞；只有當它作為下一句的主語時才保留名詞。

| 英文 | 錯譯 | 正譯 |
|---|---|---|
| the growth of wealth inequality | 財富不平等的增長 | 財富不平等擴大 |
| the assessment of X | X 的評估 | 評估 X |
| the persistence of the gap | 差距的持續性 | 差距持續存在 |

## A4　複合術語的層級

修飾語在前，中心詞在後，由大到小。連續兩層以上的修飾不加兩個「的」。

| 英文 | 正譯 | 錯譯 |
|---|---|---|
| parental education | 父母學歷 | 父母的教育程度 |
| educational attainment | 學歷完成程度 | 教育成就 |
| the wealth gap in college graduation | 大學畢業率的財富差距 | 財富差距在大學畢業 |
| higher education participation | 高等教育參與率 | 高等教育的參與 |

## A5　不可譯項

四類終身保留原文，任何情況不譯：

1. 欄位與值：`Target`、`Scholarship holder`、`Tuition fees up to date`、`Debtor`、`pass2`、`avg_grade`
2. 程式與檔案：`programs/R/*.R`、`output/tables/*.csv`
3. 統計符號：R²、ΔR²、χ²、ρ、p、OR、CI
4. 人名、機構、專有制度：Bourdieu、Pfeffer、UCI、polytechnic

## A6　抽象名詞落地

以 -tion／-ment／-ity／-ness／-ance 結尾的詞，中文須回答「誰對誰做了什麼」；答不出時，改寫成具體動詞短語。

| 英文 | 錯譯 | 正譯 |
|---|---|---|
| operationalisation | 操作 | 操作化（把概念轉成欄位） |
| measurement | 測量 | 量度（含量度方式與限制） |
| identification | 識別 | 識別策略 |
| endogeneity | 內生 | 內生性（並說明來源） |

## A7　範疇對等

不升級，也不降級。四組最常犯：

| 英文 | 不可譯為 | 理由 |
|---|---|---|
| association | 影響、因果 | 無識別策略 |
| correlation | 關聯 | 只適用 r 與 ρ |
| percentage point | 百分比 | 差額與比率之別 |
| rate | 比例 | 分母不同 |

## A8　詞義以領域用法為準

不以詞典首義。以下六個詞在詞典與本領域的差距最大：

| 英文 | 領域義（正） | 詞典首義（錯） |
|---|---|---|
| attainment | 學歷完成程度 | 成就 |
| persistence | 在學持續 | 堅持 |
| retention | 留校續讀 | 保留 |
| credential | 學歷憑證 | 證書 |
| privilege | 不勞而得的優勢 | 特權 |
| selection | 選拔 | 選擇 |

## A9　不造新詞

既有譯法可用則不造詞。必須造詞時，同段給定義句，並在 `glossary.md` 建條目。未建條目的新詞不得進正文。

## A10　一詞多義：以定義句切割

同一英文詞承擔兩義時，中文不能發明兩個詞硬分——須在首見處寫定義句，之後沿用。

本專案的唯一實例：`meritocracy` 在英文同時指制度與意識形態。中文稿仍用「績優主義」一詞，英文稿須在第一段寫明本研究的定義（對績效的崇拜，忽略客觀約束），此後一律指該義。

## A11　錯譯四型（自查用）

| 型 | 表現 | 例 |
|---|---|---|
| 詞典首義錯配 | 取了詞典第一義 | attainment → 成就 |
| 範疇升級 | 把關聯譯成因果 | association → 影響 |
| 過度歸化 | 用中文既有貶義詞套上去 | meritocracy → 精英主義；privilege → 特權 |
| 逐字直譯 | 保留英文語序與虛詞 | in terms of → 在條款上；net of → 淨的 |

---

# 乙部　常用句式的轉換方式

## B0　七步程序

每一句照此順序處理，不跳步。

1. **找主幹**：主詞＋限定動詞＋受詞，先寫成最短中文句。
2. **還原名詞化**：動詞化的名詞改回動詞，補出主詞。
3. **補施事**：被動句問「誰做的」；答不出時，判斷是否屬本研究操作句（是則可留無施事）。
4. **處置後置修飾**：關係子句與介詞片語按 R6 分流。
5. **調資訊順序**：英文重心在句末，中文重心在句首的前置成分；把結論提前。
6. **檢查否定**：每個否定詞都要有否定對象，沒有則改陳述句。
7. **檢查主張數**：一句一個主張；兩個則拆。

## B1　十五條轉換規則

| # | 英文形 | 轉換方式 | 語料實例 → 中文 |
|---|---|---|---|
| R1 | the extent to which A affects B | 不用「……的程度」開頭。改「A 在多大程度上 [動] B」，或「A 對 B 的作用有多大」 | `documents the extent to which these changes can be accounted for by changes in the distribution of family wealth` → 記錄了家庭財富分佈的變動能在多大程度上解釋這些變化 |
| R2 | to the extent that | 就……而言／只要…… | `may be a less hopeful sign to the extent that it may be driven by` → 就未必是可喜的進展，因為它可能由……推動 |
| R3 | in terms of | 接度量→「以……計」；接面向→「就……而言」；接比較→「在……上」 | `diverge more from each other in terms of their family wealth` → 在家庭財富上彼此差距更大 |
| R4 | the growth／rise／decline of X | 動詞化，補時間或範圍 | `The rise of asset nonownership and indebtedness … is an important driver of this increase` → 無資產與負債比例的上升，是這一擴大的重要成因 |
| R5 | 無施事被動 | 三種處置：補施事／改主動／保留（僅限本研究操作句） | `Reported standard errors are robust and adjusted for clustering` → 本表報告的標準誤已按群集調整 |
| R6 | which／who 關係子句 | 修飾語 ≤ 12 字可前置加「的」；超過則拆句，which 改「這」或重述名詞 | `children who grow up in a context of particularly extreme wealth inequality` → 在財富極度不均的環境中成長的兒童（12 字內，前置） |
| R7 | 冒號展開 | 冒號前先給數目：「分為三項：」。冒號後各項須同構 | `this direct inference is neither empirically nor conceptually valid: wealth is distinct from income, its association ...` → 這個推論在實證與概念上都不成立：財富與收入不是一回事，兩者與教育的關聯⋯⋯ |
| R8 | may／might + suggest／indicate | 只留一層模糊：用「可能」或「大致可說」，不叠加 | `these analyses also suggest that` → 分析結果亦指向 |
| R9 | significantly／substantially | 統計顯著譯「顯著」；量級譯「大幅」並附本報告自己的數字，不沿用原文形容詞 | 原文的 significantly higher 不譯成「顯著地高」；改寫為「高 X 個百分點（p = …）」，X 取本表數值 |
| R10 | it is X that Y | 「Y 的是 X」或「X 才是 Y 的……」 | `it is certainly the case that the modal college graduate comes from a household with significant net worth` → 典型的畢業生確實來自淨資產可觀的家庭 |
| R11 | not X but Y | 中文須有明確否定對象，且 X 與 Y 同範疇 | `not only siblings but also cousins` → 不只是兄弟姊妹，還包括表親 |
| R12 | X rather than Y | 「而非 Y」置於句末，全句只出現一次 | `population associations between wealth and education rather than the educational pathways of children of a small wealth elite` → 本文處理的是財富與教育在母體層面的關聯，而非少數富裕精英子女的求學路徑 |
| R13 | at the same time | 並存用「同時」；讓步用「雖……仍」。兩義不可共用一個詞 | `At the same time, wealthier households were less affected by the recession` → 同時，富裕家庭受衰退的衝擊較小 |
| R14 | based on | 「依」「以……為據」。避免三段連續「基於」 | `based on newly available data from the PSID` → 依 PSID 的新資料 |
| R15 | net of／controlling for | 「扣除……之後」／「控制……（並指明控制的是哪一層）」 | `conditional on income` → 在收入既定的條件下 |

## B2　拆句的三個判準

符合任一條即拆，拆點落在連接詞或逗號：

1. 中文譯句超過 45 字。
2. 修飾層數超過一層（一個名詞前有兩個以上的「的」）。
3. 一句出現兩個以上可獨立成立的謂語。

## B3　被動的保留範圍

只在本研究的三類句子保留無施事被動：資料來源句、操作定義句、統計程序句。論證句一律主動——論證句的被動會讓主體消失，而主體消失正是本報告要批評的那種寫法。

## B4　轉換後檢查（十條）

1. 每個否定詞都有否定對象。
2. 每段首句是該段的主張（topic sentence）。
3. 每段可寫成 A→B→C→D，缺一環即改寫。
4. 中文回譯後與原文同詞（A1）。
5. 沒有「基於」連用三次。
6. 沒有「進行＋名詞」（進行分析→分析）。
7. 沒有無主語長句。
8. 術語首見已附原文，第二次起未再附。
9. 數字四位有效數字，金額整數，百分點不寫成百分比。
10. 統計顯著與實質顯著分開陳述。

---

# 丙部　完整示範

英文（Pfeffer 2018，三句連續）：

> It also documents the extent to which these changes in wealth gaps in education can be accounted for solely by changes in the distribution of family wealth. The rise of asset nonownership and indebtedness (zero and negative net worth) is an important driver of this increase. At the same time, wealthier households were less affected by the recession because their wealth is typically less concentrated in housing …

三句皆為原文連續句，第三句截斷處以……標示。

按 B0 七步處理：

| 步 | 處置 |
|---|---|
| 1 主幹 | 第一句主幹是 documents＋extent；第二句是 rise＋is driver；第三句是 households＋were less affected |
| 2 名詞化 | the rise of asset nonownership → 無資產比例上升；indebtedness → 負債比例上升 |
| 3 施事 | 第一句施事是本文（documents）；第三句施事是衰退（被動改主動） |
| 4 後置修飾 | changes in the distribution of family wealth 為一層，可前置 |
| 5 順序 | 第一句結論提前：先講「只能由財富分佈解釋」 |
| 6 否定 | 無否定詞，不需處理 |
| 7 主張數 | 第一句一個主張；第二、三句各一個 |

中文：

> 本文同時記錄這些教育財富差距的變化在多大程度上只能由家庭財富分佈的變動解釋。無資產與負債比例的上升是這一擴大的重要成因。同時，富裕家庭受衰退的衝擊較小。

三句皆可回譯為原詞（A1）；第一句保留了「多大程度」而非「……的程度」（R1）；第三句「同時」只表並存，未偷渡讓步（R13）。

---

# 丁部　與 `glossary.md` 的分工

- `glossary.md`：詞條。查「這個詞該譯什麼」。
- 本文件：規則。查「為什麼這樣譯」「這句話怎麼轉」。

衝突時以本文件裁決，並回頭修 `glossary.md`，不兩處並存。
