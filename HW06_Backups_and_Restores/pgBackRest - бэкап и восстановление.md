### Задачи: 

#### 1) На машине PG4 настрою бэкап кластера main с помощью утилиты pgBackRest на удалённый сервер BCKP1 

#### 2) Вместо BCKP1 настрою бэкап pgBackRest на S3 хранилище yandex cloud

#### 3) На PG4 восстановлю кластер из бэкапа сначала с сервера BCKP — в инстанс test, а затем из S3 бакета — в инстанс s3t

### Инфраструктура:

##### PG4	(192.168.1.84) — ВМ (PostgreSQL 18) и demo — базой полётов (1,3 Гб)

##### BCKP1   (192.168.1.90) — хост для бэкапов в локальной сети 

##### patroni-bckp — имя S3-bucket в yandex cloud

##### test, s3t - тестовые кластера на PG4, в которые будут восстанавливаться бэкапы



#### Разворачивание демо-базы полётов в кластер main на ВМ PG4

##### Демо-база взята с сайта PostgresPro:

https://postgrespro.ru/education/demodb

##### Вероятно из-за того, что дамп создавался в PostgreSQL 15, при разворачивании БД из него потребовалась замена локали:

`gunzip -c demo-20250901-3m.sql.gz | sed "s/LOCALE = 'en_US.UTF-8'/LOCALE_PROVIDER = icu ICU_LOCALE = 'en-US'/" | psql -U postgres`



### Установка и настройка pgBackRest на ВМ PG4 и BCKP1

##### Устанавливаю pgBackRest из репозитория PGDG для получения более свежей версии

`sudo apt install -y curl gnupg`
`curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /usr/share/keyrings/postgresql-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/postgresql-archive-keyring.gpg] http://apt.postgresql.org/pub/repos/apt noble-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list`

`sudo apt update`
`sudo apt install -y pgbackrest`

##### Проверка:

`sudo pgbackrest version`
pgBackRest 2.57.0
`sudo useradd --system --home /var/lib/pgbackrest --shell /bin/bash pgbackrest
sudo mkdir -p /var/lib/pgbackrest /var/log/pgbackrest
sudo chown -R pgbackrest:pgbackrest /var/lib/pgbackrest /var/log/pgbackrest
sudo chmod 750 /var/lib/pgbackrest /var/log/pgbackrest`

##### Также добавил в /etc/hosts на PG4 строку: 

`BCKP1 192.168.1.90` 

##### На PG4 создал ключ: 

`sudo -u postgres ssh-keygen -t ed25519 -f /var/lib/postgresql/.ssh/id_ed25519 -N ""`

##### Скопировал ключ на BCKP1 в пользователя pgbackrest:

`sudo -u postgres ssh-copy-id -i /var/lib/postgresql/.ssh/id_ed25519.pub pgbackrest@192.168.1.90`

##### Конфиг pgBackRest на PG4:

```
cat > /etc/pgbackrest/pgbackrest.conf <<EOF
[global]
repo1-host=BCKP1
repo1-host-user=pgbackrest
repo1-path=/var/lib/pgbackrest
repo1-retention-full=3
repo1-retention-diff=10
compress-type=zst
process-max=2
spool-path=/var/spool/pgbackrest
log-level-console=info
log-level-file=debug
log-path=/var/log/pgbackrest

[main]
pg1-path=/var/lib/postgresql/18/main
pg1-port=5432
archive-async=y
EOF
```

##### Конфиг pgbackrest.conf на BCKP1:

```
[global]
repo1-path=/var/lib/pgbackrest
log-level-console=info
log-level-file=debug
log-path=/var/log/pgbackrest
```

##### Добавил/изменил конфиг postgresql.conf:

```
wal_level=replica
archive_mode=on
archive_command='pgbackrest --stanza=main archive-push %p'
archive_timeout=60s
max_wal_senders=10
wal_compression=on
```

`sudo systemctl restart postgresql@18-main`

#### Инициализация stanza и первый бэкап. 

##### Stanza — конфигурация или набор настроек для бэкапа одного конкретного кластера. Stanza создается для каждой пары кластер-репозиторий

`sudo -u postgres pgbackrest --stanza=main stanza-create`

##### Проверка валидности конфигурации stanza:

`sudo -u postgres pgbackrest --stanza=main check`

##### Бэкап кластера main на ВМ BCKP1:

`sudo -u postgres pgbackrest --stanza=main --type=full backup`



### Восстановление кластера main из бэкапа BCKP1 в инстанс test

#### 1. Подготовка - создание каталогов, копирование конфигов, выдача прав

