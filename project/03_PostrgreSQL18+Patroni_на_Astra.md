
 HA1   |	192.168.1.171  | 192.168.1.170 |  HAproxy+keepalived
 HA2   |	192.168.1.172  | 192.168.1.170 |  HAproxy+keepalived
 PG1   |	192.168.1.181  |   		       |  leader/synchronius replica
 PG2   |	192.168.1.182  |   		       |  leader/synchronius replica
 PG3   |	192.168.1.183  |   		       |  asynchronius replica
 ETCD1 |	192.168.1.191  |			   |  key-value store
 ETCD2 |	192.168.1.192  |			   |  key-value store
 ETCD3 |	192.168.1.193  |			   |  key-value store

## Установка PostgreSQL 18

### предварительно сделаю так, чтобы apt брал пакеты, связанные с patroni, только из репозитория PGDG и забыл про репозиторий на DVD (временно или постоянно)
sudo mcedit /etc/apt/sources.list
### Тут нужно закомментировать строку, начинающуюся с deb cdrom
### !!И раскомментировать строки репозиториев main и extended!!
### Установка репозитория PGDG 
sudo install -d /usr/share/postgresql-common/pgdg
sudo curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
  https://www.postgresql.org/media/keys/ACCC4CF8.asc
sudo tee /etc/apt/sources.list.d/pgdg.list >/dev/null <<'EOF'
deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main
EOF
sudo apt update
### Установка PostgreSQL 18 из PGDG (с зависимостями) - ключевые пакеты postgresql-18, postgresql-common, libpq5 будут установлены из PGDG
### Некоторые второстепенные пакеты: liburing2, libxslt1.1 - будут установлены из Astra-репозитория
### !!Рекомендованный установщиком, но необязательный, пакет postgresql-18-jit я не устанавливал!!
sudo apt update
sudo apt install -y postgresql-18
sudo apt -t bookworm-pgdg install -y postgresql-18

### Проверка, что реально встало “из PGDG”, а не из Astra
apt-cache policy postgresql-18 postgresql-common libpq5 | sed -n '1,200p'
### или
dpkg -l | egrep '^(ii)\s+(postgresql|libpq)' | awk '{print $2 "\t" $3}'
### Идея в том, чтобы все пакеты, которые начинаются на postgresql- и libpq*, должны быть из одного источника (у меня это PGDG)
### !!На будущее: расширения, если таковые будут, нужно будет тоже ставить из репозитория PGDG!!

## решение проблемы с учеткой postgres
### Переключение не удаётся: 
otus@Astra1:~$ sudo -i -u postgres
sudo: PAM account management error: Доступ запрещен
sudo: a password is required
#### В Astra работает мандатный контроль целостности (МКЦ): каждому процессу/пользователю сопоставляется “уровень доверия/целостности”, и система блокирует некоторые переходы между уровнями. МКЦ как раз предназначен для ограничения последствий компрометации и даже ограничивает возможности суперпользователя.
Я вошел в систему с высокой целостностью (63), а у пользователя ОС postgres разрешён только “низкий” уровень (0). Поэтому PAM (через sudo) запрещает переключение

#### Проверить статус учетки (L - заблокирована): 
sudo passwd -S postgres
postgres L 2026-02-08 -1 -1 -1 -1
#### Решение - разрешить пользователю postgres высокий уровень целостности (63) - есть в документации Astra такое
sudo pdpl-user -i 63 postgres

#### Проверка:
sudo -i -u postgres

## Установка Patroni
### Patroni ставлю тоже из PGDG:
sudo apt update
sudo apt install -y -t bookworm-pgdg patroni
Следующие пакеты имеют неудовлетворённые зависимости:
 patroni : Зависит: python3-cdiff но он не может быть установлен
E: Невозможно исправить ошибки: у вас зафиксированы сломанные пакеты.

#### Скачиваю python3-cdiff и устанавливаю его вручную:
otus@Astra1:/tmp$  wget -O python3-cdiff_1.0-1.1_all.deb \
  http://deb.debian.org/debian/pool/main/c/cdiff/python3-cdiff_1.0-1.1_all.deb
sudo dpkg -i python3-cdiff_1.0-1.1_all.deb

### Снова пытаюсь поставить Patroni:
sudo apt install -y patroni
### Также установил клиент etcd:
sudo apt install -y etcd-client

Смена носителя: вставьте диск с меткой
 «OS Astra Linux 1.8.4.48 1.8_x86-64 DVD»
в устройство «/media/cdrom/» и нажмите [Enter]

#### Для того, чтобы apt брал пакеты, связанные с patroni, только из репозитория PGDG и забыл про репозиторий на DVD (временно или постоянно):
sudo mcedit /etc/apt/sources.list
#### Тут нужно закомментировать строку, начинающуюся с deb cdrom
#### И раскомментировать строки репозиториев main и extended

