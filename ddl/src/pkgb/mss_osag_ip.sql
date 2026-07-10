--liquibase formatted sql logicalFilePath:pkgb/mss_osag_ip.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY MSS.OSAG_IP IS

-------------------------------------------------------------------------------------------
-- FUNCTION getbcast
-------------------------------------------------------------------------------------------

    FUNCTION getbcast(p_ip NUMBER, p_mask NUMBER)
        RETURN NUMBER
        DETERMINISTIC
        IS
        v_maskrange	NUMBER			:= 0;
        c_prefix 	CONSTANT VARCHAR2(64)	:= 'OSAG_IP.getbcast(): ';
    BEGIN
        v_maskrange := POWER(2,(32-p_mask));
        RETURN ((TRUNC(p_ip/v_maskrange,0)+1)*v_maskrange)-1;
    END;

-------------------------------------------------------------------------------------------
-- FUNCTION getnet
-------------------------------------------------------------------------------------------

    FUNCTION getnet(p_ip NUMBER, p_mask NUMBER)
        RETURN NUMBER
        DETERMINISTIC
        IS
        v_maskrange	NUMBER			:= 0;
        v_offset	NUMBER			:= 0;
        c_prefix 	CONSTANT VARCHAR2(64)	:= 'OSAG_IP.getnet(): ';
    BEGIN
        v_maskrange := POWER(2,(32-p_mask));
        v_offset := MOD(p_ip,v_maskrange);
        RETURN ( p_ip - v_offset );
    END;

-------------------------------------------------------------------------------------------
-- FUNCTION ip2num
-------------------------------------------------------------------------------------------

    FUNCTION ip2num(p_string VARCHAR2)
        RETURN NUMBER
        DETERMINISTIC
        IS
        v_byte_no 	NUMBER			:= 0;
        v_byte_start 	NUMBER			:= 0;
        v_byte_length 	NUMBER			:= 0;
        v_byte_string 	VARCHAR2(32);
        v_result 	NUMBER			:= 0;
        c_prefix 	CONSTANT VARCHAR2(64)	:= 'OSAG_IP.ip2num(): ';
    BEGIN
        if p_string is null then
          return null;
        end if;
        FOR v_byte_no IN 1..4 LOOP

                -- get position of left dot

                IF (v_byte_no > 1) THEN
                    v_byte_start := INSTR(p_string,'.',1,v_byte_no-1)+1;
                    IF (v_byte_start < 2) THEN
                        plog.debug(c_prefix||'not enough dots in ip address [pos1]: '||p_string);
                        RETURN NULL;
                    END IF;
                ELSE
                    v_byte_start := 1;
                END IF;

                -- get position of right dot

                IF (v_byte_no < 4) THEN
                    v_byte_length := INSTR(p_string,'.',1,v_byte_no) - v_byte_start;
                ELSE
                    v_byte_length := LENGTH(p_string) - INSTR(p_string,'.',1,3);
                END IF;
                IF (v_byte_start < 1) THEN
                    plog.debug(c_prefix||'not enough dots in ip address [pos2]: '||p_string);
                    RETURN NULL;
                END IF;
                -- DBMS_OUTPUT.PUT_LINE(c_prefix||' byte'||v_byte_no||': start='||v_byte_start||', length='||v_byte_length);

                -- verify we have a numeric byte

                v_byte_string := substr(p_string,v_byte_start,v_byte_length);
-- DBMS_OUTPUT.PUT_LINE(c_prefix||' byte'||v_byte_no||'='||v_byte_string);
                IF((TO_CHAR(TO_NUMBER(v_byte_string)) != v_byte_string)) THEN
                    plog.debug(c_prefix||'invalid byte 1 in ip address: '||p_string);
                    RETURN NULL;
                END IF;
                IF (TO_NUMBER(v_byte_string) > 255) THEN
                    plog.debug(c_prefix||'number too big in byte '||v_byte_no||' in ip address: '||p_string);
                    RETURn NULL;
                END IF;

                -- add to result

                v_result := v_result * 256 + TO_NUMBER(v_byte_string);
            END LOOP;
        RETURN v_result;
    END;

