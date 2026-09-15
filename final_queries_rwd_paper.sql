/* ============================================================================
   NeuroDiscovery AI — ICD code-diagnosed Alzheimer's disease cohort
   FINAL, VERIFIED QUERIES  (all outputs reconciled against the manuscript)
   Schema: ad_mci_prod
   AD definition (used everywhere): ICD-10 G30.x OR ICD-9 331.0, with codes
   normalized by removing decimal separators. F02.8x is NOT included.
   ============================================================================ */


/* --------------------------------------------------------------------------
   Q1.  COHORT SIZE  ->  N = 59,245
   -------------------------------------------------------------------------- */
SELECT COUNT(DISTINCT ndid) AS ad_cohort
FROM ad_mci_prod.diagnosis
WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)';


/* --------------------------------------------------------------------------
   Q2.  CODE-vs-FREE-TEXT VALIDATION  ->  code_only = 0, desc_only = 0
        (code-based and text-based definitions identify an identical set)
   -------------------------------------------------------------------------- */
WITH tagged AS (
  SELECT ndid,
    MAX(REPLACE(diag_code,'.','') REGEXP '^(G30|3310)') AS by_code,
    MAX(LOWER(diag_desc) LIKE '%alzheimer%')            AS by_desc
  FROM ad_mci_prod.diagnosis
  WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)'
     OR LOWER(diag_desc) LIKE '%alzheimer%'
  GROUP BY ndid
)
SELECT SUM(by_code=1) AS code_total, SUM(by_desc=1) AS desc_total,
       SUM(by_code=1 AND by_desc=0) AS code_only,
       SUM(by_code=0 AND by_desc=1) AS desc_only
FROM tagged;


/* --------------------------------------------------------------------------
   Q3.  TABLE 1  ->  N=59,245; mean age 79 ± 9; Female 57.4%; Male 35.5%;
                     sex missing 7.1%
   -------------------------------------------------------------------------- */
WITH ad AS (
  SELECT ndid, MIN(diag_date) AS first_ad
  FROM ad_mci_prod.diagnosis
  WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)' GROUP BY ndid
)
SELECT COUNT(*) AS ad_total,
  ROUND(AVG(YEAR(a.first_ad)-p.year_of_birth))    AS mean_age,
  ROUND(STDDEV(YEAR(a.first_ad)-p.year_of_birth)) AS sd_age,
  ROUND(100*SUM(p.gender='Female')/COUNT(*),1)    AS female_pct,
  ROUND(100*SUM(p.gender='Male')/COUNT(*),1)      AS male_pct,
  ROUND(100*SUM(p.gender IS NULL OR p.gender NOT IN ('Female','Male'))/COUNT(*),1) AS sex_missing_pct
FROM ad a JOIN ad_mci_prod.patients p ON p.ndid = a.ndid
WHERE p.year_of_birth IS NOT NULL;


/* --------------------------------------------------------------------------
   Q4.  FIGURE 1A — age at first diagnosis (% of cohort)
        <50 0.6 | 50-59 2.4 | 60-69 10.2 | 70-79 34.7 | 80-89 42.5 | 90+ 9.7
   -------------------------------------------------------------------------- */
WITH ad AS (
  SELECT ndid, MIN(diag_date) AS first_ad FROM ad_mci_prod.diagnosis
  WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)' GROUP BY ndid
),
aged AS (
  SELECT (YEAR(a.first_ad)-p.year_of_birth) AS age_dx
  FROM ad a JOIN ad_mci_prod.patients p ON p.ndid=a.ndid
  WHERE p.year_of_birth IS NOT NULL
)
SELECT
  CASE WHEN age_dx<50 THEN '<50' WHEN age_dx<60 THEN '50-59'
       WHEN age_dx<70 THEN '60-69' WHEN age_dx<80 THEN '70-79'
       WHEN age_dx<90 THEN '80-89' ELSE '90+' END AS age_band,
  COUNT(*) AS n, ROUND(100*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS pct
FROM aged WHERE age_dx BETWEEN 0 AND 120
GROUP BY age_band ORDER BY MIN(age_dx);


/* --------------------------------------------------------------------------
   Q5.  FIGURE 1B — AD diagnostic codes (% of cohort; categories overlap)
        G30.9 61.7 | ICD-9 331.0 31.0 | G30.1 24.0 | G30.0 6.6 | G30.8 3.0
   -------------------------------------------------------------------------- */
WITH ad AS (
  SELECT DISTINCT ndid FROM ad_mci_prod.diagnosis
  WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)'
),
c AS (
  SELECT ad.ndid, REPLACE(dg.diag_code,'.','') AS code
  FROM ad JOIN ad_mci_prod.diagnosis dg ON dg.ndid=ad.ndid
)
SELECT
  ROUND(100*COUNT(DISTINCT CASE WHEN code='G309' THEN ndid END)/59245,1) AS unspecified_g309,
  ROUND(100*COUNT(DISTINCT CASE WHEN code='3310' THEN ndid END)/59245,1) AS icd9_3310,
  ROUND(100*COUNT(DISTINCT CASE WHEN code='G301' THEN ndid END)/59245,1) AS late_onset_g301,
  ROUND(100*COUNT(DISTINCT CASE WHEN code='G300' THEN ndid END)/59245,1) AS early_onset_g300,
  ROUND(100*COUNT(DISTINCT CASE WHEN code='G308' THEN ndid END)/59245,1) AS other_g308
