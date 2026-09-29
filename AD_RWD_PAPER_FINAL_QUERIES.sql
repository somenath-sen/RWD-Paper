/* ============================================================================
   Demographic Characterization and Longitudinal Medication Use in an
   ICD Code-Diagnosed Alzheimer's Disease Cohort — NeuroDiscovery AI RWD
   ----------------------------------------------------------------------------
   Reproducible analysis queries (MySQL 8).  Schema: ad_mci_prod

   STUDY DEFINITIONS
   - AD case:      >=1 diagnosis code ICD-10 G30.x OR ICD-9 331.0,
                   with codes normalized by removing decimal separators.
   - Study window: 2015-01-01 through 2026-04-30 (uniform cutoff; 2026 partial).
   - Cohort:       any AD code dated within the window  ->  N = 51,795.
   - Anti-amyloid mAb class:  lecanemab + donanemab ONLY (aducanumab excluded,
                   withdrawn from market).  Ascertained from the medication
                   table (drug name) AND the procedures table (HCPCS J0174,
                   J0175), de-duplicated per patient.
   - ChEI / memantine:  medication table only.
   - Age at first diagnosis: computed on INCIDENT cases (first-ever AD code
                   within the window); patients with any AD code before 2015
                   are excluded from the age calculation only.
   - Coverage (Figure 3): CUMULATIVE, no death adjustment
                   = (patients ever treated in a class by year Y)
                   / (patients diagnosed by year Y) x 100.

   PERFORMANCE TIP: the medication table is large. To run several queries
   quickly, materialize the cohort once:
       CREATE TEMPORARY TABLE ad_cohort AS
         SELECT ndid, MIN(diag_date) AS first_ad
         FROM ad_mci_prod.diagnosis
         WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)'
           AND diag_date >= '2015-01-01' AND diag_date < '2026-05-01'
         GROUP BY ndid;
       ALTER TABLE ad_cohort ADD INDEX(ndid);
   then JOIN ad_cohort instead of repeating the diagnosis subquery.
   ============================================================================ */


/* ---------------------------------------------------------------------------
   Q1.  COHORT SIZE   ->  51,795
   --------------------------------------------------------------------------- */
SELECT COUNT(DISTINCT ndid) AS ad_cohort
FROM ad_mci_prod.diagnosis
WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)'
  AND diag_date >= '2015-01-01' AND diag_date < '2026-05-01';


/* ---------------------------------------------------------------------------
   Q2.  CASE-DEFINITION VALIDATION (code vs free-text)  ->  code_only = 0,
        desc_only = 0  (the two definitions identify the same patients)
   --------------------------------------------------------------------------- */
WITH tagged AS (
  SELECT ndid,
    MAX(REPLACE(diag_code,'.','') REGEXP '^(G30|3310)') AS by_code,
    MAX(LOWER(diag_desc) LIKE '%alzheimer%')            AS by_desc
  FROM ad_mci_prod.diagnosis
  WHERE diag_date >= '2015-01-01' AND diag_date < '2026-05-01'
    AND ( REPLACE(diag_code,'.','') REGEXP '^(G30|3310)'
          OR LOWER(diag_desc) LIKE '%alzheimer%' )
  GROUP BY ndid
)
SELECT SUM(by_code=1) AS code_total, SUM(by_desc=1) AS desc_total,
       SUM(by_code=1 AND by_desc=0) AS code_only,
       SUM(by_code=0 AND by_desc=1) AS desc_only
FROM tagged;


/* ---------------------------------------------------------------------------
   Q3.  TABLE 1 — sex (full cohort)
        ->  N 51,795; Female 59.1%; Male 36.4%; missing 4.6%
   --------------------------------------------------------------------------- */
WITH ad AS (
  SELECT DISTINCT ndid FROM ad_mci_prod.diagnosis
  WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)'
    AND diag_date >= '2015-01-01' AND diag_date < '2026-05-01'
)
SELECT COUNT(*) AS ad_total,
  ROUND(100*SUM(p.gender='Female')/COUNT(*),1) AS female_pct,
  ROUND(100*SUM(p.gender='Male')/COUNT(*),1)   AS male_pct,
  ROUND(100*SUM(p.gender IS NULL OR p.gender NOT IN ('Female','Male'))/COUNT(*),1) AS sex_missing_pct
FROM ad JOIN ad_mci_prod.patients p ON p.ndid = ad.ndid;


/* ---------------------------------------------------------------------------
   Q4.  MEAN AGE AT FIRST DIAGNOSIS — INCIDENT cases only
        (first-ever AD code within window; excludes pre-2015-diagnosed)
        ->  n = 49,641;  mean 79 (SD 9)
   --------------------------------------------------------------------------- */
