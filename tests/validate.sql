/*
 PT XYZ Data Warehouse – Validation Suite

 Validates three aspects:
 1) Schema: table/column/type compliance with project DDL (README + DDL scripts)
 2) Integrity: no orphan foreign keys in fact tables
 3) Aggregates: row counts match README examples

Run (PowerShell):
  docker compose exec sqlserver /bin/bash -lc '/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d PTXYZ_DataWarehouse -C -N -i /tests/validate.sql'

Run (Linux/macOS bash):
  docker compose exec sqlserver /bin/bash -lc \
    "/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P \"$MSSQL_SA_PASSWORD\" -d PTXYZ_DataWarehouse -C -N -i /tests/validate.sql"
*/

SET NOCOUNT ON;

IF DB_ID(N'PTXYZ_DataWarehouse') IS NULL
BEGIN
    RAISERROR('Database PTXYZ_DataWarehouse not found.', 16, 1);
    RETURN;
END

USE PTXYZ_DataWarehouse;

DECLARE @fail INT = 0;
PRINT '--- PT XYZ DW Validation Started ---';

/* 1) Schema existence: schemas and tables */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name='dim') BEGIN PRINT 'Missing schema: dim'; SET @fail += 1; END;
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name='fact') BEGIN PRINT 'Missing schema: fact'; SET @fail += 1; END;
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name='staging') BEGIN PRINT 'Missing schema: staging'; SET @fail += 1; END;

DECLARE @tables TABLE (schema_name sysname, table_name sysname);
INSERT INTO @tables(schema_name, table_name) VALUES
 ('dim','DimTime'),('dim','DimSite'),('dim','DimEquipment'),('dim','DimMaterial'),('dim','DimEmployee'),('dim','DimShift'),('dim','DimProject'),('dim','DimAccount'),
 ('fact','FactEquipmentUsage'),('fact','FactProduction'),('fact','FactFinancialTransaction');

;WITH t AS (
    SELECT schema_name, table_name
    FROM @tables
)
SELECT 'Missing table: ' + t.schema_name + '.' + t.table_name AS issue
INTO #missing_tables
FROM t
LEFT JOIN sys.tables st ON st.name = t.table_name
LEFT JOIN sys.schemas ss ON ss.schema_id = st.schema_id AND ss.name = t.schema_name
WHERE st.object_id IS NULL;

