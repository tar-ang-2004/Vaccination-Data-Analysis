-- SQL QUERIES FOR TABLEAU DASHBOARD
-- Ready-to-use queries for each analysis question

-- EASY LEVEL QUERIES

-- Question 1 & 9: Vaccination Rates vs Disease Incidence Correlation
SELECT 
    c.country_name,
    c.who_region,
    cov.year,
    a.antigen_description,
    d.disease_description,
    AVG(cov.coverage_percentage) as avg_coverage,
    AVG(inc.incidence_rate) as avg_incidence_rate,
    AVG(rc.cases) as avg_cases
FROM coverage cov
JOIN countries c ON cov.country_id = c.country_id
JOIN antigens a ON cov.antigen_id = a.antigen_id
LEFT JOIN incidence_rates inc ON c.country_id = inc.country_id AND cov.year = inc.year
LEFT JOIN diseases d ON inc.disease_id = d.disease_id
LEFT JOIN reported_cases rc ON c.country_id = rc.country_id AND cov.year = rc.year AND inc.disease_id = rc.disease_id
WHERE cov.year BETWEEN 2010 AND 2023
GROUP BY c.country_name, c.who_region, cov.year, a.antigen_description, d.disease_description;

-- Question 2: Drop-off Rate Between 1st and Subsequent Doses
WITH dose_comparison AS (
    SELECT 
        c.country_name,
        c.who_region,
        cov.year,
        CASE 
            WHEN a.antigen_description LIKE '%1st dose%' THEN 'First Dose'
            WHEN a.antigen_description LIKE '%3rd dose%' THEN 'Third Dose'
            WHEN a.antigen_description LIKE '%4th dose%' OR a.antigen_description LIKE '%booster%' THEN 'Booster'
        END as dose_type,
        AVG(cov.coverage_percentage) as coverage
    FROM coverage cov
    JOIN countries c ON cov.country_id = c.country_id
    JOIN antigens a ON cov.antigen_id = a.antigen_id
    WHERE a.antigen_description LIKE '%DTP%' 
        AND (a.antigen_description LIKE '%1st dose%' OR a.antigen_description LIKE '%3rd dose%')
    GROUP BY c.country_name, c.who_region, cov.year, dose_type
)
SELECT 
    country_name,
    who_region,
    year,
    MAX(CASE WHEN dose_type = 'First Dose' THEN coverage END) as first_dose_coverage,
    MAX(CASE WHEN dose_type = 'Third Dose' THEN coverage END) as third_dose_coverage,
    (MAX(CASE WHEN dose_type = 'First Dose' THEN coverage END) - 
     MAX(CASE WHEN dose_type = 'Third Dose' THEN coverage END)) as coverage_drop,
    CASE 
        WHEN MAX(CASE WHEN dose_type = 'First Dose' THEN coverage END) > 0
        THEN ((MAX(CASE WHEN dose_type = 'First Dose' THEN coverage END) - 
               MAX(CASE WHEN dose_type = 'Third Dose' THEN coverage END)) / 
               MAX(CASE WHEN dose_type = 'First Dose' THEN coverage END)) * 100
        ELSE 0 
    END as drop_off_percentage
FROM dose_comparison
GROUP BY country_name, who_region, year
HAVING first_dose_coverage IS NOT NULL AND third_dose_coverage IS NOT NULL;

-- Question 6: Booster Dose Uptake Trends
SELECT 
    c.country_name,
    c.who_region,
    cov.year,
    a.antigen_description,
    AVG(cov.coverage_percentage) as booster_coverage,
    AVG(cov.target_number) as target_population,
    AVG(cov.doses) as doses_administered
FROM coverage cov
JOIN countries c ON cov.country_id = c.country_id
JOIN antigens a ON cov.antigen_id = a.antigen_id
WHERE a.antigen_description LIKE '%booster%' 
   OR a.antigen_description LIKE '%4th dose%'
   OR a.antigen_description LIKE '%2nd booster%'
GROUP BY c.country_name, c.who_region, cov.year, a.antigen_description
ORDER BY cov.year, c.who_region, AVG(cov.coverage_percentage) DESC;

-- Question 8: Population Density vs Coverage (Using target population as proxy)
SELECT 
    c.country_name,
    c.who_region,
    cov.year,
    SUM(cov.target_number) as total_target_population,
    AVG(cov.coverage_percentage) as avg_coverage,
    SUM(cov.doses) as total_doses,
    COUNT(DISTINCT a.antigen_id) as vaccines_offered,
    SUM(cov.target_number) / COUNT(DISTINCT a.antigen_id) as avg_target_per_vaccine