WITH firstever AS (
  SELECT ndid, MIN(diag_date) AS first_ad          -- earliest AD code EVER (no floor)
  FROM ad_mci_prod.diagnosis
  WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)'
  GROUP BY ndid
)
SELECT COUNT(*) AS n_for_age,
  ROUND(AVG(YEAR(fe.first_ad)-p.year_of_birth))    AS mean_age,
  ROUND(STDDEV(YEAR(fe.first_ad)-p.year_of_birth)) AS sd_age
FROM firstever fe JOIN ad_mci_prod.patients p ON p.ndid = fe.ndid
WHERE fe.first_ad >= '2015-01-01' AND fe.first_ad < '2026-05-01'
  AND p.year_of_birth IS NOT NULL;


/* ---------------------------------------------------------------------------
   Q5.  FIGURE 1A — age at first diagnosis, % (INCIDENT cases)
        ->  <50 0.5 | 50-59 2.2 | 60-69 10.2 | 70-79 35.1 | 80-89 42.1 | 90+ 9.9
        (full-cohort variant, if preferred: drop the fe.first_ad>= filter;
         gives 34.9 / 42.3 for 70-79 / 80-89 — differs by <=0.2 pts)
   --------------------------------------------------------------------------- */
WITH firstever AS (
  SELECT ndid, MIN(diag_date) AS first_ad FROM ad_mci_prod.diagnosis
  WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)' GROUP BY ndid
),
aged AS (
  SELECT (YEAR(fe.first_ad)-p.year_of_birth) AS age_dx
  FROM firstever fe JOIN ad_mci_prod.patients p ON p.ndid=fe.ndid
  WHERE fe.first_ad >= '2015-01-01' AND fe.first_ad < '2026-05-01'
    AND p.year_of_birth IS NOT NULL
)
SELECT CASE WHEN age_dx<50 THEN '<50' WHEN age_dx<60 THEN '50-59'
            WHEN age_dx<70 THEN '60-69' WHEN age_dx<80 THEN '70-79'
            WHEN age_dx<90 THEN '80-89' ELSE '90+' END AS age_band,
       ROUND(100*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS pct
FROM aged WHERE age_dx BETWEEN 0 AND 120
GROUP BY age_band ORDER BY MIN(age_dx);


/* ---------------------------------------------------------------------------
   Q6.  FIGURE 1B — AD diagnostic codes, % of cohort (categories overlap)
        ->  G30.9 67.0 | ICD-9 331.0 24.0 | G30.1 27.4 | G30.0 7.5 | G30.8 3.5
   --------------------------------------------------------------------------- */
WITH ad AS (
  SELECT ndid FROM ad_mci_prod.diagnosis
  WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)'
    AND diag_date >= '2015-01-01' AND diag_date < '2026-05-01'
  GROUP BY ndid
),
n AS (SELECT COUNT(*) tot FROM ad),
c AS (
  SELECT ad.ndid, REPLACE(dg.diag_code,'.','') AS code
  FROM ad JOIN ad_mci_prod.diagnosis dg ON dg.ndid=ad.ndid
  WHERE dg.diag_date >= '2015-01-01' AND dg.diag_date < '2026-05-01'
)
SELECT
  ROUND(100*COUNT(DISTINCT CASE WHEN code='G309' THEN ndid END)/(SELECT tot FROM n),1) AS unspecified_g309,
  ROUND(100*COUNT(DISTINCT CASE WHEN code='3310' THEN ndid END)/(SELECT tot FROM n),1) AS icd9_3310,
  ROUND(100*COUNT(DISTINCT CASE WHEN code='G301' THEN ndid END)/(SELECT tot FROM n),1) AS late_onset_g301,
  ROUND(100*COUNT(DISTINCT CASE WHEN code='G300' THEN ndid END)/(SELECT tot FROM n),1) AS early_onset_g300,
  ROUND(100*COUNT(DISTINCT CASE WHEN code='G308' THEN ndid END)/(SELECT tot FROM n),1) AS other_g308
FROM c;


/* ---------------------------------------------------------------------------
   Q7.  FIGURE 1C — race (grouped)
        ->  Not reported 55.6% of all; among recorded: White 73.4, Black 9.9,
            Other 15.2, Asian 1.4
   --------------------------------------------------------------------------- */
