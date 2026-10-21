-- tt__util__close_old_dev / cleanup.ora.sql -- COMMITS=yes: remove the fixture tickets that
-- setup.ora.sql committed, and anything the dev path (change_status to 102) would have written
-- for them. The composer appends COMMIT.
DELETE FROM tt.ticket_time_statistic WHERE ticket_id BETWEEN 958400 AND 958402;
DELETE FROM tt.ticket_flow WHERE ticket_id BETWEEN 958400 AND 958402;
DELETE FROM tt.event WHERE ticket_id BETWEEN 958400 AND 958402;
UPDATE tt.ticket SET last_public_event_id = NULL WHERE id BETWEEN 958400 AND 958402;
DELETE FROM tt.ticket WHERE id BETWEEN 958400 AND 958402;
