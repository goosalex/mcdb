-- tt__ticket_interface__rating_flow / setup.sql -- dialect-neutral fixtures (954200-954299).
-- Reference rows reused from the master data present on both sides: tt.status 2/3/11/12,
-- tt.ticket_type 1/4, tt.event_type 101002, mss.operating_system 2, mss.service_type 6,
-- mss.service_level 1. handled_by_mcc is set explicitly on every flow ticket.
INSERT INTO stop.company (id, name, short) VALUES (954201, 'Diff Rating Co', 'dfrate');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (954202, 'Requester', 'DiffRate', 'dfraterq', 954201);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author) VALUES (954205, 'diff-rate-host', 2, 954201, 'diff');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (954206, 6, 954201, 1, 'diff-rate-svc');
INSERT INTO mss.host2service (host_id, service_id) VALUES (954205, 954206);
-- R1 engineer rating, R2 good customer rating, R3 bad customer rating (-> hot), each with a rating event
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, handled_by_mcc)
    VALUES (954210, 1, 2, 954201, 954202, 954205, 'diff rate R1', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 1);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, handled_by_mcc)
    VALUES (954211, 1, 2, 954201, 954202, 954205, 'diff rate R2', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 1);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, handled_by_mcc)
    VALUES (954212, 1, 2, 954201, 954202, 954205, 'diff rate R3', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 1);
INSERT INTO tt.event (id, type_id, ticket_id, details_public) VALUES (954220, 101002, 954210, 'R1 fixture event');
INSERT INTO tt.event (id, type_id, ticket_id, details_public) VALUES (954221, 101002, 954211, 'R2 fixture event');
INSERT INTO tt.event (id, type_id, ticket_id, details_public) VALUES (954222, 101002, 954212, 'R3 fixture event');
-- E: escalation ticket with its triggering event
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, handled_by_mcc)
    VALUES (954213, 1, 2, 954201, 954202, 954205, 'diff rate E', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 1);
INSERT INTO tt.event (id, type_id, ticket_id, details_public) VALUES (954223, 101002, 954213, 'E fixture event');
-- F1: open, MCC, type 1, not yet in the queue -> inserted
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date, handled_by_mcc)
    VALUES (954214, 1, 2, 954201, 954202, 'diff flow F1', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 1);
-- F2: open, MCC, but type 4 (isp outage) -> never queued
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date, handled_by_mcc)
    VALUES (954215, 4, 2, 954201, 954202, 'diff flow F2', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 1);
-- F3: hot (was open until 1 hour ago), MCC, in the queue since 2 hours -> stays, open_time += ~3600
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date, handled_by_mcc)
    VALUES (954216, 1, 3, 954201, 954202, 'diff flow F3', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 1);
INSERT INTO tt.ticket_flow (id, ticket_id, flow_in_date, open_time) VALUES (954226, 954216, CURRENT_TIMESTAMP - INTERVAL '2' HOUR, 0);
-- F4: open since 30 minutes, no longer MCC, in the queue since 2 hours -> taken out, open_time += ~1800
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date, handled_by_mcc)
    VALUES (954217, 1, 2, 954201, 954202, 'diff flow F4', CURRENT_TIMESTAMP - INTERVAL '30' MINUTE, 0);
INSERT INTO tt.ticket_flow (id, ticket_id, flow_in_date, open_time) VALUES (954227, 954217, CURRENT_TIMESTAMP - INTERVAL '2' HOUR, 0);
-- F5: waiting (was open until 45 minutes ago), MCC, in the queue since 2 hours -> taken out, open_time += ~2700
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date, handled_by_mcc)
    VALUES (954218, 1, 11, 954201, 954202, 'diff flow F5', CURRENT_TIMESTAMP - INTERVAL '45' MINUTE, 1);
INSERT INTO tt.ticket_flow (id, ticket_id, flow_in_date, open_time) VALUES (954228, 954218, CURRENT_TIMESTAMP - INTERVAL '2' HOUR, 0);
-- F6: third party, MCC, in the queue -> taken out without a previous status: open_time stays 0
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date, handled_by_mcc)
    VALUES (954219, 1, 12, 954201, 954202, 'diff flow F6', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 1);
INSERT INTO tt.ticket_flow (id, ticket_id, flow_in_date, open_time) VALUES (954229, 954219, CURRENT_TIMESTAMP - INTERVAL '2' HOUR, 0);
