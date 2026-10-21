-- probe: steps (ok, or the propagated error code; the routine writes no table on Oracle)
SELECT step, code, msg, s FROM diff_probe ORDER BY step;
