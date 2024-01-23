--------------------------------------------------------------------------------------
--   Created    : 21-FEB-2023
--   Created by : MAHBUB
--   Description: 
--   UPDATED BY: 
--   Revision History:
--   Modified On Modified By Comments
--   ----------- ----------- ----------------------------------------------

--------------------------------------------------------------------------------------
CREATE OR REPLACE
PROCEDURE   PD_WIP_PROCESS_IN_OUT_DML_V2 (
                                         pPROD_ID NUMBER,
                                         pBATCH_ID NUMBER,
                                         pWIP_PROCESS_ID NUMBER,
                                         pWIP_MST_ID NUMBER,
                                         pREF_ID NUMBER,
                                         pUSER_ID NUMBER,
                                         pSBU_ID NUMBER
                                        )  
    IS

    --vSTATUS             NUMBER;
    vCOUNT                      NUMBER;
    vPROCESS_ID                 NUMBER;
    vPROCESS_SEQUENCE           NUMBER:=0;
    vNEXT_PROCESS_SEQUENCE      NUMBER:=0;
    vSORT_ORDER                 NUMBER;
    vINPUT_CNT                  NUMBER;
    --vWIP_PROCESS_ID             NUMBER;
    vMESSAGE                    VARCHAR2(4000);
    vTOTAL_PROCESS              NUMBER;
    vOUTPUT_CNT                 NUMBER;
    vCURRENT_STAGE_ID           NUMBER;
    vREQ_CHK                    NUMBER;
    vPREVIOUS_PROCESS_SEQ       NUMBER;
    vPREVIOUS_STAGE_ID          NUMBER;
    vPREVIOUS_WIP_PROCESS_ID    NUMBER;
    --vLAST_PROCESS_ID            NUMBER;
    vSL_NO                      NUMBER:=0;

    CURSOR C_NEXT_PROCESS_INPUT
    IS
    SELECT PWP.ID,PWP.PROCESS_ID,PWP.PROCESS_SEQUENCE,PWP.WIP_STAGE_ID,PPTP.RECONCILIATION_REQUIRED
      FROM PP_WIP_PROCESS PWP
      LEFT JOIN PP_PROC_TYPE_PROCESS PPTP ON PWP.PROCESS_ID = PPTP.PROCESS_ID AND NVL(PWP.SUB_PROCESS_ID,0) = NVL(PPTP.SUB_PROCESS_ID,0)
      LEFT JOIN PP_PROD_PROC_TYPE PPPT ON PPTP.PROD_PROC_TYPE_ID = PPPT.ID
     WHERE WIP_MST_ID = pWIP_MST_ID --IN (SELECT ID FROM PP_WIP_MST WHERE BATCH_ID = pBATCH_ID AND PROD_ID = pPROD_ID)
      AND PWP.PROCESS_SEQUENCE = vNEXT_PROCESS_SEQUENCE
      AND PWP.REF_ID   = pREF_ID
      AND PPPT.PROD_ID = pPROD_ID;

    R_NEXT_PROCESS_INPUT C_NEXT_PROCESS_INPUT%ROWTYPE;


