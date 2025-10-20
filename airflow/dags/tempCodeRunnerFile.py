#!/usr/bin/env python3
"""
Standalone ETL Pipeline for PT XYZ Data Warehouse
This script runs the complete ETL pipeline without Airflow dependencies.
It assumes the database schema has been created by init-scripts.
"""
import os
import time
import logging
import pandas as pd
import pymssql

# Configure logging to file and console
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('etl_execution.log'),
        logging.StreamHandler()
    ]
)

def _get_env(name: str, default: str | None = None, required: bool = False) -> str | None:
    value = os.getenv(name, default)
    if required and (value is None or str(value).strip() == ""):
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def get_sql_connection(db_override: str | None = None, attempts: int = 5, delay_seconds: int = 5, autocommit: bool = False):
    """Establishes and returns a SQL Server connection with retries.

    Connection params can be configured via env vars:
    - MSSQL_HOST (default: sqlserver)
    - MSSQL_PORT (default: 1433)
    - MSSQL_USER (default: sa)
    - MSSQL_SA_PASSWORD (required)
    - MSSQL_DB (default: PTXYZ_DataWarehouse)
    """
    host = _get_env('MSSQL_HOST', 'sqlserver')
    port = int(_get_env('MSSQL_PORT', '1433'))
    user = _get_env('MSSQL_USER', 'sa')
    password = _get_env('MSSQL_SA_PASSWORD', required=True)
    database = db_override or _get_env('MSSQL_DB', 'PTXYZ_DataWarehouse')

    last_err = None
    for attempt in range(1, attempts + 1):
        try:
            conn = pymssql.connect(
                server=host,
                port=port,
                user=user,
                password=password,
                database=database,
                timeout=30,
                login_timeout=30,
                autocommit=autocommit,
            )
            logging.info(f"Connected to SQL Server '{host}:{port}' (db='{database}') on attempt {attempt}.")
            return conn
        except Exception as e:
            last_err = e
            logging.warning(f"Connection attempt {attempt} failed: {e}")
            if attempt < attempts:
                time.sleep(delay_seconds)
    logging.error(f"Error connecting to SQL Server after {attempts} attempts: {last_err}")
    raise last_err


def ensure_database_exists():
    """Ensure target database exists by connecting to 'master' and creating it if missing."""
    target_db = _get_env('MSSQL_DB', 'PTXYZ_DataWarehouse')
    # Connect to master
    conn = get_sql_connection(db_override='master', autocommit=True)
    try:
        cur = conn.cursor()
        # CREATE DATABASE cannot run inside a transaction; autocommit connection is used.
        cur.execute(f"IF DB_ID(N'{target_db}') IS NULL CREATE DATABASE [{target_db}];")
        # No commit when autocommit=True
        logging.info(f"Database ensured: {target_db}")
    finally:
        conn.close()


def ensure_staging_schema_and_tables():
    """Ensure staging schema and required tables exist in target database."""
    conn = get_sql_connection()
    try:
        cur = conn.cursor()
        # Ensure schema
        cur.execute("IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'staging') EXEC('CREATE SCHEMA staging');")

        # Ensure tables (definitions aligned with init-scripts/create-schema.sql)
        cur.execute("""
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
            capacity D