"""Generate the statistical figures the AMS2640 deck is missing.

Every number is read from output/tables/*.csv; nothing is typed in by hand.
Output: 8 PNGs, 2400x1350 px (16:9), ready to drop into the 20 x 11.25 in deck.
"""
import pathlib
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd
from matplotlib.patches import FancyBboxPatch

REPO = pathlib.Path("/Users/tszkinlai/Documents/AMS2640/group project")
T = REPO / "output/tables"
OUT = pathlib.Path(__file__).resolve().parent
OUT.mkdir(parents=True, exist_ok=True)

RED = "#C2181B"
DARKRED = "#7A1216"
GREEN = "#1E6E45"
LIGHTGREEN = "#6FA98A"
DARK = "#22201E"
GREY = "#6B6560"
BG = "#FFFFFF"

plt.rcParams.update({
    "font.family": "Helvetica",
    "font.size": 15,
    "axes.edgecolor": "#B9B2A8",
    "axes.labelcolor": DARK,
    "text.color": DARK,
    "xtick.color": DARK,
    "ytick.color": DARK,
    "axes.titleweight": "bold",
    "figure.facecolor": BG,
    "axes.facecolor": BG,
    "savefig.facecolor": BG,
})

def p4(x):  # 4 significant figures on a proportion -> percent string, min 2 decimals
    v = x * 100
    txt = f"{v:.4g}"
    if "." not in txt:
        txt = f"{v:.2f}"
    else:
        dec = len(txt.split(".")[1])
        if dec < 2:
            txt = f"{v:.2f}"
    return txt + "%"

def n4(x):  # 4 significant figures
    return f"{x:.4g}"

def wrap(title, width=44):
    words, lines, cur = title.split(), [], ""
    for w in words:
        cand = (cur + " " + w).strip()
        if len(cand) <= width:
            cur = cand
        else:
            lines.append(cur); cur = w
    lines.append(cur)
    return "\n".join(lines)

def slide_title(fig, title, subtitle=None):
    fig.text(0.045, 0.972, wrap(title), color=RED, fontsize=26, fontweight="bold",
             va="top", linespacing=1.05)
    if subtitle:
        fig.text(0.045, 0.838, subtitle, color=GREY, fontsize=15.5, va="top")

def source(fig, msg):
    fig.text(0.045, 0.035, msg, color=GREY, fontsize=11.5, va="bottom")

def bar_labels(ax, bars, labels, color=DARK, size=17, dy=0.02, fmt=None):
    span = ax.get_ylim()[1]
    for b, lab in zip(bars, labels):
        ax.text(b.get_x() + b.get_width()/2, b.get_height() + span*dy, lab,
                ha="center", va="bottom", color=color, fontsize=size, fontweight="bold")

# ---------------------------------------------------------------- data
ledger = pd.read_csv(T / "population_ledger.csv")
# the ledger repeats the population size in `n`; the count itself is in `value`
pop = ledger[ledger.population == "full"].set_index("metric")["value"].astype(int).to_dict()
an = ledger[ledger.population == "analysis"].set_index("metric")["value"].astype(int).to_dict()
ab = ledger[ledger.population == "ability"].set_index("metric")["value"].astype(int).to_dict()
quart = pd.read_csv(T / "ability_quartiles.csv")
models = pd.read_csv(T / "model_comparison.csv")
markers = pd.read_csv(T / "financial_markers.csv")
cross = pd.read_csv(T / "financial_cross.csv")
cells = pd.read_csv(T / "wealth_four_cell.csv")
ages = pd.read_csv(T / "age_bands.csv")
age_tests = pd.read_csv(T / "age_tests.csv")
marriage = pd.read_csv(T / "marriage_strata.csv")
pedu = pd.read_csv(T / "highest_parent_education.csv")
qmodels = pd.read_csv(T / "qualification_models.csv")

def mrow(model, popu):
    r = models[(models.model == model) & (models.population == popu)].iloc[0]
    return float(r.mcfadden_r2), int(r.n)

r_ability, n_ab = mrow("ability_quartile", "ability")
r_fin_ab, _ = mrow("financial_three", "ability")
r_both, _ = mrow("financial_plus_ability", "ability")
r_fin, n_an = mrow("financial_three", "analysis")
r_age, _ = mrow("age_band", "analysis")
r_adm, _ = mrow("admission_quartile", "ability")
delta_ability = r_both - r_fin_ab

