--liquibase formatted sql logicalFilePath:triggers/TT.sql
--changeset sys:1 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER "TT"."TICKET_UPDATE_TRG" BEFORE UPDATE OR INSERT OF "TYPE_ID", "STATUS_ID", "SUBJECT", "HOST_ID", "MSS_SERVICE_ID", "COMPANY_ID", "CONTACT_ID", "CUSTOMER_REFERENCE", "EMERGENCY", "ALWAYS_VISIBLE", "HANDLED_BY_MCC", "CUSTOMER_TICKET_RATING_ID", "LAST_PUBLIC_EVENT_ID" ON "TT"."TICKET" 
REFERENCING OLD AS OLD NEW AS NEW FOR EACH ROW 
BEGIN
	:new.update_timestamp := SYSTIMESTAMP;
END;
/

--changeset sys:2 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER tt.todo_item_update_trg
BEFORE INSERT OR UPDATE ON tt.todo_item
FOR EACH ROW
BEGIN
	:new.update_timestamp := SYSTIMESTAMP;
END;
/