FROM coverage cov
JOIN countries c ON cov.country_id = c.country_id
JOIN antigens a ON cov.antigen_id = a.antigen_id
WHERE cov.year = 2023  -- Latest year
GROUP BY c.country_name, c.who_region, cov.year
ORDER BY total_target_population DESC;

-- Question 10: High Disease Incidence Despite High Vaccination
SELECT 
    c.country_name,
    c.who_region,
    d.disease_description,
    inc.year,
    AVG(cov.coverage_percentage) as avg_coverage,
    AVG(inc.incidence_rate) as avg_incidence,
    AVG(rc.cases) as avg_cases
FROM incidence_rates inc
JOIN countries c ON inc.country_id = c.country_id
JOIN diseases d ON inc.disease_id = d.disease_id
LEFT JOIN coverage cov ON c.country_id = cov.country_id AND inc.year = cov.year
LEFT JOIN reported_cases rc ON c.country_id = rc.country_id AND inc.year = rc.year AND inc.disease_id = rc.disease_id
WHERE inc.year BETWEEN 2015 AND 2023
GROUP BY c.country_name, c.who_region, d.disease_description, inc.year
HAVING AVG(cov.coverage_percentage) > 70 AND AVG(inc.incidence_rate) > 10
ORDER BY AVG(inc.incidence_rate) DESC;

-- MEDIUM LEVEL QUERIES

-- Question 1: Vaccine Introduction vs Disease Case Reduction
WITH case_trends AS (
    SELECT 
        c.country_name,
        c.who_region,
        d.disease_description,
        rc.year,
        SUM(rc.cases) as total_cases,
        LAG(SUM(rc.cases), 1) OVER (PARTITION BY c.country_name, d.disease_description ORDER BY rc.year) as previous_year_cases
    FROM reported_cases rc
    JOIN countries c ON rc.country_id = c.country_id
    JOIN diseases d ON rc.disease_id = d.disease_id
    GROUP BY c.country_name, c.who_region, d.disease_description, rc.year
),
introduction_years AS (
    SELECT 
        c.country_name,
        vi.description as vaccine_description,
        MIN(vi.year) as introduction_year
    FROM vaccine_introductions vi
    JOIN countries c ON vi.iso_3_code = c.country_code
    WHERE vi.intro = 'YES'
    GROUP BY c.country_name, vi.description
)
SELECT 
    ct.country_name,
    ct.who_region,
    ct.disease_description,
    iy.introduction_year,
    AVG(CASE WHEN ct.year < iy.introduction_year THEN ct.total_cases END) as avg_cases_before,
    AVG(CASE WHEN ct.year >= iy.introduction_year THEN ct.total_cases END) as avg_cases_after,
    (AVG(CASE WHEN ct.year < iy.introduction_year THEN ct.total_cases END) - 
     AVG(CASE WHEN ct.year >= iy.introduction_year THEN ct.total_cases END)) as case_reduction,
    CASE 
        WHEN AVG(CASE WHEN ct.year < iy.introduction_year THEN ct.total_cases END) > 0
        THEN ((AVG(CASE WHEN ct.year < iy.introduction_year THEN ct.total_cases END) - 
               AVG(CASE WHEN ct.year >= iy.introduction_year THEN ct.total_cases END)) / 
               AVG(CASE WHEN ct.year < iy.introduction_year THEN ct.total_cases END)) * 100
        ELSE NULL
    END as reduction_percentage
FROM case_trends ct
LEFT JOIN introduction_years iy ON ct.country_name = iy.country_name
WHERE iy.introduction_year IS NOT NULL
GROUP BY ct.country_name, ct.who_region, ct.disease_description, iy.introduction_year
HAVING avg_cases_before IS NOT NULL AND avg_cases_after IS NOT NULL;