-------------------------------------------------------------------------------------------
-- FUNCTION num2ip
-------------------------------------------------------------------------------------------

    FUNCTION num2ip(p_number NUMBER)
        RETURN VARCHAR2
        DETERMINISTIC
        IS
        v_byte 		NUMBER			:= NULL;
        v_reminder 	NUMBER			:= NULL;
        v_result 	VARCHAR2(15)		:= NULL;
        c_prefix 	CONSTANT VARCHAR2(64)	:= 'OSAG_IP.num2ip(): ';
    BEGIN
        if p_number is null or p_number < 0 then
          return null;
        end if;
        v_byte := TRUNC(p_number/16777216);
        IF (v_byte > 255) THEN
            plog.debug(c_prefix||'invalid byte 1 in ip address: '||v_byte);
            RETURn NULL;
        END IF;
        v_reminder := p_number - v_byte * 16777216;
        v_result := TO_CHAR(v_byte);

        v_byte := TRUNC(v_reminder/65536);
        IF (v_byte > 255) THEN
            plog.debug(c_prefix||'invalid byte 2 in ip address: '||v_byte);
            RETURn NULL;
        END IF;
        v_reminder := v_reminder - v_byte * 65536;
        v_result := v_result || '.' || TO_CHAR(v_byte);

        v_byte := TRUNC(v_reminder/256);
        IF (v_byte > 255) THEN
            plog.debug(c_prefix||'invalid byte 3 in ip address: '||v_byte);
            RETURn NULL;
        END IF;
        v_reminder := v_reminder - v_byte * 256;
        v_result := v_result || '.' || TO_CHAR(v_byte) || '.' || v_reminder;
        RETURN v_result;
    END;


    -- expands :: in an ipv6 canonical address to groups of zero
    -- returns the IP with the full set of 8 16-bit groups separated by single colons
    function ipv6pad0(p_ip varchar2) return varchar2 DETERMINISTIC
      is
      v_colons_pos integer;
      v_groups integer;
      v_pad varchar2(64);
      v_res varchar2(64);
    begin
      v_colons_pos := instr(p_ip, '::');
      if v_colons_pos = 0 then
        return p_ip;
      end if;
      if p_ip = '::' then
        return '0:0:0:0:0:0:0:0';
      end if;

      -- number of colons in the IP equals the number of 16 bit groups present
      v_groups := length(p_ip) - nvl(length(replace(p_ip, ':', '')), 0);
      
      -- except if :: is at the beginning or at the end
      if v_colons_pos = 1 or v_colons_pos = length(p_ip)-1 then
        v_groups := v_groups - 1;
      end if;
      
      if v_groups >= 8 then
        -- already complete, for example 1:1:1:1::1:1:1:1
        -- we handle this case although this syntax is invalid, because
        -- :: must indicate at least one all-zero group according to RFC 5952
        return replace(p_ip, '::', ':');
      end if;

      -- the padding like :0:0:0:
      v_pad := LPAD(':0', 2*(8-v_groups), ':0') ||':';
      v_res := replace(p_ip, '::', v_pad);

      -- remove extra : from begin/end
      if v_res like ':%' then
        v_res := substr(v_res, 2);
      end if;
      if v_res like '%:' then
        v_res := substr(v_res, 1, length(v_res)-1);
      end if;
      return v_res;
    end;

    function ipv6left(p_ip varchar2) return integer DETERMINISTIC
      is
      v_ip varchar2(64);
      v_beg integer;
      v_end integer;
      v_grp varchar2(64);
      v_left integer;
    begin
      v_ip := ipv6pad0(p_ip);
      v_left := 0;
      v_end := 0;

      -- 4 hex groups of 1-4 digits (16 bits)
      for v_i in 1..4 loop
          v_beg := v_end+1;
          v_end := instr(v_ip, ':', v_beg);
          v_grp := substr(v_ip, v_beg, v_end-v_beg);
          -- shift left by 16 bits
          v_left := v_left * 65536;
          v_left := v_left + to_number(v_grp, 'xxxx');
        end loop;

      return v_left;
    end;

    function ipv6right(p_ip varchar2) return integer DETERMINISTIC
      is
      v_ip varchar2(64);
      v_beg integer;
      v_end integer;
      v_grp varchar2(64);
      v_right integer;
    begin
      v_ip := ipv6pad0(p_ip);
      v_right := 0;
      v_end := instr(v_ip, ':', 1, 4);

      -- 4 hex groups of 1-4 digits (16 bits)
      for v_i in 1..4 loop
          v_beg := v_end+1;
          v_end := instr(v_ip, ':', v_beg);
          if v_end = 0 then
            v_end := length(v_ip)+1;
          end if;
          v_grp := substr(v_ip, v_beg, v_end-v_beg);
          -- shift left by 16 bits
          v_right := v_right * 65536;
          v_right := v_right + to_number(v_grp, 'xxxx');
        end loop;

      return v_right;
    end;

    -- collapses the longest 0:0: range with ::
    function ipv6shorten(p_ip varchar2) return varchar2 deterministic
      is
      v_start integer;
      v_end integer;
      v_j integer;
      v_len integer;
      v_ip varchar2(64);
      v_res varchar2(64);
    begin
      v_start := 255;
      v_end := 255;
      v_ip := p_ip || ':'; -- adding trailing colon simplifies processing below
      for v_i in 1..(length(v_ip) - 1) loop
          -- ensure v_i is aligned to a colon
          if substr(v_ip, v_i, 1) != ':' then
            continue;
          end if;
          v_j := v_i + 1;
          while v_j < length(v_ip) and (substr(v_ip, v_j, 1) = '0' or substr(v_ip, v_j, 1) = ':') loop
              v_j := v_j + 1;
            end loop;
          -- ensure v_j is aligned to a colon
          while v_j >= v_i and substr(v_ip, v_j, 1) != ':' loop
              v_j := v_j - 1;
            end loop;
          v_len := v_j - v_i;
          if v_len > 3 and v_len > (v_end - v_start) then
            v_start := v_i;
            v_end := v_j;
          end if;
        end loop;

      v_res := v_ip;
      if (v_end - v_start) > 0 then
        v_res := substr(v_ip, 1, v_start) || substr(v_ip, v_end);
      end if;

      -- remove trailing extra colon
      if v_res like '%:' and v_res not like '%::' then
        v_res := substr(v_res, 1, length(v_res)-1);
      end if;

      -- remove leading 0 from '0::...'
      if v_res like '0::%' then
        v_res := substr(v_res, 2);
      end if;

      return v_res;
    end;

    function num2ipv6(p_left integer, p_right integer) return varchar2 deterministic
      is
      v_n integer;
      v_grp integer;
      v_res varchar2(64);
    begin
      v_res := '';

      v_n := p_right;
      for v_i in 1..4 loop
          v_grp := v_n mod 65536;
          v_n := (v_n - v_grp) / 65536;
          v_res := trim(to_char(v_grp, 'xxxx')) ||':'|| v_res;
        end loop;

      v_n := p_left;
      for v_i in 1..4 loop
          v_grp := v_n mod 65536;
          v_n := (v_n - v_grp) / 65536;
          v_res := trim(to_char(v_grp, 'xxxx')) ||':'|| v_res;
        end loop;

      -- this left us with an extra colon at the end
      v_res := substr(v_res, 1, length(v_res)-1);
      v_res := ipv6shorten(v_res);
      return v_res;
    end;
END OSAG_ip;
/
