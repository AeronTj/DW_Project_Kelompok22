SHELL := /usr/bin/env bash

.PHONY: up wait init etl validate all

up:
	docker compose up -d

wait:
	MSSQL_SA_PASSWORD=$$(grep -E '^MSSQL_SA_PASSWORD=' .env | sed 's/^MSSQL_SA_PASSWORD=//') \
	 SQLSERVER_CONTAINER=ptxyz_sqlserver \
	 bash scripts/wait-for-sqlserver.sh

init:
	docker compose exec airflow-worker python /opt/airflow/dags/init_schema.py

etl:
	docker compose exec airflow-worker python /opt/airflow/dags/standalone_etl.py

validate:
	docker compose exec sqlserver /bin/bash -lc '/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$$MSSQL_SA_PASSWORD" -d PTXYZ_DataWarehouse -C -N -i /tests/validate.sql'

all: up wait init etl validate

