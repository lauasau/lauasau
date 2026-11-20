USE INFORMRMSREPORTS;

/*
  Cases, addresses and vehicles for a list of people.

  Add one row per person to @People (LASTNAME, FIRSTNAME, MIDDLENAME, DATEOFBIRTH).
  MIDDLENAME may be NULL: then any middle name (or none) matches.

  Returns three result grids:
    1. Cases from the past 5 years (Suspect, DNA Databank Hit, Latent Print
       Identification and Person of Interest rows hidden when the same person
       is an Arrestee on the case)
    2. Addresses linked to those person records
    3. Vehicles linked to those person records

  Lines marked CHECK use guessed table/column names; confirm them with the
  INFORMATION_SCHEMA query at the bottom of this file.
*/
DECLARE @People TABLE (
    LASTNAME    VARCHAR(100) NOT NULL,
    FIRSTNAME   VARCHAR(100) NOT NULL,
    MIDDLENAME  VARCHAR(100) NULL,       -- NULL = no middle name / match any
    DATEOFBIRTH DATE         NOT NULL,
    UNIQUE (LASTNAME, FIRSTNAME, MIDDLENAME, DATEOFBIRTH)
);

INSERT INTO @People (LASTNAME, FIRSTNAME, MIDDLENAME, DATEOFBIRTH) VALUES
    ('SMITH',   'ADAM', NULL,    '1990-01-01'),
    ('ANDREWS', 'ADAM', 'JAMES', '1990-01-01');   -- last row ends with ;

-- Matching person records, saved once and reused by all three result grids.
IF OBJECT_ID('tempdb..#VIP') IS NOT NULL DROP TABLE #VIP;

SELECT DISTINCT
    P.ID AS PERSON_ID,                                   -- CHECK
    R.CASENUMBER,
    CONCAT(P.LASTNAME, ',', P.FIRSTNAME) AS FULLNAME,    -- no space after comma
    P.MIDDLENAME,                                        -- CHECK
    P.DATEOFBIRTH,
    P.INVOLVEMENTTYPE_CODE
INTO #VIP
FROM @People L
    INNER JOIN REPORTING.PERSON P ON P.LASTNAME    = L.LASTNAME
                                 AND P.FIRSTNAME   = L.FIRSTNAME
                                 AND P.DATEOFBIRTH = L.DATEOFBIRTH
                                 AND (L.MIDDLENAME IS NULL OR P.MIDDLENAME = L.MIDDLENAME)
    INNER JOIN REPORTING.REPORT R ON R.ID = P.RECORD_ID
WHERE P.INVOLVEMENTTYPE_CODE IS NOT NULL;   -- all involvement types except blank

-- 1. Cases
SELECT DISTINCT
    R.CASENUMBER,
    E.DATEREPORTED,
    O.VIOLATIONCODEREFERENCE_DESCRIPTION,
    VIP.FULLNAME,
    VIP.MIDDLENAME,
    VIP.DATEOFBIRTH,
    VIP.INVOLVEMENTTYPE_CODE
FROM #VIP VIP
    INNER JOIN REPORTING.REPORT  R ON R.CASENUMBER = VIP.CASENUMBER
    INNER JOIN REPORTING.OFFENSE O ON O.RECORD_ID  = R.ID
    INNER JOIN REPORTING.EVENT   E ON E.RECORD_ID  = R.ID
