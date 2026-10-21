-- probe: steps (ok, or the error code of a failed step)
SELECT step, code, msg, n, s FROM diff_probe ORDER BY step;

-- probe: merged tickets (rating ids are fixture ids; last_public_event_id classified, never selected)
SELECT id, status_id, merged_into_ticket_id, partner_reference, fast_resolvable, recoverable_status_id,
       customer_ticket_rating_id, engineer_ticket_rating_id,
       CASE WHEN close_date IS NOT NULL THEN 1 ELSE 0 END AS has_close_date,
       CASE WHEN last_resolved_date IS NOT NULL THEN 1 ELSE 0 END AS has_last_resolved,
       CASE WHEN last_public_event_id IS NULL THEN 'null'
            WHEN last_public_event_id = 954341 THEN 'src new event'
            WHEN last_public_event_id = 954342 THEN 'tgt event'
            ELSE 'other' END AS last_public_event
FROM tt.ticket WHERE id IN (954320, 954321, 954322, 954323) ORDER BY id;

-- probe: events of the merged tickets (fixture events re-pointed with org_ticket_id, merge and status events)
SELECT type_id, ticket_id, org_ticket_id, public_event, company_id, contact_id, details_public, details_private
FROM tt.event WHERE ticket_id IN (954320, 954321, 954322, 954323)
ORDER BY ticket_id, type_id, details_public, details_private;

-- probe: notifications (A duplicate deleted, B kept, D moved)
SELECT id, ticket_id, login_id FROM tt.event_notification WHERE id IN (954350, 954351, 954352) ORDER BY id;

-- probe: change request and suppressed signature moved to the target
SELECT 'change_request' AS tbl, id, ticket_id FROM tt.change_request WHERE id = 954360
UNION ALL
SELECT 'suppressed_signature' AS tbl, id, ticket_id FROM guma2.suppressed_signature WHERE id = 954370
ORDER BY tbl;

-- probe: time statistics and queue rows written by the two change_status calls per merge
SELECT ts.ticket_id,
       CASE WHEN ts.open_time > 0 THEN 1 ELSE 0 END AS has_open_time,
       CASE WHEN ts.resolved_time > 0 THEN 1 ELSE 0 END AS has_resolved_time,
       (SELECT COUNT(*) FROM tt.ticket_flow tf WHERE tf.ticket_id = ts.ticket_id AND tf.flow_out_date IS NULL) AS open_flows,
       (SELECT COUNT(*) FROM tt.ticket_flow tf WHERE tf.ticket_id = ts.ticket_id AND tf.flow_out_date IS NOT NULL) AS closed_flows
FROM tt.ticket_time_statistic ts WHERE ts.ticket_id IN (954320, 954321, 954322, 954323) ORDER BY ts.ticket_id;

