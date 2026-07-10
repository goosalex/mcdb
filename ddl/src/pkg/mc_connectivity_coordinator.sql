--liquibase formatted sql logicalFilePath:pkg/mc_connectivity_coordinator.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE MC.CONNECTIVITY_COORDINATOR IS

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- sync_interrupt: insert a new entry in table connection_interrupt_open
--
-- parameter:  p_host_id
--             p_interrupt_type
--             p_details
--             p_timestamp
-------------------------------------------------------------------------------

  PROCEDURE sync_interrupt_prod(
      p_host_id             mss.host.id%TYPE,
      p_interrupt_type      mc.connection_interrupt_open.type_id%TYPE,
      p_details             mc.connection_interrupt_open.details%TYPE,
      p_timestamp           mc.HOST_CONNECTION_STATUS.con_timestamp%TYPE
  ) ;




-------------------------------------------------------------------------------
-- update_isp_link_status:
-- * calls update_isp_link_status_w_date with SYSDATE
-------------------------------------------------------------------------------
  PROCEDURE update_isp_link_status
  (
    p_isp_link_id      mc.isp_link_history.isp_link_id%type,
    p_status           mc.isp_link_status_type.id%type,
    p_previous_status  mc.isp_link_status_type.id%type,
    p_reported_by      mc.isp_link_history.reporting_host_id%type
  ) ;


-------------------------------------------------------------------------------
-- update_isp_link_status_w_date:
-- * updates the isp_link and isp_link_history tables
-- * does a sanity check with p_previous_status
-------------------------------------------------------------------------------
  PROCEDURE update_isp_link_status_w_date
  (
    p_isp_link_id      mc.isp_link_history.isp_link_id%type,
    p_status           mc.isp_link_status_type.id%type,
    p_previous_status  mc.isp_link_status_type.id%type,
    p_reported_by      mc.isp_link_history.reporting_host_id%type,
    on_date            mc.isp_link_history.change_date%type
  );

-------------------------------------------------------------------------------
-- sync_isp_link_status:
-- * updates the isp_link and isp_link_history tables
-- * does whatever change necessary to the history
-------------------------------------------------------------------------------
  PROCEDURE sync_isp_link_status
  (
    p_isp_link_id      mc.isp_link_history.isp_link_id%type,
    p_status           mc.isp_link_status_type.id%type
  ) ;

END CONNECTIVITY_COORDINATOR;
    --
/
