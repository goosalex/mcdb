# CHANGELOG

## 2.5.2 - 07.08.2026
- Fix missing VPN jdo properties
- export to state ogl:2650

## 2.5.1 - 05.08.2026
- Refresh export to state alg:2603
- SCN 628454616564

## 2.5.0 - 23.03.2026
- update list of schemas
- use changelog-sync-to-tag
- add test case

## 2.4.0 - 21.03.2026
- contains changes until changeset alg:2500
- Migrated most CLOBs to VARCHAR2(32K)

## 2.3.4 - 13.01.2026
- reinstate missing MV log grants

## 2.3.3 - 12.01.2026
- updated REDEFINITION scripts for CLOB to VARCHAR2 migration
- contains changes until changeset alg:2400

## 2.3.2 - 03.12.2025
- no changes

## 2.3.1 - 03.12.2025
- Adds CLOB migration procedures in sy.osag_..
- contains changes until changeset alg:2375
 
## 2.3.0 - 17.11.2025
- contains changes until changeset ogl:2338

## 2.2.2 - 16.11.2025
- Prevent corruption during container build exit

## 2.2.1 - 10.11.2025
- FK constraints have their ON DELETE condition exported correctly now

## 2.2.0 - 10.11.2025
- MAX_STRING_SIZE=EXTENDED (32K MAX) for CLOB transition to VARCHAR2
- contains changes until changeset alg:2323

## 2.1.2 - 01.09.2025
- contains changes until changeset alg:2220
- ca. SCN 10361443897 on DEV

## 2.1.1 - 18.08.2025
- contains changes until changeset ogl:2206
- Repairs export of ON DELETE CASCADE options

## 2.1.0 - 04.08.2025
- contains changes until changeset alg:2200
- Repairs export of constrains, which were erroneously all exported as DEFERRABLE by Liquibase
- Base for first PostgrSql PoC migration of MCDB

## 2.0.4 - 23.05.2025
- simplify build process: add also unit tests to the container
- test cases are now present and no longer just pretended to be present 
- remove a broken, unused make target

## 2.0.3 - 21.05.2025
- fix unit-tests: test packages were not part of the container but marked as present
- add triggers: they were not present in the container but marked as present
- this changelog order is now standard with latest at the top
- CI now builds snapshots

## 2.0.2 - 16.04.2025
- no changes

## 2.0.1 - 11.04.2025
- contains changes until changeset lut:1712
- Fixes 2.0.0, updates all masterdata

## 2.0.0 - 04.04.2025
- contains changes until changeset alg:1702
- based on pure docker and Ora23-Free version.
- Does not work! breaks ORM Layer in OSIXINFO

## 1.1.1 - 19.6.2024
- contains changes until changeset alg:1500

## 1.1.0 - 26.10.2023
- contains changes until changeset alg:1200
- built on Oracle EE 19c
- available as ARM and x86 image
- new artifact name osdb/build_base_ee_arch:19.3.0-amd64 / arm64

## 1.0.4 - 22.6.2023
- contains changes until changeset alg:1104

## 1.0.3 - 22.6.2023
- fix empty changelog from v1.0.2

## 1.0.2 - 20.6.2023
- prevent re-application of past changesets
- contains changes until changeset alg:1100

## 1.0.1 - 07.03.2023
- fix ExposedPorts in image
- contains changes until changeset dmg:1044

## 1.0.0 - 06.03.2023
- contains changes until changeset dmg:1044
- tagged as :latest

## 0.9.3 - 06.03.2023
- database is now flashback enabled
- contains changes until changeset dmg:1044
- first release that is completely built by Buildkite and Kaeter
