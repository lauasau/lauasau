USE INFORMRMSREPORTS;

/*
  Cases (with reported date and offense description) involving a list of people.

  To search for more people, add one row per person to @People below
  (LASTNAME, FIRSTNAME, DATEOFBIRTH as YYYYMMDD). Nothing else needs to change.

  Notes:
  - People are filtered first, then offenses/events are pulled only for their cases.
  - LEFT JOIN EVENT + "E.DATEREPORTED IS NOT NULL" is really an INNER JOIN; say so.
  - ISO dates (YYYYMMDD) are unambiguous regardless of the session's DATEFORMAT.
*/
DECLARE @People TABLE (
    LASTNAME    VARCHAR(100) NOT NULL,
    FIRSTNAME   VARCHAR(100) NOT NULL,
    DATEOFBIRTH DATE         NOT NULL,
    PRIMARY KEY (LASTNAME, FIRSTNAME, DATEOFBIRTH)
);

INSERT INTO @People (LASTNAME, FIRSTNAME, DATEOFBIRTH) VALUES
    ('DOE', 'JOHN', '19980710'),
    ('DOE', 'JANE', '19990617')    -- no comma after the last row

;WITH VIP AS (  -- leading ; ends the INSERT so the CTE always parses
    SELECT DISTINCT
        R.CASENUMBER,
        CONCAT(P.LASTNAME, ',', P.FIRSTNAME) AS FULLNAME,  -- no space after comma
        P.DATEOFBIRTH,
        P.INVOLVEMENTTYPE_CODE,
        P.INVOLVEMENTTYPE_DESCRIPTION
    FROM @People L
        INNER JOIN REPORTING.PERSON P ON P.LASTNAME    = L.LASTNAME
                                     AND P.FIRSTNAME   = L.FIRSTNAME
                                     AND P.DATEOFBIRTH = L.DATEOFBIRTH
        INNER JOIN REPORTING.REPORT R ON R.ID = P.RECORD_ID
    WHERE P.INVOLVEMENTTYPE_DESCRIPTION IN (
        'Arrest',
        'Arrestee',
        'DNA Databank Hit',
        'Latent Print Identification',
        'Person of Interest (For Records Management Only)',
        'S',
        'Suspect',
        'Suspected Offender'
    )
)
SELECT DISTINCT
    R.CASENUMBER,
    E.DATEREPORTED,
    O.VIOLATIONCODEREFERENCE_DESCRIPTION,
    VIP.FULLNAME,
    VIP.DATEOFBIRTH,
    VIP.INVOLVEMENTTYPE_CODE,
    VIP.INVOLVEMENTTYPE_DESCRIPTION
FROM VIP
    INNER JOIN REPORTING.REPORT  R ON R.CASENUMBER = VIP.CASENUMBER
    INNER JOIN REPORTING.OFFENSE O ON O.RECORD_ID  = R.ID
    INNER JOIN REPORTING.EVENT   E ON E.RECORD_ID  = R.ID
WHERE E.DATEREPORTED >= DATEADD(YEAR, -5, CAST(GETDATE() AS DATE))  -- past 5 years (also excludes NULLs)
  -- Hide a person's Suspect rows on a case where they are also an Arrestee
  AND NOT (
        VIP.INVOLVEMENTTYPE_CODE = 'Suspect'
        AND EXISTS (
            SELECT 1
            FROM VIP A
            WHERE A.CASENUMBER  = VIP.CASENUMBER
              AND A.FULLNAME    = VIP.FULLNAME
              AND A.DATEOFBIRTH = VIP.DATEOFBIRTH
              AND A.INVOLVEMENTTYPE_CODE = 'Arrestee'
        )
  )
ORDER BY VIP.FULLNAME, E.DATEREPORTED;

/*
  Suggested indexes (if they don't already exist):

  CREATE INDEX IX_PERSON_NAME_DOB ON REPORTING.PERSON (LASTNAME, FIRSTNAME, DATEOFBIRTH) INCLUDE (RECORD_ID);
  CREATE INDEX IX_REPORT_CASENUMBER ON REPORTING.REPORT (CASENUMBER) INCLUDE (ID);
  CREATE INDEX IX_OFFENSE_RECORD_ID ON REPORTING.OFFENSE (RECORD_ID) INCLUDE (VIOLATIONCODEREFERENCE_DESCRIPTION);
  CREATE INDEX IX_EVENT_RECORD_ID ON REPORTING.EVENT (RECORD_ID) INCLUDE (DATEREPORTED);
*/
