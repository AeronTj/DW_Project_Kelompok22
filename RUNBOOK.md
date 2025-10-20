# PT XYZ Data Warehouse – Runbook

Dokumen ini merangkum cara menjalankan, memvalidasi, dan memahami arsitektur Data Warehouse PT XYZ sesuai implementasi pada repository ini. Seluruh isi disusun agar konsisten dengan README.md dan artefak yang sudah kita bangun (Docker Compose, skrip ETL, dan tes validasi).


## 1) Ringkas Arsitektur (Gambar Sederhana)

```
┌─────────────────────────────────────────────────────────────────────┐
│                        PT XYZ Data Warehouse                        │
├─────────────────────────────────────────────┬───────────────────────┤
│              Orchestration (Airflow)        │    Visualization      │
│  - Webserver / Scheduler / Worker (Celery)  │  - Grafana (3000)     │
│  - Metadata: PostgreSQL, Broker: Redis      │  - Superset (8088)    │
├─────────────────────────────────────────────┴───────────┬───────────┤
│                         ETL / ELT                       │           │
│  - Python ETL (standalone_etl.py)                       │           │
│  - Airflow DAGs (opsional)                              │           │
├─────────────────────────────────────────────────────────┴───────────┤
│                         Storage (DW)                                │
│  - SQL Server 2022                                                  │
│  - Schemas: staging, dim, fact                                      │
│  - Star Schema:                                                     │
│      * Dims: DimTime, DimSite, DimEquipment, DimMaterial,           │
│              DimEmployee, DimShift, DimProject, DimAccount          │
│      * Facts: FactEquipmentUsage, FactProduction,                   │
│               FactFinancialTransaction                              │
├─────────────────────────────────────────────────────────────────────┤
│                         Data Sources                                │
│  - CSV pada folder ./data (alat berat, produksi, transaksi)         │
└─────────────────────────────────────────────────────────────────────┘
```

## 2) Pemetaan Langkah README
  - Jalankan semua service
    - `docker compose up -d`
    - Cek status: `docker compose ps`
  - Inisialisasi database & skema DW
    - `docker compose exec airflow-worker python /opt/airflow/dags/init_schema.py`
  - Jalankan ETL
    - `docker compose exec airflow-worker python /opt/airflow/dags/standalone_etl.py`
  - Validasi hasil DW (schema + FK + agregat)
    - PowerShell: `docker compose exec sqlserver /bin/bash -lc '/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d PTXYZ_DataWarehouse -C -N -i /tests/validate.sql'`

## 3) Bukti Hasil Sesuai README

Output validasi (tests/validate.sql) memperlihatkan kesesuaian struktur, integritas, dan agregat dengan README:

```
Schema OK: required tables present:
  dim.DimTime, dim.DimSite, dim.DimEquipment, dim.DimMaterial,
  dim.DimEmployee, dim.DimShift, dim.DimProject, dim.DimAccount,
  fact.FactEquipmentUsage, fact.FactProduction, fact.FactFinancialTransaction

Schema OK: columns and types match for all expected fields (103 checked).

Integrity OK (0 orphans) untuk seluruh FK utama:
  - FactEquipmentUsage: time_key, site_key, equipment_key
  - FactProduction    : time_key, site_key, material_key, employee_key, shift_key
  - FactFinancial     : time_key, site_key, project_key, account_key

Aggregate counts (README vs Actual):
  dim.DimTime                 830 = 830   OK
  dim.DimSite               1,747 = 1,747 OK
  dim.DimEquipment              6 = 6     OK
  dim.DimMaterial               5 = 5     OK
  dim.DimEmployee              10 = 10    OK
  dim.DimShift                  3 = 3     OK
  dim.DimProject               50 = 50    OK
  dim.DimAccount               30 = 30    OK
  fact.FactEquipmentUsage  236,892 = 236,892 OK
  fact.FactProduction        2,261 = 2,261  OK
  fact.FactFinancialTxn    115,901 = 115,901 OK
```

