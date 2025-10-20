#!/usr/bin/env python3
"""
Initialize PTXYZ Data Warehouse schemas (dim, fact) and tables if missing.
This is a one-off helper to fix "Invalid object name 'dim.*'" without
changing the core ETL code. Run inside Airflow container:

  docker compose exec airflow-worker python /opt/airflow/dags/init_schema.py

"""
import os
import logging
import pymssql

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)


def _default_sql_host() -> str:
    try:
        if os.path.exists('/.dockerenv') or os.getenv('AIRFLOW_HOME'):
            return 'sqlserver'
    except Exception:
        pass
    return 'localhost'


def get_conn(database: str | None = None, autocommit: bool = False) -> pymssql.Connection:
    server = os.getenv('MSSQL_HOST') or os.getenv('DB_SERVER') or _default_sql_host()
    password = os.getenv('MSSQL_SA_PASSWORD') or os.getenv('SA_PASSWORD')
    if not password:
        raise ValueError('MSSQL_SA_PASSWORD/SA_PASSWORD is not set')
    user = os.getenv('MSSQL_USER', 'sa')
    port = int(os.getenv('MSSQL_PORT', '1433'))
    logging.info(f"Connecting to SQL Server at {server} (db={database or 'master'}) ...")
    return pymssql.connect(
        server=server,
        port=port,
        user=user,
        password=password,
        database=database or 'master',
        timeout=30,
        login_timeout=30,
        autocommit=autocommit,
    )


def ensure_database(db_name: str | None = None) -> None:
    if not db_name:
        db_name = os.getenv('MSSQL_DB', 'PTXYZ_DataWarehouse')
    conn = get_conn('master', autocommit=True)
    try:
        cur = conn.cursor()
        cur.execute(f"IF DB_ID(N'{db_name}') IS NULL CREATE DATABASE [{db_name}];")
        logging.info(f"Database ensured: {db_name}")
    finally:
        conn.close()