`sudo mkdir -p /var/lib/postgresql/18/test /etc/postgresql/18/test /etc/postgresql/18/test/conf.d`
`sudo chown -R postgres:postgres /var/lib/postgresql/18/test /etc/postgresql/18/test /etc/postgresql/18/test/conf.d`
`sudo chmod 700 /var/lib/postgresql/18/test
``sudo chmod 755 /etc/postgresql/18/test /etc/postgresql/18/test/conf.d`

`sudo -u postgres cp /etc/postgresql/18/main/*.conf /etc/postgresql/18/test/`

##### В postgresql.conf (инстанс test) изменяю параметры:

```
data_directory = '/var/lib/postgresql/18/test'
port = 5434
cluster_name = '18/test'
а также все пути, где встречается упоминание кластера main
archive_mode=off
archive_command=''
```

##### В конфиг /etc/pgbackrest/pgbackrest.conf на PG4 добавляю секцию [test]

```
[test]
pg1-path=/var/lib/postgresql/18/test
pg1-port=5434
```

#### 2. Восстановление кластера main из бэкапа BCKP1 в инстанс test

`sudo -u postgres pgbackrest --stanza=main --pg1-path=/var/lib/postgresql/18/test restore`

#### 3. Cтарт нового инстанса test

`sudo systemctl start postgresql@18-test`

##### Контроль лога:

`cat /var/log/postgresql/postgresql-18-test.log`
LOG:  database system is ready to accept read-only connections
LOG:  recovery stopping after reaching consistency
LOG:  pausing at the end of recovery
HINT:  Execute pg_wal_replay_resume() to promote.

##### Выполняю promote:

`sudo -u postgres psql -p 5434 -c "SELECT pg_wal_replay_resume();"`
LOG:  archive recovery complete
LOG:  database system is ready to accept connections



## Настройка резервирования кластера main на S3 backet yandex cloud

#### 1) Создаю сервисный аккаунт
`yc iam service-account create --name patroni-backup-sa --description "Service account for Patroni backups"`
done (2s)
id: ajelgceoqdm*******

folder_id: b1g40ajl********
created_at: "2025-11-16T07:35:46.995357114Z"
name: patroni-backup-sa
description: Service account for Patroni backups

#### 2) Назначаю роли сервисному аккаунту
`yc resource-manager folder add-access-binding b1g40ajl********* --service-account-name patroni-backup-sa --role storage.editor`
done (2s)
effective_deltas:

  - action: ADD
    access_binding:
      role_id: storage.editor
      subject:
        id: ajelgceoqdm8va3l87h8
        type: serviceAccount

`yc resource-manager folder add-access-binding b1g40ajl********* --service-account-name patroni-backup-sa --role storage.uploader`
done (3s)
effective_deltas:

  - action: ADD
    access_binding:
      role_id: storage.uploader
      subject:
        id: ajelgceoqdm8va3l87h8
        type: serviceAccount

#### 3) Создаю статический ключ доступа
`yc iam access-key create --service-account-name patroni-backup-sa`
access_key:
  id: ajevgisdvbsc******************
  service_account_id: ajelgceo**************
  created_at: "2025-11-16T07:41:24.964217034Z"
  key_id: YCAJEAa1IuCH***********
secret: YCNopCXdW0tFIVtb0***********

#### 4) Создаю бакет размером 5 Гб
`yc storage bucket create --name patroni-bckp --default-storage-class standard --max-size 5368709120`
name: patroni-bckp
folder_id: b1g40ajl********
anonymous_access_flags: {}
default_storage_class: STANDARD
versioning: VERSIONING_DISABLED
max_size: "5368709120"
created_at: "2025-11-16T07:48:05.559399Z"
resource_id: e3em2o7d7**********

#### 5) Устанавливаю утилиту aws для работы с S3
`curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"`

`unzip awscliv2.zip`

`sudo ./aws/install`

`aws --version`
aws-cli/2.31.37 Python/3.13.9 Linux/6.8.0-87-generic exe/x86_64.ubuntu.24

#### 6) Создаю профиль для Yandex Cloud
`aws configure --profile yandex`
AWS Access Key ID [None]: YCAJEAa1IuCH***********
AWS Secret Access Key [None]: YCNopCXdW0tFIVtb0***********
Default region name [None]: ru-central1
Default output format [None]: json

##### Список всех бакетов:

`aws --endpoint-url=https://storage.yandexcloud.net s3 ls --profile yandex`
2025-11-16 12:48:05 patroni-bckp

##### Попытка создать тестовый файл и затем проверить его наличие на S3:

`echo "test file" > test.txt`
`aws --endpoint-url=https://storage.yandexcloud.net s3 cp test.txt s3://patroni-bckp/test.txt --profile yandex`
`aws --endpoint-url=https://storage.yandexcloud.net s3 ls s3://patroni-bckp/ --profile yandex`
2025-11-16 19:50:21         10 test.txt