WITH ad AS (
  SELECT DISTINCT ndid FROM ad_mci_prod.diagnosis
  WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)'
    AND diag_date >= '2015-01-01' AND diag_date < '2026-05-01'
),
rg AS (
  SELECT CASE
    WHEN p.race IS NULL OR p.race IN ('NS','UNK','Unknown') THEN 'Not reported'
    WHEN p.race='White' THEN 'White'
    WHEN p.race IN ('Black or African American','African American','Black','African') THEN 'Black or African American'
    WHEN p.race IN ('Asian','Asian Indian','Chinese','Japanese','Filipino','Korean',
                    'Vietnamese','Pakistani','Taiwanese','Indonesian') THEN 'Asian'
    ELSE 'Other' END AS grp
  FROM ad JOIN ad_mci_prod.patients p ON p.ndid=ad.ndid
)
SELECT grp,
  ROUND(100*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS pct_of_all,
  CASE WHEN grp='Not reported' THEN NULL
       ELSE ROUND(100*COUNT(*)/SUM(CASE WHEN grp<>'Not reported' THEN COUNT(*) END) OVER (),1)
  END AS pct_of_recorded
FROM rg GROUP BY grp ORDER BY COUNT(*) DESC;


/* ---------------------------------------------------------------------------
   Q8.  FIGURE 2 — drug-class utilization (ever prescribed in window)
        mAb = lecanemab + donanemab, merged medication + procedures.
        ->  any 70.3 | ChEI 60.4 | memantine 44.6 | combo 36.4 (all) /
            51.8 (treated) | mAb 5.9   [mab_patients = 3,051]
   --------------------------------------------------------------------------- */
WITH ad AS (
  SELECT ndid FROM ad_mci_prod.diagnosis
  WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)'
    AND diag_date >= '2015-01-01' AND diag_date < '2026-05-01'
  GROUP BY ndid
),
chei AS (SELECT DISTINCT me.ndid FROM ad_mci_prod.medication me JOIN ad ON ad.ndid=me.ndid
  WHERE LOWER(me.med_name) REGEXP 'donepezil|aricept|rivastigmine|exelon|galantamine|razadyne'
    AND COALESCE(me.medication_start_date,me.fill_date,me.enc_date) BETWEEN '2015-01-01' AND '2026-04-30'),
mem AS (SELECT DISTINCT me.ndid FROM ad_mci_prod.medication me JOIN ad ON ad.ndid=me.ndid
  WHERE LOWER(me.med_name) REGEXP 'memantine|namenda'
    AND COALESCE(me.medication_start_date,me.fill_date,me.enc_date) BETWEEN '2015-01-01' AND '2026-04-30'),
mab AS (
  SELECT me.ndid FROM ad_mci_prod.medication me JOIN ad ON ad.ndid=me.ndid
    WHERE LOWER(me.med_name) REGEXP 'lecanemab|leqembi|donanemab|kisunla'
      AND COALESCE(me.medication_start_date,me.fill_date,me.enc_date) BETWEEN '2015-01-01' AND '2026-04-30'
  UNION
  SELECT pr.ndid FROM ad_mci_prod.procedures pr JOIN ad ON ad.ndid=pr.ndid
    WHERE UPPER(pr.proc_code) IN ('J0174','J0175')
      AND COALESCE(pr.proc_start_date,pr.proc_end_date,pr.enc_date) BETWEEN '2015-01-01' AND '2026-04-30'),
tot AS (SELECT COUNT(*) n FROM ad)
SELECT (SELECT n FROM tot) AS cohort_n,
  ROUND(100*(SELECT COUNT(*) FROM (SELECT ndid FROM chei UNION SELECT ndid FROM mem UNION SELECT ndid FROM mab) u)/(SELECT n FROM tot),1) AS any_pct,
  ROUND(100*(SELECT COUNT(*) FROM chei)/(SELECT n FROM tot),1) AS chei_pct,
  ROUND(100*(SELECT COUNT(*) FROM mem)/(SELECT n FROM tot),1)  AS memantine_pct,
  ROUND(100*(SELECT COUNT(*) FROM chei WHERE ndid IN (SELECT ndid FROM mem))/(SELECT n FROM tot),1) AS combo_all_pct,
  ROUND(100*(SELECT COUNT(*) FROM chei WHERE ndid IN (SELECT ndid FROM mem))
          /NULLIF((SELECT COUNT(*) FROM (SELECT ndid FROM chei UNION SELECT ndid FROM mem UNION SELECT ndid FROM mab) u),0),1) AS combo_treated_pct,
  (SELECT COUNT(DISTINCT ndid) FROM mab) AS mab_patients,
  ROUND(100*(SELECT COUNT(DISTINCT ndid) FROM mab)/(SELECT n FROM tot),1) AS mab_pct;


