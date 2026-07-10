--liquibase formatted sql logicalFilePath:pkgb/osag_osag_msg.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY OSAG.OSAG_MSG IS
    -------------------------------------------------------------------------
    PROCEDURE send_mail(p_reply_to VARCHAR2, p_from VARCHAR2, p_mail_from VARCHAR2, p_recipient VARCHAR2, p_subject VARCHAR2,
                        p_body VARCHAR2, p_opt_headers smtp_headers_t := NULL) AS

        S_PREFIX CONSTANT VARCHAR2(64)    := 'OSAG.OSAG_MSG.send_mail(): ';
        S_SMTP_PORT CONSTANT PLS_INTEGER  := 25;
        -- local postfix instance queues and relays to main MTA
        S_SMTP_HOST CONSTANT VARCHAR2(32) := 'localhost';
        CRLF CONSTANT VARCHAR(2)          := CHR(13)||CHR(10);

        mail_conn UTL_SMTP.connection;
        l_rfc822_reply_to VARCHAR2(128);
        l_rfc822_mail_from VARCHAR2(128);
        l_rfc822_recipient VARCHAR2(128);
        l_message VARCHAR2(32767);
        l_opt_header smtp_header_t;
        S_SMTP_HELO VARCHAR2(32);
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        select host_name into S_SMTP_HELO from v$instance;
        l_rfc822_reply_to := REGEXP_REPLACE(p_reply_to, '^([^\<])(.*)([^\>]$)', '<\1\2\3>');
        l_rfc822_recipient := REGEXP_REPLACE(p_recipient, '^([^\<])(.*)([^\>]$)', '<\1\2\3>');
        l_rfc822_mail_from := REGEXP_REPLACE(p_mail_from, '^([^\<])(.*)([^\>]$)', '<\1\2\3>');

        plog.debug(S_PREFIX||'from: '''||nvl(l_rfc822_mail_from,l_rfc822_reply_to)||''', recipient: '''||l_rfc822_recipient||''', subject: '''||p_subject||'''');

        -- Add optional headers to message
        IF ((p_opt_headers IS NOT NULL) AND (p_opt_headers.count > 0)) THEN
            FOR l_row IN p_opt_headers.first .. p_opt_headers.last LOOP
                    l_opt_header := p_opt_headers(l_row);
                    l_message := l_message||l_opt_header.h_name;

                    l_message := l_message||': '||l_opt_header.h_value||CRLF;
                END LOOP;
        END IF;

        l_message := l_message||
                     'Date: '||TO_CHAR(SYSTIMESTAMP, 'Dy, dd Mon YYYY HH24:MI:SS TZHTZM')||CRLF||
                     'From: '||NVL(p_from, p_reply_to)||CRLF||
                     'Reply-To: '||p_reply_to||CRLF||
                     'To: '||l_rfc822_recipient||CRLF||
                     'Subject: '||p_subject||CRLF||CRLF||
                     p_body;

        -- dot-stuffing (DB-316)
        l_message := REGEXP_REPLACE(l_message, '^\.', '..', 1, 0, 'm');

        mail_conn := UTL_SMTP.OPEN_CONNECTION(S_SMTP_HOST, S_SMTP_PORT);
        UTL_SMTP.HELO(mail_conn, S_SMTP_HELO);
        UTL_SMTP.MAIL(mail_conn, NVL(l_rfc822_mail_from,l_rfc822_reply_to));
        UTL_SMTP.RCPT(mail_conn, l_rfc822_recipient);
        UTL_SMTP.DATA(mail_conn, l_message);
        UTL_SMTP.QUIT(mail_conn);

        plog.notice(S_PREFIX||'sent mail from '''||NVL(l_rfc822_mail_from,l_rfc822_reply_to)||''' to '''||l_rfc822_recipient||''' subject: '''||p_subject||'''');

    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line(S_PREFIX||'exception: '||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE||': '||sqlerrm);
            plog.err(S_PREFIX||'send mail to '''||l_rfc822_recipient||''' failed: '||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE||': '||sqlerrm);
            BEGIN
              UTL_SMTP.CLOSE_CONNECTION(mail_conn);
            EXCEPTION
              when others then
                null;
            END;
            RAISE;
    END send_mail;


    -------------------------------------------------------------------------
    PROCEDURE send_sms(p_sms_no VARCHAR2, p_body VARCHAR2) AS

        S_PREFIX CONSTANT VARCHAR2(64)          := 'OSAG.OSAG_MSG.send_sms(): ';

        S_EMAIL_REPLY_TO CONSTANT VARCHAR2(32)  := 'support@open.ch';
        S_SMS_DOMAIN CONSTANT VARCHAR2(32)      := 'mx-sms.open.ch';

        l_sms_no VARCHAR2(32);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        l_sms_no := REPLACE(p_sms_no, ' ', '');
        send_mail(S_EMAIL_REPLY_TO, NULL, NULL, l_sms_no||'@'||S_SMS_DOMAIN, '', p_body);

        plog.notice(S_PREFIX||'sent SMS to '''||l_sms_no||''' subject: '''||p_body||'''');

    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line(S_PREFIX||'exception: '||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE||': '||sqlerrm);
            plog.err(S_PREFIX||'sending SMS to '''||l_sms_no||''' failed: '||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE||': '||sqlerrm);
    END send_sms;
END OSAG_MSG;
/