WHERE E.DATEREPORTED >= DATEADD(YEAR, -5, CAST(GETDATE() AS DATE))  -- past 5 years (also excludes NULLs)
  -- Hide a person's Suspect/DNA/print/POI rows on a case where they are also
  -- an Arrestee (keep only the Arrestee row). Never arrested -> rows are kept.
  AND NOT (
        VIP.INVOLVEMENTTYPE_CODE IN (
            'Suspect',
            'DNA Databank Hit',
            'Latent Print Identification',
            'Person of Interest (For Records Management Only)'
        )
        AND EXISTS (
            SELECT 1
            FROM #VIP A
            WHERE A.CASENUMBER  = VIP.CASENUMBER
              AND A.FULLNAME    = VIP.FULLNAME
              AND A.DATEOFBIRTH = VIP.DATEOFBIRTH
              AND A.INVOLVEMENTTYPE_CODE = 'Arrestee'
        )
  )
  -- Hide the UCR-coded copy of an offense ("... 23C 23C SHOPLIFTING") when the
  -- plain version of the same offense is on the case. Only hidden when the extra
  -- text is a UCR code (2 digits + digit/letter, twice), so "THEFT" never hides
  -- "THEFT OF MOTOR VEHICLE". UCR-only offenses are kept.
  AND NOT EXISTS (
        SELECT 1
        FROM REPORTING.REPORT  R2
            INNER JOIN REPORTING.OFFENSE O2 ON O2.RECORD_ID = R2.ID
        WHERE R2.CASENUMBER = R.CASENUMBER
          -- starts with the other offense's full description...
          AND LEFT(O.VIOLATIONCODEREFERENCE_DESCRIPTION, LEN(O2.VIOLATIONCODEREFERENCE_DESCRIPTION))
              = O2.VIOLATIONCODEREFERENCE_DESCRIPTION
          -- ...and what follows is " 23C 23C ..."
          AND SUBSTRING(O.VIOLATIONCODEREFERENCE_DESCRIPTION, LEN(O2.VIOLATIONCODEREFERENCE_DESCRIPTION) + 1, 8000)
              LIKE ' [0-9][0-9][0-9A-Z] [0-9][0-9][0-9A-Z]%'
  )
ORDER BY VIP.FULLNAME, E.DATEREPORTED;

-- 2. Addresses linked to these people
SELECT DISTINCT
    VIP.FULLNAME,
    VIP.DATEOFBIRTH,
    VIP.CASENUMBER,
    A.*                                                  -- trim to the columns you want
FROM #VIP VIP
    INNER JOIN REPORTING.ADDRESS A ON A.PERSON_ID = VIP.PERSON_ID   -- CHECK
ORDER BY VIP.FULLNAME, VIP.CASENUMBER;

-- 3. Vehicles linked to these people
SELECT DISTINCT
    VIP.FULLNAME,
    VIP.DATEOFBIRTH,
    VIP.CASENUMBER,
    V.*                                                  -- trim to the columns you want
FROM #VIP VIP
    INNER JOIN REPORTING.VEHICLE V ON V.PERSON_ID = VIP.PERSON_ID   -- CHECK
ORDER BY VIP.FULLNAME, VIP.CASENUMBER;

DROP TABLE #VIP;

/*
  Find the real table/column names for the CHECK lines:

  SELECT TABLE_NAME, COLUMN_NAME
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'REPORTING'
    AND (   TABLE_NAME LIKE '%ADDRESS%'
         OR TABLE_NAME LIKE '%VEHICLE%'
         OR (TABLE_NAME = 'PERSON' AND (COLUMN_NAME LIKE '%MIDDLE%' OR COLUMN_NAME LIKE '%ID%')))
  ORDER BY TABLE_NAME, ORDINAL_POSITION;

  Suggested indexes (if they don't already exist):

  CREATE INDEX IX_PERSON_NAME_DOB ON REPORTING.PERSON (LASTNAME, FIRSTNAME, DATEOFBIRTH) INCLUDE (RECORD_ID);
  CREATE INDEX IX_REPORT_CASENUMBER ON REPORTING.REPORT (CASENUMBER) INCLUDE (ID);
  CREATE INDEX IX_OFFENSE_RECORD_ID ON REPORTING.OFFENSE (RECORD_ID) INCLUDE (VIOLATIONCODEREFERENCE_DESCRIPTION);
  CREATE INDEX IX_EVENT_RECORD_ID ON REPORTING.EVENT (RECORD_ID) INCLUDE (DATEREPORTED);
*/