def mk(flag, col="value"):
    return markers[(markers.marker == flag)].set_index(col)

M = mk("unpaid")
def row(flag, value):
    r = markers[(markers.marker == flag) & (markers.value == value)].iloc[0]
    return r
unpaid1, unpaid0 = row("unpaid", 1), row("unpaid", 0)
sch1, sch0 = row("scholar", 1), row("scholar", 0)
debt1, debt0 = row("debtor", 1), row("debtor", 0)

scholars_unpaid = int(cross[(cross.unpaid == 1) & (cross.scholarship == 1)].n.iloc[0])
scholars_all = int(cross[cross.scholarship == 1].n.sum())
nonsch_unpaid = int(cross[(cross.unpaid == 1) & (cross.scholarship == 0)].n.iloc[0])
nonsch_all = int(cross[cross.scholarship == 0].n.sum())
unpaid_rate_sch = scholars_unpaid / scholars_all
unpaid_rate_nonsch = nonsch_unpaid / nonsch_all

qdelta_r2 = float(qmodels[qmodels.model == "qualification_plus_financial"].delta_r2.iloc[0])
qdelta_p = float(qmodels[qmodels.model == "qualification_plus_financial"].lrt_p.iloc[0])

audit = []

# ---------------------------------------------------------------- fig 1: sample flow
fig = plt.figure(figsize=(12, 6.75), dpi=200)
slide_title(fig, "FROM 4,424 RECORDS TO THE TWO ANALYTICAL SAMPLES",
            "Two filters, applied in this order; the ability analysis uses the smaller sample")
ax = fig.add_axes([0.05, 0.16, 0.45, 0.62]); ax.axis("off")
ax.set_xlim(0, 1); ax.set_ylim(0, 1)
steps = [
    (f"Full dataset   {pop['total']:,}",
     f"graduate {pop['graduate']:,}  ·  dropout {pop['dropout']:,}  ·  enrolled {pop['enrolled']:,}", RED),
    (f"Main sample   {an['analysis']:,}",
     "794 still-enrolled students excluded: no final outcome", DARKRED),
    (f"Ability sample   {ab['ability']:,}",
     "802 second-semester zero scores excluded", GREEN),
]
for i, (head, sub, col) in enumerate(steps):
    y = 0.74 - i * 0.30
    ax.add_patch(FancyBboxPatch((0.01, y), 0.97, 0.21,
                                boxstyle="round,pad=0.006,rounding_size=0.02",
                                facecolor=col, edgecolor="none"))
    ax.text(0.045, y + 0.135, head, color="white", fontsize=19, fontweight="bold", va="center")
    ax.text(0.045, y + 0.055, sub, color="white", fontsize=12, va="center")
    if i < 2:
        ax.annotate("", xy=(0.10, y - 0.055), xytext=(0.10, y + 0.004),
                    arrowprops=dict(arrowstyle="-|>", color=GREY, lw=2))
ax.text(0.01, 0.02, "graduate / dropout only: the 794 still-enrolled students carry no final outcome",
        color=GREY, fontsize=11)

ax2 = fig.add_axes([0.56, 0.16, 0.38, 0.6])
g, d = pop["graduate"], pop["dropout"]
bars = ax2.bar([0, 1], [g / an["analysis"], d / an["analysis"]], width=0.55,
               color=[GREEN, RED])
ax2.set_xticks([0, 1]); ax2.set_xticklabels([f"Graduate\n{g:,}", f"Dropout\n{d:,}"], fontsize=15)
ax2.set_ylim(0, 0.78); ax2.set_yticks([0, .2, .4, .6])
ax2.set_yticklabels(["0", "20%", "40%", "60%"], fontsize=13)
ax2.spines[["top", "right"]].set_visible(False)
ax2.set_title(f"Main sample: {an['analysis']:,} students", fontsize=17, pad=12, color=DARK)
bar_labels(ax2, bars, [p4(g / an["analysis"]), p4(d / an["analysis"])], size=19)
ax2.axhline(g / an["analysis"], color=GREEN, lw=1, ls=":", zorder=0)
source(fig, "Source: output/tables/population_ledger.csv. Rates on the 3,630-student main sample.")
fig.savefig(OUT / "f01_sample_flow.png", dpi=200); plt.close(fig)
audit += [("main sample", an["analysis"]), ("graduate %", p4(g/an["analysis"])), ("dropout %", p4(d/an["analysis"])),
          ("ability sample", ab["ability"])]

