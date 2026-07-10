--liquibase formatted sql logicalFilePath:triggers/GUMA2.sql
--changeset sys:1 runOnChange:true endDelimiter:/
CREATE OR REPLACE TRIGGER guma2.pattern_pos
BEFORE INSERT or UPDATE OF position ON guma2.pattern
FOR EACH ROW
DECLARE
  PRAGMA AUTONOMOUS_TRANSACTION;

  c_prefix CONSTANT VARCHAR2(64) := 'TRIGGER guma2.pattern_pos: ';
  l_maxpos NUMBER;

BEGIN
  IF :new.position is NULL THEN
    SELECT MAX(position) INTO l_maxpos FROM guma2.PATTERN;

    IF (l_maxpos IS NULL) THEN
      :new.position := 1;
    ELSE
      :new.position := l_maxpos + 1;
    END IF;
  END IF;
END;
/

