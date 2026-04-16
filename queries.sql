-- =====================================================================
-- PROJECT 3: DATA-DRIVEN STATION PLACEMENT FOR NETWORK EXPANSION
-- =====================================================================
-- Business Question: Where should we place 15 new stations to maximize
-- ridership, improve equity, and strengthen transit connectivity?
--
-- These queries prepare the criteria that feed the Python scoring model.
-- Additional tables assumed (in production):
--   ward_demographics  (ward, population, density, median_income)
--   transit_stops      (stop_id, latitude, longitude, stop_type)
--   bike_lanes         (segment_id, ward, length_km)
-- =====================================================================


-- ---------------------------------------------------------------------
-- QUERY 1: Ward-level baseline demand
-- ---------------------------------------------------------------------
-- Purpose: Compute average trips per existing station in each ward.
-- This is the "demand proxy" for candidates in the same ward.

WITH ward_trips AS (
    SELECT
        s.ward,
        COUNT(*) AS historical_trips
    FROM trips t
    JOIN stations s ON t.start_station_id = s.station_id
    GROUP BY s.ward
),
ward_station_count AS (
    SELECT ward, COUNT(*) AS existing_stations
    FROM stations
    GROUP BY ward
)
SELECT
    ws.ward,
    ws.existing_stations,
    wt.historical_trips,
    ROUND(wt.historical_trips::numeric / ws.existing_stations, 0) AS trips_per_station
FROM ward_station_count ws
LEFT JOIN ward_trips wt USING (ward)
ORDER BY trips_per_station DESC;


-- ---------------------------------------------------------------------
-- QUERY 2: Station density and equity gap
-- ---------------------------------------------------------------------
-- Purpose: Identify underserved wards — those with fewer stations
-- per 100,000 residents than the city average.

WITH station_counts AS (
    SELECT ward, COUNT(*) AS station_count
    FROM stations
    GROUP BY ward
),
ward_equity AS (
    SELECT
        sc.ward,
        sc.station_count,
        wd.population,
        ROUND(100000.0 * sc.station_count / wd.population, 2) AS stations_per_100k
    FROM station_counts sc
    JOIN ward_demographics wd USING (ward)
),
city_avg AS (
    SELECT AVG(stations_per_100k) AS avg_stations_per_100k FROM ward_equity
)
SELECT
    we.ward,
    we.station_count,
    we.population,
    we.stations_per_100k,
    ROUND(ca.avg_stations_per_100k, 2) AS city_avg,
    ROUND(we.stations_per_100k - ca.avg_stations_per_100k, 2) AS gap_vs_city_avg,
    CASE
        WHEN we.stations_per_100k < ca.avg_stations_per_100k * 0.7 THEN 'Severely underserved'
        WHEN we.stations_per_100k < ca.avg_stations_per_100k       THEN 'Underserved'
        ELSE 'Adequately served'
    END AS equity_tier
FROM ward_equity we
CROSS JOIN city_avg ca
ORDER BY stations_per_100k;


-- ---------------------------------------------------------------------
-- QUERY 3: Distance-to-nearest-station for each candidate
-- ---------------------------------------------------------------------
-- Purpose: Compute the "coverage gap" metric — how far is each candidate
-- from the nearest existing station? Larger gap = more network value.
-- Uses Haversine approximation (111 km per degree of latitude).

WITH distances AS (
    SELECT
        c.candidate_id,
        c.candidate_name,
        c.ward,
        s.station_id,
        111 * SQRT(
            POWER(c.latitude - s.latitude, 2) +
            POWER((c.longitude - s.longitude) * COS(RADIANS(c.latitude)), 2)
        ) AS distance_km
    FROM candidate_locations c
    CROSS JOIN stations s
)
SELECT
    candidate_id,
    candidate_name,
    ward,
    ROUND(MIN(distance_km)::numeric, 2) AS nearest_station_km,
    CASE
        WHEN MIN(distance_km) < 0.3 THEN 'Too close — redundant'
        WHEN MIN(distance_km) < 0.8 THEN 'Moderate coverage'
        WHEN MIN(distance_km) < 1.5 THEN 'Good coverage gap'
        ELSE 'Large coverage gap'
    END AS coverage_tier
FROM distances
GROUP BY candidate_id, candidate_name, ward
ORDER BY nearest_station_km DESC;


-- ---------------------------------------------------------------------
-- QUERY 4: Transit connectivity score per candidate
-- ---------------------------------------------------------------------
-- Purpose: Count TTC subway/streetcar stops within 500 m of each candidate.
-- Assumes a transit_stops table with coordinates.