## 4) Kendala dan Solusi Saat Eksekusi

- Login failed (18456) untuk user `sa`
  - Penyebab: password di `.env` tidak sinkron dengan password yang tersimpan di volume SQL Server.
  - Solusi: samakan `MSSQL_SA_PASSWORD` di `.env` dengan password yang aktif (saat ini `DataWarehouse_2025!`), atau hapus volume SQL Server untuk reset total sebelum ganti password.

- Database `PTXYZ_DataWarehouse` belum ada
  - Gejala: koneksi ke DB tertentu gagal walau kredensial benar.
  - Solusi: jalankan `init_schema.py` untuk membuat DB, schemas (dim/fact/staging), dan tabel.

- Tabel `staging.*` tidak ada saat pertama kali ETL
  - Solusi: tambahkan pembuatan schema `staging` dan tabel staging pada `init_schema.py`.

- Service `db_init` gagal eksekusi skrip (CRLF: `/bin/bash^M`)
  - Solusi ringan: gunakan `init_schema.py` untuk init. Solusi permanen: konversi `init-scripts/init-db.sh` ke LF.

- Airflow error: folder plugins tidak ditemukan
  - Solusi:
    - Pastikan ada folder `plugins` di root repo: `mkdir plugins` (tambahkan file kosong `.gitkeep` agar tersimpan di Git jika perlu).
    - Pastikan docker-compose sudah me-mount folder tersebut ke semua service Airflow:
      - `- ./plugins:/opt/airflow/plugins` pada `airflow-webserver`, `airflow-scheduler`, `airflow-worker`.
    - Restart komponen Airflow agar mount terbaca: `docker compose up -d airflow-webserver airflow-scheduler airflow-worker`.
    - Verifikasi di dalam container: `docker compose exec airflow-worker bash -lc 'ls -la /opt/airflow/plugins'`.

## 5) Desain OLTP Source Data

- Sumber berbasis CSV (simulasi OLTP) di `./data`:
  - EquipmentUsage: pemakaian alat, jam operasi/downtime, konsumsi bahan bakar, biaya perawatan per tanggal & lokasi.
  - Production: volume produksi, material, shift, tenaga kerja, biaya per unit, per tanggal & lokasi.
  - FinancialTransaction: anggaran vs realisasi per proyek & akun, termasuk metadata lokasi dan waktu.

## 6) Desain Arsitektur End-to-End Data Warehouse

- Extract: CSV dibaca oleh Python (pandas) → staging (SQL Server).
- Transform: pengisian Dimensi (konversi time_id→DimTime, deduplikasi lokasi/peralatan/material/dll).
- Load: pembuatan fakta dengan join ke dimensi (menggunakan surrogate key di dimensi).
- Validate: skrip SQL `tests/validate.sql` untuk schema/FK/agregat.
- Consume: Grafana, Superset, Metabase, Jupyter terhubung ke SQL Server (DW).

## 7) ETL Diagram

```
CSV (data/) → Extract (pandas) → staging.* → Transform (SQL) → dim.* → fact.* → Validate (tests/validate.sql) → BI Tools
                             ^                                                            |
                             |                                                            v
                    init_schema.py (create DB/schemas/tables)                      Data Quality Checks
```

## 8) Scheduling
- Airflow DAGs disiapkan untuk pemuatan dimensi/fakta (`ptxyz_dimension_loader`, `ptxyz_fact_loader`) dengan `schedule_interval='@daily'`.
- Alasan: batch harian cukup untuk operasi pertambangan; meminimalkan beban sistem dan menjaga konsistensi agregat. Dapat disesuaikan (hourly/weekly) tergantung SLA.
- Executor: Celery (Redis broker + Postgres metadata) untuk skalabilitas worker.

## 9) Desain Dimension Modelling (Star Schema)

