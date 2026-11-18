# 高頻常用詞：這批論證文章反覆使用的非術語詞彙

中文公文有「全面、深化、統籌、切實」。英文學術論證文章同樣有一套慣用詞，但它們主要以**詞組**的形式出現——單看單詞會漏掉最有特徵的部分。本文件量的是這一層：除去研究主題的術語之後，文章反覆用來搭架子、降調、加碼、引述的詞與詞組。

語料 3003 句、87258 詞，全部數字來自同一次執行（`docs/literature/scripts/lexis.py`）。

## 一、方法與三個決定

1. **三層詞彙分開**：功能詞（the、of、and）不進單詞表但保留在詞組裡；**主題領域術語**（income、attainment、dropout、college、neoliberal…）整層排除；**學術慣用語**（study、evidence、finding、significant、effect…）保留並標記 meta——後者才是本文要量的。若把 meta 詞也排除，剩下的就只有研究對象的專有名詞。
2. **詞組以句子為界，只留出現 ≥ 3 次的 2 至 4 詞組合**，並分 scaffold（框架型，本文主體）與 topic（含主題詞，另存）。
3. **每千詞為分母**。各語料長度差一個數量級，用原始次數會讓 38,000 詞的專書壓過 9,000 詞的論文。

清理：連字（ﬀ／ﬁ）先做 NFKC 正規化，否則會得到 `erent`、`cant`、`eld`、`ects` 這類殘字；參考書目、圖說樣板（Reproduced courtesy of）、網頁殘字（Open in a new tab）、目錄點線一律濾除。

## 二、語料

| 語料 | 句數 | 詞數 | 平均句長 |
|---|---|---|---|
| Pfeffer 2018 | 264 | 9030 | 34.2 |
| Hong & Youngs＋摘要 | 223 | 6252 | 28.04 |
| Littler 前段 | 1300 | 38077 | 29.29 |
| Littler 後段 | 1216 | 33899 | 27.88 |
| **合計** | **3003** | **87258** | **29.06** |

## 三、跨語料的通用公式（出現於 3 篇以上）

這一組是文體的骨架：任何人寫這類論證都會用到，與作者風格無關。

| 詞組 | 總次數 | 每千詞 | 出現語料數 | 功能（判讀） |
|---|---|---|---|---|
| `for example` | 60 | 0.688 | 4 | 引述與立場 |
| `rather than` | 44 | 0.504 | 4 | 讓步對比 |
| `based on` | 40 | 0.458 | 4 | 框架設定 |
| `the extent` | 36 | 0.413 | 3 |  |
| `need to` | 34 | 0.39 | 3 |  |
| `effects of` | 28 | 0.321 | 3 |  |
| `number of` | 28 | 0.321 | 3 |  |
| `form of` | 27 | 0.309 | 3 |  |
| `in particular` | 26 | 0.298 | 3 |  |
| `work on` | 26 | 0.298 | 3 |  |
| `at the same time` | 25 | 0.287 | 3 | 讓步對比 |
| `able to` | 25 | 0.287 | 3 |  |
| `the way` | 25 | 0.287 | 4 |  |
| `the case` | 22 | 0.252 | 3 |  |
| `to make` | 22 | 0.252 | 3 |  |
| `lack of` | 20 | 0.229 | 3 |  |
| `the extent to which` | 18 | 0.206 | 3 | 量化與程度 |
| `the effects of` | 15 | 0.172 | 3 |  |
| `in the form of` | 12 | 0.138 | 3 |  |
| `as a result` | 10 | 0.115 | 3 |  |
| `in the early` | 10 | 0.115 | 3 |  |
| `on the other hand` | 7 | 0.08 | 3 |  |
| `to the extent that` | 7 | 0.08 | 3 |  |

## 四、作者特有的公式

同一位置換作者就換詞，這部分才是「像不像這個人」的判準。

**Pfeffer 2018**：`from the top`（10）、`born in the`（9）、`changes in the`（6）、`from the bottom`（6）、`online resource section`（6）、`the growth of`（6）、`the increase in`（6）、`based on the`（5）、`from the middle`（5）、`in the top`（5）

**Littler 前段**：`rise of the`（18）、`level playing field`（15）、`the basis of`（14）、`on the basis`（13）、`the global north`（10）、`the meaning of`（10）、`in favour of`（9）、`in the global`（9）、`of the term`（9）、`the civil service`（9）

**Littler 後段**：`we have seen`（12）、`part of the`（9）、`the issue of`（9）、`an array of`（8）、`figure of the`（8）、`the damonsplaining incident`（8）、`as we saw`（7）、`needs to be`（7）、`part of a`（7）、`the gendering of`（7）

**Hong & Youngs＋摘要**：`as a result`（7）、`more likely to`（5）、`opportunities to acquire`（5）、`reading and mathematics`（5）、`seemed to have`（5）、`with regard to`（5）、`argued that the`（4）、`grissmer and flanagan`（4）、`had to meet`（4）、`in the u`（4）

