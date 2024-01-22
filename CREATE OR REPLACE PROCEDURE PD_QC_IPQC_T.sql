CREATE OR REPLACE PROCEDURE PD_QC_IPQC_TEST_DML (
	pINPUT   CLOB,
	pUSER_ID NUMBER,
	pSBU_ID  NUMBER,
	pSTATUS  OUT CLOB
) IS
    vINPUT_OBJ          JSON_OBJECT_T := NEW JSON_OBJECT_T;
    vOUTPUT_OBJ         JSON_OBJECT_T := NEW JSON_OBJECT_T;
    vMESSAGE    VARCHAR2(4000);

    vID              NUMBER;
    vTEST_NAME       VARCHAR2(2000);
    vPARENT_ID       NUMBER;
    vLVL             NUMBER;

BEGIN
	vINPUT_OBJ  :=  JSON_OBJECT_T.PARSE(pINPUT);
    vINPUT_OBJ  :=  vINPUT_OBJ.GET_OBJECT('test_list');
    declare
        vSUB_TEST_ARR   JSON_ARRAY_T;
    begin
        vID                 := vINPUT_OBJ.GET_NUMBER('id');
        vTEST_NAME          := vINPUT_OBJ.GET_NUMBER('test_name');
        vPARENT_ID          := vINPUT_OBJ.GET_NUMBER('parent_id');
        vLVL                := vINPUT_OBJ.GET_NUMBER('lvl');

        if nvl(vID,0)=0 then
            vID := nvl(vID,0)+1;

            insert into pp_qc_ipqc_test (id,test_name,parent_id,lvl)
            values (vID,vTEST_NAME,vPARENT_ID,vLVL);
        end if;

        vMESSAGE := 'DATA SAVE SUCCESSFULLY. ';
                vOUTPUT_OBJ.PUT('response_code',200);
                vOUTPUT_OBJ.PUT('test_id', vID);
                vOUTPUT_OBJ.PUT('test_name', vTEST_NAME);
                vOUTPUT_OBJ.PUT('message', vMESSAGE);
                pSTATUS := vOUTPUT_OBJ.TO_CLOB;
    end;
EXCEPTION
	WHEN OTHERS THEN
		vOUTPUT_OBJ.PUT('response_code',400);
        vMESSAGE := 'ERROR CODE : '|| SQLCODE || ' ERROR TEXT_MST : ' || SQLERRM;
        vOUTPUT_OBJ.PUT('message', vMESSAGE);
        pSTATUS := vOUTPUT_OBJ.TO_CLOB;
        --DBMS_OUTPUT.PUT_LINE(VMESSAGE);
        ROLLBACK;
        RETURN;
END PD_QC_IPQC_TEST_DML;