/* ---------------------------------------------------------------------------
   Q9.  FIGURE 3 — CUMULATIVE medication use by year (2015-2026; 2026 partial)
        Numerator = patients who had EVER received a class by year Y.
        Denominator = patients DIAGNOSED by year Y (no death adjustment).
        Panel A = cumulative counts; Panels B/C = cumulative coverage %.
        ->  2026 endpoints equal the cross-sectional "ever treated" values:
            any 70.3% | ChEI 60.4% | memantine 44.5% | mAb 5.9%
            (mAb cumulative: 2023 0.5, 2024 2.5, 2025 5.0, 2026 5.9)
   --------------------------------------------------------------------------- */
WITH ad AS (
  SELECT ndid, YEAR(MIN(diag_date)) AS dx_year
  FROM ad_mci_prod.diagnosis
  WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)'
    AND diag_date >= '2015-01-01' AND diag_date < '2026-05-01'
  GROUP BY ndid
),
yrs AS (
  SELECT 2015 yr UNION SELECT 2016 UNION SELECT 2017 UNION SELECT 2018 UNION SELECT 2019
  UNION SELECT 2020 UNION SELECT 2021 UNION SELECT 2022 UNION SELECT 2023 UNION SELECT 2024
  UNION SELECT 2025 UNION SELECT 2026
),
denom AS (  -- cumulative diagnosed by each year (NO death adjustment)
  SELECT y.yr, COUNT(*) AS ad_dx
  FROM yrs y JOIN ad a ON a.dx_year <= y.yr
  GROUP BY y.yr
),
firstyr AS (  -- first year each patient received each class
  SELECT ndid, cls, MIN(yr) AS first_yr FROM (
    SELECT me.ndid,
      CASE WHEN LOWER(me.med_name) REGEXP 'donepezil|aricept|rivastigmine|exelon|galantamine|razadyne' THEN 'chei'
           WHEN LOWER(me.med_name) REGEXP 'memantine|namenda' THEN 'mem'
           WHEN LOWER(me.med_name) REGEXP 'lecanemab|leqembi|donanemab|kisunla' THEN 'mab' END AS cls,
      YEAR(COALESCE(me.medication_start_date,me.fill_date,me.enc_date)) AS yr
    FROM ad_mci_prod.medication me JOIN ad ON ad.ndid=me.ndid
    WHERE LOWER(me.med_name) REGEXP 'donepezil|aricept|rivastigmine|exelon|galantamine|razadyne|memantine|namenda|lecanemab|leqembi|donanemab|kisunla'
      AND COALESCE(me.medication_start_date,me.fill_date,me.enc_date) <= '2026-04-30'
    UNION ALL
    SELECT pr.ndid, 'mab', YEAR(COALESCE(pr.proc_start_date,pr.proc_end_date,pr.enc_date))
    FROM ad_mci_prod.procedures pr JOIN ad ON ad.ndid=pr.ndid
    WHERE UPPER(pr.proc_code) IN ('J0174','J0175')
      AND COALESCE(pr.proc_start_date,pr.proc_end_date,pr.enc_date) <= '2026-04-30'
  ) e WHERE yr BETWEEN 2015 AND 2026 GROUP BY ndid, cls
),
cum AS (
  SELECT y.yr,
    COUNT(DISTINCT CASE WHEN f.cls='chei' AND f.first_yr<=y.yr THEN f.ndid END) AS chei,
    COUNT(DISTINCT CASE WHEN f.cls='mem'  AND f.first_yr<=y.yr THEN f.ndid END) AS mem,
    COUNT(DISTINCT CASE WHEN f.cls='mab'  AND f.first_yr<=y.yr THEN f.ndid END) AS mab,
    COUNT(DISTINCT CASE WHEN f.first_yr<=y.yr THEN f.ndid END)                  AS any_agent
  FROM yrs y LEFT JOIN firstyr f ON f.first_yr <= y.yr
  GROUP BY y.yr
)
SELECT d.yr, d.ad_dx,
  c.chei, c.mem, c.mab, c.any_agent,                       -- Panel A (cumulative counts)
  ROUND(100*c.chei/d.ad_dx,1)      AS chei_pct,            -- Panel B
  ROUND(100*c.mem/d.ad_dx,1)       AS mem_pct,
  ROUND(100*c.any_agent/d.ad_dx,1) AS any_pct,
  ROUND(100*c.mab/d.ad_dx,1)       AS mab_pct              -- Panel C
FROM denom d JOIN cum c ON c.yr = d.yr
ORDER BY d.yr;
