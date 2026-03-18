
### Создаю группу безопасности
yc vpc security-group create otus-sg \
  --network-name default \
  --rule "direction=ingress,protocol=tcp,port=6432,v4-cidrs=212.220.84.197/32,description=allow-6432" \
  --rule "direction=egress,protocol=tcp,port=6432,v4-cidrs=0.0.0.0/0,description=allow-6432"
  
### Создаю managed postgresql в ЯО
### Минимально доступные параметры сейчас следующие: Класс хоста b1.medium (2 vCPU, 50% vCPU rate, 4 ГБ RAM), Intel Broadwell
yc managed-postgresql cluster create \
  --name otus-mp \
  --environment production \
  --postgresql-version 18 \
  --network-name default \
  --resource-preset b1.medium \
  --host zone-id=ru-central1-a,subnet-id=e9b9s2lpljejdl1kp9bq,assign-public-ip=true \
  --disk-type network-ssd \
  --disk-size 10 \
  --user name=otus,password='Pa$$w0rd!' \
  --database name=otusdb,owner=otus \
  --security-group-ids enpgeo4cbg3t23ffktrv

### Для подключения необходим SSL-сертификат. Выпускаю его:
mkdir -p ~/.postgresql && \
wget "https://storage.yandexcloud.net/cloud-certs/CA.pem" \
  --output-document ~/.postgresql/root.crt && \
chmod 0655 ~/.postgresql/root.crt

### Подключение через FQDN:
psql "host=c-${CLUSTER_ID}.rw.mdb.yandexcloud.net \
port=6432 \
sslmode=verify-full \
dbname=otusdb \
user=otus \
target_session_attrs=read-write"
Password for user otus: 
psql (16.13 (Ubuntu 16.13-0ubuntu0.24.04.1), server 18.0 (Ubuntu 18.0-201-yandex.61907.ef91e8757e))
WARNING: psql major version 16, server major version 18.
         Some psql features might not work.
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.

otusdb=> SELECT current_database(), current_user;
 current_database | current_user 
------------------+--------------
 otusdb           | otus
(1 row)

### Параметры инстанса
otusdb=> \x on
Expanded display is on.
otusdb=> SELECT
    version()                          AS "PostgreSQL version",
    current_database()                 AS "Database",
    current_user                       AS "User",
    inet_server_addr()                 AS "Server IP",
    inet_server_port()                 AS "Server port",
    CASE
        WHEN pg_is_in_recovery() THEN 'replica'
        ELSE 'primary'
    END                                AS "Role",
    pg_postmaster_start_time()         AS "Started at",
    now() - pg_postmaster_start_time() AS "Uptime",
    current_setting('max_connections') AS "Max connections",
    current_setting('shared_buffers')  AS "Shared buffers",
    current_setting('work_mem')        AS "Work mem",
    current_setting('statement_timeout') AS "Statement timeout";
-[ RECORD 1 ]------+--------------------------------------------------------------------------------------------------------------------------------------------------
PostgreSQL version | PostgreSQL 18.0 (Ubuntu 18.0-201-yandex.61907.ef91e8757e) on x86_64-pc-linux-gnu (Ubuntu 11.4.0-1ubuntu1~22.04.2) 11.4.0, 64-bit
Database           | otusdb
User               | otus
Server IP          | 127.0.0.1
Server port        | 5432
Role               | primary
Started at         | 2026-03-18 08:55:00.250665+03
Uptime             | 01:44:46.887033
Max connections    | 200
Shared buffers     | 1GB
Work mem           | 4MB
Statement timeout  | 0