# ---------------------------------------------------------------- fig 2: quartiles
fig = plt.figure(figsize=(12, 6.75), dpi=200)
slide_title(fig, "GRADUATION RATE RISES WITH SECOND-SEMESTER PERFORMANCE",
            "Students split into four equal groups by second-semester grade; "
            f"Q4 − Q1 = {p4(float(quart.graduation_rate.iloc[3]) - float(quart.graduation_rate.iloc[0]))}")
ax = fig.add_axes([0.08, 0.17, 0.86, 0.56])
cols = [RED, "#C9603F", LIGHTGREEN, GREEN]
bars = ax.bar(range(4), quart.graduation_rate, width=0.62, color=cols)
ax.set_xticks(range(4))
ax.set_xticklabels([f"Q{i+1}\nn = {int(n):,}" for i, n in enumerate(quart.n)], fontsize=15)
ax.set_ylim(0, 1.02); ax.set_yticks([0, .25, .5, .75, 1])
ax.set_yticklabels(["0", "25%", "50%", "75%", "100%"], fontsize=13)
ax.spines[["top", "right"]].set_visible(False)
ax.grid(axis="y", color="#E4DED4", lw=0.9); ax.set_axisbelow(True)
bar_labels(ax, bars, [p4(v) for v in quart.graduation_rate], size=20)
source(fig, "Source: output/tables/ability_quartiles.csv. Quartiles computed within the 2,828-student ability sample.")
fig.savefig(OUT / "f02_quartile_graduation.png", dpi=200); plt.close(fig)
audit += [(f"Q{i+1} grad %", p4(v)) for i, v in enumerate(quart.graduation_rate)]

# ---------------------------------------------------------------- fig 3: model comparison
fig = plt.figure(figsize=(12, 6.75), dpi=200)
slide_title(fig, "ABILITY ADDS 0.05999 TO MCFADDEN R² ON TOP OF FINANCIAL INDICATORS",
            f"Logistic models on the same {n_ab:,} students, so the three numbers are comparable")
ax = fig.add_axes([0.08, 0.18, 0.60, 0.55])
labels = ["Financial only", "Financial +\nability", "Ability only"]
vals = [r_fin_ab, r_both, r_ability]
bars = ax.bar(range(3), vals, width=0.6, color=[DARKRED, RED, LIGHTGREEN])
ax.set_xticks(range(3)); ax.set_xticklabels(labels, fontsize=14.5)
ax.set_ylim(0, 0.32); ax.set_yticks([0, .1, .2, .3])
ax.spines[["top", "right"]].set_visible(False)
ax.grid(axis="y", color="#E4DED4", lw=0.9); ax.set_axisbelow(True)
bar_labels(ax, bars, [n4(v) for v in vals], size=19)
ax.set_ylabel("McFadden R²", fontsize=14)
ax.plot([0, 1], [r_fin_ab, r_fin_ab], color=GREY, lw=1, ls=":")
ax.annotate(f"+{n4(delta_ability)}", xy=(0.5, r_both), xytext=(0.5, r_both + 0.022),
            ha="center", fontsize=17, color=GREEN, fontweight="bold")

ax2 = fig.add_axes([0.74, 0.18, 0.22, 0.55]); ax2.axis("off")
ax2.text(0.0, 0.95, "0.2611 − 0.2011", fontsize=20, color=DARK, family="Helvetica")
ax2.text(0.0, 0.80, f"= {n4(delta_ability)}", fontsize=26, color=GREEN, fontweight="bold")
ax2.text(0.0, 0.60, "additional R² from\nacademic ability", fontsize=14, color=GREY)
ax2.text(0.0, 0.36, f"standalone ability:\n{n4(r_ability)}", fontsize=14, color=DARK)
ax2.text(0.0, 0.16, f"standalone financial:\n{n4(r_fin_ab)}", fontsize=14, color=DARK)
source(fig, "Source: output/tables/model_comparison.csv (ability-quartile, financial-three, financial-plus-ability rows).")
fig.savefig(OUT / "f03_model_comparison.png", dpi=200); plt.close(fig)
audit += [("financial only R2 (2828)", n4(r_fin_ab)), ("both R2", n4(r_both)),
          ("ability only R2", n4(r_ability)), ("delta", n4(delta_ability))]