- Surrogate keys di semua dimensi (identity `*_key`).
- Dimensi: Time, Site, Equipment, Material, Employee, Shift, Project, Account.
- Fakta: EquipmentUsage, Production, FinancialTransaction.
- Relasi: setiap fakta membawa foreign key ke dimensi terkait melalui `*_key`.
- Keuntungan star schema: query OLAP lebih sederhana, agregasi cepat, kompatibel dengan BI tools.

## 10) Progress Pengerjaan

- Setup Docker Compose dan .env.
- Sinkronisasi kredensial DB di `.env` (hindari hard‑code di kode).
- Tambah inisialisasi DB/Schema/Tabel (init_schema.py) termasuk `staging`.
- Parametrisasi koneksi di semua skrip Python (host/port/user/db/password dari env).
- Tambahkan runner (`scripts/run_all.sh`, `Makefile`) untuk orkestrasi end‑to‑end.
- Tambahkan validasi `tests/validate.sql` (schema, FK, agregat) – lulus sesuai README.

## 11) Insight yang Didapat

- Fakta dan dimensi terisi sesuai ekspektasi README; tidak ada orphan FK (kualitas join baik).
- Volume data (±350K baris total) dapat diproses cepat (lihat README: <5 menit) pada setup Docker lokal.
- Variance budget vs actual (FinancialTransaction) siap digunakan untuk KPI (over/under budget).
- DimTime menyertakan `is_weekend`, memudahkan analisis pola akhir pekan.

## 12) Diskusi Perbandingan dengan Arsitektur Berlawanan

- Star Schema vs 3NF
  - Star: lebih sederhana untuk agregasi dan dashboard, denormalisasi terkontrol, performa OLAP lebih baik.
  - 3NF: integritas tinggi untuk OLTP, namun query analitik kompleks (join banyak), optimasi agregat lebih sulit.
  - Pilihan: DW untuk analitik → star schema (yang kita pakai). Jika kebutuhan transaksi/CRUD tinggi → 3NF.

- ETL vs ELT
  - ETL (sekarang): transformasi utama di aplikasi/SQL sebelum masuk ke fact/dim akhir.
  - ELT: cocok untuk data lake/engine MPP; transformasi berat didelegasikan ke warehouse.
  - Dengan skala data saat ini, pendekatan ETL berbasis SQL Server sudah memadai.


## 13) Perbaikan dan Penambahan yang dilakukan

- Penyelarasan kredensial dan parameter koneksi via `.env` (tidak lagi hard‑code di kode Python) untuk reproducibility lintas mesin.
- Penambahan inisialisasi DW yang idempotent (`init_schema.py`): pastikan DB, schemas (dim/fact/staging), tabel dimensi/fakta/staging ada sebelum ETL.
- Penambahan suite validasi SQL satu perintah (`tests/validate.sql`) untuk membuktikan kepatuhan terhadap README: struktur, integritas FK, dan agregat.
- Orkestrasi end‑to‑end: `Makefile`, `scripts/run_all.sh`, dan `scripts/wait-for-sqlserver.sh` agar proses otomatis dan mudah diulang.
- Konfigurasi Compose diperluas: mount `./tests` ke container SQL Server, serta pass‑through env DB ke container Airflow.

## 14) Dokumentasi Perubahan Hard-coded → Otomatis (Before/After)

### 14.1 `.env`

Before:
```env
# SQL Server Configuration
MSSQL_SA_PASSWORD=DataWarehouse_2025!
ACCEPT_EULA=Y
MSSQL_PID=Developer
```

After:
```env
# SQL Server Configuration
MSSQL_SA_PASSWORD=DataWarehouse_2025!
MSSQL_USER=sa
MSSQL_HOST=sqlserver
MSSQL_PORT=1433
MSSQL_DB=PTXYZ_DataWarehouse
```

### 14.2 `docker-compose.yml` (environment Airflow + mount tests)

Before (contoh potongan `airflow-worker`):
```yaml
environment:
  - AIRFLOW_UID=${AIRFLOW_UID:-50000}
  - AIRFLOW__CORE__EXECUTOR=CeleryExecutor
  # ...
  - MSSQL_HOST=sqlserver
  - MSSQL_SA_PASSWORD=${MSSQL_SA_PASSWORD:-PTXYZSecure123!}
```

