PROCEDURE GET_VACCINES_PER_FILTERS(
    P_DATE_TYPE           IN  NUMBER,
    P_FROM_DATE           IN  VARCHAR2,
    P_TO_DATE             IN  VARCHAR2,
    P_FACILITY            IN  NUMBER,
    P_REGION              IN  NUMBER,
    P_VACCINATION         IN  NUMBER, 
    P_DOSAGE              IN  NUMBER,
    P_STATUS              IN  NUMBER,   
    P_vaccination_type    IN  NUMBER,   
    P_clinic_type         IN  NUMBER,  
    RESULT_CUR            OUT SYS_REFCURSOR
)
AS
    SQL_STM        VARCHAR2(30000);
    WHERE_RESULT   VARCHAR2(30000);
    WHERE_ALL      VARCHAR2(30000);
    isCampaign_valReal NUMBER;
BEGIN

/* ============================================================
   Base SELECT
============================================================ */
SQL_STM := '
SELECT
    PHCT.PHC_CENTER_ID,
    PHCT.NAME_AR  AS PHC_NAME_AR,
    PHCT.NAME_EN  AS PHC_NAME_EN,
    GE.NAME_EN    AS GE_NAME_EN,
    SU.SUB_CONSTANT_NAME_EN AS SU_NAME_EN,

    /* Children count (RN = 1) */
    COUNT(DISTINCT CASE WHEN RN_SUB.RN = 1 THEN RN_SUB.PERSON_ID END) AS CHILDREN_VACCINATED,

    /* Total real vaccinations */
    COUNT(PVT_ALL.VACCINE_DOSES_ID) AS TOTAL_VACCINATIONS,

    /* Example: BCG */
    SUM(CASE WHEN PVT_ALL.VACCINE_DOSES_ID = 1 THEN 1 ELSE 0 END) AS BCG_VACCINATIONS

FROM PHC_CENTER_TB PHCT
JOIN geolocation_tb GE
    ON GE.GEOLOCATION_ID = PHCT.GEOLOCATION_ID
JOIN sub_constant_tb SU
    ON SU.SUB_CONSTANT_ID = PHCT.PHC_TYPE_ID

/* ===== Subquery for children (RN logic) ===== */
LEFT JOIN (
    SELECT
        PVT.PERSON_ID,
        PVT.PHC_ENTRY_ID,
        ROW_NUMBER() OVER (
            PARTITION BY PVT.PERSON_ID
            ORDER BY PVT.VACCINATION_DATE DESC
        ) AS RN
    FROM PERSON_VACCINE_TB PVT
    WHERE 1=1 ';

/* ================= Date filters (RN subquery) ================= */
IF P_DATE_TYPE = 1 AND P_FROM_DATE IS NOT NULL AND P_TO_DATE IS NOT NULL THEN
    WHERE_RESULT := WHERE_RESULT ||
        ' AND TRUNC(PVT.VACCINATION_DATE) BETWEEN TO_DATE('''||P_FROM_DATE||''',''DD/MM/YYYY'')
                                             AND TO_DATE('''||P_TO_DATE||''',''DD/MM/YYYY'')';
ELSIF P_DATE_TYPE = 2 AND P_FROM_DATE IS NOT NULL AND P_TO_DATE IS NOT NULL THEN
    WHERE_RESULT := WHERE_RESULT ||
        ' AND TRUNC(PVT.CREATED_ON) BETWEEN TO_DATE('''||P_FROM_DATE||''',''DD/MM/YYYY'')
                                         AND TO_DATE('''||P_TO_DATE||''',''DD/MM/YYYY'')';
END IF;

IF P_vaccination_type IS NOT NULL AND P_vaccination_type > 0 THEN
    isCampaign_valReal := CASE P_vaccination_type WHEN 1 THEN 1 ELSE 0 END;
    WHERE_RESULT := WHERE_RESULT || ' AND PVT.IS_CAMPAIGN = ' || isCampaign_valReal;
END IF;

SQL_STM := SQL_STM || WHERE_RESULT || '
) RN_SUB
    ON RN_SUB.PHC_ENTRY_ID = PHCT.PHC_CENTER_ID

/* ===== All vaccinations (no RN) ===== */
LEFT JOIN PERSON_VACCINE_TB PVT_ALL
    ON PVT_ALL.PHC_ENTRY_ID = PHCT.PHC_CENTER_ID ';

/* ================= Filters for ALL vaccinations ================= */
IF P_DATE_TYPE = 1 AND P_FROM_DATE IS NOT NULL AND P_TO_DATE IS NOT NULL THEN
    WHERE_ALL := WHERE_ALL ||
        ' AND TRUNC(PVT_ALL.VACCINATION_DATE) BETWEEN TO_DATE('''||P_FROM_DATE||''',''DD/MM/YYYY'')
                                                  AND TO_DATE('''||P_TO_DATE||''',''DD/MM/YYYY'')';
ELSIF P_DATE_TYPE = 2 AND P_FROM_DATE IS NOT NULL AND P_TO_DATE IS NOT NULL THEN
    WHERE_ALL := WHERE_ALL ||
        ' AND TRUNC(PVT_ALL.CREATED_ON) BETWEEN TO_DATE('''||P_FROM_DATE||''',''DD/MM/YYYY'')
                                             AND TO_DATE('''||P_TO_DATE||''',''DD/MM/YYYY'')';
END IF;

IF P_FACILITY > 0 THEN
    WHERE_ALL := WHERE_ALL || ' AND PVT_ALL.PHC_ENTRY_ID = ' || P_FACILITY;
END IF;

IF P_DOSAGE > 0 THEN
    WHERE_ALL := WHERE_ALL || ' AND PVT_ALL.VACCINE_DOSES_ID = ' || P_DOSAGE;
END IF;

IF P_STATUS > 0 THEN
    WHERE_ALL := WHERE_ALL || ' AND PVT_ALL.CHILD_VACCINATION_STATUS = ' || P_STATUS;
END IF;

IF P_vaccination_type IS NOT NULL AND P_vaccination_type > 0 THEN
    WHERE_ALL := WHERE_ALL || ' AND PVT_ALL.IS_CAMPAIGN = ' || isCampaign_valReal;
END IF;

SQL_STM := SQL_STM || WHERE_ALL;

/* ================= Outer filters ================= */
SQL_STM := SQL_STM || ' WHERE 1=1 ';

IF P_REGION > 0 THEN
    SQL_STM := SQL_STM || ' AND PHCT.GEOLOCATION_ID = ' || P_REGION;
END IF;

IF P_clinic_type > 0 THEN
    SQL_STM := SQL_STM || ' AND PHCT.PHC_TYPE_ID = ' || P_clinic_type;
END IF;

SQL_STM := SQL_STM || '
GROUP BY
    PHCT.PHC_CENTER_ID,
    PHCT.NAME_AR,
    PHCT.NAME_EN,
    GE.NAME_EN,
    SU.SUB_CONSTANT_NAME_EN
ORDER BY PHCT.PHC_CENTER_ID';

DBMS_OUTPUT.PUT_LINE(SQL_STM);
OPEN RESULT_CUR FOR SQL_STM;

EXCEPTION
    WHEN OTHERS THEN
        RAISE_APPLICATION_ERROR(-20001,
            ''Error in GET_VACCINES_PER_FILTERS: '' || SQLERRM);
END;