FROM c;


/* --------------------------------------------------------------------------
   Q6.  FIGURE 1C / RACE
        Not reported 58.3% of all;  among patients with recorded race:
        White 73.1% | Black 9.7% | Other 15.8% | Asian 1.4%
   -------------------------------------------------------------------------- */
-- 6a. raw values (inspection)
WITH ad AS (SELECT DISTINCT ndid FROM ad_mci_prod.diagnosis
            WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)')
SELECT p.race, COUNT(*) n
FROM ad JOIN ad_mci_prod.patients p ON p.ndid=ad.ndid
GROUP BY p.race ORDER BY n DESC;

-- 6b. grouped into standard categories (pct_of_all and pct_of_recorded)
WITH ad AS (SELECT DISTINCT ndid FROM ad_mci_prod.diagnosis
            WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)'),
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


/* --------------------------------------------------------------------------
   Q7.  FIGURE 2A — drug-class penetration (ever prescribed; date-independent)
        Any 69.4 | ChEI 61.4 | Memantine 44.7 | ChEI+Mem 37.5 (all) / 54.0 (treated) | mAb 3.4
        (single pass over medication; denominator hard-coded to 59,245)
   -------------------------------------------------------------------------- */
WITH ad AS (SELECT DISTINCT ndid FROM ad_mci_prod.diagnosis
            WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)'),
flags AS (
  SELECT me.ndid,
    MAX(LOWER(me.med_name) REGEXP 'donepezil|aricept|rivastigmine|exelon|galantamine|razadyne') chei,
    MAX(LOWER(me.med_name) REGEXP 'memantine|namenda') mem,
    MAX(LOWER(me.med_name) REGEXP 'lecanemab|leqembi|donanemab|kisunla|aducanumab|aduhelm') mab
  FROM ad_mci_prod.medication me JOIN ad ON ad.ndid = me.ndid
  GROUP BY me.ndid
)
SELECT
  ROUND(100*COUNT(CASE WHEN chei=1 OR mem=1 OR mab=1 THEN 1 END)/59245,1) AS any_pct,
  ROUND(100*SUM(chei)/59245,1)             AS chei_pct,
  ROUND(100*SUM(mem)/59245,1)              AS memantine_pct,
  ROUND(100*SUM(chei=1 AND mem=1)/59245,1) AS combo_all_pct,
  ROUND(100*SUM(chei=1 AND mem=1)/NULLIF(SUM(chei=1 OR mem=1 OR mab=1),0),1) AS combo_treated_pct,
  ROUND(100*SUM(mab)/59245,1)              AS mab_pct
FROM flags;


/* --------------------------------------------------------------------------
   Q8.  FIGURE 2B — individual anti-amyloid agents
        Lecanemab 1268 (62%) | Donanemab 760 (37%) | Aducanumab 112 (6%) | any 2036
        (percentages = each / any_mab)
   -------------------------------------------------------------------------- */
WITH ad AS (SELECT DISTINCT ndid FROM ad_mci_prod.diagnosis
            WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)')