After:
```yaml
environment:
  - AIRFLOW_UID=${AIRFLOW_UID:-50000}
  - AIRFLOW__CORE__EXECUTOR=CeleryExecutor
  # ...
  - MSSQL_HOST=${MSSQL_HOST:-sqlserver}
  - MSSQL_PORT=${MSSQL_PORT:-1433}
  - MSSQL_USER=${MSSQL_USER:-sa}
  - MSSQL_DB=${MSSQL_DB:-PTXYZ_DataWarehouse}
  - MSSQL_SA_PASSWORD=${MSSQL_SA_PASSWORD:-PTXYZSecure123!}
```

Tambahan mount tests ke SQL Server:
```yaml
services:
  sqlserver:
    # ...
    volumes:
      - sqlserver_data:/var/opt/mssql
      - ./data:/data
      - ./init-scripts:/init-scripts
      - ./tests:/tests   
      - ./misi3:/scripts
```

### 14.3 `airflow/dags/standalone_etl.py` (koneksi DB)

Before:
```python
db_server = os.environ.get('MSSQL_HOST') or os.environ.get('DB_SERVER') or default_host
db_password = os.environ.get('MSSQL_SA_PASSWORD') or os.environ.get('SA_PASSWORD') or 'PTXYZSecure123!'
conn = pymssql.connect(
    server=db_server,
    port=1433,
    database='PTXYZ_DataWarehouse',
    user='sa',
    password=db_password,
    timeout=30
)
```

After:
```python
db_server = os.environ.get('MSSQL_HOST') or os.environ.get('DB_SERVER') or default_host
db_port = int(os.environ.get('MSSQL_PORT', '1433'))
db_user = os.environ.get('MSSQL_USER', 'sa')
db_name = os.environ.get('MSSQL_DB', 'PTXYZ_DataWarehouse')
db_password = os.environ.get('MSSQL_SA_PASSWORD') or os.environ.get('SA_PASSWORD')
if not db_password:
    raise ValueError('MSSQL_SA_PASSWORD/SA_PASSWORD is not set')
conn = pymssql.connect(
    server=db_server,
    port=db_port,
    database=db_name,
    user=db_user,
    password=db_password,
    timeout=30
)
```

### 14.4 `airflow/dags/init_schema.py`

Before (koneksi & default password hard‑code):
```python
password = os.getenv('MSSQL_SA_PASSWORD') or os.getenv('SA_PASSWORD') or 'PTXYZSecure123!'
return pymssql.connect(
    server=server,
    port=1433,
    user='sa',
    password=password,
    database=database or 'master',
    timeout=30,
    login_timeout=30,
    autocommit=autocommit,
)
```

After (parametrisasi host/port/user/db/password):
```python
password = os.getenv('MSSQL_SA_PASSWORD') or os.getenv('SA_PASSWORD')
if not password:
    raise ValueError('MSSQL_SA_PASSWORD/SA_PASSWORD is not set')
user = os.getenv('MSSQL_USER', 'sa')
port = int(os.getenv('MSSQL_PORT', '1433'))
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
```

Penambahan fungsional: pastikan `staging` schema & tabel ada (idempotent) selain `dim`/`fact`.

### 14.5 `airflow/dags/test_connection.py`

Before:
```python
db_password = os.getenv('MSSQL_SA_PASSWORD')
conn = pymssql.connect(
    server='sqlserver',
    port=1433,
    user='sa',
    password=db_password,
    database='PTXYZ_DataWarehouse',
    timeout=10,
    login_timeout=10
)
```

After:
```python
db_password = os.getenv('MSSQL_SA_PASSWORD') or os.getenv('SA_PASSWORD')
db_host = os.getenv('MSSQL_HOST', 'sqlserver')
db_port = int(os.getenv('MSSQL_PORT', '1433'))
db_user = os.getenv('MSSQL_USER', 'sa')
db_name = os.getenv('MSSQL_DB', 'PTXYZ_DataWarehouse')
conn = pymssql.connect(
    server=db_host,
    port=db_port,
    user=db_user,
    password=db_password,
    database=db_name,
    timeout=10,
    login_timeout=10
)
```