sudo apt update
sudo apt install -y -t bookworm-pgdg patroni

#### Проверка, откуда взят Patroni и какие зависимости он подтянул
apt-cache policy patroni patroni-doc | sed -n '1,120p'
dpkg -l | egrep '^(ii)\s+patroni(\s|-)'
apt-cache show patroni | sed -n '1,120p' | egrep -i '^(Package|Version|Depends|Recommends|Suggests):'

#### версии Patroni и python3-etcd:
otus@template:~$ patroni --version && dpkg -s python3-etcd | grep Version
patroni 4.1.0
Version: 0.4.5-4+b3

### Подготовка к созданию кластера Patroni
#### Останавливаю и удаляю экземлпяр постгреса, который запускается по умолчанию:
sudo systemctl status postgresql@18-main
sudo systemctl stop postgresql@18-main
sudo -u postgres pg_dropcluster 18 main 
sudo systemctl daemon-reload
#### Проверка отсутствия экземпляра postgresql:
pg_lsclusters
Ver Cluster Port Status Owner Data directory Log file

#### Подготовка каталогов, выдача прав
sudo touch /etc/patroni/patroni.yml
sudo chown postgres:postgres /etc/patroni
sudo chmod 0750 /etc/patroni
sudo chown postgres:postgres /etc/patroni/patroni.yml
sudo chmod 0640 /etc/patroni/patroni.yml
sudo mkdir /var/log/patroni/
sudo chown postgres:postgres /var/log/patroni/
sudo chmod 0750 /var/log/patroni/

#### Конфиг для aPG1
cat > /etc/patroni/patroni.yml <<EOF
scope: p-cluster
name: apg1

restapi:
  listen: 192.168.1.181:8008
  connect_address: 192.168.1.181:8008

etcd3:
  hosts: 192.168.1.191:2379,192.168.1.192:2379,192.168.1.193:2379
  protocol: http
  
log:
  dir: /var/log/patroni
  file_num: 5
  file_size: 20971520
  mode: 0640
  level: DEBUG
  format: '%(asctime)s %(levelname)s [%(name)s] %(message)s'
  dateformat: '%Y-%m-%d %H:%M:%S'
  deduplicate_heartbeat_logs: false

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    synchronous_mode: true
    synchronous_node_count: 1
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
		max_connections: 500
        max_wal_senders: 7
        max_replication_slots: 7
        wal_keep_size: 1GB
        max_slot_wal_keep_size: 2GB
        wal_compression: on
        wal_recycle: on
        wal_log_hints: on

        log_destination: stderr
        logging_collector: on
        log_directory: /var/log/postgresql
        log_filename: postgresql-18-main.log
        log_rotation_age: 7d
        log_rotation_size: 100MB
        log_checkpoints: on
        log_connections: on
        log_disconnections: on
        log_lock_waits: on

  initdb:
     - encoding: UTF8
     - data-checksums

  pg_hba:
    - host replication replicator 192.168.1.0/24 md5
    - host replication replicator 127.0.0.1/32 md5
    - host all rewind_user 192.168.1.0/24 md5
	- host all pgscv 192.168.1.0/24 md5
    - host all postgres 192.168.1.0/24 trust
    - host all postgres_exporter 192.168.1.0/24 md5
    - host all all 127.0.0.1/32 trust
    - local all all trust

postgresql:
  listen: 127.0.0.1, 192.168.1.181:5432
  connect_address: 192.168.1.181:5432
  data_dir: /var/lib/postgresql/18/main
  bin_dir: /usr/lib/postgresql/18/bin
  pgpass: /var/lib/postgresql/pgpass0
  authentication:
    replication:
      username: replicator
      password: "123"
    superuser:
      username: postgres
      password: "123"
    rewind:
      username: rewind_user
      password: "123"

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF
  
#### Конфиг для aPG2
cat > /etc/patroni/patroni.yml <<EOF
scope: p-cluster
name: apg2

restapi:
  listen: 192.168.1.182:8008
  connect_address: 192.168.1.182:8008

etcd3:
  hosts: 192.168.1.191:2379,192.168.1.192:2379,192.168.1.193:2379
  protocol: http

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 192.168.1.0/24 md5
    - host all rewind_user 192.168.1.0/24 md5
    - host all all 127.0.0.1/32 trust
    - local all all trust
	
log:
  dir: /var/log/patroni
  file_num: 5
  file_size: 20971520
  mode: 0640
  level: INFO
  format: '%(asctime)s %(levelname)s [%(name)s] %(message)s'
  dateformat: '%Y-%m-%d %H:%M:%S'
  deduplicate_heartbeat_logs: false