IF EXISTS (SELECT 1 FROM #missing_tables)
BEGIN
    SET @fail += (SELECT COUNT(*) FROM #missing_tables);
    PRINT 'Schema issues (missing tables):';
    SELECT issue FROM #missing_tables;
END
ELSE
BEGIN
    PRINT 'Schema OK: required tables present:';
    SELECT schema_name + '.' + table_name AS table_fqn FROM @tables ORDER BY schema_name, table_name;
END
DROP TABLE #missing_tables;

/* 1b) Column/type conformance (core columns used by ETL) */
DECLARE @expected TABLE (
    schema_name sysname,
    table_name  sysname,
    column_name sysname,
    expected_type nvarchar(100)
);

-- DimTime
INSERT INTO @expected VALUES
 ('dim','DimTime','time_key','int'),
 ('dim','DimTime','time_id','int'),
 ('dim','DimTime','date','date'),
 ('dim','DimTime','day_of_month','int'),
 ('dim','DimTime','day_name','varchar(20)'),
 ('dim','DimTime','month','int'),
 ('dim','DimTime','month_name','varchar(20)'),
 ('dim','DimTime','quarter','int'),
 ('dim','DimTime','year','int'),
 ('dim','DimTime','is_weekend','bit'),
 ('dim','DimTime','created_at','datetime2'),
 ('dim','DimTime','created_by','varchar(50)');

-- DimSite
INSERT INTO @expected VALUES
 ('dim','DimSite','site_key','int'),
 ('dim','DimSite','site_id','int'),
 ('dim','DimSite','site_name','varchar(100)'),
 ('dim','DimSite','region','varchar(50)'),
 ('dim','DimSite','latitude','decimal(10,8)'),
 ('dim','DimSite','longitude','decimal(11,8)'),
 ('dim','DimSite','created_at','datetime2'),
 ('dim','DimSite','created_by','varchar(50)');

-- DimEquipment
INSERT INTO @expected VALUES
 ('dim','DimEquipment','equipment_key','int'),
 ('dim','DimEquipment','equipment_name','varchar(100)'),
 ('dim','DimEquipment','equipment_type','varchar(50)'),
 ('dim','DimEquipment','manufacture','varchar(50)'),
 ('dim','DimEquipment','model','varchar(50)'),
 ('dim','DimEquipment','capacity','decimal(10,2)'),
 ('dim','DimEquipment','purchase_date','date'),
 ('dim','DimEquipment','created_at','datetime2'),
 ('dim','DimEquipment','created_by','varchar(50)');

-- DimMaterial
INSERT INTO @expected VALUES
 ('dim','DimMaterial','material_key','int'),
 ('dim','DimMaterial','material_id','int'),
 ('dim','DimMaterial','material_name','varchar(100)'),
 ('dim','DimMaterial','material_type','varchar(50)'),
 ('dim','DimMaterial','unit_of_measure','varchar(20)'),
 ('dim','DimMaterial','created_at','datetime2'),
 ('dim','DimMaterial','created_by','varchar(50)');

-- DimEmployee
INSERT INTO @expected VALUES
 ('dim','DimEmployee','employee_key','int'),
 ('dim','DimEmployee','employee_id','int'),
 ('dim','DimEmployee','employee_name','varchar(100)'),
 ('dim','DimEmployee','position','varchar(50)'),
 ('dim','DimEmployee','department','varchar(50)'),
 ('dim','DimEmployee','status','varchar(20)'),
 ('dim','DimEmployee','hire_date','date'),
 ('dim','DimEmployee','created_at','datetime2'),
 ('dim','DimEmployee','created_by','varchar(50)');

-- DimShift
INSERT INTO @expected VALUES
 ('dim','DimShift','shift_key','int'),
 ('dim','DimShift','shift_id','int'),
 ('dim','DimShift','shift_name','varchar(50)'),
 ('dim','DimShift','start_time','time'),
 ('dim','DimShift','end_time','time'),
 ('dim','DimShift','created_at','datetime2'),
 ('dim','DimShift','created_by','varchar(50)');

-- DimProject
INSERT INTO @expected VALUES
 ('dim','DimProject','project_key','int'),
 ('dim','DimProject','project_id','int'),
 ('dim','DimProject','project_name','varchar(100)'),
 ('dim','DimProject','project_manager','varchar(100)'),
 ('dim','DimProject','status','varchar(20)'),
 ('dim','DimProject','start_date','date'),
 ('dim','DimProject','end_date','date'),
 ('dim','DimProject','created_at','datetime2'),
 ('dim','DimProject','created_by','varchar(50)');

-- DimAccount
INSERT INTO @expected VALUES
 ('dim','DimAccount','account_key','int'),
 ('dim','DimAccount','account_id','int'),
 ('dim','DimAccount','account_name','varchar(100)'),
 ('dim','DimAccount','account_type','varchar(50)'),
 ('dim','DimAccount','budget_category','varchar(50)'),
 ('dim','DimAccount','created_at','datetime2'),
 ('dim','DimAccount','created_by','varchar(50)');

-- FactEquipmentUsage
INSERT INTO @expected VALUES
 ('fact','FactEquipmentUsage','usage_key','int'),
 ('fact','FactEquipmentUsage','equipment_usage_id','int'),
 ('fact','FactEquipmentUsage','time_key','int'),
 ('fact','FactEquipmentUsage','site_key','int'),
 ('fact','FactEquipmentUsage','equipment_key','int'),
 ('fact','FactEquipmentUsage','operating_hours','decimal(8,2)'),
 ('fact','FactEquipmentUsage','downtime_hours','decimal(8,2)'),
 ('fact','FactEquipmentUsage','fuel_consumption','decimal(10,2)'),
 ('fact','FactEquipmentUsage','maintenance_cost','decimal(12,2)'),
 ('fact','FactEquipmentUsage','created_at','datetime2'),
 ('fact','FactEquipmentUsage','created_by','varchar(50)');

-- FactProduction
INSERT INTO @expected VALUES
 ('fact','FactProduction','production_key','int'),
 ('fact','FactProduction','production_id','int'),
 ('fact','FactProduction','time_key','int'),
 ('fact','FactProduction','site_key','int'),
 ('fact','FactProduction','material_key','int'),
 ('fact','FactProduction','employee_key','int'),
 ('fact','FactProduction','shift_key','int'),
 ('fact','FactProduction','produced_volume','decimal(12,2)'),
 ('fact','FactProduction','unit_cost','decimal(10,2)'),
 ('fact','FactProduction','material_quantity','decimal(12,2)'),
 ('fact','FactProduction','created_at','datetime2'),
 ('fact','FactProduction','created_by','varchar(50)');

-- FactFinancialTransaction
INSERT INTO @expected VALUES
 ('fact','FactFinancialTransaction','transaction_key','int'),
 ('fact','FactFinancialTransaction','transaction_id','int'),
 ('fact','FactFinancialTransaction','time_key','int'),
 ('fact','FactFinancialTransaction','site_key','int'),
 ('fact','FactFinancialTransaction','project_key','int'),
 ('fact','FactFinancialTransaction','account_key','int'),
 ('fact','FactFinancialTransaction','budgeted_cost','decimal(12,2)'),
 ('fact','FactFinancialTransaction','actual_cost','decimal(12,2)'),
 ('fact','FactFinancialTransaction','variance_status','varchar(20)'),
 ('fact','FactFinancialTransaction','account_cost','decimal(12,2)'),
 ('fact','FactFinancialTransaction','created_at','datetime2'),
 ('fact','FactFinancialTransaction','created_by','varchar(50)');

;WITH actual AS (
    SELECT ss.name AS schema_name, st.name AS table_name, sc.name AS column_name,
           LOWER(
             CASE 
               WHEN ty.name IN ('decimal','numeric') THEN ty.name + '(' + CAST(sc.precision AS varchar(10)) + ',' + CAST(sc.scale AS varchar(10)) + ')'
               WHEN ty.name IN ('varchar','char','nvarchar','nchar') THEN ty.name + '(' + CAST(CASE WHEN ty.name IN ('nvarchar','nchar') THEN sc.max_length/2 ELSE sc.max_length END AS varchar(10)) + ')'
               ELSE ty.name
             END
           ) AS actual_type
    FROM sys.columns sc
    JOIN sys.types ty ON sc.user_type_id = ty.user_type_id AND ty.is_user_defined = 0
    JOIN sys.tables st ON sc.object_id = st.object_id
    JOIN sys.schemas ss ON st.schema_id = ss.schema_id
    WHERE ss.name IN ('dim','fact')
)
SELECT e.schema_name, e.table_name, e.column_name, e.expected_type, a.actual_type
INTO #col_missing
FROM @expected e
LEFT JOIN actual a
  ON a.schema_name = e.schema_name AND a.table_name = e.table_name AND a.column_name = e.column_name;

-- Missing columns
IF EXISTS (SELECT 1 FROM #col_missing WHERE actual_type IS NULL)
BEGIN
    PRINT 'Schema issues (missing columns):';
    SELECT schema_name + '.' + table_name + '.' + column_name AS column_fqn FROM #col_missing WHERE actual_type IS NULL;
    SET @fail += (SELECT COUNT(*) FROM #col_missing WHERE actual_type IS NULL);
END

-- Type mismatches (present but wrong type family)
IF EXISTS (SELECT 1 FROM #col_missing WHERE actual_type IS NOT NULL AND LOWER(expected_type) <> actual_type)
BEGIN
    PRINT 'Schema issues (type mismatches):';
    SELECT schema_name + '.' + table_name + '.' + column_name AS column_fqn,
           expected_type AS expected,
           actual_type   AS actual
    FROM #col_missing
    WHERE actual_type IS NOT NULL AND LOWER(expected_type) <> actual_type;
    SET @fail += (SELECT COUNT(*) FROM #col_missing WHERE actual_type IS NOT NULL AND LOWER(expected_type) <> actual_type);
END

IF NOT EXISTS (
    SELECT 1 FROM #col_missing 
    WHERE actual_type IS NULL OR (actual_type IS NOT NULL AND LOWER(expected_type) <> actual_type)
)
BEGIN
    DECLARE @col_total INT = (SELECT COUNT(*) FROM @expected);
    PRINT 'Schema OK: columns and types match for all expected fields (' + CAST(@col_total AS varchar(20)) + ' checked).';
END

DROP TABLE #col_missing;

/* 2) Integrity: no orphan FK references from fact tables to dimensions */
DECLARE @cnt INT;

-- FactEquipmentUsage
SELECT @cnt = COUNT(*) FROM fact.FactEquipmentUsage f LEFT JOIN dim.DimTime t ON f.time_key = t.time_key WHERE t.time_key IS NULL;
IF @cnt > 0 BEGIN PRINT 'Orphans: FactEquipmentUsage.time_key -> DimTime: ' + CAST(@cnt AS varchar(20)); SET @fail += 1; END ELSE PRINT 'Integrity OK: FactEquipmentUsage.time_key -> DimTime (0 orphans)';

SELECT @cnt = COUNT(*) FROM fact.FactEquipmentUsage f LEFT JOIN dim.DimSite s ON f.site_key = s.site_key WHERE s.site_key IS NULL;
IF @cnt > 0 BEGIN PRINT 'Orphans: FactEquipmentUsage.site_key -> DimSite: ' + CAST(@cnt AS varchar(20)); SET @fail += 1; END ELSE PRINT 'Integrity OK: FactEquipmentUsage.site_key -> DimSite (0 orphans)';

SELECT @cnt = COUNT(*) FROM fact.FactEquipmentUsage f LEFT JOIN dim.DimEquipment e ON f.equipment_key = e.equipment_key WHERE e.equipment_key IS NULL;
IF @cnt > 0 BEGIN PRINT 'Orphans: FactEquipmentUsage.equipment_key -> DimEquipment: ' + CAST(@cnt AS varchar(20)); SET @fail += 1; END ELSE PRINT 'Integrity OK: FactEquipmentUsage.equipment_key -> DimEquipment (0 orphans)';

-- FactProduction
SELECT @cnt = COUNT(*) FROM fact.FactProduction f LEFT JOIN dim.DimTime t ON f.time_key = t.time_key WHERE t.time_key IS NULL;
IF @cnt > 0 BEGIN PRINT 'Orphans: FactProduction.time_key -> DimTime: ' + CAST(@cnt AS varchar(20)); SET @fail += 1; END ELSE PRINT 'Integrity OK: FactProduction.time_key -> DimTime (0 orphans)';

SELECT @cnt = COUNT(*) FROM fact.FactProduction f LEFT JOIN dim.DimSite s ON f.site_key = s.site_key WHERE s.site_key IS NULL;
IF @cnt > 0 BEGIN PRINT 'Orphans: FactProduction.site_key -> DimSite: ' + CAST(@cnt AS varchar(20)); SET @fail += 1; END ELSE PRINT 'Integrity OK: FactProduction.site_key -> DimSite (0 orphans)';

SELECT @cnt = COUNT(*) FROM fact.FactProduction f LEFT JOIN dim.DimMaterial m ON f.material_key = m.material_key WHERE m.material_key IS NULL;
IF @cnt > 0 BEGIN PRINT 'Orphans: FactProduction.material_key -> DimMaterial: ' + CAST(@cnt AS varchar(20)); SET @fail += 1; END ELSE PRINT 'Integrity OK: FactProduction.material_key -> DimMaterial (0 orphans)';

SELECT @cnt = COUNT(*) FROM fact.FactProduction f LEFT JOIN dim.DimEmployee e ON f.employee_key = e.employee_key WHERE e.employee_key IS NULL;
IF @cnt > 0 BEGIN PRINT 'Orphans: FactProduction.employee_key -> DimEmployee: ' + CAST(@cnt AS varchar(20)); SET @fail += 1; END ELSE PRINT 'Integrity OK: FactProduction.employee_key -> DimEmployee (0 orphans)';

SELECT @cnt = COUNT(*) FROM fact.FactProduction f LEFT JOIN dim.DimShift sh ON f.shift_key = sh.shift_key WHERE sh.shift_key IS NULL;
IF @cnt > 0 BEGIN PRINT 'Orphans: FactProduction.shift_key -> DimShift: ' + CAST(@cnt AS varchar(20)); SET @fail += 1; END ELSE PRINT 'Integrity OK: FactProduction.shift_key -> DimShift (0 orphans)';

-- FactFinancialTransaction
SELECT @cnt = COUNT(*) FROM fact.FactFinancialTransaction f LEFT JOIN dim.DimTime t ON f.time_key = t.time_key WHERE t.time_key IS NULL;
IF @cnt > 0 BEGIN PRINT 'Orphans: FactFinancialTransaction.time_key -> DimTime: ' + CAST(@cnt AS varchar(20)); SET @fail += 1; END ELSE PRINT 'Integrity OK: FactFinancialTransaction.time_key -> DimTime (0 orphans)';

SELECT @cnt = COUNT(*) FROM fact.FactFinancialTransaction f LEFT JOIN dim.DimSite s ON f.site_key = s.site_key WHERE s.site_key IS NULL;
IF @cnt > 0 BEGIN PRINT 'Orphans: FactFinancialTransaction.site_key -> DimSite: ' + CAST(@cnt AS varchar(20)); SET @fail += 1; END ELSE PRINT 'Integrity OK: FactFinancialTransaction.site_key -> DimSite (0 orphans)';

SELECT @cnt = COUNT(*) FROM fact.FactFinancialTransaction f LEFT JOIN dim.DimProject p ON f.project_key = p.project_key WHERE p.project_key IS NULL;
IF @cnt > 0 BEGIN PRINT 'Orphans: FactFinancialTransaction.project_key -> DimProject: ' + CAST(@cnt AS varchar(20)); SET @fail += 1; END ELSE PRINT 'Integrity OK: FactFinancialTransaction.project_key -> DimProject (0 orphans)';

SELECT @cnt = COUNT(*) FROM fact.FactFinancialTransaction f LEFT JOIN dim.DimAccount a ON f.account_key = a.account_key WHERE a.account_key IS NULL;
IF @cnt > 0 BEGIN PRINT 'Orphans: FactFinancialTransaction.account_key -> DimAccount: ' + CAST(@cnt AS varchar(20)); SET @fail += 1; END ELSE PRINT 'Integrity OK: FactFinancialTransaction.account_key -> DimAccount (0 orphans)';

/* 3) Aggregates: match README counts */
DECLARE @expected_counts TABLE (table_fqn sysname, expected_count bigint);
INSERT INTO @expected_counts(table_fqn, expected_count) VALUES
 ('dim.DimTime', 830),
 ('dim.DimSite', 1747),
 ('dim.DimEquipment', 6),
 ('dim.DimMaterial', 5),
 ('dim.DimEmployee', 10),
 ('dim.DimShift', 3),
 ('dim.DimProject', 50),
 ('dim.DimAccount', 30),
 ('fact.FactEquipmentUsage', 236892),
 ('fact.FactProduction', 2261),
 ('fact.FactFinancialTransaction', 115901);

IF OBJECT_ID('tempdb..#actual_counts') IS NOT NULL DROP TABLE #actual_counts;
SELECT * INTO #actual_counts FROM (
  SELECT 'dim.DimTime' AS table_fqn, COUNT(*) AS cnt FROM dim.DimTime
  UNION ALL SELECT 'dim.DimSite', COUNT(*) FROM dim.DimSite
  UNION ALL SELECT 'dim.DimEquipment', COUNT(*) FROM dim.DimEquipment
  UNION ALL SELECT 'dim.DimMaterial', COUNT(*) FROM dim.DimMaterial
  UNION ALL SELECT 'dim.DimEmployee', COUNT(*) FROM dim.DimEmployee
  UNION ALL SELECT 'dim.DimShift', COUNT(*) FROM dim.DimShift
  UNION ALL SELECT 'dim.DimProject', COUNT(*) FROM dim.DimProject
  UNION ALL SELECT 'dim.DimAccount', COUNT(*) FROM dim.DimAccount
  UNION ALL SELECT 'fact.FactEquipmentUsage', COUNT(*) FROM fact.FactEquipmentUsage
  UNION ALL SELECT 'fact.FactProduction', COUNT(*) FROM fact.FactProduction
  UNION ALL SELECT 'fact.FactFinancialTransaction', COUNT(*) FROM fact.FactFinancialTransaction
) a;

SELECT a.table_fqn, e.expected_count, a.cnt AS actual_count,
       CASE WHEN a.cnt = e.expected_count THEN 'OK' ELSE 'MISMATCH' END AS status
FROM #actual_counts a
JOIN @expected_counts e ON e.table_fqn = a.table_fqn
ORDER BY a.table_fqn;

SELECT e.table_fqn, e.expected_count, a.cnt AS actual_count
INTO #count_mismatch
FROM @expected_counts e
JOIN #actual_counts a ON a.table_fqn = e.table_fqn
WHERE a.cnt <> e.expected_count;

IF EXISTS (SELECT 1 FROM #count_mismatch)
BEGIN
    PRINT 'Aggregate mismatches (README vs actual):';
    SELECT table_fqn, expected_count, actual_count FROM #count_mismatch;
    SET @fail += (SELECT COUNT(*) FROM #count_mismatch);
END
DROP TABLE #count_mismatch;

/* Final */
IF (@fail > 0)
BEGIN
    RAISERROR('Validation failed with %d issues.', 16, 1, @fail);
END
ELSE
BEGIN
    PRINT 'All validations passed ✅';
END