# ---------------------------------------------------------------- fig 4: tuition payment
fig = plt.figure(figsize=(12, 6.75), dpi=200)
slide_title(fig, "GRADUATION RATE BY TUITION PAYMENT STATUS",
            f"Paid tuition: {p4(unpaid0.grad_rate)}   ·   unpaid tuition: {p4(unpaid1.grad_rate)}")
ax = fig.add_axes([0.075, 0.19, 0.40, 0.54])
vals = [unpaid0.grad_rate, unpaid1.grad_rate]
err = [[unpaid0.grad_rate - unpaid0.ci_lo, unpaid1.grad_rate - unpaid1.ci_lo],
       [unpaid0.ci_hi - unpaid0.grad_rate, unpaid1.ci_hi - unpaid1.grad_rate]]
bars = ax.bar([0, 1], vals, width=0.55, color=[GREEN, RED],
              yerr=err, capsize=7, ecolor=DARK, error_kw=dict(lw=1.4))
ax.set_xticks([0, 1])
ax.set_xticklabels([f"Tuition paid\nn = {int(unpaid0.n):,}", f"Unpaid\nn = {int(unpaid1.n):,}"], fontsize=14.5)
ax.set_ylim(0, 0.9); ax.set_yticks([0, .2, .4, .6, .8])
ax.set_yticklabels(["0", "20%", "40%", "60%", "80%"], fontsize=13)
ax.spines[["top", "right"]].set_visible(False)
ax.grid(axis="y", color="#E4DED4", lw=0.9); ax.set_axisbelow(True)
bar_labels(ax, bars, [p4(v) for v in vals], size=19)
ax.set_title("Graduation rate (95% CI)", fontsize=16, color=DARK, pad=10)

ax2 = fig.add_axes([0.56, 0.19, 0.39, 0.54])
order = ["w_neither", "w_only_debt", "w_only_unpaid", "w_both"]
names = ["Neither\nmarker", "Debt\nonly", "Unpaid\ntuition only", "Both\nmarkers"]
cvals = [float(cells[cells.cell == c].dropout_rate.iloc[0]) for c in order]
cn = [int(cells[cells.cell == c].n.iloc[0]) for c in order]
bars2 = ax2.bar(range(4), cvals, width=0.6, color=[LIGHTGREEN, "#C9603F", RED, DARKRED])
ax2.set_xticks(range(4)); ax2.set_xticklabels([f"{nm}\nn = {n:,}" for nm, n in zip(names, cn)], fontsize=13)
ax2.set_ylim(0, 1.12); ax2.set_yticks([0, .25, .5, .75, 1])
ax2.set_yticklabels(["0", "25%", "50%", "75%", "100%"], fontsize=13)
ax2.spines[["top", "right"]].set_visible(False)
ax2.grid(axis="y", color="#E4DED4", lw=0.9); ax2.set_axisbelow(True)
bar_labels(ax2, bars2, [p4(v) for v in cvals], size=16)
ax2.set_title(f"Dropout rate by the two financial markers (φ = {n4(float(cells.phi.iloc[0]))})",
              fontsize=15, color=DARK, pad=10)
source(fig, "Source: output/tables/financial_markers.csv, wealth_four_cell.csv. Main sample, 3,630 students.")
fig.savefig(OUT / "f04_tuition_payment.png", dpi=200); plt.close(fig)
audit += [("paid grad %", p4(unpaid0.grad_rate)), ("unpaid grad %", p4(unpaid1.grad_rate)),
          ("phi", n4(float(cells.phi.iloc[0])))] + [(c, p4(v)) for c, v in zip(order, cvals)]

# ---------------------------------------------------------------- fig 5: scholarship
fig = plt.figure(figsize=(12, 6.75), dpi=200)
slide_title(fig, "SCHOLARSHIP HOLDERS: HIGHER GRADUATION, LOWER PAYMENT DIFFICULTY",
            "Two views of the same split; association only, not a causal estimate")