### 14.6 `airflow/dags/ptxyz_dimension_loader.py` & `ptxyz_fact_loader.py`

Before:
```python
sql_password = os.getenv('MSSQL_SA_PASSWORD', 'PTXYZSecure123!')
return pymssql.connect(
    server='ptxyz_sqlserver',
    port=1433,
    database='PTXYZ_DataWarehouse',
    user='sa',
    password=sql_password,
    timeout=30
)
```

After:
```python
sql_password = os.getenv('MSSQL_SA_PASSWORD') or os.getenv('SA_PASSWORD')
server = os.getenv('MSSQL_HOST', 'sqlserver')
port = int(os.getenv('MSSQL_PORT', '1433'))
database = os.getenv('MSSQL_DB', 'PTXYZ_DataWarehouse')
user = os.getenv('MSSQL_USER', 'sa')
return pymssql.connect(
    server=server,
    port=port,
    database=database,
    user=user,
    password=sql_password,
    timeout=30
)
```

### 14.7 Validasi Otomatis (`tests/validate.sql`)

- Tambahan script untuk:
  - Verifikasi schema/tabel/kolom/tipe utama.
  - Cek orphan FK (0 orphan = OK) untuk semua fakta.
  - Cocokkan agregat dengan README (counts dim & fact).
- Output positif sekarang merinci “Schema OK”, “Integrity OK”, dan matriks expected vs actual.

## 15) File Ditambahkan / Diedit

- Ditambahkan:
  - `tests/validate.sql`
  - `scripts/wait-for-sqlserver.sh`
  - `scripts/run_all.sh`
  - `Makefile`
  - `runbook.md`

- Diedit:
  - `.env` (tambah MSSQL_USER/HOST/PORT/DB)
  - `docker-compose.yml` (pass‑through env DB; mount ./tests)
  - `airflow/dags/standalone_etl.py` (parametrisasi koneksi)
  - `airflow/dags/init_schema.py` (parametrisasi + ensure staging)
  - `airflow/dags/test_connection.py` (parametrisasi koneksi)
  - `airflow/dags/ptxyz_dimension_loader.py` (parametrisasi koneksi)
  - `airflow/dags/ptxyz_fact_loader.py` (parametrisasi koneksi)

## 16) Catatan Operasional & Keamanan

- Password SA mengikuti volume SQL Server. Mengganti `MSSQL_SA_PASSWORD` di `.env` tanpa reset volume akan menyebabkan “Login failed”.
- Untuk reset password dari nol: `docker compose down` → `docker volume rm ptxyz-dw_sqlserver_data` → update `.env` → `docker compose up -d` → jalankan `init_schema.py`.
- Simpan `.env` di luar Git untuk lingkungan produksi, atau gunakan Docker secrets/variable injection CI/CD.


## 17) Shutdown dan Start Ulang (Aman)

- Shutdown:
  - Hentikan service: `docker compose stop` (data aman), atau `docker compose down` (hapus containers, simpan volumes).
  - Hindari `docker compose down -v` kecuali ingin hapus semua data DW.

- Start ulang:
  - `docker compose up -d`
  - Pastikan password di `.env` sama dengan yang tersimpan di volume SQL Server.
  - (Opsional) `bash scripts/wait-for-sqlserver.sh`
  - Validasi koneksi: `docker compose exec airflow-worker python /opt/airflow/dags/test_connection.py`

---

Referensi file penting:
- Docker Compose: `docker-compose.yml`
- Variabel environment: `.env`
- Runner: `scripts/run_all.sh`, `Makefile`
- Inisialisasi DB/Schema: `airflow/dags/init_schema.py`
- ETL: `airflow/dags/standalone_etl.py`
- Validasi DW: `tests/validate.sql`