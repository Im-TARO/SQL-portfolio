USE public;
DROP TABLE IF EXISTS dates;

/* ============================================================================
|* Table:	dates
|* Purpose:	Date dimension table 
|*				Each row represents one calendar day, with date related
|*				attributes to support filtering, grouping, and sorting
|*				in reports and BI tools	
|*
|* Grain:			One row per calendar day.
|* Primary key:	date_key (smart key in YYYYMMDD format, e.g. 202600101)
|* Joins to:		Tables via their date foreign key column(s).
|* ============================================================================ */

CREATE TABLE dates (
  `date_key` int NOT NULL comment 'Primary key. Date as integer (YYYYMMDD)',
  `date` DATE NOT NULL UNIQUE comment 'Calendar date (YYYY-MM-DD)',
  `year` int NOT NULL comment 'Four digit calendar year',
  `quarter` int DEFAULT NULL comment 'Calendar quarter, 1-4',
  `month_name` varchar(9) DEFAULT NULL comment 'Full month name for display',
  `month_sort` int DEFAULT NULL comment 'Month number 1-12, use to sort month_name',
  `day_name` varchar(9) DEFAULT NULL comment 'Full weekday name for dispay',
  `day_sort` int DEFAULT NULL comment 'Day of week number, use to sort day_name',
  `is_weekend` tinyint DEFAULT NULL comment 'Flag 1 = Saturday/Sunday, 0 = weekday',
  `is_holiday` tinyint DEFAULT NULL comment 'Flag 1 = US holiday, 0 = not a holiday',
  `holiday_name` varchar(30) DEFAULT NULL comment 'Holiday name for display',
  PRIMARY KEY (`date_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci comment='Date dimension: one row per calendar date with date related attributes';