-- probe: deleteTicket leftovers (every count must be 0; de-referenced rows report their nulled column)
SELECT 'tt.ticket' AS tbl, COUNT(*) AS n FROM tt.ticket WHERE id = 954325
UNION ALL SELECT 'tt.event', COUNT(*) FROM tt.event WHERE ticket_id = 954325
UNION ALL SELECT 'tt.ticket_rating', COUNT(*) FROM tt.ticket_rating WHERE id IN (954335, 954336, 954337)
UNION ALL SELECT 'tt.ticket2related_ticket', COUNT(*) FROM tt.ticket2related_ticket WHERE ticket_id = 954325 OR related_ticket_id = 954325
UNION ALL SELECT 'tt.ticket2mc_file', COUNT(*) FROM tt.ticket2mc_file WHERE ticket_id = 954325
UNION ALL SELECT 'tt.ticket_docs_page', COUNT(*) FROM tt.ticket_docs_page WHERE ticket_id = 954325
UNION ALL SELECT 'tt.ticket_flow', COUNT(*) FROM tt.ticket_flow WHERE ticket_id = 954325
UNION ALL SELECT 'tt.todo_item', COUNT(*) FROM tt.todo_item WHERE ticket_id = 954325
UNION ALL SELECT 'tt.ticket_request_classification', COUNT(*) FROM tt.ticket_request_classification WHERE ticket_id = 954325
UNION ALL SELECT 'tt.change_request', COUNT(*) FROM tt.change_request WHERE ticket_id = 954325
UNION ALL SELECT 'tt.event_notification', COUNT(*) FROM tt.event_notification WHERE ticket_id = 954325
UNION ALL SELECT 'tt.ticket_time_statistic', COUNT(*) FROM tt.ticket_time_statistic WHERE ticket_id = 954325
UNION ALL SELECT 'tt.attachment', COUNT(*) FROM tt.attachment WHERE ticket_id = 954325
UNION ALL SELECT 'tt.service_window', COUNT(*) FROM tt.service_window WHERE ticket_id = 954325
UNION ALL SELECT 'tt.maintenance_window', COUNT(*) FROM tt.maintenance_window WHERE service_window_id = 954389
UNION ALL SELECT 'tt.cust_maintenance_window', COUNT(*) FROM tt.cust_maintenance_window WHERE service_window_id = 954389
UNION ALL SELECT 'tt.host2service_window', COUNT(*) FROM tt.host2service_window WHERE service_window_id = 954389
UNION ALL SELECT 'mss.deleted_host2service_window', COUNT(*) FROM mss.deleted_host2service_window WHERE service_window_id = 954389
UNION ALL SELECT 'nids.ticket2rule', COUNT(*) FROM nids.ticket2rule WHERE ticket_id = 954325
UNION ALL SELECT 'fw.rule2ticket', COUNT(*) FROM fw.rule2ticket WHERE ticket_id = 954325
UNION ALL SELECT 'fw.source_nat_rule2ticket', COUNT(*) FROM fw.source_nat_rule2ticket WHERE ticket_id = 954325
UNION ALL SELECT 'fw.destination_nat_rule2ticket', COUNT(*) FROM fw.destination_nat_rule2ticket WHERE ticket_id = 954325
UNION ALL SELECT 'guma2.suppressed_signature', COUNT(*) FROM guma2.suppressed_signature WHERE ticket_id = 954325
UNION ALL SELECT 'fw.change', COUNT(*) FROM fw.change WHERE ticket_id = 954325
UNION ALL SELECT 'prx.prx_policy_item still referencing', COUNT(*) FROM prx.prx_policy_item WHERE ticket_id = 954325
UNION ALL SELECT 'prx.prx_policy_item nulled', COUNT(*) FROM prx.prx_policy_item WHERE id = 954397 AND ticket_id IS NULL
UNION ALL SELECT 'mcaudit.record still referencing', COUNT(*) FROM mcaudit.record WHERE ticket_id = 954325
UNION ALL SELECT 'mcaudit.record nulled', COUNT(*) FROM mcaudit.record WHERE id = 954398 AND ticket_id IS NULL
UNION ALL SELECT 'mc.isp_link_history nulled', COUNT(*) FROM mc.isp_link_history WHERE id = 954399 AND event_id IS NULL
UNION ALL SELECT 'mss.installation_project_item nulled', COUNT(*) FROM mss.installation_project_item WHERE id = 954300 AND ticket_id IS NULL
UNION ALL SELECT 'mc.isp_link_maintenance_history nulled', COUNT(*) FROM mc.isp_link_maintenance_history WHERE id = 954312 AND ticket_id IS NULL
UNION ALL SELECT 'mc.host_maintenance_history nulled', COUNT(*) FROM mc.host_maintenance_history WHERE id = 954313 AND ticket_id IS NULL
UNION ALL SELECT 'OTHER merged_into nulled', COUNT(*) FROM tt.ticket WHERE id = 954326 AND merged_into_ticket_id IS NULL
UNION ALL SELECT 'OTHER customer rating nulled', COUNT(*) FROM tt.ticket WHERE id = 954326 AND customer_ticket_rating_id IS NULL
ORDER BY tbl;
