DROP PROCEDURE IF EXISTS load_dates;

delimiter $$

CREATE PROCEDURE load_dates (p_start_date DATE, p_end_date DATE) begin
/* ========================================================	*|
|* Generates a complete calendar table with weekend and US	*|
|* federal holiday flags												*|
|* ======================================================== */
SET SESSION cte_max_recursion_depth=5000;

INSERT INTO dates
WITH RECURSIVE
/* ------------------------------------------------------------*|
|* STEP 1: DATE RANGE														*|	
|* Recursively generates one row per day between start_date 	*|
|* and end_date (inclusive). The end_date is carried through 	*|
|* each iteration to avoid re-running the subquery each loop.	*|
|* ------------------------------------------------------------ */
date_range AS (
    -- Anchor: start at the p_start date
    SELECT p_start_date AS dates, p_end_date end_date -- FROM bounds
    UNION ALL
    -- Recursion: add one day at a time until p_end_date is reached
    SELECT DATE_ADD(dates, INTERVAL 1 DAY), end_date
    FROM date_range
    WHERE dates < end_date
),

/* ---------------------------------------------------------*|
|* STEP 2: MONDAYS														*|
|* Identifies all Mondays in the months needed for 			*|
|* Monday-based federal holidays:									*|
|*     Jan (1)  = MLK Jr Day       (3rd Monday)					*|
|*     Feb (2)  = Presidents Day   (3rd Monday)					*|
|*     May (5)  = Memorial Day     (last Monday)				*|
|*     Sep (9)  = Labor Day        (1st Monday)					*|
|*     Oct (10) = Columbus Day     (2nd Monday)					*|
|*																				*|
|*   Two rankings are computed per month/year partition:		*|
|*     monday_num  (ASC)  = 1st, 2nd, 3rd... Monday			*|
|*     monday_rank (DESC) = 1 = last Monday in the month		*|
|* -------------------------------------------------------- */
mondays AS (
    SELECT
        dates,
        MONTH(dates) AS mth,
        ROW_NUMBER() OVER (PARTITION BY YEAR(dates), MONTH(dates) ORDER BY dates)      AS monday_num,
        ROW_NUMBER() OVER (PARTITION BY YEAR(dates), MONTH(dates) ORDER BY dates DESC) AS monday_rank
    FROM date_range
    WHERE MONTH(dates) IN (1, 2, 5, 9, 10)  -- Only months with Monday-based holidays
      AND DAYOFWEEK(dates) = 2               -- 2 = Monday in MySQL
),

/* --------------------------------------------------------------	*|
|* STEP 3: THANKSGIVING															*|
|* Identifies all Thursdays in November and ranks them 				*|
|* ascending within each year.												*|
|* Thanksgiving = 4th Thursday in November (thursday_num = 4).		*|
|* Note: If November has 5 Thursdays, the 4th is still correct.	*|
|* -------------------------------------------------------------- */
thanksgiving AS (
    SELECT
        dates,
        ROW_NUMBER() OVER (PARTITION BY YEAR(dates) ORDER BY dates) AS thursday_num
    FROM date_range
    WHERE MONTH(dates) = 11
      AND DAYOFWEEK(dates) = 5   -- 5 = Thursday in MySQL
),

