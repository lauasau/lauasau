USE INFORMRMSREPORTS;

/*
  Cases for a list of people.

  Add one row per person to @People (LASTNAME, FIRSTNAME, DATEOFBIRTH).

  Returns cases from the past 5 years:
    - Suspect, DNA Databank Hit, Latent Print Identification and Person of
      Interest rows are hidden when the same person is an Arrestee on the case
    - UCR-coded copies of an offense ("... 23C 23C SHOPLIFTING") are hidden
    - The statute number is removed from the offense description
*/
DECLARE @People TABLE (
    LASTNAME    VARCHAR(100) NOT NULL,
    FIRSTNAME   VARCHAR(100) NOT NULL,
    DATEOFBIRTH DATE         NOT NULL,
    PRIMARY KEY (LASTNAME, FIRSTNAME, DATEOFBIRTH)
);

INSERT INTO @People (LASTNAME, FIRSTNAME, DATEOFBIRTH) VALUES
    ('SMITH',   'ADAM', '1990-01-01'),
    ('ANDREWS', 'ADAM', '1990-01-01');   -- last row ends with ;

-- Matching person records, saved once and reused below.
IF OBJECT_ID('tempdb..#VIP') IS NOT NULL DROP TABLE #VIP;

SELECT DISTINCT
    R.CASENUMBER,
    CONCAT(P.LASTNAME, ',', P.FIRSTNAME) AS FULLNAME,    -- no space after comma
    P.DATEOFBIRTH,
    P.INVOLVEMENTTYPE_CODE
INTO #VIP
FROM @People L
    INNER JOIN REPORTING.PERSON P ON P.LASTNAME    = L.LASTNAME
                                 AND P.FIRSTNAME   = L.FIRSTNAME
                                 AND P.DATEOFBIRTH = L.DATEOFBIRTH
    INNER JOIN REPORTING.REPORT R ON R.ID = P.RECORD_ID
WHERE P.INVOLVEMENTTYPE_CODE IN (
    'Arrestee',
    'DNA Databank Hit',
    'Latent Print Identification',
    'Person of Interest (For Records Management Only)',
    'Suspect'
);

-- Cases
SELECT DISTINCT
    R.CASENUMBER,
    E.DATEREPORTED,
    -- Description without the leading statute number:
    -- "943.50(1m)(b) Retail Theft - ..." -> "Retail Theft - ..."
    CASE
        WHEN O.VIOLATIONCODEREFERENCE_DESCRIPTION LIKE '[0-9]% %'
        THEN LTRIM(SUBSTRING(O.VIOLATIONCODEREFERENCE_DESCRIPTION,
                             CHARINDEX(' ', O.VIOLATIONCODEREFERENCE_DESCRIPTION) + 1, 8000))
        ELSE O.VIOLATIONCODEREFERENCE_DESCRIPTION
    END AS VIOLATION_DESCRIPTION,
    VIP.FULLNAME,
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
  -- plain version of the same offense is on the case: the row's description is
  -- another offense's description followed by this row's own UCR code. So
  -- "THEFT" never hides "THEFT OF MOTOR VEHICLE", and UCR-only offenses are kept.
  AND NOT EXISTS (
        SELECT 1
        FROM REPORTING.REPORT  R2
            INNER JOIN REPORTING.OFFENSE O2 ON O2.RECORD_ID = R2.ID
        WHERE R2.CASENUMBER = R.CASENUMBER
          AND LTRIM(RTRIM(O.VIOLATIONCODEREFERENCE_UCRCODE)) <> ''
          -- starts with the other offense's full description...
          AND LEFT(O.VIOLATIONCODEREFERENCE_DESCRIPTION, LEN(O2.VIOLATIONCODEREFERENCE_DESCRIPTION))
              = O2.VIOLATIONCODEREFERENCE_DESCRIPTION
          -- ...followed by a space and this row's UCR code
          AND SUBSTRING(O.VIOLATIONCODEREFERENCE_DESCRIPTION,
                        LEN(O2.VIOLATIONCODEREFERENCE_DESCRIPTION) + 1,
                        LEN(LTRIM(RTRIM(O.VIOLATIONCODEREFERENCE_UCRCODE))) + 1)
              = ' ' + LTRIM(RTRIM(O.VIOLATIONCODEREFERENCE_UCRCODE))
  )
ORDER BY VIP.FULLNAME, E.DATEREPORTED;

DROP TABLE #VIP;

/*
  Suggested indexes (if they don't already exist):

  CREATE INDEX IX_PERSON_NAME_DOB ON REPORTING.PERSON (LASTNAME, FIRSTNAME, DATEOFBIRTH) INCLUDE (RECORD_ID);
  CREATE INDEX IX_REPORT_CASENUMBER ON REPORTING.REPORT (CASENUMBER) INCLUDE (ID);
  CREATE INDEX IX_OFFENSE_RECORD_ID ON REPORTING.OFFENSE (RECORD_ID) INCLUDE (VIOLATIONCODEREFERENCE_DESCRIPTION);
  CREATE INDEX IX_EVENT_RECORD_ID ON REPORTING.EVENT (RECORD_ID) INCLUDE (DATEREPORTED);
*/