## 五、七族：這些詞在做什麼

| 功能 | 主要詞組（次數） | 它在做什麼 |
|---|---|---|
| 框架設定 | `in terms of`（80）、`for instance`（49）、`based on`（40）、`in relation to`（35）、`in chapter`（34）、`this book`（33）、`part of the`（13）、`the meaning of`（11） | 先把論述範圍或依據框住，避免命題被讀成全稱 |
| 因果推論 | `in order to`（25）、`in the process`（16）、`on the basis of`（12）、`related to`、`account for` | 把前一句接成後一句的原因或結果 |
| 讓步對比 | `rather than`（44）、`the same time`（27）、`at the same time`（25）、`in favour of`（14）、`not only` | 先讓一步，再把對比項提出來 |
| 量化與程度 | `range of`（47）、`the extent to which`（18）、`by percentage`、`an array of` | 把命題降級為程度問題，或標明差距的大小 |
| 引述與立場 | `for example`（60）、`the term`（25）、`the idea that`（18）、`we have seen`（16）、`in other words`（12）、`needs to be`（12）、`as we saw`（11）、`we need to`（11） | 標記誰說的、或指出這是例證 |
| 評價形容 | `hard work`（30）、`level playing field`（18）、`the importance of`（13）、`the problems of` | 對現象下價值判斷 |
| 名詞化推進 | `forms of`（66）、`the idea of`（57）、`the rise of`（27）、`changes in the`、`the growth of`、`the assessment of`、`notion of`、`the racialisation of` | 把動作包成名詞，作為下一句的主語 |
| 其他 | `the top`（60）、`at the top`（17）、`the top of the`（15）、`from the top`（10）、`born in the`（10）、`the great`、`home values`、`the wealthiest` | — |

分類由四份語料的判讀者各自給出，未經第二人覆核；同一詞組換一位讀者可能落到相鄰類。

## 六、高頻實詞（單詞，meta 為學術慣用語）

### 6.1 學術慣用語（meta 表中實測出現者）

這一組就是英文版的「統籌、切實」：它們不帶研究內容，只負責把論述接起來。

| 詞 | 次數 | 每千詞 |
|---|---|---|
| effects | 51 | 0.584 |
| studies | 51 | 0.584 |
| show | 50 | 0.573 |
| context | 48 | 0.55 |
| research | 46 | 0.527 |
| analysis | 43 | 0.493 |
| increase | 42 | 0.481 |
| process | 42 | 0.481 |
| significant | 39 | 0.447 |
| model | 38 | 0.435 |
| argued | 36 | 0.413 |
| changes | 33 | 0.378 |
| trends | 31 | 0.355 |
| study | 31 | 0.355 |
| change | 31 | 0.355 |
| role | 30 | 0.344 |
| argues | 29 | 0.332 |
| large | 26 | 0.298 |
| shows | 26 | 0.298 |
| data | 25 | 0.287 |
| analyses | 21 | 0.241 |
| argue | 21 | 0.241 |

### 6.2 其餘高頻實詞

| 詞 | 次數 | 每千詞 | 出現語料數 |
|---|---|---|---|
| work | 252 | 2.888 | 4 |
| new | 194 | 2.223 | 4 |
| people | 156 | 1.788 | 2 |
| terms | 122 | 1.398 | 2 |
| whilst | 116 | 1.329 | 1 |
| chapter | 114 | 1.306 | 1 |
| different | 105 | 1.203 | 3 |
| like | 105 | 1.203 | 2 |
| idea | 104 | 1.192 | 1 |
| power | 99 | 1.135 | 3 |
| book | 91 | 1.043 | 1 |
| forms | 91 | 1.043 | 2 |
| time | 91 | 1.043 | 3 |
| example | 87 | 0.997 | 4 |
| popular | 83 | 0.951 | 1 |
| society | 83 | 0.951 | 5 |
| term | 77 | 0.882 | 1 |
| hard | 74 | 0.848 | 2 |
| see | 74 | 0.848 | 2 |
| public | 73 | 0.837 | 4 |
| working | 70 | 0.802 | 1 |
| top | 69 | 0.791 | 2 |
| become | 68 | 0.779 | 3 |
| contemporary | 68 | 0.779 | 1 |
| particular | 66 | 0.756 | 3 |
| rise | 66 | 0.756 | 2 |
| used | 66 | 0.756 | 2 |
| success | 64 | 0.733 | 6 |

## 七、立場標記（每千詞）

| 類別 | 總數 | 密度 | 前三名 |
|---|---|---|---|
| 模糊限制 | 557 | 6.38 | about 119、may 111、often 78 |
| 強化語 | 499 | 5.72 | particularly 66、key 63、important 60 |
| 連接詞 | 1061 | 12.16 | also 223、so 102、because 76 |
| 評價形容詞 | 401 | 4.6 | key 63、important 60、significant 38 |

名詞化密度：每千詞 42.59 個 -tion／-ment／-ity／-ness／-ance 詞。名詞化愈高，動作愈被包成物件，主語愈長。

