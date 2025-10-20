#!/usr/bin/env python3
"""
Launcher for the standalone ETL to match the expected invocation:
    python3 standalone_etl.py

It delegates to airflow/dags/standalone_etl.py to run the full pipeline.
"""
import os
import runpy


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    target = os.path.join(here, 'airflow', 'dags', 'standalone_etl.py')
    runpy.run_path(target, run_name='__main__')


if __name__ == '__main__':
    main()