#### 7) Новый конфиг pgBackRest:
```
cat > /etc/pgbackrest/pgbackrest.conf <<EOF
[global]
repo1-type=s3
repo1-s3-endpoint=storage.yandexcloud.net
repo1-s3-region=ru-central1
repo1-s3-bucket=patroni-bckp
repo1-s3-key=YCAJEAa1******
repo1-s3-key-secret=YCNopCXdW0******
repo1-path=/pgbackrest
compress-type=lz4
compress-level=3

log-level-console=info
log-level-file=debug
log-path=/var/log/pgbackrest

start-fast=y
stop-auto=y
process-max=2

repo1-retention-full=3
repo1-retention-diff=7
repo1-s3-uri-style=path
repo1-cipher-type=none

[main]
pg1-path=/var/lib/postgresql/18/main
pg1-port=5432
pg1-user=postgres
EOF
```

#### Комментарии к конфигу:

##### Путь внутри бакета, где будут храниться бэкапы:
repo1-path=/pgbackrest

##### Начинать бэкап немедленно без ожидания checkpoint (ускоряет начало бэкапа, но может увеличить нагрузку):
start-fast=y
##### Останавливать работающие бэкапы при запуске нового:
stop-auto=y
##### Количество полных бэкапов, которые нужно хранить
repo1-retention-full=4
##### Количество дифференциальных бэкапов для хранения
repo1-retention-diff=10
##### Стиль URI для S3 - path style - нужен для совместимости с Yandex Cloud
repo1-s3-uri-style=path
##### Включить проверку целостности репозитория
repo1-cipher-type=none

#### 8) Создание stanza-конфигурации

`sudo -u postgres pgbackrest --stanza=main stanza-create`
2025-11-16 20:28:55.555 P00   INFO: stanza-create command begin 2.57.0: --config=/etc/pgbackrest/pgbackrest.conf --exec-id=2046-eed1694f --log-level-console=info --log-level-file=debug --log-path=/var/log/pgbackrest --pg1-path=/var/lib/postgresql/18/main --pg1-port=5432 --pg1-user=postgres --repo1-cipher-type=none --repo1-path=/pgbackrest --repo1-s3-bucket=patroni-bckp --repo1-s3-endpoint=storage.yandexcloud.net --repo1-s3-key=<redacted> --repo1-s3-key-secret=<redacted> --repo1-s3-region=ru-central1 --repo1-s3-uri-style=path --repo1-type=s3 --stanza=main
2025-11-16 20:28:55.603 P00   INFO: stanza-create for stanza 'main' on repo1
2025-11-16 20:28:56.711 P00   INFO: stanza-create command end: completed successfully (1170ms)

#### 9) Проверка валидности конфигурации

`sudo -u postgres pgbackrest --stanza=main check`
2025-11-16 20:30:18.318 P00   INFO: check repo1 configuration (primary)
2025-11-16 20:30:18.923 P00   INFO: check repo1 archive for WAL (primary)
2025-11-16 20:30:20.236 P00   INFO: check command end: completed successfully (1954ms)

#### 10) Бэкап и настройка расписания создания резервных копий

`sudo -u postgres pgbackrest --stanza=main backup`

`sudo crontab -u postgres -e`

##### Инкрементальный бэкап каждые 2 часа с 1:00 до 23:00, полный бэкап ежедневно в 21:30
`crontab -l`

0 1,3,5,7,9,11,13,15,17,19,21,23 * * * /usr/bin/pgbackrest --stanza=main --type=incr backup

30 21 * * * /usr/bin/pgbackrest --stanza=main --type=full backup

##### Какие и за какое число есть бэкапы:

`sudo -u postgres pgbackrest --stanza=main info` 

