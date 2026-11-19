# English figures

English counterparts of the Mermaid sources in `../`. Each `.mmd` here keeps the
node ids, the edge list, the layout direction and the `classDef` styling of its
Chinese original; only label text and the `%%` provenance comment are translated.
The structural equivalence was checked line by line with quoted labels replaced by
a placeholder, so the two files differ only where a label was translated.

| file | diagram type | corresponds to |
| --- | --- | --- |
| `01-argument.mmd` | flowchart TD | `../01-argument.mmd` — claim, two warrants, condition, policy move, conclusion, plus the dashed limitation node |
| `02-criterion.mmd` | flowchart LR | `../02-criterion.mmd` — the two conditions for counting a factor as having an effect |
| `03-fields.mmd` | mindmap | `../03-fields.mmd` — the fields behind each term |
| `04-thinking.mmd` | timeline | `../04-thinking.mmd` — how the line of thought developed, by clock time |

## Rendering

Both `.svg` and `.png` were produced by mermaid-cli, in the same palette the
Chinese set uses — which is not one palette but two, because the two diagram
types carry meaning differently:

| source | config | why |
| --- | --- | --- |
| `01-argument.mmd`, `02-criterion.mmd` | `mermaid.config.json` (theme `neutral`, `wrappingWidth` 420) | the flowchart reads off shape and edge direction; neutral keeps the dashed "not yet established" node the only dashed thing on the page |
| `03-fields.mmd`, `04-thinking.mmd` | `mermaid.default.config.json` (theme `default`) | the mindmap's branch colour and the timeline's period colour are the structure; the neutral theme renders both as greys and the eleven periods stop being distinguishable |

```bash
for f in 01-argument 02-criterion; do
  npx -y @mermaid-js/mermaid-cli -i "$f.mmd" -o "$f.svg" -c mermaid.config.json -q
  npx -y @mermaid-js/mermaid-cli -i "$f.mmd" -o "$f.png" -b white -c mermaid.config.json -s 2 -q
done
for f in 03-fields 04-thinking; do
  npx -y @mermaid-js/mermaid-cli -i "$f.mmd" -o "$f.svg" -c mermaid.default.config.json -q
  npx -y @mermaid-js/mermaid-cli -i "$f.mmd" -o "$f.png" -b white -c mermaid.default.config.json -s 2 -q
done
```

## Translation glosses

Explanatory notes only; none of these add a claim the Chinese source does not make.

| 中文 | English used | note |
| --- | --- | --- |
| 績優主義 | meritocratic worship | pejorative in the source: worship of performance that ignores objective constraints |
| 績效主義 | merit-based assessment | the neutral term; the source is explicit that this is not the object of criticism |
| 離鄉就學 | displaced student | a student who moved away from home to study |
| 在讀 | still enrolled | students neither graduated nor dropped out; excluded from the graduation-rate denominator |
| 各期成績分位數 | grade quantiles by term | first and second term, quantile groups computed within each term |
| 詞的用法 | terms in use | the root of the mindmap: how each term is defined and operated |
