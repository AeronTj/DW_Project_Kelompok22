#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)
cd "$ROOT_DIR"

if [ ! -f .env ]; then
  echo "ERROR: .env not found. Copy .env.example to .env and configure it." >&2
  exit 1
fi

echo "Bringing up services..."
docker compose up -d

echo "Waiting for SQL Server..."
MSSQL_SA_PASSWORD=$(grep -E '^MSSQL_SA_PASSWORD=' .env | sed 's/^MSSQL_SA_PASSWORD=//') \
 SQLSERVER_CONTAINER=ptxyz_sqlserver \
 bash scripts/wait-for-sqlserver.sh

echo "Initializing database schemas..."
docker compose exec airflow-worker python /opt/airflow/dags/init_schema.py

echo "Running ETL pipeline..."
docker compose exec airflow-worker python /opt/airflow/dags/standalone_etl.py

echo "Running validation suite..."
docker compose exec sqlserver /bin/bash -lc \
  "/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P '$MSSQL_SA_PASSWORD' -d PTXYZ_DataWarehouse -C -N -i /tests/validate.sql"

echo "All done."