-- Question 3: Diseases with Most Significant Reduction
WITH decade_comparison AS (
    SELECT 
        d.disease_description,
        SUM(CASE WHEN rc.year BETWEEN 1980 AND 1989 THEN rc.cases ELSE 0 END) as cases_1980s,
        SUM(CASE WHEN rc.year BETWEEN 2010 AND 2019 THEN rc.cases ELSE 0 END) as cases_2010s,
        COUNT(CASE WHEN rc.year BETWEEN 1980 AND 1989 THEN 1 END) as countries_1980s,
        COUNT(CASE WHEN rc.year BETWEEN 2010 AND 2019 THEN 1 END) as countries_2010s
    FROM reported_cases rc
    JOIN diseases d ON rc.disease_id = d.disease_id
    GROUP BY d.disease_description
)
SELECT 
    disease_description,
    cases_1980s,
    cases_2010s,
    (cases_1980s - cases_2010s) as absolute_reduction,
    CASE 
        WHEN cases_1980s > 0 
        THEN ((cases_1980s - cases_2010s) / CAST(cases_1980s AS FLOAT)) * 100
        ELSE 0 
    END as reduction_percentage,
    countries_1980s,
    countries_2010s
FROM decade_comparison
WHERE cases_1980s > 0
ORDER BY reduction_percentage DESC;

-- Question 4: Target Population Coverage by Vaccine
SELECT 
    a.antigen_description,
    c.who_region,
    cov.year,
    SUM(cov.target_number) as total_target,
    SUM(cov.doses) as total_doses,
    CASE 
        WHEN SUM(cov.target_number) > 0 
        THEN (SUM(cov.doses) / CAST(SUM(cov.target_number) AS FLOAT)) * 100
        ELSE 0 
    END as actual_coverage_rate,
    AVG(cov.coverage_percentage) as reported_coverage_rate,
    COUNT(DISTINCT c.country_id) as countries_with_data
FROM coverage cov
JOIN countries c ON cov.country_id = c.country_id
JOIN antigens a ON cov.antigen_id = a.antigen_id
WHERE cov.year >= 2015
GROUP BY a.antigen_description, c.who_region, cov.year
ORDER BY actual_coverage_rate DESC;

-- Question 6: Regional Vaccine Introduction Disparities
SELECT 
    c.who_region,
    vi.description as vaccine_description,
    MIN(vi.year) as earliest_introduction,
    MAX(vi.year) as latest_introduction,
    AVG(vi.year) as average_introduction_year,
    (MAX(vi.year) - MIN(vi.year)) as introduction_span_years,
    COUNT(DISTINCT c.country_name) as countries_introduced,
    COUNT(DISTINCT c2.country_name) as total_countries_in_region
FROM vaccine_introductions vi
JOIN countries c ON vi.iso_3_code = c.country_code
JOIN countries c2 ON c.who_region = c2.who_region
WHERE vi.intro = 'YES'
GROUP BY c.who_region, vi.description
ORDER BY c.who_region, average_introduction_year;

-- SCENARIO-BASED QUERIES

-- Scenario 1: Resource Allocation - Low Coverage Countries
SELECT 
    c.country_name,
    c.who_region,
    AVG(cov.coverage_percentage) as avg_coverage,
    SUM(cov.target_number) as total_target_population,
    SUM(cov.doses) as total_doses_given,
    SUM(cov.target_number) - SUM(cov.doses) as coverage_gap,
    CASE 
        WHEN AVG(cov.coverage_percentage) < 30 THEN 'Critical Priority'
        WHEN AVG(cov.coverage_percentage) < 50 THEN 'High Priority'
        WHEN AVG(cov.coverage_percentage) < 70 THEN 'Medium Priority'
        ELSE 'Low Priority'
    END as priority_level,
    COUNT(DISTINCT a.antigen_id) as vaccines_tracked
FROM coverage cov
JOIN countries c ON cov.country_id = c.country_id
JOIN antigens a ON cov.antigen_id = a.antigen_id
WHERE cov.year >= 2020  -- Recent data only
GROUP BY c.country_name, c.who_region
ORDER BY avg_coverage ASC, total_target_population DESC;

-- Scenario 2: Measles Campaign Effectiveness (2015-2020)
SELECT 
    c.country_name,
    c.who_region,
    cov.year,
    AVG(cov.coverage_percentage) as measles_coverage,
    AVG(rc.cases) as measles_cases,
    AVG(inc.incidence_rate) as measles_incidence,
    LAG(AVG(cov.coverage_percentage), 1) OVER (PARTITION BY c.country_name ORDER BY cov.year) as previous_coverage,
    AVG(cov.coverage_percentage) - LAG(AVG(cov.coverage_percentage), 1) OVER (PARTITION BY c.country_name ORDER BY cov.year) as coverage_change