/* -----------------------------------------------------------	*|
|* STEP 4: FIXED HOLIDAYS													*|
|* Handles all fixed-date federal holidays in a single CTE,		*|
|* applying the standard weekend observation rule:					*|
|*   - If the holiday falls on Saturday, observed on Friday		*|
|*   - If the holiday falls on Sunday, observed on Monday		*|
|*   - Otherwise observed on same day									*|
|*																					*|
|* Holidays included:														*|
|*   Jan  1  = New Year's Day												*|
|*   Jun  19 = Juneteenth (federal holiday from 2021 onward)	*|
|*   Jul  4  = Independence Day											*|
|*   Nov  11 = Veterans Day												*|
|*   Dec  25 = Christmas Day												*|
|* ----------------------------------------------------------- */
fixed_holidays AS (
    SELECT
        dates AS actual_date,
        CASE DAYOFWEEK(dates)
            WHEN 7 THEN DATE_SUB(dates, INTERVAL 1 DAY)  -- Saturday → Friday
            WHEN 1 THEN DATE_ADD(dates, INTERVAL 1 DAY)  -- Sunday   → Monday
            ELSE dates                                   -- same day
        END AS observed_date,
        CASE
            WHEN MONTH(dates) = 1  AND DAY(dates) = 1  THEN 'New Years Day'
            WHEN MONTH(dates) = 6  AND DAY(dates) = 19 THEN 'Juneteenth'
            WHEN MONTH(dates) = 7  AND DAY(dates) = 4  THEN 'Independence Day'
            WHEN MONTH(dates) = 11 AND DAY(dates) = 11 THEN 'Veterans Day'
            WHEN MONTH(dates) = 12 AND DAY(dates) = 25 THEN 'Christmas'
        END AS holiday_name
    FROM date_range
    WHERE (MONTH(dates) = 1  AND DAY(dates) = 1)                            -- New Year's Day
       OR (MONTH(dates) = 6  AND DAY(dates) = 19 AND YEAR(dates) >= 2021)  -- Juneteenth (2021+)
       OR (MONTH(dates) = 7  AND DAY(dates) = 4)                            -- Independence Day
       OR (MONTH(dates) = 11 AND DAY(dates) = 11)                           -- Veterans Day
       OR (MONTH(dates) = 12 AND DAY(dates) = 25)                           -- Christmas
)

/* ============================================================
   FINAL SELECT
   Joins all CTEs back to the full date_range and produces 
   one row per day with the following flags:

     is_weekend  = 1 if Saturday or Sunday, else 0
     is_holiday  = 1 if the date is a US federal holiday 
                   (observed date), else 0

   JOIN notes:
     - mondays      joins only on Monday dates in relevant months
                    all other dates return NULL (handled by CASE)
     - thanksgiving joins only on Thursday dates in November
     - fixed_holidays joins on the OBSERVED date, so shifted 
                    holidays correctly flag the observed day
   ============================================================ */
SELECT
    DATE_FORMAT(d.dates, '%Y%m%d')   date_key,    -- Surrogate key: YYYYMMDD integer format
    DATE(d.dates)                    date,
    YEAR(d.dates)                    year,
    QUARTER(d.dates)                 quarter,
    MONTHNAME(d.dates)               month_name,
    MONTH(d.dates)                   month_sort,
    DAYNAME(d.dates)                 day_name,
    DAYOFWEEK(d.dates)               day_sort,

    -- Weekend flag: 1 = Saturday (7) or Sunday (1)
    CASE WHEN DAYOFWEEK(d.dates) IN (1, 7) THEN 1 ELSE 0 END AS is_weekend,

    -- Holiday flag: evaluates fixed holidays first, then Monday-based holidays,
    -- then Thanksgiving. Returns 1 if any condition matches, else 0.
    CASE
        WHEN fh.observed_date IS NOT NULL                THEN 1  -- New Year's, Juneteenth, Jul 4, Veterans, Christmas
        WHEN MONTH(d.dates) = 1  AND m.monday_num  = 3  THEN 1  -- MLK Jr Day        (3rd Mon in Jan)
        WHEN MONTH(d.dates) = 2  AND m.monday_num  = 3  THEN 1  -- Presidents Day    (3rd Mon in Feb)
        WHEN MONTH(d.dates) = 5  AND m.monday_rank = 1  THEN 1  -- Memorial Day      (last Mon in May)
        WHEN MONTH(d.dates) = 9  AND m.monday_num  = 1  THEN 1  -- Labor Day         (1st Mon in Sep)
        WHEN MONTH(d.dates) = 10 AND m.monday_num  = 2  THEN 1  -- Columbus Day      (2nd Mon in Oct)
        WHEN MONTH(d.dates) = 11 AND t.thursday_num = 4 THEN 1  -- Thanksgiving      (4th Thu in Nov)
        ELSE 0
    END AS is_holiday

FROM date_range d
LEFT JOIN mondays        m  ON d.dates = m.dates           -- Matches only Mondays in relevant months
LEFT JOIN thanksgiving   t  ON d.dates = t.dates           -- Matches only Thursdays in November
LEFT JOIN fixed_holidays fh ON d.dates = fh.observed_date  -- Matches on observed (possibly shifted) date
ORDER BY d.dates;
END $$ 

delimiter ;