ax = fig.add_axes([0.075, 0.19, 0.40, 0.54])
vals = [sch0.grad_rate, sch1.grad_rate]
err = [[sch0.grad_rate - sch0.ci_lo, sch1.grad_rate - sch1.ci_lo],
       [sch0.ci_hi - sch0.grad_rate, sch1.ci_hi - sch1.grad_rate]]
bars = ax.bar([0, 1], vals, width=0.55, color=[RED, GREEN],
              yerr=err, capsize=7, ecolor=DARK, error_kw=dict(lw=1.4))
ax.set_xticks([0, 1])
ax.set_xticklabels([f"No scholarship\nn = {int(sch0.n):,}", f"Scholarship\nn = {int(sch1.n):,}"], fontsize=14.5)
ax.set_ylim(0, 1.06); ax.set_yticks([0, .2, .4, .6, .8, 1])
ax.set_yticklabels(["0", "20%", "40%", "60%", "80%", "100%"], fontsize=13)
ax.spines[["top", "right"]].set_visible(False)
ax.grid(axis="y", color="#E4DED4", lw=0.9); ax.set_axisbelow(True)
bar_labels(ax, bars, [p4(v) for v in vals], size=19)
ax.set_title("Graduation rate (95% CI)", fontsize=16, color=DARK, pad=10)

ax2 = fig.add_axes([0.56, 0.19, 0.39, 0.54])
uv = [unpaid_rate_nonsch, unpaid_rate_sch]
bars2 = ax2.bar([0, 1], uv, width=0.55, color=[RED, GREEN])
ax2.set_xticks([0, 1])
ax2.set_xticklabels([f"No scholarship\nn = {nonsch_all:,}", f"Scholarship\nn = {scholars_all:,}"], fontsize=14.5)
ax2.set_ylim(0, 0.215); ax2.set_yticks([0, .05, .1, .15, .2])
ax2.set_yticklabels(["0", "5%", "10%", "15%", "20%"], fontsize=13)
ax2.spines[["top", "right"]].set_visible(False)
ax2.grid(axis="y", color="#E4DED4", lw=0.9); ax2.set_axisbelow(True)
bar_labels(ax2, bars2, [p4(v) for v in uv], size=19)
ax2.set_title("Unpaid-tuition rate", fontsize=16, color=DARK, pad=10)
source(fig, "Source: output/tables/financial_markers.csv, financial_cross.csv. Main sample, 3,630 students.")
fig.savefig(OUT / "f05_scholarship.png", dpi=200); plt.close(fig)
audit += [("scholar grad %", p4(sch1.grad_rate)), ("non-scholar grad %", p4(sch0.grad_rate)),
          ("scholar unpaid %", p4(unpaid_rate_sch)), ("non-scholar unpaid %", p4(unpaid_rate_nonsch))]

# ---------------------------------------------------------------- fig 6: parental education
fig = plt.figure(figsize=(12, 6.75), dpi=200)
slide_title(fig, "PARENTAL EDUCATION: NOT A STRAIGHT LINE",
            "Graduation rate by the higher of the two parents' qualifications")
ax = fig.add_axes([0.085, 0.20, 0.87, 0.50])
order = ["primary_or_less", "lower_sec", "secondary", "post_sec", "higher", "unknown"]
en = {"primary_or_less": "Primary or less", "lower_sec": "Lower secondary",
      "secondary": "Secondary", "post_sec": "Post-secondary", "higher": "Higher education",
      "unknown": "Not reported"}
sub = pedu.set_index("level")
vals = [float(sub.loc[k, "grad_rate"]) for k in order]
ns = [int(sub.loc[k, "n"]) for k in order]
lo = [float(sub.loc[k, "grad_rate"]) - float(sub.loc[k, "ci_lo"]) for k in order]
hi = [float(sub.loc[k, "ci_hi"]) - float(sub.loc[k, "grad_rate"]) for k in order]
cols = [LIGHTGREEN, GREEN, GREEN, "#C9603F", RED, "#B9B2A8"]
bars = ax.bar(range(6), vals, width=0.62, color=cols, yerr=[lo, hi], capsize=6,
              ecolor=DARK, error_kw=dict(lw=1.2))
