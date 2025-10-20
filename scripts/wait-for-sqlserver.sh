#!/usr/bin/env bash
set -euo pipefail

PASSWORD=${MSSQL_SA_PASSWORD:?MSSQL_SA_PASSWORD not set}
CONTAINER=${SQLSERVER_CONTAINER:-ptxyz_sqlserver}
TRIES=${TRIES:-60}
SLEEP=${SLEEP:-5}

echo "Waiting for SQL Server in container $CONTAINER ..."
for i in $(seq 1 "$TRIES"); do
  if docker exec "$CONTAINER" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$PASSWORD" -Q "SELECT 1" -C -N >/dev/null 2>&1; then
    echo "SQL Server is ready."
    exit 0
  fi
  echo "Attempt $i/$TRIES..."
  sleep "$SLEEP"
done

echo "SQL Server did not become ready in time" >&2
exit 1

