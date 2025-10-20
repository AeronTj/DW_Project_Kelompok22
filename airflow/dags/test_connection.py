# test_connection.py
import os
import pymssql
import sys

print("--- Memulai Tes Koneksi ke SQL Server ---")

try:
    # Ambil password dari environment variable, sama seperti skrip ETL
    db_password = os.getenv('MSSQL_SA_PASSWORD') or os.getenv('SA_PASSWORD')
    db_host = os.getenv('MSSQL_HOST', 'sqlserver')
    db_port = int(os.getenv('MSSQL_PORT', '1433'))
    db_user = os.getenv('MSSQL_USER', 'sa')
    db_name = os.getenv('MSSQL_DB', 'PTXYZ_DataWarehouse')
    
    if not db_password:
        print("ERROR: Environment variable MSSQL_SA_PASSWORD/SA_PASSWORD tidak ditemukan!")
        sys.exit(1)

    print(f"Mencoba terhubung ke '{db_host}:{db_port}' DB '{db_name}' dengan user '{db_user}'...")

    # Buat koneksi
    conn = pymssql.connect(
        server=db_host,
        port=db_port,
        user=db_user,
        password=db_password,
        database=db_name,
        timeout=10,
        login_timeout=10
    )

    cursor = conn.cursor()
    cursor.execute("SELECT @@VERSION")
    version = cursor.fetchone()[0]
    
    print("\n======================================")
    print("✅ KONEKSI BERHASIL!")
    print(f"Versi SQL Server: {version[:30]}...")
    print("======================================")
    
    conn.close()

except Exception as e:
    print("\n======================================")
    print(f"❌ KONEKSI GAGAL!")
    print(f"Error: {e}")
    print("======================================")
    sys.exit(1)
