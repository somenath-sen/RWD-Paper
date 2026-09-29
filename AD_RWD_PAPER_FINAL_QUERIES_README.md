# Alzheimer's Disease Real-World Cohort — Analysis Code

SQL to reproduce every reported number and figure in the manuscript
*"Demographic Characterization and Longitudinal Medication Use in an Alzheimer's
Disease Cohort: A Real-World Data Study Using the NeuroDiscovery AI Neurology
Clinical Database."*

## File
- `ad_cohort_analysis.sql` — nine labeled queries (Q1–Q9), MySQL 8, run against
  the `ad_mci_prod` schema. Each query's expected output is written in its comment.

## Study definitions
- **AD case:** ≥1 diagnosis code ICD-10 `G30.x` or ICD-9 `331.0` (decimal separators removed).
- **Study window:** 2015-01-01 to 2026-04-30 (uniform data cutoff; 2026 is a partial year).
- **Cohort:** any AD code dated in the window → **N = 51,795**.
- **Anti-amyloid mAb class:** lecanemab + donanemab only (aducanumab excluded — withdrawn).
  Ascertained from the medication table (drug name) **and** the procedures table
  (HCPCS `J0174`, `J0175`), de-duplicated per patient.
- **Cholinesterase inhibitors / memantine:** medication table only.
- **Age at first diagnosis:** incident cases only (first-ever AD code within the
  window); patients with an AD code before 2015 are excluded from the age calculation.
- **Coverage (Figure 3):** cumulative, no death adjustment =
  (patients ever treated in a class by year *Y*) ÷ (patients diagnosed by year *Y*).

## Query map
| Query | Produces |
|-------|----------|
| Q1 | Cohort size (51,795) |
| Q2 | Code-vs-free-text case validation |
| Q3 | Table 1 — sex distribution |
| Q4 | Mean age at first diagnosis (incident cases) |
| Q5 | Figure 1A — age distribution |
| Q6 | Figure 1B — diagnostic-code distribution |
| Q7 | Figure 1C — race distribution |
| Q8 | Figure 2 — drug-class utilization |
| Q9 | Figure 3 — cumulative medication use by year |

## Notes
- Data are de-identified (HIPAA); dates carry a per-patient random offset and only
  year of birth is retained, so age is computed at year resolution.
- A performance tip (materializing the cohort as a temp table) is included in the
  SQL header for faster repeated runs.