BEGIN

    SELECT COUNT(*) INTO vTOTAL_PROCESS FROM PP_PROC_TYPE_PROCESS
     WHERE PROD_PROC_TYPE_ID IN (SELECT ID FROM PP_PROD_PROC_TYPE WHERE PROD_ID = pPROD_ID AND STATUS=1)
       AND STATUS=1;

    SELECT PROCESS_ID,PROCESS_SEQUENCE,PROCESS_SEQUENCE+1,WIP_STAGE_ID,PROCESS_SEQUENCE-1--,PWM.TOTAL_PROCESS_NO
      INTO vPROCESS_ID,vPROCESS_SEQUENCE,vNEXT_PROCESS_SEQUENCE,vCURRENT_STAGE_ID,vPREVIOUS_PROCESS_SEQ--,vTOTAL_PROCESS
      FROM PP_WIP_PROCESS  PWP
      LEFT JOIN PP_WIP_MST PWM ON PWP.WIP_MST_ID = PWM.ID
     WHERE PWP.ID = pWIP_PROCESS_ID;
     
    /* Find Previous Process Information  */
    
    BEGIN
    
        SELECT PWP.ID,PWP.WIP_STAGE_ID 
          INTO vPREVIOUS_WIP_PROCESS_ID,vPREVIOUS_STAGE_ID
          FROM PP_WIP_PROCESS PWP
         WHERE PWP.WIP_MST_ID = pWIP_MST_ID 
           AND PWP.PROCESS_SEQUENCE = vPREVIOUS_PROCESS_SEQ;
    
    EXCEPTION
        WHEN OTHERS THEN
        vPREVIOUS_WIP_PROCESS_ID    := NULL;
        vPREVIOUS_STAGE_ID          := NULL;
    END;

    /* Start Current Process Output Data Insert */
    
    SELECT COUNT(*) INTO vOUTPUT_CNT FROM PP_WIP_PROC_OUTPUT  WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID;

    IF vOUTPUT_CNT = 0 THEN

        OPEN C_NEXT_PROCESS_INPUT; FETCH C_NEXT_PROCESS_INPUT INTO R_NEXT_PROCESS_INPUT; CLOSE C_NEXT_PROCESS_INPUT;

        --- next process requisition check ---
        SELECT COUNT(*) INTO VREQ_CHK FROM MM_INT_REQ_MST
        WHERE FOR_PRODUCTS = pPROD_ID AND FOR_BATCHES = pBATCH_ID AND PROCESS_ID = R_NEXT_PROCESS_INPUT.PROCESS_ID AND STATUS = 1;

        IF VREQ_CHK > 0 THEN 

            INSERT INTO PP_WIP_PROC_OUTPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,OUTPUT_QTY,OUTPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID)
            SELECT pWIP_PROCESS_ID,ROWNUM SL_NO,MID.PROD_ID, ASP.DISPLAY_NAME, MIIDB.ISS_QTY APPROVE_QTY,MID.UOM,pUSER_ID,SYSDATE,NVL(APL.ID,MIM.FOR_BATCHES) LOT_ID
              FROM MM_INT_ISS_MST MIM
              JOIN MM_INT_ISS_DTL MID ON MIM.ID=MID.ISS_ID
              JOIN ADM_SBU_PRODUCTS ASP ON MID.PROD_ID=ASP.PROD_ID
              JOIN ADM_CODE_ELEMENTS ACE ON MID.UOM=ACE.ID
              LEFT JOIN MM_INT_ISS_DTL_BATCH MIIDB ON MID.ID = MIIDB.ISS_DTL_ID AND MIM.ID = MIIDB.ISS_ID
              LEFT JOIN ADM_PRODUCT_LOT APL ON MIIDB.BATCH_LOT_NUMBER = APL.LOT_NO AND MIIDB.PROD_ID = APL.PROD_ID
              LEFT JOIN MM_INT_REQ_MST MIRM ON MIM.REFERENCES = MIRM.ID 
              LEFT JOIN (
                     SELECT WP.ID WIP_PROCESS_ID, PT.PROD_ID OUTPUT_PROD_ID, ASP.DISPLAY_NAME, PT.ITEM_NAME, PT.OUTPUT_QTY, PT.OUTPUT_UOM
                       FROM PP_WIP_MST WM
                       JOIN PP_WIP_PROCESS WP ON WM.ID=WP.WIP_MST_ID
                       LEFT JOIN PP_WIP_PROC_OUTPUT PT ON WP.ID=PT.WIP_PROCESS_ID
                       LEFT JOIN ADM_SBU_PRODUCTS ASP ON PT.PROD_ID=ASP.PROD_ID
                      WHERE WM.PROD_ID = pPROD_ID AND BATCH_ID = pBATCH_ID
                        --AND WP.PROCESS_ID IN(10459,10462,10304,10461,10463)
                        AND WP.PROCESS_ID = R_NEXT_PROCESS_INPUT.PROCESS_ID
                        AND PT.PROD_ID IS NOT NULL
                        AND (pREF_ID IS NULL OR WP.REF_ID = pREF_ID)
                    ) WP ON MID.PROD_ID=WP.OUTPUT_PROD_ID AND WIP_PROCESS_ID=WP.WIP_PROCESS_ID
            WHERE MIM.FOR_PRODUCTS = pPROD_ID
              AND MIM.FOR_BATCHES = pBATCH_ID AND (WP.WIP_PROCESS_ID IS NULL OR WP.OUTPUT_PROD_ID IS NULL)
              AND MIM.STATUS = 1
              AND (pREF_ID IS NULL OR MIRM.BMR_BPR_ID = pREF_ID) 
              AND MIRM.PROCESS_ID = R_NEXT_PROCESS_INPUT.PROCESS_ID;

		END IF;

    ELSE --CURRENT OUTPUT DATA EXIST

        OPEN C_NEXT_PROCESS_INPUT; FETCH C_NEXT_PROCESS_INPUT INTO R_NEXT_PROCESS_INPUT; CLOSE C_NEXT_PROCESS_INPUT;
        
        --- next process requisition check ---
        SELECT COUNT(*) INTO VREQ_CHK FROM MM_INT_REQ_MST
        WHERE FOR_PRODUCTS = pPROD_ID AND FOR_BATCHES = pBATCH_ID AND PROCESS_ID = R_NEXT_PROCESS_INPUT.PROCESS_ID AND STATUS = 1;

        IF VREQ_CHK > 0 THEN
        
            FOR I IN (SELECT MID.PROD_ID, ASP.DISPLAY_NAME, MIIDB.ISS_QTY APPROVE_QTY,MID.UOM,NVL(APL.ID,MIM.FOR_BATCHES) LOT_ID
                        FROM MM_INT_ISS_MST MIM
                        JOIN MM_INT_ISS_DTL MID ON MIM.ID=MID.ISS_ID
                        JOIN ADM_SBU_PRODUCTS ASP ON MID.PROD_ID=ASP.PROD_ID
                        JOIN ADM_CODE_ELEMENTS ACE ON MID.UOM=ACE.ID
                        LEFT JOIN MM_INT_ISS_DTL_BATCH MIIDB ON MID.ID = MIIDB.ISS_DTL_ID AND MIM.ID = MIIDB.ISS_ID
                        LEFT JOIN ADM_PRODUCT_LOT APL ON MIIDB.BATCH_LOT_NUMBER = APL.LOT_NO AND MIIDB.PROD_ID = APL.PROD_ID
                        LEFT JOIN MM_INT_REQ_MST MIRM ON MIM.REFERENCES = MIRM.ID 
                        LEFT JOIN (
                                 SELECT WP.ID WIP_PROCESS_ID, PT.PROD_ID OUTPUT_PROD_ID, ASP.DISPLAY_NAME, PT.ITEM_NAME, PT.OUTPUT_QTY, PT.OUTPUT_UOM
                                   FROM PP_WIP_MST WM
                                   JOIN PP_WIP_PROCESS WP ON WM.ID=WP.WIP_MST_ID
                                   LEFT JOIN PP_WIP_PROC_OUTPUT PT ON WP.ID=PT.WIP_PROCESS_ID
                                   LEFT JOIN ADM_SBU_PRODUCTS ASP ON PT.PROD_ID=ASP.PROD_ID
                                  WHERE WM.PROD_ID = pPROD_ID AND BATCH_ID = pBATCH_ID
                                    --AND WP.PROCESS_ID IN(10459,10462,10304,10461,10463)
                                    AND WP.PROCESS_ID = R_NEXT_PROCESS_INPUT.PROCESS_ID
                                    AND PT.PROD_ID IS NOT NULL
                                    AND (pREF_ID IS NULL OR WP.REF_ID = pREF_ID)
                                ) WP ON MID.PROD_ID=WP.OUTPUT_PROD_ID AND WIP_PROCESS_ID=WP.WIP_PROCESS_ID
                      WHERE MIM.FOR_PRODUCTS = pPROD_ID
                        AND MIM.FOR_BATCHES = pBATCH_ID AND (WP.WIP_PROCESS_ID IS NULL OR WP.OUTPUT_PROD_ID IS NULL)
                        AND MIRM.PROCESS_ID = R_NEXT_PROCESS_INPUT.PROCESS_ID
                        AND (pREF_ID IS NULL OR MIRM.BMR_BPR_ID = pREF_ID)
                        AND MIRM.STATUS = 1
                      UNION
                     SELECT PROD_ID,ITEM_NAME,OUTPUT_QTY,OUTPUT_UOM,LOT_ID
                       FROM PP_WIP_PROC_OUTPUT
                      WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID
                     )
            LOOP

                SELECT COUNT(*) INTO vCOUNT FROM PP_WIP_PROC_OUTPUT  WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID AND PROD_ID = I.PROD_ID AND LOT_ID=I.LOT_ID;

                IF vCOUNT = 0 THEN

                    vSL_NO  := vSL_NO+1;
                    
                    INSERT INTO PP_WIP_PROC_OUTPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,OUTPUT_QTY,OUTPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID)
                                            VALUES(pWIP_PROCESS_ID,vSL_NO,I.PROD_ID,I.DISPLAY_NAME,I.APPROVE_QTY,I.UOM,pUSER_ID,SYSDATE,I.LOT_ID);

                ELSE

                    UPDATE PP_WIP_PROC_OUTPUT
                       SET OUTPUT_QTY = I.APPROVE_QTY
                     WHERE PROD_ID    =   I.PROD_ID
                       AND LOT_ID     = I.LOT_ID
                       AND WIP_PROCESS_ID = pWIP_PROCESS_ID;

                END IF;

            END LOOP;
         /*
         ELSE
        
            FOR I IN (
                  SELECT WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,OUTPUT_QTY,OUTPUT_UOM,LOT_ID
                    FROM PP_WIP_PROC_OUTPUT
                   WHERE WIP_PROCESS_ID=pWIP_PROCESS_ID
                 )
            LOOP

                SELECT COUNT(*) INTO vCOUNT FROM PP_WIP_PROC_OUTPUT  WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID AND PROD_ID = I.PROD_ID;

                IF vCOUNT = 0 THEN

                    INSERT INTO PP_WIP_PROC_OUTPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,OUTPUT_QTY,OUTPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID)
                                            VALUES(pWIP_PROCESS_ID,I.SL_NO,I.PROD_ID,I.ITEM_NAME,I.OUTPUT_QTY,I.OUTPUT_UOM,pUSER_ID,SYSDATE,I.LOT_ID);

                ELSE

                    UPDATE PP_WIP_PROC_OUTPUT
                       SET OUTPUT_QTY = I.OUTPUT_QTY,
                           OUTPUT_UOM = I.OUTPUT_UOM
                     WHERE PROD_ID =   I.PROD_ID
                       AND WIP_PROCESS_ID = pWIP_PROCESS_ID;

                END IF;

            END LOOP;
            */
        
        END IF;

    END IF;

    /* End Current Process Output Data Insert */
    
    /* Previous Process Output Data Insert Current Process Inuput Output Table For (BPR) */
    
    IF vCURRENT_STAGE_ID <> vPREVIOUS_STAGE_ID THEN
    
        DECLARE
            vCHK    NUMBER;
        BEGIN
        
            FOR L IN (SELECT * FROM PP_WIP_PROC_OUTPUT WHERE WIP_PROCESS_ID = vPREVIOUS_WIP_PROCESS_ID)
        
            LOOP
            
                SELECT COUNT(*) INTO vCHK FROM PP_WIP_PROC_OUTPUT WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID AND PROD_ID = L.PROD_ID;
                
                IF vCHK = 0 THEN
                
                    INSERT INTO PP_WIP_PROC_OUTPUT
                    (WIP_PROCESS_ID, SL_NO, PROD_ID, ITEM_NAME, LOT_ID, OUTPUT_QTY, OUTPUT_UOM, YIELD_PERCENT, CONTAINER_NO, OUTPUT_RATE,
                     OUTPUT_VALUE, RC_CODE, FICO_TRAN_ID, CAN_SHOW, SORT_ORDER, STATUS, CREATED_BY, CREATED_AT, UPDATED_BY, UPDATED_AT)
                    SELECT pWIP_PROCESS_ID, SL_NO, PROD_ID, ITEM_NAME, LOT_ID, OUTPUT_QTY, OUTPUT_UOM, YIELD_PERCENT, CONTAINER_NO, OUTPUT_RATE, 
                           OUTPUT_VALUE, RC_CODE, FICO_TRAN_ID, CAN_SHOW, SORT_ORDER, STATUS, CREATED_BY, CREATED_AT, UPDATED_BY, UPDATED_AT 
                      FROM PP_WIP_PROC_OUTPUT 
                    WHERE WIP_PROCESS_ID = vPREVIOUS_WIP_PROCESS_ID AND PROD_ID = L.PROD_ID;
                    
                    vCHK    := NULL;
                
                ELSE
                
                    UPDATE PP_WIP_PROC_OUTPUT
                       SET OUTPUT_QTY = L.OUTPUT_QTY,
                           OUTPUT_UOM = L.OUTPUT_UOM
                     WHERE PROD_ID    = L.PROD_ID
                       AND WIP_PROCESS_ID = pWIP_PROCESS_ID;
                       
                    vCHK    := NULL;   
                    
                END IF;
                
                SELECT COUNT(*) INTO vCHK FROM PP_WIP_PROC_INPUT WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID AND PROD_ID = L.PROD_ID;
                
                IF vCHK = 0 THEN
                
                    INSERT INTO PP_WIP_PROC_INPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,INPUT_QTY,INPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID)
                    SELECT pWIP_PROCESS_ID, SL_NO, PROD_ID, ITEM_NAME, OUTPUT_QTY, OUTPUT_UOM,pUSER_ID,SYSDATE,LOT_ID
                      FROM PP_WIP_PROC_OUTPUT
                     WHERE WIP_PROCESS_ID = vPREVIOUS_WIP_PROCESS_ID
                       AND PROD_ID = L.PROD_ID;
                    
                    vCHK    := NULL;
                
                ELSE
                
                    DELETE FROM PP_WIP_PROC_INPUT WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID AND PROD_ID = L.PROD_ID;
                    
                    INSERT INTO PP_WIP_PROC_INPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,INPUT_QTY,INPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID)
                    SELECT pWIP_PROCESS_ID, SL_NO, PROD_ID, ITEM_NAME, OUTPUT_QTY, OUTPUT_UOM,pUSER_ID,SYSDATE,LOT_ID
                      FROM PP_WIP_PROC_OUTPUT
                     WHERE WIP_PROCESS_ID = vPREVIOUS_WIP_PROCESS_ID
                       AND PROD_ID = L.PROD_ID;
                       
                    vCHK    := NULL;   
                    
                END IF;
            
            END LOOP;
        
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
    
    END IF;
    
    /* First Process Input Data */

    IF vPROCESS_SEQUENCE = 1 THEN
    
        SELECT COUNT(*) INTO vINPUT_CNT FROM PP_WIP_PROC_INPUT  WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID;
    
        IF vINPUT_CNT = 0 THEN

            INSERT INTO PP_WIP_PROC_INPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,INPUT_QTY,INPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID)
            SELECT pWIP_PROCESS_ID, SL_NO, PROD_ID, ITEM_NAME, OUTPUT_QTY, OUTPUT_UOM,pUSER_ID,SYSDATE,LOT_ID
              FROM PP_WIP_PROC_OUTPUT
             WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID;

        ELSE

            FOR I IN (SELECT * FROM PP_WIP_PROC_OUTPUT    WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID)
            
            LOOP
            
                SELECT COUNT(*) INTO vINPUT_CNT FROM PP_WIP_PROC_INPUT  
                WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID AND PROD_ID = I.PROD_ID;
                
                IF vINPUT_CNT = 0 THEN 
                
                    INSERT INTO PP_WIP_PROC_INPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,INPUT_QTY,INPUT_UOM,SORT_ORDER,CREATED_BY,CREATED_AT,LOT_ID)
                    SELECT pWIP_PROCESS_ID, SL_NO, PROD_ID, ITEM_NAME, OUTPUT_QTY, OUTPUT_UOM,vSORT_ORDER+ROWNUM,pUSER_ID,SYSDATE,LOT_ID
                      FROM PP_WIP_PROC_OUTPUT
                     WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID
                       AND PROD_ID = I.PROD_ID;
                
                ELSE
                
                    UPDATE PP_WIP_PROC_INPUT
                       SET INPUT_QTY    = I.OUTPUT_QTY,
                           INPUT_UOM    = I.OUTPUT_UOM
                     WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID
                       AND PROD_ID = I.PROD_ID; 
                
                END IF;
            
            END LOOP;

        END IF;
    
    END IF;
    
    /* First Process Input Data */

    /* End Current Process Input Output Data */

    /* Next Process Input Output Data Insert */

    IF vNEXT_PROCESS_SEQUENCE < vTOTAL_PROCESS THEN

        OPEN C_NEXT_PROCESS_INPUT;
        FETCH C_NEXT_PROCESS_INPUT INTO R_NEXT_PROCESS_INPUT;

        IF C_NEXT_PROCESS_INPUT%FOUND THEN
            CLOSE C_NEXT_PROCESS_INPUT;

            IF vCURRENT_STAGE_ID <> R_NEXT_PROCESS_INPUT.WIP_STAGE_ID THEN --CONVERT PRODUCT BULK TO SFG

                --- NEXT PROCESS INPUT DATA INSERT ---

                SELECT COUNT(*) INTO vINPUT_CNT FROM PP_WIP_PROC_INPUT  WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID;
                
                IF R_NEXT_PROCESS_INPUT.PROCESS_ID = 10304 THEN --if next process is Dispensing
                
                    BEGIN
                    
                        IF vINPUT_CNT = 0 THEN

                            INSERT INTO PP_WIP_PROC_INPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,INPUT_QTY,INPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID,CONSUMED_QTY)
                            SELECT R_NEXT_PROCESS_INPUT.ID, SL_NO, B.PROD_ID, B.DISPLAY_NAME, OUTPUT_QTY, OUTPUT_UOM,pUSER_ID,SYSDATE,pBATCH_ID,OUTPUT_QTY
                              FROM PP_WIP_PROC_OUTPUT A
                              LEFT JOIN (SELECT PROD_ID,DISPLAY_NAME FROM ADM_SBU_PRODUCTS
                                          WHERE PARENT_PROD_ID=pPROD_ID
                                            AND PROD_TYPE=504) B ON 1=1
                                          WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID;

                        ELSE

                            DELETE FROM PP_WIP_PROC_INPUT  WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID;

                            INSERT INTO PP_WIP_PROC_INPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,INPUT_QTY,INPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID,CONSUMED_QTY)
                            SELECT R_NEXT_PROCESS_INPUT.ID, SL_NO, B.PROD_ID, B.DISPLAY_NAME, OUTPUT_QTY, OUTPUT_UOM,pUSER_ID,SYSDATE,pBATCH_ID,OUTPUT_QTY
                              FROM PP_WIP_PROC_OUTPUT A
                              LEFT JOIN (SELECT PROD_ID,DISPLAY_NAME FROM ADM_SBU_PRODUCTS
                                            WHERE PARENT_PROD_ID=pPROD_ID
                                            AND PROD_TYPE=504) B ON 1=1  --504 for sfg prod_id
                                WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID;

                        END IF;
                    
                    EXCEPTION
                        WHEN OTHERS THEN NULL;
                    END;
                    
                
                ELSE --if next process is not Dispensing
               
                    BEGIN
                    
                        IF vINPUT_CNT = 0 THEN

                            INSERT INTO PP_WIP_PROC_INPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,INPUT_QTY,INPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID)
                            SELECT R_NEXT_PROCESS_INPUT.ID, SL_NO, B.PROD_ID, B.DISPLAY_NAME, OUTPUT_QTY, OUTPUT_UOM,pUSER_ID,SYSDATE,pBATCH_ID
                              FROM PP_WIP_PROC_OUTPUT A
                              LEFT JOIN (SELECT PROD_ID,DISPLAY_NAME FROM ADM_SBU_PRODUCTS
                                          WHERE PARENT_PROD_ID=pPROD_ID
                                            AND PROD_TYPE=504) B ON 1=1  --504 for sfg prod_id
                                          WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID;

                        ELSE

                            DELETE FROM PP_WIP_PROC_INPUT  WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID;

                            INSERT INTO PP_WIP_PROC_INPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,INPUT_QTY,INPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID)
                            SELECT R_NEXT_PROCESS_INPUT.ID, SL_NO, B.PROD_ID, B.DISPLAY_NAME, OUTPUT_QTY, OUTPUT_UOM,pUSER_ID,SYSDATE,pBATCH_ID
                              FROM PP_WIP_PROC_OUTPUT A
                              LEFT JOIN (SELECT PROD_ID,DISPLAY_NAME FROM ADM_SBU_PRODUCTS
                                            WHERE PARENT_PROD_ID=pPROD_ID
                                            AND PROD_TYPE=504) B ON 1=1  --504 for sfg prod_id
                                WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID;

                        END IF;
                    
                    EXCEPTION
                        WHEN OTHERS THEN NULL;
                    END;
                    
                
                END IF;
                --- END NEXT PROCESS INPUT   ---

                --- NEXT PROCESS OUTPUT  DATA INSERT OR UPDATE ---
                
                SELECT COUNT(*) INTO vOUTPUT_CNT FROM PP_WIP_PROC_OUTPUT  WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID;
                
                IF R_NEXT_PROCESS_INPUT.PROCESS_ID = 10304 THEN --if next process is Dispensing
                
                    BEGIN
                    
                        IF vOUTPUT_CNT = 0 THEN
                    
                            INSERT INTO PP_WIP_PROC_OUTPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,OUTPUT_QTY,OUTPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID,OUTPUT_VALUE)
                            SELECT DISTINCT R_NEXT_PROCESS_INPUT.ID, 1, B.PROD_ID, B.DISPLAY_NAME, NULL, INPUT_UOM,pUSER_ID,SYSDATE,pBATCH_ID,INPUT_QTY
                              FROM PP_WIP_PROC_INPUT A
                              LEFT JOIN ADM_PRODUCTS AP ON A.PROD_ID = AP.ID
                              LEFT JOIN (SELECT PROD_ID,DISPLAY_NAME,PROD_TYPE FROM ADM_SBU_PRODUCTS
                                            WHERE PARENT_PROD_ID=pPROD_ID
                                            AND PROD_TYPE=504  --504 for sfg prod_id
                                        ) B ON 1=1
                             WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID
                               AND AP.PROD_TYPE=B.PROD_TYPE;
                          
                        ELSE
                        
                            FOR I IN (
                                        SELECT DISTINCT  B.PROD_ID, B.DISPLAY_NAME,INPUT_UOM,pUSER_ID,SYSDATE,pBATCH_ID LOT_ID,INPUT_QTY
                                          FROM PP_WIP_PROC_INPUT A
                                          LEFT JOIN ADM_PRODUCTS AP ON A.PROD_ID = AP.ID
                                          LEFT JOIN (SELECT PROD_ID,DISPLAY_NAME,PROD_TYPE FROM ADM_SBU_PRODUCTS
                                                        WHERE PARENT_PROD_ID=pPROD_ID
                                                        AND PROD_TYPE=504
                                                    ) B ON 1=1
                                         WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID
                                           AND AP.PROD_TYPE=B.PROD_TYPE
                                      )
                            LOOP
                            
                                SELECT COUNT(*) INTO vOUTPUT_CNT FROM PP_WIP_PROC_OUTPUT WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID AND PROD_ID = I.PROD_ID;
                                
                                IF vOUTPUT_CNT = 0 THEN

                                    INSERT INTO PP_WIP_PROC_OUTPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,OUTPUT_QTY,OUTPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID,OUTPUT_VALUE)
                                                            VALUES(R_NEXT_PROCESS_INPUT.ID,ROWNUM,I.PROD_ID,I.DISPLAY_NAME,NULL,I.INPUT_UOM,pUSER_ID,SYSDATE,I.LOT_ID,I.INPUT_QTY);

                                 
                                ELSE

                                    UPDATE PP_WIP_PROC_OUTPUT
                                       SET OUTPUT_UOM      = I.INPUT_UOM,
                                           OUTPUT_VALUE   = I.INPUT_QTY
                                     WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID
                                       AND PROD_ID = I.PROD_ID;

                                END IF;
                            
                            
                            END LOOP;   
                        
                        END IF;
                    
                    EXCEPTION
                        WHEN OTHERS THEN NULL;
                    END;
                    
                
                ELSE --if next process is not Dispensing
                
                    BEGIN
                    
                        IF vOUTPUT_CNT = 0 THEN

                            INSERT INTO PP_WIP_PROC_OUTPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,OUTPUT_QTY,OUTPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID)
                            SELECT R_NEXT_PROCESS_INPUT.ID,ROWNUM,PROD_ID,DISPLAY_NAME,NULL,BASE_UOM,pUSER_ID,SYSDATE,pBATCH_ID
                              FROM ADM_SBU_PRODUCTS
                             WHERE PARENT_PROD_ID = pPROD_ID
                               AND PROD_TYPE = 504
                               AND SBU_ID = pSBU_ID;

                        END IF;
                    
                    EXCEPTION
                        WHEN OTHERS THEN NULL;
                    END;
                    
                
                END IF;

            ELSIF vCURRENT_STAGE_ID = R_NEXT_PROCESS_INPUT.WIP_STAGE_ID THEN--WHEN CURRENT STAGE AND NEXT STAGE IS EQUAL

                --- NEXT PROCESS INPUT DATA INSERT ---
                
                SELECT COUNT(*) INTO vINPUT_CNT FROM PP_WIP_PROC_INPUT  WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID;
                
                IF R_NEXT_PROCESS_INPUT.PROCESS_ID = 10304 THEN --if next process is  Dispensing
                
                    BEGIN
                    
                        IF vINPUT_CNT = 0 THEN

                            INSERT INTO PP_WIP_PROC_INPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,INPUT_QTY,INPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID,CONSUMED_QTY)
                            SELECT R_NEXT_PROCESS_INPUT.ID, SL_NO, PROD_ID, ITEM_NAME, OUTPUT_QTY, OUTPUT_UOM,pUSER_ID,SYSDATE,LOT_ID,NULL
                              FROM PP_WIP_PROC_OUTPUT
                             WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID;

                        ELSE

                            FOR I IN (SELECT * FROM PP_WIP_PROC_OUTPUT  WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID)

                            LOOP

                                SELECT COUNT(*) INTO vINPUT_CNT FROM PP_WIP_PROC_INPUT
                                WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID AND PROD_ID = I.PROD_ID;

                                IF vINPUT_CNT = 0 THEN

                                    INSERT INTO PP_WIP_PROC_INPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,INPUT_QTY,INPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID,CONSUMED_QTY)
                                    SELECT R_NEXT_PROCESS_INPUT.ID, SL_NO, PROD_ID, ITEM_NAME, OUTPUT_QTY, OUTPUT_UOM,pUSER_ID,SYSDATE,LOT_ID,NULL
                                      FROM PP_WIP_PROC_OUTPUT
                                     WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID
                                       AND PROD_ID = I.PROD_ID;

                                ELSE

                                    UPDATE PP_WIP_PROC_INPUT
                                       SET INPUT_QTY      = I.OUTPUT_QTY,
                                           INPUT_UOM      = I.OUTPUT_UOM
                                           --CONSUMED_QTY   = I.OUTPUT_QTY
                                     WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID
                                       AND PROD_ID = I.PROD_ID;

                                END IF;

                            END LOOP;

                        END IF;
                
                    EXCEPTION
                        WHEN OTHERS THEN NULL;
                    END;
                
                
                ELSE --if next process is not Dispensing
                
                    BEGIN
                    
                        IF vINPUT_CNT = 0 THEN

                            INSERT INTO PP_WIP_PROC_INPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,INPUT_QTY,INPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID)
                            SELECT R_NEXT_PROCESS_INPUT.ID, SL_NO, PROD_ID, ITEM_NAME, OUTPUT_QTY, OUTPUT_UOM,pUSER_ID,SYSDATE,LOT_ID
                              FROM PP_WIP_PROC_OUTPUT
                             WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID;

                        ELSE

                            FOR I IN (SELECT * FROM PP_WIP_PROC_OUTPUT    WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID)

                            LOOP

                                SELECT COUNT(*) INTO vINPUT_CNT FROM PP_WIP_PROC_INPUT
                                WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID AND PROD_ID = I.PROD_ID;

                                IF vINPUT_CNT = 0 THEN

                                    INSERT INTO PP_WIP_PROC_INPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,INPUT_QTY,INPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID)
                                    SELECT R_NEXT_PROCESS_INPUT.ID, SL_NO, PROD_ID, ITEM_NAME, OUTPUT_QTY, OUTPUT_UOM,pUSER_ID,SYSDATE,LOT_ID
                                      FROM PP_WIP_PROC_OUTPUT
                                     WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID
                                       AND PROD_ID = I.PROD_ID;

                                ELSE

                                    UPDATE PP_WIP_PROC_INPUT
                                       SET INPUT_QTY      = I.OUTPUT_QTY,
                                           INPUT_UOM      = I.OUTPUT_UOM
                                           --CONSUMED_QTY   = I.OUTPUT_QTY
                                     WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID
                                       AND PROD_ID = I.PROD_ID;

                                END IF;

                            END LOOP;

                        END IF;
                    
                    EXCEPTION
                        WHEN OTHERS THEN NULL;
                    END;
                    
                
                END IF;

                --- END NEXT PROCESS INPUT  ---

                --- NEXT PROCESS OUTPUT DATA INSERT UPDATE ---
                SELECT COUNT(*) INTO vOUTPUT_CNT FROM PP_WIP_PROC_OUTPUT  WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID AND CAN_SHOW='Y';
                
                BEGIN
                
                    IF R_NEXT_PROCESS_INPUT.PROCESS_ID = 10304 THEN --if next process is  Dispensing
                
                        IF vOUTPUT_CNT = 0 THEN
                        
                            vSORT_ORDER := DFN_FOR_SORT_ORDER_SERIAL ('PP_WIP_PROC_OUTPUT');
                            
                            INSERT INTO PP_WIP_PROC_OUTPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,OUTPUT_QTY,OUTPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID,OUTPUT_VALUE)
                            SELECT DISTINCT R_NEXT_PROCESS_INPUT.ID, 1, B.PROD_ID, B.DISPLAY_NAME, NULL, INPUT_UOM,pUSER_ID,SYSDATE,DECODE(B.PROD_TYPE,504,pBATCH_ID,514,pBATCH_ID,LOT_ID),INPUT_QTY
                              FROM PP_WIP_PROC_INPUT A
                              LEFT JOIN ADM_PRODUCTS AP ON A.PROD_ID = AP.ID
                              LEFT JOIN (SELECT PROD_ID,DISPLAY_NAME,PROD_TYPE FROM ADM_SBU_PRODUCTS
                                            WHERE PARENT_PROD_ID = pPROD_ID
                                            AND PROD_TYPE = DECODE(R_NEXT_PROCESS_INPUT.WIP_STAGE_ID,7611,514,7612,504)
                                        ) B ON 1=1
                             WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID
                               AND AP.PROD_TYPE=B.PROD_TYPE;
                               
                        ELSE
                            
                            FOR I IN (
                                        SELECT DISTINCT  B.PROD_ID, B.DISPLAY_NAME,INPUT_UOM,DECODE(B.PROD_TYPE,504,pBATCH_ID,514,pBATCH_ID,LOT_ID) LOT_ID,INPUT_QTY
                                          FROM PP_WIP_PROC_INPUT A
                                          LEFT JOIN ADM_PRODUCTS AP ON A.PROD_ID = AP.ID
                                          LEFT JOIN (SELECT PROD_ID,DISPLAY_NAME,PROD_TYPE FROM ADM_SBU_PRODUCTS
                                                        WHERE PARENT_PROD_ID = pPROD_ID
                                                        AND PROD_TYPE = DECODE(R_NEXT_PROCESS_INPUT.WIP_STAGE_ID,7611,514,7612,504)
                                                    ) B ON 1=1
                                         WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID
                                           AND AP.PROD_TYPE=B.PROD_TYPE
                                      )
                            LOOP
                            
                                SELECT COUNT(*) INTO vOUTPUT_CNT FROM PP_WIP_PROC_OUTPUT WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID AND PROD_ID = I.PROD_ID;
                                
                                IF vOUTPUT_CNT = 0 THEN

                                    INSERT INTO PP_WIP_PROC_OUTPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,OUTPUT_QTY,OUTPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID,OUTPUT_VALUE)
                                                            VALUES(R_NEXT_PROCESS_INPUT.ID,1,I.PROD_ID,I.DISPLAY_NAME,NULL,I.INPUT_UOM,pUSER_ID,SYSDATE,I.LOT_ID,I.INPUT_QTY);

                                ELSE

                                    UPDATE PP_WIP_PROC_OUTPUT
                                       SET OUTPUT_UOM      = I.INPUT_UOM,
                                           OUTPUT_VALUE   = I.INPUT_QTY
                                     WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID
                                       AND PROD_ID = I.PROD_ID;

                                END IF;
                            
                            
                            END LOOP;               
                        
                        END IF; 
                    
                    ELSE --if next process is not Dispensing
                    
                        IF vOUTPUT_CNT = 0 THEN
                        
                            vSORT_ORDER := DFN_FOR_SORT_ORDER_SERIAL ('PP_WIP_PROC_OUTPUT');

                            INSERT INTO PP_WIP_PROC_OUTPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,OUTPUT_QTY,OUTPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID)
                            SELECT DISTINCT R_NEXT_PROCESS_INPUT.ID, 1, B.PROD_ID, B.DISPLAY_NAME, NULL INPUT_QTY, DECODE(B.PROD_TYPE,504,532,514,538),pUSER_ID,SYSDATE,DECODE(B.PROD_TYPE,504,pBATCH_ID,514,pBATCH_ID,LOT_ID)
                              FROM PP_WIP_PROC_INPUT A
                              LEFT JOIN (SELECT PROD_ID,DISPLAY_NAME,PROD_TYPE FROM ADM_SBU_PRODUCTS
                                            WHERE PARENT_PROD_ID = pPROD_ID
                                            AND PROD_TYPE = DECODE(R_NEXT_PROCESS_INPUT.WIP_STAGE_ID,7611,514,7612,504)
                                        ) B ON 1=1
                             WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID;

                        END IF;
                    
                    END IF;
                
                EXCEPTION
                    WHEN OTHERS THEN NULL;
                END;
                
                --- END NEXT PROCESS OUTPUT DATA INSERT UPDATE ---

            END IF;

        END IF;
        
        /* NEXT PROCESS OR SUB-PROCESS DATA FOUND CHECK*/

    ELSIF vNEXT_PROCESS_SEQUENCE = vTOTAL_PROCESS THEN --LAST PROCESS CHECK

        OPEN C_NEXT_PROCESS_INPUT;
        FETCH C_NEXT_PROCESS_INPUT INTO R_NEXT_PROCESS_INPUT; CLOSE C_NEXT_PROCESS_INPUT;

        SELECT COUNT(*) INTO vINPUT_CNT FROM PP_WIP_PROC_INPUT  WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID;

        BEGIN
        
            IF vINPUT_CNT = 0 THEN

                INSERT INTO PP_WIP_PROC_INPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,INPUT_QTY,INPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID)
                SELECT NVL(R_NEXT_PROCESS_INPUT.ID,pWIP_PROCESS_ID), SL_NO, PROD_ID, ITEM_NAME, OUTPUT_QTY, OUTPUT_UOM,pUSER_ID,SYSDATE,LOT_ID
                  FROM PP_WIP_PROC_OUTPUT
                 WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID;

            ELSE

                FOR I IN (SELECT * FROM PP_WIP_PROC_OUTPUT    WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID)

                LOOP

                    SELECT COUNT(*) INTO vINPUT_CNT FROM PP_WIP_PROC_INPUT
                    WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID AND PROD_ID = I.PROD_ID;

                    IF vINPUT_CNT = 0 THEN

                        INSERT INTO PP_WIP_PROC_INPUT(WIP_PROCESS_ID,SL_NO,PROD_ID,ITEM_NAME,INPUT_QTY,INPUT_UOM,CREATED_BY,CREATED_AT,LOT_ID)
                        SELECT NVL(R_NEXT_PROCESS_INPUT.ID,pWIP_PROCESS_ID), SL_NO, PROD_ID, ITEM_NAME, OUTPUT_QTY, OUTPUT_UOM,pUSER_ID,SYSDATE,LOT_ID
                          FROM PP_WIP_PROC_OUTPUT
                         WHERE WIP_PROCESS_ID = pWIP_PROCESS_ID
                           AND PROD_ID = I.PROD_ID;

                    ELSE

                        UPDATE PP_WIP_PROC_INPUT
                           SET INPUT_QTY      = I.OUTPUT_QTY,
                               INPUT_UOM      = I.OUTPUT_UOM
                               --CONSUMED_QTY   = I.OUTPUT_QTY
                         WHERE WIP_PROCESS_ID = R_NEXT_PROCESS_INPUT.ID
                           AND PROD_ID = I.PROD_ID;

                    END IF;

                END LOOP;

            END IF;
        
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
        

    END IF;

EXCEPTION
    WHEN OTHERS THEN
    vMESSAGE := 'Error Code : '|| SQLCODE || ' Error Text Wip-Mst : ' || SQLERRM;
    ROLLBACK;
    RETURN;

END PD_WIP_PROCESS_IN_OUT_DML_V2;


     