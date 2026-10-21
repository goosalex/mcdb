-- probe: steps (id set for rate_ticket, ok otherwise; error code for failed steps)
SELECT step, code, msg, n, s FROM diff_probe ORDER BY step;

-- probe: rated tickets (rating values resolved through the rating columns of the ticket, ids never selected)
SELECT t.id, t.status_id,
       (SELECT r.rating FROM tt.ticket_rating r WHERE r.id = t.customer_ticket_rating_id) AS customer_rating,
       (SELECT r.rating FROM tt.ticket_rating r WHERE r.id = t.engineer_ticket_rating_id) AS engineer_rating,
       CASE WHEN t.last_public_event_id IS NOT NULL THEN 1 ELSE 0 END AS has_last_public_event,
       CASE WHEN t.status_valid_until_date IS NOT NULL THEN 1 ELSE 0 END AS has_valid_until
FROM tt.ticket t WHERE t.id IN (954210, 954211, 954212, 954213) ORDER BY t.id;

-- probe: rating rows per rating event
SELECT event_id, rating, COUNT(*) AS n_rows
FROM tt.ticket_rating WHERE event_id IN (954220, 954221, 954222, 954223)
GROUP BY event_id, rating ORDER BY event_id, rating;

-- probe: events written by the routines (escalation 100007, status change to hot 101003)
SELECT type_id, ticket_id, public_event, company_id, host_id, contact_id, details_public, details_private
FROM tt.event
WHERE ticket_id IN (954210, 954211, 954212, 954213, 954099999) AND type_id IN (100007, 101003)
ORDER BY ticket_id, type_id, details_private;

-- probe: ticket_flow rows (open_time compared as buckets; both engines measure wall-clock time)
SELECT ticket_id,
       CASE WHEN flow_out_date IS NULL THEN 0 ELSE 1 END AS flow_closed,
       CASE WHEN open_time = 0 THEN 'zero'
            WHEN open_time BETWEEN 1700 AND 1900 THEN 'about 1800'
            WHEN open_time BETWEEN 2600 AND 2800 THEN 'about 2700'
            WHEN open_time BETWEEN 3500 AND 3700 THEN 'about 3600'
            ELSE 'other' END AS open_time_bucket,
       COUNT(*) AS n_rows
FROM tt.ticket_flow WHERE ticket_id IN (954212, 954214, 954215, 954216, 954217, 954218, 954219, 954099999)
GROUP BY ticket_id, CASE WHEN flow_out_date IS NULL THEN 0 ELSE 1 END,
         CASE WHEN open_time = 0 THEN 'zero'
              WHEN open_time BETWEEN 1700 AND 1900 THEN 'about 1800'
              WHEN open_time BETWEEN 2600 AND 2800 THEN 'about 2700'
              WHEN open_time BETWEEN 3500 AND 3700 THEN 'about 3600'
              ELSE 'other' END
ORDER BY ticket_id, flow_closed;