```
stanza: main
    status: ok
    cipher: none

db (current)
    wal archive min/max (18): 0000000400000000000000A6/0000000400000000000000CB

    full backup: 20251118-183246F
        timestamp start/stop: 2025-11-18 18:32:46+05 / 2025-11-18 18:35:27+05
        wal start/stop: 0000000400000000000000A6 / 0000000400000000000000A7
        database size: 1.4GB, database backup size: 1.4GB
        repo1: backup set size: 418.6MB, backup size: 418.6MB

    incr backup: 20251118-183246F_20251118-190001I
        timestamp start/stop: 2025-11-18 19:00:01+05 / 2025-11-18 19:00:06+05
        wal start/stop: 0000000400000000000000A9 / 0000000400000000000000AA
        database size: 1.4GB, database backup size: 8.3KB
        repo1: backup set size: 418.6MB, backup size: 459B
        backup reference total: 1 full

    full backup: 20251118-193259F
        timestamp start/stop: 2025-11-18 19:32:59+05 / 2025-11-18 19:35:30+05
        wal start/stop: 0000000400000000000000B0 / 0000000400000000000000B1
        database size: 1.4GB, database backup size: 1.4GB
        repo1: backup set size: 418.6MB, backup size: 418.6MB

    incr backup: 20251118-193259F_20251118-210002I
        timestamp start/stop: 2025-11-18 21:00:02+05 / 2025-11-18 21:00:08+05
        wal start/stop: 0000000400000000000000B6 / 0000000400000000000000B6
        database size: 1.4GB, database backup size: 64.3KB
        repo1: backup set size: 418.6MB, backup size: 15.2KB
        backup reference total: 1 full

    full backup: 20251118-222511F
        timestamp start/stop: 2025-11-18 22:25:11+05 / 2025-11-18 22:28:04+05
        wal start/stop: 0000000400000000000000BE / 0000000400000000000000BF
        database size: 1.4GB, database backup size: 1.4GB
        repo1: backup set size: 418.6MB, backup size: 418.6MB

    incr backup: 20251118-222511F_20251118-230002I
        timestamp start/stop: 2025-11-18 23:00:02+05 / 2025-11-18 23:00:07+05
        wal start/stop: 0000000400000000000000C1 / 0000000400000000000000C2
        database size: 1.4GB, database backup size: 8.3KB
        repo1: backup set size: 418.6MB, backup size: 459B
        backup reference total: 1 full
```



### Восстановление кластера main из бэкапа S3 yandex cloud в инстанс s3t

##### 1) Подготовка - создание каталогов, копирование конфигов, выдача прав

`sudo mkdir -p /var/lib/postgresql/18/s3t /etc/postgresql/18/s3t /etc/postgresql/18/s3t/conf.d`
`sudo chown -R postgres:postgres /var/lib/postgresql/18/s3t /etc/postgresql/18/s3t /etc/postgresql/18/s3t/conf.d`
`sudo chmod 700 /var/lib/postgresql/18/s3t`
`sudo chmod 755 /etc/postgresql/18/s3t /etc/postgresql/18/s3t/conf.d`
`sudo -u postgres cp /etc/postgresql/18/main/*.conf /etc/postgresql/18/s3t/`

##### 2) В postgresql.conf (s3t) нахожу и изменяю:

```
data_directory = '/var/lib/postgresql/18/s3t'
port = 5436
cluster_name = '18/s3t'
а также все пути, где встречается упоминание кластера main
archive_mode=off
archive_command=''
```

##### 3) В конфиг /etc/pgbackrest/pgbackrest.conf на PG4 добавляю секцию [s3t]

```
[s3t]
pg1-path=/var/lib/postgresql/18/s3t
pg1-port=5436
```

##### 4) В базе demo инстанса main 18.11 в 18:32 "случайно" удалил часть записей:

```
SELECT COUNT(*) FROM bookings.seats;
1294
DELETE FROM bookings.seats WHERE airplaine_code='351';
DELETE 325
SELECT COUNT(*) FROM bookings.seats;
969
```

После удаления данных прошло какое-то время и выполнилось 2 полных бэкапа.

##### 5) Восстановление бэкапа по метке бэкапа: 20251118-183246F 

Ключ type=immediate restore позволяет восстановить кластер на момент бэкапа, без него pgbackrest будет докатывать WAL-файлы до актуального состояния
`sudo -u postgres pgbackrest --stanza=main --pg1-path=/var/lib/postgresql/18/s3t --set=20251118-183246F --type=immediate restore`

##### 6) Старт инстанса s3t

`sudo systemctl start postgresql@18-s3t`
2025-11-18 23:33:57.621 +05 [12140] LOG:  completed backup recovery with redo LSN 0/A6000028
2025-11-18 23:33:57.621 +05 [12140] LOG:  consistent recovery state reached at 0/A7000050
2025-11-18 23:33:57.621 +05 [12134] LOG:  database system is ready to accept read-only connections
2025-11-18 23:33:57.623 +05 [12140] LOG:  recovery stopping after reaching consistency
2025-11-18 23:33:57.623 +05 [12140] LOG:  pausing at the end of recovery
2025-11-18 23:33:57.623 +05 [12140] HINT:  Execute pg_wal_replay_resume() to promote.

##### 7) Выполняю promote:	

`sudo -u postgres psql -p 5436 -c "SELECT pg_wal_replay_resume();"`
2025-11-18 23:35:45.157 +05 [12140] LOG:  archive recovery complete
2025-11-18 23:35:45.214 +05 [12134] LOG:  database system is ready to accept connections

##### 8) Проверяю, что данные в демо-базе восстановились:

`psql -h 192.168.1.84 -p 5436 -d demo -U postgres -c "SELECT COUNT(*) FROM bookings.seats;"`

1294

##### Удалённые ранее данные - восстановлены.