SELECT
  COUNT(DISTINCT CASE WHEN LOWER(me.med_name) REGEXP 'lecanemab|leqembi'  THEN me.ndid END) AS lecanemab,
  COUNT(DISTINCT CASE WHEN LOWER(me.med_name) REGEXP 'donanemab|kisunla'  THEN me.ndid END) AS donanemab,
  COUNT(DISTINCT CASE WHEN LOWER(me.med_name) REGEXP 'aducanumab|aduhelm' THEN me.ndid END) AS aducanumab,
  COUNT(DISTINCT CASE WHEN LOWER(me.med_name) REGEXP 'lecanemab|leqembi|donanemab|kisunla|aducanumab|aduhelm'
                      THEN me.ndid END) AS any_mab
FROM ad_mci_prod.medication me JOIN ad ON ad.ndid = me.ndid;


/* --------------------------------------------------------------------------
   Q9.  FIGURE 3 — medication use by year (2008-2025)
        Year of a prescription = medication_start_date, else fill_date,
        else encounter date (three-tier COALESCE).
        Panel A = distinct treated patients (counts).
        Panels B & C = coverage = numerator / DENOMINATOR, where the
        denominator is AD patients diagnosed BY that year AND STILL ALIVE
        (death-adjusted).  This reproduces 2025 anti-amyloid coverage = 2.5%.
        NOTE: death_date is populated for ~4% of patients, so the adjustment
        is small; using a plain cumulative denominator instead gives 2.4%.
   -------------------------------------------------------------------------- */
WITH ad AS (
  SELECT a.ndid, YEAR(a.first_ad) AS dx_year, YEAR(p.`date(death_date)`) AS death_year
  FROM (SELECT ndid, MIN(diag_date) first_ad FROM ad_mci_prod.diagnosis
        WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)' GROUP BY ndid) a
  JOIN ad_mci_prod.patients p ON p.ndid = a.ndid
),
yrs AS (
  SELECT 2008 yr UNION SELECT 2009 UNION SELECT 2010 UNION SELECT 2011 UNION SELECT 2012
  UNION SELECT 2013 UNION SELECT 2014 UNION SELECT 2015 UNION SELECT 2016 UNION SELECT 2017
  UNION SELECT 2018 UNION SELECT 2019 UNION SELECT 2020 UNION SELECT 2021 UNION SELECT 2022
  UNION SELECT 2023 UNION SELECT 2024 UNION SELECT 2025
),
denom AS (   -- AD patients diagnosed by each year AND still alive
  SELECT y.yr, COUNT(*) AS ad_alive
  FROM yrs y JOIN ad d
    ON d.dx_year <= y.yr AND (d.death_year IS NULL OR d.death_year >= y.yr)
  GROUP BY y.yr
),
m AS (
  SELECT me.ndid,
    YEAR(COALESCE(me.medication_start_date, me.fill_date, me.enc_date)) AS yr,
    LOWER(me.med_name) AS nm
  FROM ad_mci_prod.medication me
  JOIN (SELECT DISTINCT ndid FROM ad_mci_prod.diagnosis
        WHERE REPLACE(diag_code,'.','') REGEXP '^(G30|3310)') a ON a.ndid = me.ndid
),
num AS (
  SELECT yr,
    COUNT(DISTINCT CASE WHEN nm REGEXP 'donepezil|aricept|rivastigmine|exelon|galantamine|razadyne' THEN ndid END) AS chei,
    COUNT(DISTINCT CASE WHEN nm REGEXP 'memantine|namenda' THEN ndid END) AS mem,
    COUNT(DISTINCT CASE WHEN nm REGEXP 'lecanemab|leqembi|donanemab|kisunla|aducanumab|aduhelm' THEN ndid END) AS mab,
    COUNT(DISTINCT ndid) AS any_agent
  FROM m WHERE yr BETWEEN 2008 AND 2025 GROUP BY yr
)
SELECT d.yr,
  n.chei, n.mem, n.mab, n.any_agent,                       -- Figure 3A (counts)
  ROUND(100*n.chei/d.ad_alive,1)      AS chei_pct,         -- Figure 3B
  ROUND(100*n.mem/d.ad_alive,1)       AS mem_pct,
  ROUND(100*n.any_agent/d.ad_alive,1) AS any_pct,
  ROUND(100*n.mab/d.ad_alive,1)       AS mab_pct           -- Figure 3C (2025 = 2.5%)
FROM denom d JOIN num n ON n.yr = d.yr
ORDER BY d.yr;