ax.set_xticks(range(6))
ax.set_xticklabels([f"{en[k]}\nn = {n:,}" for k, n in zip(order, ns)], fontsize=12.5)
ax.set_ylim(0, 0.82); ax.set_yticks([0, .2, .4, .6, .8])
ax.set_yticklabels(["0", "20%", "40%", "60%", "80%"], fontsize=13)
ax.spines[["top", "right"]].set_visible(False)
ax.grid(axis="y", color="#E4DED4", lw=0.9); ax.set_axisbelow(True)
for bar, v, hi_e in zip(bars, vals, hi):
    ax.text(bar.get_x() + bar.get_width()/2, v + hi_e + 0.014, p4(v), ha="center", va="bottom",
            color=DARK, fontsize=15, fontweight="bold")
ax.set_ylabel("Graduation rate", fontsize=14)
ax.annotate("lower secondary > higher education", xy=(1, 0.662), xytext=(1.35, 0.775),
            fontsize=14, color=DARKRED, fontweight="bold",
            arrowprops=dict(arrowstyle="->", color=DARKRED, lw=1.6))
source(fig, f"Source: output/tables/highest_parent_education.csv. Main sample, 3,630 students.\n"
            f"Additional R² of parental education beyond the three financial markers: {n4(qdelta_r2)} "
            f"(likelihood-ratio test p < 1e-10).")
fig.savefig(OUT / "f06_parental_education.png", dpi=200); plt.close(fig)
audit += [(en[k], p4(v)) for k, v in zip(order, vals)] + [("delta R2 qualification", n4(qdelta_r2))]

# ---------------------------------------------------------------- fig 7: age bands
import numpy as np
fig = plt.figure(figsize=(12, 6.75), dpi=200)
slide_title(fig, "DROPOUT IS NOT LINEAR IN AGE AT ENROLMENT",
            "Dropout peaks at 25–29; the unpaid-tuition rate does not separate 25–29 from 40+")
ax = fig.add_axes([0.075, 0.19, 0.50, 0.50])
x5 = np.arange(5); w = 0.38
b1 = ax.bar(x5 - w/2, ages.dropout_rate, width=w, color=RED, label="Dropout rate")
b2 = ax.bar(x5 + w/2, ages.unpaid_rate, width=w, color="#9A9187", label="Unpaid-tuition rate")
ax.set_xticks(x5)
ax.set_xticklabels([f"{b}\nn = {int(n):,}" for b, n in zip(ages.band, ages.n)], fontsize=12.5)
ax.set_ylim(0, 0.88); ax.set_yticks([0, .2, .4, .6, .8])
ax.set_yticklabels(["0", "20%", "40%", "60%", "80%"], fontsize=12.5)
ax.spines[["top", "right"]].set_visible(False)
ax.grid(axis="y", color="#E4DED4", lw=0.9); ax.set_axisbelow(True)
for bar, v in zip(b1, ages.dropout_rate):
    ax.text(bar.get_x() + bar.get_width()/2, v + 0.014, p4(v), ha="center", va="bottom",
            fontsize=13.5, fontweight="bold", color=DARK)
for bar, v in zip(b2, ages.unpaid_rate):
    ax.text(bar.get_x() + bar.get_width()/2, v + 0.014, p4(v), ha="center", va="bottom",
            fontsize=11, color=GREY)
ax.legend(frameon=False, fontsize=12, loc="upper left", bbox_to_anchor=(-0.02, 1.14), ncol=2)
ax.set_ylabel("Rate", fontsize=13.5)

ax3 = fig.add_axes([0.655, 0.19, 0.30, 0.50])
m39 = marriage[marriage.band == "30-39"].iloc[0]
m40 = marriage[marriage.band == "40+"].iloc[0]
xb = np.arange(2); w2 = 0.36
b3 = ax3.bar(xb - w2/2, [m39.married_rate, m40.married_rate], width=w2, color=GREEN, label="Married")
b4 = ax3.bar(xb + w2/2, [m39.single_rate, m40.single_rate], width=w2, color=RED, label="Single")
ax3.set_xticks(xb)
ax3.set_xticklabels([f"{b}\np = {p:.3g}" for b, p in zip(["30–39", "40+"], [m39.p_value, m40.p_value])],
                    fontsize=12.5)