SELECT
    c.candidate_id,
    c.candidate_name,
    c.ward,
    COUNT(ts.stop_id) FILTER (WHERE ts.stop_type = 'subway')    AS subway_stops_500m,
    COUNT(ts.stop_id) FILTER (WHERE ts.stop_type = 'streetcar') AS streetcar_stops_500m,
    COUNT(ts.stop_id) FILTER (WHERE ts.stop_type = 'bus')       AS bus_stops_500m,
    COUNT(ts.stop_id) AS total_transit_stops
FROM candidate_locations c
LEFT JOIN transit_stops ts
    ON 111000 * SQRT(
        POWER(c.latitude - ts.latitude, 2) +
        POWER((c.longitude - ts.longitude) * COS(RADIANS(c.latitude)), 2)
    ) < 500
GROUP BY c.candidate_id, c.candidate_name, c.ward
ORDER BY total_transit_stops DESC;


-- ---------------------------------------------------------------------
-- QUERY 5: Ridership validation — new stations from 2023-2024
-- ---------------------------------------------------------------------
-- Purpose: Backtest the scoring model. For stations that opened in the
-- last 18 months, did ridership match what our model would have predicted?

WITH new_stations AS (
    SELECT *
    FROM stations
    WHERE opened_date >= CURRENT_DATE - INTERVAL '18 months'
),
actual_trips AS (
    SELECT
        start_station_id AS station_id,
        COUNT(*) AS trips_since_opening
    FROM trips
    GROUP BY start_station_id
),
ward_avg AS (
    SELECT
        s.ward,
        AVG(at.trips_since_opening) AS ward_avg_trips
    FROM stations s
    JOIN actual_trips at USING (station_id)
    GROUP BY s.ward
)
SELECT
    ns.station_id,
    ns.station_name,
    ns.ward,
    ns.opened_date,
    at.trips_since_opening              AS actual_trips,
    ROUND(wa.ward_avg_trips, 0)         AS predicted_trips_baseline,
    ROUND(
        100.0 * (at.trips_since_opening - wa.ward_avg_trips) / wa.ward_avg_trips,
        1
    ) AS deviation_pct
FROM new_stations ns
LEFT JOIN actual_trips at USING (station_id)
LEFT JOIN ward_avg wa USING (ward)
ORDER BY ABS(at.trips_since_opening - wa.ward_avg_trips) DESC;


-- ---------------------------------------------------------------------
-- QUERY 6: Weighted composite scoring (final rank)
-- ---------------------------------------------------------------------
-- Purpose: Apply the stakeholder-agreed weights and produce the final rank.
-- Weights: demand 20%, coverage 25%, equity 30%, transit 15%, infra 10%
-- Scores must be normalized to [0,1] beforehand (done in the staging layer).

WITH scored AS (
    SELECT
        candidate_id,
        candidate_name,
        ward,
        (0.20 * norm_demand +
         0.25 * norm_coverage +
         0.30 * norm_equity +
         0.15 * norm_transit +
         0.10 * norm_infra) AS final_score
    FROM candidate_scores_normalized
)
SELECT
    candidate_id,
    candidate_name,
    ward,
    ROUND(final_score::numeric, 3) AS final_score,
    RANK() OVER (ORDER BY final_score DESC) AS overall_rank,
    RANK() OVER (PARTITION BY ward ORDER BY final_score DESC) AS rank_within_ward
FROM scored
ORDER BY final_score DESC
LIMIT 30;


-- ---------------------------------------------------------------------
-- QUERY 7: Year-1 revenue forecast for selected sites
-- ---------------------------------------------------------------------
-- Purpose: Translate the selected 15 into a projected annual revenue
-- figure, using ward-level trips-per-station as the demand baseline
-- and blended $2.20 revenue per trip.

WITH ward_baseline AS (
    SELECT
        s.ward,
        COUNT(*)::numeric / COUNT(DISTINCT s.station_id) AS trips_per_station_6mo
    FROM trips t
    JOIN stations s ON t.start_station_id = s.station_id
    GROUP BY s.ward
)
SELECT
    sel.candidate_name,
    sel.ward,
    sel.selection_rank,
    ROUND(wb.trips_per_station_6mo * (365.0 / 182.0), 0) AS projected_annual_trips,
    ROUND(wb.trips_per_station_6mo * (365.0 / 182.0) * 2.20, 0) AS projected_annual_revenue
FROM selected_sites sel
JOIN ward_baseline wb USING (ward)
ORDER BY sel.selection_rank;