def ensure_dim_fact_objects(db_name: str | None = None) -> None:
    if not db_name:
        db_name = os.getenv('MSSQL_DB', 'PTXYZ_DataWarehouse')
    conn = get_conn(db_name)
    try:
        cur = conn.cursor()
        # Schemas
        cur.execute("IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name='dim') EXEC('CREATE SCHEMA dim');")
        cur.execute("IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name='fact') EXEC('CREATE SCHEMA fact');")
        cur.execute("IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name='staging') EXEC('CREATE SCHEMA staging');")

        # Dimensions
        cur.execute(
            """
            IF OBJECT_ID('dim.DimTime','U') IS NULL
            CREATE TABLE dim.DimTime (
                time_key INT IDENTITY(1,1) PRIMARY KEY,
                time_id INT NOT NULL,
                date DATE NOT NULL,
                day_of_month INT NOT NULL,
                day_name VARCHAR(20) NOT NULL,
                month INT NOT NULL,
                month_name VARCHAR(20) NOT NULL,
                quarter INT NOT NULL,
                year INT NOT NULL,
                is_weekend BIT NOT NULL,
                created_at DATETIME2 DEFAULT GETDATE(),
                created_by VARCHAR(50) DEFAULT 'System'
            );
            """
        )
        cur.execute(
            """
            IF OBJECT_ID('dim.DimSite','U') IS NULL
            CREATE TABLE dim.DimSite (
                site_key INT IDENTITY(1,1) PRIMARY KEY,
                site_id INT NOT NULL,
                site_name VARCHAR(100) NOT NULL,
                region VARCHAR(50) NOT NULL,
                latitude DECIMAL(10,8),
                longitude DECIMAL(11,8),
                created_at DATETIME2 DEFAULT GETDATE(),
                created_by VARCHAR(50) DEFAULT 'System'
            );
            """
        )
        cur.execute(
            """
            IF OBJECT_ID('dim.DimEquipment','U') IS NULL
            CREATE TABLE dim.DimEquipment (
                equipment_key INT IDENTITY(1,1) PRIMARY KEY,
                equipment_name VARCHAR(100) NOT NULL,
                equipment_type VARCHAR(50) NOT NULL,
                manufacture VARCHAR(50),
                model VARCHAR(50),
                capacity DECIMAL(10,2),
                purchase_date DATE,
                created_at DATETIME2 DEFAULT GETDATE(),
                created_by VARCHAR(50) DEFAULT 'System'
            );
            """
        )
        cur.execute(
            """
            IF OBJECT_ID('dim.DimMaterial','U') IS NULL
            CREATE TABLE dim.DimMaterial (
                material_key INT IDENTITY(1,1) PRIMARY KEY,
                material_id INT NOT NULL,
                material_name VARCHAR(100) NOT NULL,
                material_type VARCHAR(50) NOT NULL,
                unit_of_measure VARCHAR(20) NOT NULL,
                created_at DATETIME2 DEFAULT GETDATE(),
                created_by VARCHAR(50) DEFAULT 'System'
            );
            """
        )
        cur.execute(
            """
            IF OBJECT_ID('dim.DimEmployee','U') IS NULL
            CREATE TABLE dim.DimEmployee (
                employee_key INT IDENTITY(1,1) PRIMARY KEY,
                employee_id INT NOT NULL,
                employee_name VARCHAR(100) NOT NULL,
                position VARCHAR(50),
                department VARCHAR(50),
                status VARCHAR(20),
                hire_date DATE,
                created_at DATETIME2 DEFAULT GETDATE(),
                created_by VARCHAR(50) DEFAULT 'System'
            );
            """
        )
        cur.execute(
            """
            IF OBJECT_ID('dim.DimShift','U') IS NULL
            CREATE TABLE dim.DimShift (
                shift_key INT IDENTITY(1,1) PRIMARY KEY,
                shift_id INT NOT NULL,
                shift_name VARCHAR(50) NOT NULL,
                start_time TIME NOT NULL,
                end_time TIME NOT NULL,
                created_at DATETIME2 DEFAULT GETDATE(),
                created_by VARCHAR(50) DEFAULT 'System'
            );
            """
        )
        cur.execute(
            """
            IF OBJECT_ID('dim.DimProject','U') IS NULL
            CREATE TABLE dim.DimProject (
                project_key INT IDENTITY(1,1) PRIMARY KEY,
                project_id INT NOT NULL,
                project_name VARCHAR(100) NOT NULL,
                project_manager VARCHAR(100),
                status VARCHAR(20),
                start_date DATE,
                end_date DATE,
                created_at DATETIME2 DEFAULT GETDATE(),
                created_by VARCHAR(50) DEFAULT 'System'
            );
            """
        )
        cur.execute(
            """
            IF OBJECT_ID('dim.DimAccount','U') IS NULL
            CREATE TABLE dim.DimAccount (
                account_key INT IDENTITY(1,1) PRIMARY KEY,
                account_id INT NOT NULL,
                account_name VARCHAR(100) NOT NULL,
                account_type VARCHAR(50),
                budget_category VARCHAR(50),
                created_at DATETIME2 DEFAULT GETDATE(),
                created_by VARCHAR(50) DEFAULT 'System'
            );
            """
        )

        # Facts
        cur.execute(
            """
            IF OBJECT_ID('fact.FactEquipmentUsage','U') IS NULL
            CREATE TABLE fact.FactEquipmentUsage (
                usage_key INT IDENTITY(1,1) PRIMARY KEY,
                equipment_usage_id INT NOT NULL,
                time_key INT NOT NULL,
                site_key INT NOT NULL,
                equipment_key INT NOT NULL,
                operating_hours DECIMAL(8,2),
                downtime_hours DECIMAL(8,2),
                fuel_consumption DECIMAL(10,2),
                maintenance_cost DECIMAL(12,2),
                created_at DATETIME2 DEFAULT GETDATE(),
                created_by VARCHAR(50) DEFAULT 'ETL'
            );
            """
        )
        cur.execute(
            """
            IF OBJECT_ID('fact.FactProduction','U') IS NULL
            CREATE TABLE fact.FactProduction (
                production_key INT IDENTITY(1,1) PRIMARY KEY,
                production_id INT NOT NULL,
                time_key INT NOT NULL,
                site_key INT NOT NULL,
                material_key INT NOT NULL,
                employee_key INT NOT NULL,
                shift_key INT NOT NULL,
                produced_volume DECIMAL(12,2),
                unit_cost DECIMAL(10,2),
                material_quantity DECIMAL(12,2),
                created_at DATETIME2 DEFAULT GETDATE(),
                created_by VARCHAR(50) DEFAULT 'ETL'
            );
            """
        )
        cur.execute(
            """
            IF OBJECT_ID('fact.FactFinancialTransaction','U') IS NULL
            CREATE TABLE fact.FactFinancialTransaction (
                transaction_key INT IDENTITY(1,1) PRIMARY KEY,
                transaction_id INT NOT NULL,
                time_key INT NOT NULL,
                site_key INT NOT NULL,
                project_key INT NOT NULL,
                account_key INT NOT NULL,
                budgeted_cost DECIMAL(12,2),
                actual_cost DECIMAL(12,2),
                variance_status VARCHAR(20),
                account_cost DECIMAL(12,2),
                created_at DATETIME2 DEFAULT GETDATE(),
                created_by VARCHAR(50) DEFAULT 'ETL'
            );
            """
        )

        # Staging tables (ensure exist for ETL loads)
        cur.execute(
            """
            IF OBJECT_ID('staging.EquipmentUsage','U') IS NULL
            CREATE TABLE staging.EquipmentUsage (
                equipment_usage_id INT,
                time_id INT,
                date DATE,
                day INT,
                day_name VARCHAR(20),
                month INT,
                year INT,
                site_name VARCHAR(100),
                region VARCHAR(50),
                latitude DECIMAL(10,8),
                longitude DECIMAL(11,8),
                equipment_name VARCHAR(100),
                equipment_type VARCHAR(50),
                manufacture VARCHAR(50),
                model VARCHAR(50),
                capacity DECIMAL(10,2),
                purchase_date DATE,
                operating_hours DECIMAL(8,2),
                downtime_hours DECIMAL(8,2),
                fuel_consumption DECIMAL(10,2),
                maintenance_cost DECIMAL(12,2),
                created_at DATETIME2,
                created_by VARCHAR(50)
            );
            """
        )
        cur.execute(
            """
            IF OBJECT_ID('staging.Production','U') IS NULL
            CREATE TABLE staging.Production (
                production_id INT,
                time_id INT,
                site_id INT,
                material_id INT,
                employee_id INT,
                shift_id INT,
                produced_volume DECIMAL(12,2),
                unit_cost DECIMAL(10,2),
                date DATE,
                day INT,
                month INT,
                year INT,
                day_name VARCHAR(20),
                site_name VARCHAR(100),
                region VARCHAR(50),
                latitude DECIMAL(10,8),
                longitude DECIMAL(11,8),
                material_name VARCHAR(100),
                material_type VARCHAR(50),
                unit_of_measure VARCHAR(20),
                quantity DECIMAL(12,2),
                employee_name VARCHAR(100),
                position VARCHAR(50),
                department VARCHAR(50),
                status VARCHAR(20),
                hire_date DATE,
                shift_name VARCHAR(50),
                start_time TIME,
                end_time TIME
            );
            """
        )
        cur.execute(
            """
            IF OBJECT_ID('staging.FinancialTransaction','U') IS NULL
            CREATE TABLE staging.FinancialTransaction (
                id INT,
                time_id INT,
                site_id INT,
                project_id INT,
                account_id INT,
                variance VARCHAR(20),
                budgeted_cost DECIMAL(12,2),
                actual_cost DECIMAL(12,2),
                created_at DATETIME2,
                created_by VARCHAR(50),
                date DATE,
                day INT,
                day_name VARCHAR(20),
                month INT,
                year INT,
                site_name VARCHAR(100),
                region VARCHAR(50),
                latitude DECIMAL(10,8),
                longitude DECIMAL(11,8),
                project_name VARCHAR(100),
                project_manager VARCHAR(100),
                status VARCHAR(20),
                start_date DATE,
                end_date DATE,
                account_name VARCHAR(100),
                account_type VARCHAR(50),
                budget_category VARCHAR(50),
                cost DECIMAL(12,2)
            );
            """
        )

        conn.commit()
        logging.info("dim/fact schemas and tables ensured.")
    finally:
        conn.close()


def main():
    ensure_database('PTXYZ_DataWarehouse')
    ensure_dim_fact_objects('PTXYZ_DataWarehouse')
    logging.info("Initialization complete. You can rerun the ETL now.")


if __name__ == '__main__':
    main()