FROM coverage cov
JOIN countries c ON cov.country_id = c.country_id
JOIN antigens a ON cov.antigen_id = a.antigen_id
LEFT JOIN reported_cases rc ON c.country_id = rc.country_id AND cov.year = rc.year
LEFT JOIN diseases d ON rc.disease_id = d.disease_id AND d.disease_description = 'Measles'
LEFT JOIN incidence_rates inc ON c.country_id = inc.country_id AND cov.year = inc.year AND inc.disease_id = d.disease_id
WHERE a.antigen_description LIKE '%Measles%'
    AND cov.year BETWEEN 2015 AND 2020
GROUP BY c.country_name, c.who_region, cov.year
ORDER BY c.country_name, cov.year;

-- Scenario 6: WHO 95% Coverage Target Progress for Measles by 2030
WITH measles_trends AS (
    SELECT 
        c.country_name,
        c.who_region,
        cov.year,
        AVG(cov.coverage_percentage) as coverage
    FROM coverage cov
    JOIN countries c ON cov.country_id = c.country_id
    JOIN antigens a ON cov.antigen_id = a.antigen_id
    WHERE a.antigen_description LIKE '%Measles%'
        AND cov.year >= 2015
    GROUP BY c.country_name, c.who_region, cov.year
),
latest_coverage AS (
    SELECT 
        country_name,
        who_region,
        coverage as current_coverage,
        ROW_NUMBER() OVER (PARTITION BY country_name ORDER BY year DESC) as rn
    FROM measles_trends
),
trend_analysis AS (
    SELECT 
        country_name,
        who_region,
        AVG(coverage) as avg_coverage_2015_2023,
        (MAX(CASE WHEN year = 2023 THEN coverage END) - MAX(CASE WHEN year = 2015 THEN coverage END)) / 8 as annual_trend
    FROM measles_trends
    WHERE year IN (2015, 2023)
    GROUP BY country_name, who_region
)
SELECT 
    lc.country_name,
    lc.who_region,
    lc.current_coverage,
    ta.annual_trend,
    lc.current_coverage + (ta.annual_trend * 7) as projected_2030_coverage,
    CASE 
        WHEN lc.current_coverage + (ta.annual_trend * 7) >= 95 THEN 'On Track'
        WHEN lc.current_coverage + (ta.annual_trend * 7) >= 85 THEN 'Needs Acceleration'
        ELSE 'Off Track'
    END as target_status,
    95 - lc.current_coverage as current_gap,
    95 - (lc.current_coverage + (ta.annual_trend * 7)) as projected_gap_2030
FROM latest_coverage lc
JOIN trend_analysis ta ON lc.country_name = ta.country_name
WHERE lc.rn = 1
ORDER BY projected_2030_coverage DESC;

-- Global Summary Dashboard Query
SELECT 
    'Global Summary' as metric_type,
    COUNT(DISTINCT c.country_name) as total_countries,
    COUNT(DISTINCT a.antigen_description) as total_vaccines,
    COUNT(DISTINCT d.disease_description) as total_diseases,
    AVG(cov.coverage_percentage) as global_avg_coverage,
    SUM(cov.target_number) as global_target_population,
    SUM(cov.doses) as global_doses_administered,
    MAX(cov.year) as latest_data_year,
    COUNT(*) as total_records
FROM coverage cov
JOIN countries c ON cov.country_id = c.country_id
JOIN antigens a ON cov.antigen_id = a.antigen_id
LEFT JOIN incidence_rates inc ON c.country_id = inc.country_id AND cov.year = inc.year
LEFT JOIN diseases d ON inc.disease_id = d.disease_id

UNION ALL

SELECT 
    'Regional Breakdown' as metric_type,
    COUNT(DISTINCT c.country_name) as countries_in_region,
    COUNT(DISTINCT a.antigen_description) as vaccines_tracked,
    COUNT(DISTINCT d.disease_description) as diseases_tracked,
    AVG(cov.coverage_percentage) as regional_avg_coverage,
    SUM(cov.target_number) as regional_target,
    SUM(cov.doses) as regional_doses,
    MAX(cov.year) as latest_year,
    0 as placeholder
FROM coverage cov
JOIN countries c ON cov.country_id = c.country_id
JOIN antigens a ON cov.antigen_id = a.antigen_id
LEFT JOIN incidence_rates inc ON c.country_id = inc.country_id AND cov.year = inc.year
LEFT JOIN diseases d ON inc.disease_id = d.disease_id
GROUP BY c.who_region;