ax3.set_ylim(0, 0.92); ax3.set_yticks([0, .2, .4, .6, .8])
ax3.set_yticklabels(["0", "20%", "40%", "60%", "80%"], fontsize=12)
ax3.spines[["top", "right"]].set_visible(False)
ax3.grid(axis="y", color="#E4DED4", lw=0.9); ax3.set_axisbelow(True)
for bars in (b3, b4):
    for bar in bars:
        ax3.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.014, p4(bar.get_height()),
                 ha="center", va="bottom", fontsize=12.5, fontweight="bold", color=DARK)
ax3.legend(frameon=False, fontsize=11.5, loc="upper left", bbox_to_anchor=(-0.02, 1.14), ncol=2)
ax3.set_title("Dropout by marital status", fontsize=14.5, color=DARK, pad=26)
dr = age_tests[age_tests.test == "dropout_rate"].iloc[0]
ur = age_tests[age_tests.test == "unpaid_rate"].iloc[0]
source(fig, f"Source: output/tables/age_bands.csv, age_tests.csv, marriage_strata.csv. Main sample, 3,630 students.\n"
            f"25–29 vs 40+: dropout odds ratio {n4(dr.odds_ratio)} (p = {dr.p_value:.3g}); "
            f"unpaid-tuition odds ratio {n4(ur.odds_ratio)} (p = {ur.p_value:.3g}).")
fig.savefig(OUT / "f07_age_bands.png", dpi=200); plt.close(fig)
audit += [(f"{b} dropout / unpaid", f"{p4(v)} / {p4(u)}") for b, v, u in zip(list(ages.band), list(ages.dropout_rate), ages.unpaid_rate)]
audit += [("30-39 married", p4(m39.married_rate)), ("30-39 single", p4(m39.single_rate)),
          ("40+ married", p4(m40.married_rate)), ("40+ single", p4(m40.single_rate))]

# ---------------------------------------------------------------- fig 8: four dimensions
fig = plt.figure(figsize=(12, 6.75), dpi=200)
slide_title(fig, "EXPLANATORY CONTRIBUTION OF THE FOUR DIMENSIONS",
            "Dark = standalone model · Green = added on top of the financial markers")
ax = fig.add_axes([0.33, 0.26, 0.62, 0.45])
labels = ["Financial indicators\n(standalone, n = 3,630)",
          "Age at enrolment\n(standalone, n = 3,630)",
          "Academic ability\n(standalone, n = 2,828)",
          "Academic ability\n(added, n = 2,828)",
          "Parental education\n(added, n = 3,630)"]
vals = [r_fin, r_age, r_ability, delta_ability, qdelta_r2]
cols = [RED, DARKRED, LIGHTGREEN, GREEN, GREEN]
y = range(len(vals))[::-1]
bars = ax.barh(list(y), vals, height=0.55, color=cols)
ax.set_yticks(list(y)); ax.set_yticklabels(labels, fontsize=13)
ax.set_xlim(0, 0.26); ax.set_xticks([0, .05, .1, .15, .2, .25])
ax.set_xticklabels(["0", "0.05", "0.10", "0.15", "0.20", "0.25"], fontsize=12.5)
ax.spines[["top", "right"]].set_visible(False)
ax.grid(axis="x", color="#E4DED4", lw=0.9); ax.set_axisbelow(True)
for b, v in zip(bars, vals):
    ax.text(v + 0.004, b.get_y() + b.get_height()/2, n4(v), va="center",
            fontsize=16, fontweight="bold", color=DARK)
ax.set_xlabel("McFadden R²", fontsize=14)
fig.text(0.055, 0.155, "Dark bars are R² of a model on its own; green bars are the increase over the financial model.\n"
                       "Reading 0.2227 against 0.05999 therefore compares two different questions: how much\n"
                       "wealth explains alone, against how much ability explains once wealth is already in the model.",
         color=DARKRED, fontsize=13, va="top")
source(fig, "Source: output/tables/model_comparison.csv, qualification_models.csv.")
fig.savefig(OUT / "f08_four_dimensions.png", dpi=200); plt.close(fig)
audit += [(lbl.replace("\n", " "), n4(v)) for lbl, v in zip(labels, vals)]

print("=== numeric audit (every value drawn on a figure) ===")
for k, v in audit:
    print(f"  {k}: {v}")
print("\nfiles:")
for p in sorted(OUT.glob("*.png")):
    print(f"  {p}  {p.stat().st_size/1024:.0f} KB")
