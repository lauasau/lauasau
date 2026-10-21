USE INFORMRMSREPORTS;

/*
  Cases (with reported date and offense description) involving specific people.

  Changes from the original version:
  - Filter people first (the selective part) in a small CTE, then pull
    offenses/events only for those cases, instead of building the full
    REPORT x OFFENSE x EVENT set for every case and joining it afterwards.
  - LEFT JOIN EVENT + "E.DATEREPORTED IS NOT NULL" is really an INNER JOIN; say so.
  - Only the columns actually used are selected (CREATEDON, RACE_CODE, SEX_CODE,
    INVOLVEMENTTYPE_CODE were carried through DISTINCT for nothing).
  - LASTNAME = 'DOE' factored out of the OR so it can drive an index seek.
  - Unambiguous ISO dates (YYYYMMDD) instead of '07/10/1998', which depends
    on the session's language/DATEFORMAT setting.
*/
WITH VIP AS (
    SELECT DISTINCT
        R.CASENUMBER,
        CONCAT(P.LASTNAME, ',', P.FIRSTNAME) AS FULLNAME,  -- no space after comma
        P.DATEOFBIRTH
    FROM REPORTING.PERSON P
        INNER JOIN REPORTING.REPORT R ON R.ID = P.RECORD_ID
    WHERE P.LASTNAME = 'DOE'
      AND (   (P.FIRSTNAME = 'JOHN' AND P.DATEOFBIRTH = '19980710')
           OR (P.FIRSTNAME = 'JANE' AND P.DATEOFBIRTH = '19990617'))
)
SELECT DISTINCT
    R.CASENUMBER,
    E.DATEREPORTED,
    O.VIOLATIONCODEREFERENCE_DESCRIPTION,
    VIP.FULLNAME,
    VIP.DATEOFBIRTH
FROM VIP
    INNER JOIN REPORTING.REPORT  R ON R.CASENUMBER = VIP.CASENUMBER
    INNER JOIN REPORTING.OFFENSE O ON O.RECORD_ID  = R.ID
    INNER JOIN REPORTING.EVENT   E ON E.RECORD_ID  = R.ID
WHERE E.DATEREPORTED IS NOT NULL;

/*
  Suggested indexes (if they don't already exist):

  CREATE INDEX IX_PERSON_NAME_DOB ON REPORTING.PERSON (LASTNAME, FIRSTNAME, DATEOFBIRTH) INCLUDE (RECORD_ID);
  CREATE INDEX IX_REPORT_CASENUMBER ON REPORTING.REPORT (CASENUMBER) INCLUDE (ID);
  CREATE INDEX IX_OFFENSE_RECORD_ID ON REPORTING.OFFENSE (RECORD_ID) INCLUDE (VIOLATIONCODEREFERENCE_DESCRIPTION);
  CREATE INDEX IX_EVENT_RECORD_ID ON REPORTING.EVENT (RECORD_ID) INCLUDE (DATEREPORTED);
*/