## 八、與中文公文的對照

| 中文公文 | 英文對應 | 實測 | 作用 |
|---|---|---|---|
| 在……層面上 | `in terms of` / `in relation to` | 80／35 次 | 先框範圍 |
| 在多大程度上 | `the extent to which` / `to the extent that` | 18 次（3 篇） | 把命題降為程度 |
| 統籌／兼顧 | `account for` / `take into account` | — | 宣告已處理某因素 |
| 全面 | `across the board` / `overall` / `broadly` | — | 擴大適用範圍 |
| 切實／有效 | `consistently` / `robust` / `significantly` | — | 強化可信度 |
| 值得注意 | `notably` / `it is worth noting` | — | 標記讀者該注意處 |
| 由此可見 | `thus` / `it follows that` / `consistent with` | 39 次（thus） | 推進推論 |
| 換言之 | `in other words` / `that is` | — | 重述 |

## 九、可直接套用的句式（依實測頻率）

- `at the same time`（25 次，0.287/千詞）
- `the rise of the`（20 次，0.229/千詞）
- `the extent to which`（18 次，0.206/千詞）
- `the top of the`（15 次，0.172/千詞）
- `as we have seen`（14 次，0.16/千詞）
- `in the form of`（12 次，0.138/千詞）
- `on the basis of`（12 次，0.138/千詞）
- `in terms of`（80 次，0.917/千詞）
- `the idea of`（57 次，0.653/千詞）
- `in relation to`（35 次，0.401/千詞）
- `in order to`（25 次，0.287/千詞）
- `level playing field`（18 次，0.206/千詞）
- `the idea that`（18 次，0.206/千詞）
- `at the top`（17 次，0.195/千詞）
- `in the process`（16 次，0.183/千詞）
- `idea of a`（15 次，0.172/千詞）
- `of the new`（15 次，0.172/千詞）
- `the effects of`（15 次，0.172/千詞）
- `the fact that`（15 次，0.172/千詞）
- `in favour of`（14 次，0.16/千詞）
- `to the top`（14 次，0.16/千詞）
- `part of the`（13 次，0.149/千詞）
- `the importance of`（13 次，0.149/千詞）
- `in other words`（12 次，0.138/千詞）
- `in the global`（12 次，0.138/千詞）
- `needs to be`（12 次，0.138/千詞）
- `over the past`（12 次，0.138/千詞）
- `the end of`（12 次，0.138/千詞）
- `forms of`（66 次，0.756/千詞）
- `for example`（60 次，0.688/千詞）
- `for instance`（49 次，0.562/千詞）
- `range of`（47 次，0.539/千詞）
- `rather than`（44 次，0.504/千詞）
- `based on`（40 次，0.458/千詞）
- `popular parables`（36 次，0.413/千詞）
- `in chapter`（34 次，0.39/千詞）
- `need to`（34 次，0.39/千詞）
- `this book`（33 次，0.378/千詞）
- `use of`（31 次，0.355/千詞）
- `hard work`（30 次，0.344/千詞）
- `work and`（29 次，0.332/千詞）
- `number of`（28 次，0.321/千詞）
- `of people`（27 次，0.309/千詞）
- `in particular`（26 次，0.298/千詞）
- `work on`（26 次，0.298/千詞）
- `able to`（25 次，0.287/千詞）
- `of course`（25 次，0.287/千詞）
- `project greenlight`（25 次，0.287/千詞）
- `put it`（25 次，0.287/千詞）
- `the term`（25 次，0.287/千詞）
- `the way`（25 次，0.287/千詞）
- `image of`（24 次，0.275/千詞）
- `argued that`（23 次，0.264/千詞）
- `nature of`（23 次，0.264/千詞）
- `of work`（23 次，0.264/千詞）
- `since the`（22 次，0.252/千詞）
- `the case`（22 次，0.252/千詞）
- `the word`（22 次，0.252/千詞）
- `to acquire`（22 次，0.252/千詞）
- `to make`（22 次，0.252/千詞）
- `just like`（21 次，0.241/千詞）
- `the contemporary`（21 次，0.241/千詞）
- `to consider`（21 次，0.241/千詞）
- `trends in`（21 次，0.241/千詞）
- `lack of`（20 次，0.229/千詞）
- `the book`（20 次，0.229/千詞）
- `the chapter`（20 次，0.229/千詞）

## 十、限制

1. 詞組以相鄰詞計，未做句法分析。稽核抽 30 條回原文，precision 0.7333——`the top`、`the great`、`from the bottom` 這類片段會混入，因為它們確實常相鄰，但只是主題片語。
2. 七族分類是判讀，不是測量。
3. Littler 是專書，語域比期刊論文口語，`we have seen`、`this book` 這類公式不宜直接搬進期刊文。
4. 摘要組只占 223 句，摘要體的結論不宜外推。
5. 主題詞表由人手寫，稽核已指出 10 個應搬移的詞並已修正；仍可能殘留個別誤判。
