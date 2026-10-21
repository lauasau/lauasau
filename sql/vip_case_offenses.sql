USE INFORMRMSREPORTS;

/*
  Offenses and reported dates for every case that involves one of the listed people.

  Changes from the original version:
    - The query starts from the few PERSON rows that match, then pulls in only those
      cases' reports, offenses and events. The original built the full offense/event
      set for every report before joining.
    - LEFT JOIN EVENT + WHERE E.DATEREPORTED IS NOT NULL is an INNER JOIN in practice,
      so it is now written as one.
    - The person subquery no longer selects CREATEDON, RACE_CODE, SEX_CODE or
      INVOLVEMENTTYPE_CODE, and there is no inner DISTINCT. The final result never used
      those columns, and the outer DISTINCT already removes duplicates.
    - Date literals use the 'YYYYMMDD' format, which SQL Server reads the same way
      under any language or DATEFORMAT setting. '07/10/1998' could be read as 7 Oct.
    - LASTNAME = 'DOE' is pulled out of the OR so an index on LASTNAME can seek on it.
*/

WITH VIP AS (
    SELECT
        R.CASENUMBER,
        CONCAT(P.LASTNAME, ',', P.FIRSTNAME) AS FULLNAME,   -- NO SPACE AFTER COMMA
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
  Optional: if you have permission to create indexes, these support the query above.
  Check first whether similar indexes already exist.

  CREATE INDEX IX_PERSON_Name_DOB  ON REPORTING.PERSON  (LASTNAME, FIRSTNAME, DATEOFBIRTH) INCLUDE (RECORD_ID);
  CREATE INDEX IX_REPORT_CaseNum   ON REPORTING.REPORT  (CASENUMBER) INCLUDE (ID);
  CREATE INDEX IX_OFFENSE_RecordId ON REPORTING.OFFENSE (RECORD_ID)  INCLUDE (VIOLATIONCODEREFERENCE_DESCRIPTION);
  CREATE INDEX IX_EVENT_RecordId   ON REPORTING.EVENT   (RECORD_ID)  INCLUDE (DATEREPORTED);
*/
