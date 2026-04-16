# Data-Driven Station Placement for Network Expansion

**Capital Planning & Equity Analysis**
**Author:** Wesley Haruo Kurosawa
**Stack:** Python (pandas, numpy, matplotlib), SQL (PostgreSQL syntax)

---

## Executive Summary

.... planning the next tranche of network expansion. With the system already at 1,042 stations across all 25 wards, the question is no longer *whether* to expand but *where*. Three competing pressures shape the decision: maximizing ridership (revenue), serving underserved wards (equity), and strengthening first/last-mile transit connections.

This project builds a multi-criteria scoring model that evaluates 150 candidate locations against five weighted factors, selects 15 new sites with a geographic-diversity constraint, forecasts year-1 ridership, and tests the robustness of the recommendation through sensitivity analysis.

**Key findings:**

| Metric | Value |
|---|---|
| Candidate locations evaluated | 150 |
| Sites selected | 15 |
| Wards receiving new stations | 11 |
| Projected new annual trips | 56,185 |
| Projected new annual revenue | $123,608 |
| Share of sites in currently-underserved wards | 73% |

**Recommendation:** Deploy the 15 selected sites with the following phasing:

- **Phase 1 (priority underserved wards):** Scarborough Centre, Willowdale, Scarborough-Guildwood, Etobicoke-Lakeshore, Etobicoke North, Scarborough Southwest — 8 stations
- **Phase 2 (coverage gaps in middle-ring wards):** Don Valley East, Humber River-Black Creek, Eglinton-Lawrence, York Centre, Beaches-East York — 7 stations

The selection emphasizes equity over pure revenue maximization, consistent with the City of Toronto's Growth Plan and TPA's 2030 strategy of expanded access across all 25 wards.

---

## Business Context

Between 2021 and 2025, Bike Share Toronto executed a 4-year Growth Plan that brought stations to all 25 wards for the first time. The next phase moves from *coverage* to *density* — adding stations within wards that already have presence but where residents still travel too far to reach one.

With the 2030 target of 12–16 million rides (up from 7.8 million in 2025), every new station must carry its weight analytically. But raw ridership projection is only one input: if it were the only criterion, the system would concentrate all new investment in downtown, reinforcing existing inequity.

The role of the Data Analyst in this workflow is to build the decision framework, quantify the trade-offs, and let Operations, Policy, and Finance stakeholders choose the weights transparently.

---

## Approach

The analysis follows a six-step decision-science framework:

1. **Generate candidates** — plausible placement locations from GIS inputs (simulated here, real project would use public right-of-way data, parks permits, TTC coordinates)
2. **Define criteria** — five factors that capture ridership, coverage, equity, connectivity, and infrastructure
3. **Normalize scores** — put each criterion on a 0–1 scale so weighted sums are meaningful
4. **Apply stakeholder weights** — agreed with Operations, Policy, and Finance
5. **Apply diversity constraint** — greedy selection with 2.5 km minimum spacing to prevent clustering
6. **Sensitivity test** — verify the recommendation is robust to reasonable weight changes

---

## Data

- **`trips.csv`** — 435,132 trips (historical ridership baseline per ward)
- **`stations.csv`** — 118 existing stations with location, ward, capacity
- **Synthetic ward attributes** — population, density, transit score, median income, existing bike infrastructure (km) — in a production system these would be joined from open data sources (Statistics Canada census, City of Toronto GIS, TTC feeds)
- **Generated candidates** — 150 plausible new locations (6 per ward)

---

## Scoring Model

### Five Criteria

| Criterion | Weight | Definition | Rationale |
|---|---|---|---|
| **Demand** | 20% | Ward-level trips per existing station (proxy for latent demand) | Revenue-generating potential |
| **Coverage gap** | 25% | Distance to nearest existing station (km) | Fills network gaps; reduces first-mile friction |
| **Equity** | 30% | Inverse of stations per 100,000 residents in ward | Explicitly addresses City's Growth Plan equity goal |
| **Transit** | 15% | Transit score (subway/streetcar/bus density near candidate) | Supports first/last-mile mission |
| **Infrastructure** | 10% | Existing bike lane km in ward | Safer deployment, signals city cycling investment |

The total weight of 100% is split so that equity + coverage combined (55%) outweighs pure demand (20%). This reflects the stakeholder agreement that the next phase should favor underserved areas over downtown revenue maximization.

### Normalization

Each criterion is min-max normalized to [0, 1]:

```
normalized = (raw - min) / (max - min)
```

For "lower is better" criteria (stations per 100k for equity), we invert so that higher normalized score = higher priority.

### Composite Score

```
final_score = 0.20 × demand + 0.25 × coverage + 0.30 × equity + 0.15 × transit + 0.10 × infrastructure
```

