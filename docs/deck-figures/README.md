# Deck figures

Eight charts for the group presentation, one per slide that argues from numbers.
Every value is read from `output/tables/*.csv` at generation time; nothing is typed
into the script by hand. 2400 × 1350 px (16:9, 200 dpi), English labels, red/green
palette to match the deck.

| figure | deck slide | what it shows | source tables |
| --- | --- | --- | --- |
| `f01_sample_flow.png` | 8 DATASET INFORMATION | 4,424 → 3,630 → 2,828, and the 60.85% / 39.15% outcome split | `population_ledger.csv` |
| `f02_quartile_graduation.png` | 13 ACADEMIC PERFORMANCE GROUP | graduation rate by second-semester quartile, 51.77 → 89.25% | `ability_quartiles.csv` |
| `f03_model_comparison.png` | 14 MODEL COMPARISON | 0.09577 / 0.2011 / 0.2611 and the +0.05999 increment | `model_comparison.csv` |
| `f04_tuition_payment.png` | 15 WEALTH: FINANCIAL BACKGROUND | 69.34% vs 5.967% by tuition status; the four-cell dropout rates | `financial_markers.csv`, `wealth_four_cell.csv` |
| `f05_scholarship.png` | 16 SCHOLARSHIP | 86.17% vs 51.63% graduation; 3.818% vs 16.87% unpaid | `financial_markers.csv`, `financial_cross.csv` |
| `f06_parental_education.png` | 17–18 PARENTAL EDUCATION | six qualification levels, non-monotonic; ΔR² 0.01572 | `highest_parent_education.csv`, `qualification_models.csv` |
| `f07_age_bands.png` | 19 AGE AND FAMILY CIRCUMSTANCES | dropout and unpaid rates by age band; marital status at 30–39 | `age_bands.csv`, `age_tests.csv`, `marriage_strata.csv` |
| `f08_four_dimensions.png` | 21 COMPARING THE FOUR DIMENSIONS | standalone R² beside incremental ΔR², colour-coded | `model_comparison.csv`, `qualification_models.csv` |

## Two corrections the figures carry against the slide text

1. **The outcome split is 60.85% / 39.15%, not 60.80% / 39.20%.** 2,209 ÷ 3,630 and
   1,421 ÷ 3,630. The slide's pair also sums to 100, which is why the error is invisible.
2. **The four dimensions are not on one scale.** 0.2227 and 0.07557 are the R² of a
   model on its own; 0.05999 and 0.01572 are the increase over the financial model.
   `f08` separates them by colour and says so on the figure; a single ranked bar chart
   of the four numbers compares two different questions.

## Regenerating

```bash
env -u PYTHONPATH python3 docs/deck-figures/make_figs.py
```

Paths resolve from the repository root, so the script writes its PNGs beside itself.
The output is deterministic: re-running produces byte-identical files.
