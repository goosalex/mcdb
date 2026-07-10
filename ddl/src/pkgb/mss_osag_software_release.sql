--liquibase formatted sql logicalFilePath:pkgb/mss_osag_software_release.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY MSS.osag_software_release IS

-- ----------------------------------------------------------------------------------------
-- PROCEDURE update_release_installations
-- Purpose: Periodically called to update the MSS.RELEASE_INSTALLATIONS
-- ----------------------------------------------------------------------------------------
    PROCEDURE update_release_installations IS

        v_total_host_count            NUMBER;
        v_release_count               NUMBER;
        v_split_position              NUMBER;
        v_release_number              mss.software_release.release_number%TYPE;
        v_release_cartridge           mss.software_release.release_cartridge%TYPE;
        v_version                     osixinfo.v_firmware.firmware%TYPE;
        v_software_release_id         mss.software_release.id%TYPE;
        v_major_software_release_id   mss.software_release.id%TYPE;
        v_installation_id             mss.release_installation.id%TYPE;
        v_install_count               mss.release_installation.install_count%TYPE;
        v_install_end_date            TIMESTAMP;
        v_complete_date               TIMESTAMP;
        l_now                         TIMESTAMP WITH TIME ZONE := SYSTIMESTAMP;
        c_not_available CONSTANT VARCHAR2(64) := 'n/a';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        DECLARE
            -- define a cursor to loop over all companies
            CURSOR company_cursor IS
                SELECT id
                FROM stop.company company, stop.comp_comptype_ref company_ref
                WHERE company.id = company_ref.company_id AND company_ref.comptype_id = 1;

            company_row company_cursor%ROWTYPE;

        BEGIN
            FOR company_row in company_cursor
                LOOP -- loop over all companies
            -- get the number of OSIX hosts sending heartbeats for this company
                    SELECT count(*) INTO v_total_host_count
                    FROM osixinfo.v_firmware fw, mss.host host
                    WHERE fw.hardware_id = host.hardware_id
                      AND host.service_company_id = company_row.id
                      AND host.operating_system_id = 22
                      AND host.active = 1;

                    DECLARE
                        -- define a cursor to loop over all OSIX versions of this company reported by heartbeats
                        CURSOR version_cursor IS
                            SELECT fw.firmware as version, count(*) AS versionCount
                            FROM osixinfo.v_firmware fw, mss.host host
                            WHERE fw.hardware_id = host.hardware_id
                              AND host.service_company_id = company_row.id
                              AND host.operating_system_id = 22
                              AND host.active = 1
                            GROUP BY fw.firmware;

                        version_row version_cursor%ROWTYPE;

                    BEGIN
                        FOR version_row in version_cursor
                            LOOP -- loop over all versions

                        -- parse release number and cartridge from the version
                                v_split_position := INSTR(version_row.version, '.');
                                v_release_number := SUBSTR(version_row.version, 1, v_split_position-1);
                                v_release_cartridge := SUBSTR(version_row.version, v_split_position+1);

                                -- get software release
                                BEGIN
                                    SELECT id INTO v_software_release_id
                                    FROM mss.software_release
                                    WHERE release_number = v_release_number AND release_cartridge = v_release_cartridge;
                                EXCEPTION
                                    WHEN NO_DATA_FOUND THEN
                                        -- create new software release
                                        SELECT mss.software_release_seq.NextVal INTO v_software_release_id FROM DUAL;

                                        -- find major software release
                                        BEGIN
                                            SELECT id INTO v_major_software_release_id
                                            FROM mss.software_release
                                            WHERE release_number = v_release_number AND major_software_release_id is NULL;
                                        EXCEPTION
                                            WHEN NO_DATA_FOUND THEN
                                                v_major_software_release_id := NULL;
                                        END;

                                        -- store new software release in DB
                                        INSERT INTO mss.software_release(id, major_software_release_id, release_date, release_notes, release_number, release_cartridge, security_update, performance_update,
                                                                         feature_update, published )
                                        VALUES(v_software_release_id, v_major_software_release_id, l_now, c_not_available, v_release_number, v_release_cartridge, 0, 0, 0, 0);
                                END;

                                -- get release installion entry
                                BEGIN
                                    SELECT install_end_date, id, install_count, install_complete_date INTO v_install_end_date, v_installation_id, v_install_count, v_complete_date
                                    FROM mss.release_installation
                                    WHERE software_release_id = v_software_release_id AND company_id = company_row.id FOR UPDATE;

                                EXCEPTION
                                    WHEN NO_DATA_FOUND THEN
                                        -- create release installation entry
                                        SELECT mss.release_installation_seq.NextVal INTO v_installation_id FROM DUAL;
                                        v_install_end_date := NULL;
                                        v_complete_date := NULL;
                                        v_install_count := 0;

                                        INSERT INTO mss.release_installation(id, software_release_id, company_id, install_start_date, install_count)
                                        VALUES (v_installation_id, v_software_release_id, company_row.id, l_now, v_install_count);
                                END;

                                IF (v_install_end_date IS NULL) THEN
                                    -- update install count
                                    UPDATE mss.release_installation
                                    SET install_count = version_row.versionCount
                                    WHERE id = v_installation_id;

                                    IF (v_complete_date IS NULL and v_total_host_count > 0) THEN
                                        -- update install ratio
                                        IF (version_row.versionCount/v_total_host_count >= 0.95) THEN
                                            UPDATE mss.release_installation
                                            SET install_complete_date = l_now
                                            WHERE id = v_installation_id;
                                        END IF;
                                    END IF;
                                END IF;

                            END LOOP; -- end loop over all versions
                    END;

                    DECLARE
                        -- define a cursor to loop over all release installations of this company with no install end date
                        CURSOR release_installation_cursor IS
                            SELECT release_installation.id, software_release.release_number, software_release.release_cartridge
                            FROM mss.release_installation release_installation, mss.software_release software_release
                            WHERE release_installation.company_id = company_row.id
                              AND release_installation.install_end_date is NULL
                              AND release_installation.software_release_id = software_release.id;

                        release_installation_row release_installation_cursor%ROWTYPE;

                    BEGIN
                        FOR release_installation_row in release_installation_cursor
                            LOOP -- loop over all release installations

                        v_version := release_installation_row.release_number || '.' || release_installation_row.release_cartridge;
                        -- get number of heartbeats
                        SELECT count(*) INTO v_release_count
                        FROM  osixinfo.v_firmware fw, mss.host host
                        WHERE fw.hardware_id = host.hardware_id
                          AND host.service_company_id = company_row.id
                          AND host.operating_system_id = 22
                          AND fw.firmware = v_version;

                        IF (v_release_count = 0) THEN
                            UPDATE mss.release_installation
                            SET install_end_date = l_now
                            WHERE id = release_installation_row.id;
                        END IF;

                            END LOOP; -- end loop over all release installations
                    END;


                END LOOP; -- end loop over all companies
        END;

    END update_release_installations;


END osag_software_release;
/
