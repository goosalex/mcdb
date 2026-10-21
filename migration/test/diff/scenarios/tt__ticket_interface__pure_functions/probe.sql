-- probe: steps (next ticket id in n with found/null in s; placeholder results in s)
SELECT step, code, msg, n, s FROM diff_probe ORDER BY step;

-- probe: fixture tickets untouched by the two functions
SELECT id, type_id, status_id, host_id,
       CASE WHEN last_resolved_date IS NOT NULL THEN 1 ELSE 0 END AS has_last_resolved
FROM tt.ticket WHERE id BETWEEN 954080 AND 954086 ORDER BY id;