postgresql:
  listen: 127.0.0.1, 192.168.1.182:5432
  connect_address: 192.168.1.182:5432
  data_dir: /var/lib/postgresql/18/main
  bin_dir: /usr/lib/postgresql/18/bin
  pgpass: /var/lib/postgresql/pgpass0
  authentication:
    replication:
      username: replicator
      password: "123"
    superuser:
      username: postgres
      password: "123"
    rewind:
      username: rewind_user
      password: "123"

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF

sudo systemctl status patroni.service
sudo systemctl stop patroni.service

cat > /usr/lib/systemd/system/patroni.service <<EOF
[Unit]
Description=High availability PostgreSQL Cluster
After=syslog.target network.target

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/bin/patroni /etc/patroni/patroni.yml
KillMode=process
TimeoutSec=30
Restart=no

[Install]
WantedBy=multi-user.target
EOF

#### После изменения конфига службы нужно перезагрузить конфигурацию systemd:
sudo systemctl daemon-reload

#### Если это первая поднимаемая нода в кластере Patroni, то первый запуск - вручную, затем (если нет ошибок) - активируем и запускаем службу.
sudo -i -u postgres
patroni /etc/patroni/patroni.yml

#### Останавливаю первый успешный запуск, стартую службу на PG1:
sudo systemctl start patroni
sudo systemctl status patroni

#### Далее запускаю службу на PG2:
sudo systemctl start patroni
sudo systemctl status patroni

#### Проверка показала, что всё хорошо:
patronictl -c /etc/patroni/patroni.yml list

#### Добавил переменную PATRONICTL_CONFIG_FILE для удобства использования:
#### вместо "patronictl -c /etc/patroni/patroni.yml list" => "patronictl list"

#### На Astra/Debian-подобных системах частая причина: вы заходите как postgres через su - postgres (login shell), а login shell читает ~/.bash_profile / ~/.profile, но не обязан читать ~/.bashrc
#### Поэтому прописываю переменную в .bash_profile:
cat > ~/.bash_profile <<'EOF'
export PATRONICTL_CONFIG_FILE=/etc/patroni/patroni.yml
EOF

#### Пробую switchover aPG1 -> aPG2:
patronictl -c /etc/patroni/patroni.yml switchover
Primary [apg1]: apg1
Candidate ['apg2'] []: apg2
When should the switchover take place (e.g. 2026-02-11T20:00 )  [now]: now
Are you sure you want to switchover cluster p-cluster, demoting current leader apg1? [y/N]: y
2026-02-11 19:00:39.39525 Successfully switched over to "apg2"
#### Процесс полного переключения занимает порядка 15 секунд.

### Конфиг для pg3
cat > /etc/patroni/patroni.yml <<EOF
scope: p-cluster
name: apg3

restapi:
  listen: 192.168.1.183:8008
  connect_address: 192.168.1.183:8008

etcd3:
  hosts: 192.168.1.191:2379,192.168.1.192:2379,192.168.1.193:2379
  protocol: http

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 192.168.1.0/24 md5
    - host all rewind_user 192.168.1.0/24 md5
    - host all all 127.0.0.1/32 trust
    - local all all trust
	
log:
  dir: /var/log/patroni
  file_num: 5
  file_size: 20971520
  mode: 0640
  level: INFO
  format: '%(asctime)s %(levelname)s [%(name)s] %(message)s'
  dateformat: '%Y-%m-%d %H:%M:%S'
  deduplicate_heartbeat_logs: false

postgresql:
  listen: 127.0.0.1, 192.168.1.183:5432
  connect_address: 192.168.1.183:5432
  data_dir: /var/lib/postgresql/18/main
  bin_dir: /usr/lib/postgresql/18/bin
  pgpass: /var/lib/postgresql/pgpass0
  authentication:
    replication:
      username: replicator
      password: "123"
    superuser:
      username: postgres
      password: "123"
    rewind:
      username: rewind_user
      password: "123"

tags:
    nofailover: true
    noloadbalance: true
    clonefrom: false
    nosync: true
EOF

#### Так же как и на aPG1-PG2 останавливаю и удаляю кластер PostgreSQL на aPG3.
#### Точно так же прописываю службу patroni.service. 

#### Стартую ноду Patroni на aPG3:
sudo systemctl start patroni
sudo systemctl status patroni

#### Контроль:
patronictl -c /etc/patroni/patroni.yml list

#### Скопировал среднюю демо-базу:
scp -P 229 -p demo-20250901-6m.sql.gz otus@192.168.1.181:/home/otus
sudo chown postgres:postgres demo-20250901-6m.sql.gz
#### Распаковка (успешна)
gunzip -c demo-20250901-6m.sql.gz | psql -U postgres