### Geographic Diversity Constraint

Greedy selection: select the top-ranked candidate, exclude all candidates within 2.5 km, repeat until 15 are chosen. Without this constraint, 8 of the top 15 would cluster in three downtown wards; with it, 11 different wards are represented.

---

## Key Results

### Top 5 Selected Sites

| Rank | Site | Ward | Score | Primary driver |
|---|---|---|---|---|
| 1 | Scarborough Centre – Candidate 5 | Scarborough Centre | 0.605 | Equity + coverage gap |
| 2 | Willowdale – Candidate 2 | Willowdale | 0.602 | Equity + transit (Finch subway) |
| 3 | Scarborough-Guildwood – Candidate 2 | Scarborough-Guildwood | 0.579 | Equity + coverage gap |
| 4 | Etobicoke-Lakeshore – Candidate 1 | Etobicoke-Lakeshore | 0.576 | Transit + coverage gap |
| 5 | Etobicoke North – Candidate 2 | Etobicoke North | 0.571 | Equity (severely underserved) |

### Ward Coverage

15 stations distributed across 11 wards:

- **Scarborough wards:** 4 sites (addresses the largest equity gap in the city)
- **Etobicoke wards:** 3 sites (western underserved areas)
- **North York / Willowdale:** 2 sites (Willowdale, Don Valley East)
- **Middle-ring wards:** 6 sites

### Forecast

Each new station is projected to generate trips equal to the median trips-per-station in its ward, adjusted by ±5% based on transit score. Aggregated:

- **Year-1 trips projected:** 56,185
- **Year-1 revenue projected:** $123,608 (at blended $2.20/trip)
- **5-year NPV at 8% discount:** approximately $485,000 per $1M invested (before maintenance)

Note: these are conservative baseline forecasts using existing-station performance. Real ridership typically exceeds baseline after 12–18 months as network effects take hold.

---

## Sensitivity Analysis

To test the robustness of the recommendation, the scoring was rerun under four alternative weight scenarios:

| Scenario | Weights | Top 5 wards shift |
|---|---|---|
| **Balanced (baseline)** | 20/25/30/15/10 | As documented above |
| **Revenue-focused** | 50/15/05/20/10 | Downtown wards dominate (Toronto Centre, Spadina-Fort York, University-Rosedale) |
| **Equity-focused** | 15/25/40/15/05 | Nearly identical to baseline — confirms equity weight is decisive |
| **Transit-integration focused** | 20/15/15/40/10 | Shifts toward wards near subway stations; still includes Scarborough Centre |

**Interpretation:** The baseline recommendation is robust to weight changes *within the equity-first family*. Only a deliberate shift to revenue-first would change the top selections — and that change would move 80% of investment downtown, which conflicts with the stated strategic direction.

---

## Validation Approach (Backtesting)

Query 5 in the SQL file implements a backtest: for stations that opened in the last 18 months, compare actual ridership against what the model would have predicted using ward-level baselines. A rigorous model should show:

- Median prediction deviation within ±20% of actual
- No systematic bias (under- or over-prediction by area type)
- Outliers explained by specific factors (e.g., a new major development)

In production, this backtest would run quarterly and feed into weight recalibration.

---

## Repository Structure

```
project3_station_placement/
├── README.md
├── analysis.py                        # Full Python analysis pipeline
├── queries.sql                        # 7 SQL queries for the data prep layer
└── outputs/
    ├── 01_all_candidates_scored.csv
    ├── 02_selected_top_15.csv
    ├── 03_ward_baseline_demand.csv
    ├── 04_equity_analysis.csv
    ├── 05_sensitivity_analysis.csv
    ├── chart_01_map.png
    ├── chart_02_score_breakdown.png
    ├── chart_03_equity.png
    └── chart_04_sensitivity.png
```

---

## How to Run

```bash
pip install pandas numpy matplotlib
python ../_shared_data/generate_data.py
python analysis.py
```

---

## What This Project Demonstrates

- **Multi-criteria decision modelling** — combining competing objectives (revenue, equity, coverage) into a single decision framework
- **Normalization discipline** — understanding how scale differences between criteria would distort a weighted sum without normalization
- **Stakeholder-aligned weighting** — treating weights as a policy choice, not a technical one, with transparent sensitivity testing
- **Geographic optimization** — greedy selection with spatial constraints to enforce diversity
- **Backtesting mindset** — validating a predictive model against historical outcomes before deploying it
- **Equity-aware analytics** — recognizing that pure revenue-maximization can entrench existing inequities, and building explicit guardrails
- **Communication for multiple audiences** — technical methodology for engineering, trade-offs for finance, equity impact for policy
