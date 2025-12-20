### Развернул виртуальную машину на VirtualBox со следующими параметрами:

ЦПУ - 4 ядра; ОЗУ - 8 Гб; SSD - 20 Гб; ОС - Ubuntu 24

#### Развернул инстанс PostgreSQL 18:

`sudo apt update && sudo apt upgrade -y -q && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo apt-get update && sudo apt -y install postgresql`

#### Создал БД test

`create database test;`

#### Инициализирую БД test с коэффициентом масштабирования 200:

`pgbench -i -s 200 test`

##### Выбор меньшего коэффициента масштабирования не позволит осуществить качественное тестирование. Создалось 200 млн. строк, размер БД:

`test=# SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;`

 2998 MB

### 1. Тестирую производительность PostgreSQL с параметрами по умолчанию

##### Ряд экспериментов показал, что при тестировании 50-сессионного режима pgbench моя ВМ "не вывозила" по CPU. В результате настройка любых параметров производительности, не затрагивающих durability, практически не влияла на итоги тестирования - цифры "стояли" на месте. 

##### Поэтому опытным путём пришёл к параметру в 20 одновременных сессий. Не учитывал результаты первого теста, считая его "прогревочным".

```
postgres@pg4:~$ pgbench -c 20 -j 4 -P 10 -T 60 test

pgbench (18.0 (Ubuntu 18.0-1.pgdg24.04+3))
starting vacuum...end.
progress: 10.0 s, 463.8 tps, lat 42.443 ms stddev 13.161, 0 failed
progress: 20.0 s, 458.6 tps, lat 43.597 ms stddev 20.796, 0 failed
progress: 30.0 s, 500.5 tps, lat 39.923 ms stddev 11.559, 0 failed
progress: 40.0 s, 486.0 tps, lat 41.171 ms stddev 14.103, 0 failed
progress: 50.0 s, 430.0 tps, lat 46.514 ms stddev 28.122, 0 failed
progress: 60.0 s, 507.8 tps, lat 39.355 ms stddev 11.857, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 200
query mode: simple
number of clients: 20
number of threads: 4
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 28487
number of failed transactions: 0 (0.000%)
latency average = 42.033 ms
latency stddev = 17.474 ms
initial connection time = 140.469 ms
tps = 475.574960 (without initial connection time)

postgres@pg4:~$ pgbench -c 20 -j 4 -P 10 -T 60 test
pgbench (18.0 (Ubuntu 18.0-1.pgdg24.04+3))
starting vacuum...end.
progress: 10.0 s, 491.7 tps, lat 40.070 ms stddev 13.420, 0 failed
progress: 20.0 s, 460.9 tps, lat 43.380 ms stddev 25.687, 0 failed
progress: 30.0 s, 486.8 tps, lat 41.026 ms stddev 19.095, 0 failed
progress: 40.0 s, 490.7 tps, lat 40.744 ms stddev 19.604, 0 failed
progress: 50.0 s, 430.8 tps, lat 46.450 ms stddev 31.101, 0 failed
progress: 60.0 s, 508.1 tps, lat 39.332 ms stddev 16.875, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 200
query mode: simple
number of clients: 20
number of threads: 4
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 28710
number of failed transactions: 0 (0.000%)
latency average = 41.714 ms
latency stddev = 21.576 ms
initial connection time = 134.698 ms
tps = 479.019025 (without initial connection time)
```

#### Итого средний показатель tps при дефолтных настройках PostgreSQL: 477



### 2. Получаю максимум производительности без влияния на стабильность

`sudo -u postgres psql -X -v ON_ERROR_STOP=1 <<'SQL'
ALTER SYSTEM SET shared_buffers = '2GB';
ALTER SYSTEM SET effective_cache_size = '6GB';
ALTER SYSTEM SET work_mem = '10MB';
ALTER SYSTEM SET checkpoint_timeout = '15min';
ALTER SYSTEM SET wal_buffers = '16MB';
ALTER SYSTEM SET max_wal_size = '4GB';
ALTER SYSTEM SET min_wal_size = '1GB';
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET effective_io_concurrency = 200;
ALTER SYSTEM SET log_checkpoints = off;
ALTER SYSTEM SET log_statement = none;
SQL`

Здесь **shared_buffers** привожу в соответствие с рекомендациями:  shared_buffers = 25% от ОЗУ

Параметр **work_mem** по умолчанию очень мал, увеличиваю его

Параметр **checkpoint_timeout** будет делаться пореже

Параметры, касающиеся WAL файлов настроить важно при большом числе изменений

Параметры **random_page_cost** и **effective_io_concurrency** выставляю исходя из того, что у меня - SSD

Параметр **log_checkpoints** негативно влияет на производительность

Параметр **log_checkpoints** выключил "за компанию"

#### Для применения параметров:

`sudo pg_ctlcluster 18 main restart`

##### Перед каждой серией тестов очищаю кэш ОС:

`echo 3 | sudo tee /proc/sys/vm/drop_caches`

```
postgres@pg4:~$ pgbench -c 20 -j 4 -P 10 -T 60 test
pgbench (18.0 (Ubuntu 18.0-1.pgdg24.04+3))
starting vacuum...end.
progress: 10.0 s, 497.6 tps, lat 39.511 ms stddev 11.049, 0 failed
progress: 20.0 s, 520.9 tps, lat 38.417 ms stddev 10.099, 0 failed
progress: 30.0 s, 512.2 tps, lat 39.059 ms stddev 11.615, 0 failed
progress: 40.0 s, 529.6 tps, lat 37.752 ms stddev 10.562, 0 failed
progress: 50.0 s, 538.5 tps, lat 37.184 ms stddev 10.277, 0 failed
progress: 60.0 s, 531.1 tps, lat 37.611 ms stddev 11.566, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 200
query mode: simple
number of clients: 20
number of threads: 4
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 31314
number of failed transactions: 0 (0.000%)
latency average = 38.236 ms
latency stddev = 10.902 ms
initial connection time = 131.415 ms
tps = 522.681836 (without initial connection time)

postgres@pg4:~$ pgbench -c 20 -j 4 -P 10 -T 60 test
pgbench (18.0 (Ubuntu 18.0-1.pgdg24.04+3))
starting vacuum...end.
progress: 10.0 s, 517.9 tps, lat 38.057 ms stddev 10.906, 0 failed
progress: 20.0 s, 515.4 tps, lat 38.679 ms stddev 11.446, 0 failed
progress: 30.0 s, 540.6 tps, lat 37.058 ms stddev 9.854, 0 failed
progress: 40.0 s, 557.6 tps, lat 35.904 ms stddev 9.238, 0 failed
progress: 50.0 s, 560.3 tps, lat 35.653 ms stddev 9.644, 0 failed
progress: 60.0 s, 558.9 tps, lat 35.765 ms stddev 9.554, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 200
query mode: simple
number of clients: 20
number of threads: 4
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 32526
number of failed transactions: 0 (0.000%)
latency average = 36.827 ms
latency stddev = 10.199 ms
initial connection time = 132.751 ms
tps = 542.575477 (without initial connection time)
```

#### Итого средний показатель tps при улучшенных настройках PostgreSQL: 532

#### Это +11% к настройкам по умолчанию



### 3. Попытаюсь более тонкими настройками добиться лучшего результата (всё ещё без влияния на стабильность)

##### В топе - события WALWrite:

`postgres=# SELECT wait_event_type, wait_event, count(*)
FROM pg_stat_activity
WHERE state <> 'idle'
GROUP BY 1,2
ORDER BY 3 DESC;`

```
wait_event_type |  wait_event  | count
-----------------+--------------+-------
 LWLock          | WALWrite     |    14
                 |              |     4
 IO              | DataFileRead |     1
 Client          | ClientRead   |     1
 IO              | WalSync      |     1
```



```
ALTER SYSTEM SET wal_writer_delay = '10ms';
ALTER SYSTEM SET wal_writer_flush_after = '1MB';
ALTER SYSTEM SET checkpoint_flush_after = '1MB';
ALTER SYSTEM SET bgwriter_flush_after = '1MB';
```

`SELECT pg_reload_conf();`

`sudo sync`
`echo 3 | sudo tee /proc/sys/vm/drop_caches`

```
postgres@pg4:~$ pgbench -c 20 -j 4 -P 10 -T 60 test
pgbench (18.0 (Ubuntu 18.0-1.pgdg24.04+3))
starting vacuum...end.
progress: 10.0 s, 503.1 tps, lat 39.132 ms stddev 11.339, 0 failed
progress: 20.0 s, 529.4 tps, lat 37.734 ms stddev 10.281, 0 failed
progress: 30.0 s, 546.4 tps, lat 36.626 ms stddev 9.562, 0 failed
progress: 40.0 s, 539.2 tps, lat 37.088 ms stddev 10.164, 0 failed
progress: 50.0 s, 550.3 tps, lat 36.344 ms stddev 9.875, 0 failed
progress: 60.0 s, 484.1 tps, lat 41.268 ms stddev 13.954, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 200
query mode: simple
number of clients: 20
number of threads: 4
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 31545
number of failed transactions: 0 (0.000%)
latency average = 37.967 ms
latency stddev = 11.033 ms
initial connection time = 136.961 ms
tps = 526.508216 (without initial connection time)

postgres@pg4:~$ pgbench -c 20 -j 4 -P 10 -T 60 test
pgbench (18.0 (Ubuntu 18.0-1.pgdg24.04+3))
starting vacuum...end.
progress: 10.0 s, 529.6 tps, lat 37.188 ms stddev 10.958, 0 failed
progress: 20.0 s, 546.6 tps, lat 36.587 ms stddev 10.481, 0 failed
progress: 30.0 s, 567.9 tps, lat 35.232 ms stddev 9.724, 0 failed
progress: 40.0 s, 562.2 tps, lat 35.498 ms stddev 10.066, 0 failed
progress: 50.0 s, 556.5 tps, lat 35.937 ms stddev 11.341, 0 failed
progress: 60.0 s, 573.8 tps, lat 34.835 ms stddev 11.037, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 200
query mode: simple
number of clients: 20
number of threads: 4
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 33386
number of failed transactions: 0 (0.000%)
latency average = 35.867 ms
latency stddev = 10.646 ms
initial connection time = 133.739 ms
tps = 557.355953 (without initial connection time)
```

#### Итого средний показатель tps при оптимальных настройках PostgreSQL: 541

#### Это +13% к настройкам по умолчанию



### 4. Настройка кластера на оптимальную производительность, не обращая внимания на стабильность БД - перенос его в RAM

##### Сколько занимает кластер:

`postgres@pg4:~/18/main$ du -sh`
4.0G 

`sudo pg_ctlcluster 18 main stop
sudo mkdir -p /pg_tmpfs
sudo chown postgres:postgres /pg_tmpfs
sudo chmod 700 /pg_tmpfs
sudo mount -t tmpfs -o size=5G,noatime tmpfs /pg_tmpfs`

##### под postgres:

`cp -r /var/lib/postgresql/18/main/ /pg_tmpfs/`
`mcedit /etc/postgresql/18/main/postgresql.conf`
data_directory = '/pg_tmpfs/main'
`sudo systemctl start postgresql`

##### Проверка:

`postgres=# SHOW data_directory;`

 data_directory

 /pg_tmpfs

##### Тест, не изменяя durability-параметров PostgreSQL:

```
postgres@pg4:~$ pgbench -c 20 -j 4 -P 10 -T 60 test
pgbench (18.0 (Ubuntu 18.0-1.pgdg24.04+3))
starting vacuum...end.
progress: 10.0 s, 696.5 tps, lat 28.287 ms stddev 9.755, 0 failed
progress: 20.0 s, 721.0 tps, lat 27.731 ms stddev 9.002, 0 failed
progress: 30.0 s, 731.2 tps, lat 27.364 ms stddev 9.371, 0 failed
progress: 40.0 s, 732.7 tps, lat 27.280 ms stddev 8.478, 0 failed
progress: 50.0 s, 707.1 tps, lat 28.275 ms stddev 9.894, 0 failed
progress: 60.0 s, 726.0 tps, lat 27.563 ms stddev 8.214, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 200
query mode: simple
number of clients: 20
number of threads: 4
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 43160
number of failed transactions: 0 (0.000%)
latency average = 27.746 ms
latency stddev = 9.141 ms
initial connection time = 135.974 ms
tps = 720.419366 (without initial connection time)

postgres@pg4:~$ pgbench -c 20 -j 4 -P 10 -T 60 test
pgbench (18.0 (Ubuntu 18.0-1.pgdg24.04+3))
starting vacuum...end.
progress: 10.0 s, 698.8 tps, lat 28.204 ms stddev 9.900, 0 failed
progress: 20.0 s, 721.4 tps, lat 27.722 ms stddev 9.103, 0 failed
progress: 30.0 s, 736.9 tps, lat 27.133 ms stddev 8.654, 0 failed
progress: 40.0 s, 721.6 tps, lat 27.718 ms stddev 9.128, 0 failed
progress: 50.0 s, 737.3 tps, lat 27.100 ms stddev 8.617, 0 failed
progress: 60.0 s, 745.4 tps, lat 26.851 ms stddev 10.483, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 200
query mode: simple
number of clients: 20
number of threads: 4
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 43631
number of failed transactions: 0 (0.000%)
latency average = 27.447 ms
latency stddev = 9.348 ms
initial connection time = 133.517 ms
tps = 728.391954 (without initial connection time)
```

#### Итого средний показатель tps после переезда кластера в RAM: 724

#### Это +51% к первоначальным настройкам (по умолчанию)



### Настраиваю экземпляр в ущерб стабильности (он по прежнему находится в RAM)

`sudo -u postgres psql -X -v ON_ERROR_STOP=1 <<'SQL'
ALTER SYSTEM SET fsync = off;
ALTER SYSTEM SET wal_level = minimal;
ALTER SYSTEM SET max_wal_senders = 0;
ALTER SYSTEM SET synchronous_commit = off;
ALTER SYSTEM SET archive_command = '';
ALTER SYSTEM SET archive_mode = off;
ALTER SYSTEM SET full_page_writes = off;
SQL`

`sudo sync`
`echo 3 | sudo tee /proc/sys/vm/drop_caches`
`sudo pg_ctlcluster 18 main restart`

```
postgres@pg4:~$ pgbench -c 20 -j 4 -P 10 -T 60 test
pgbench (18.0 (Ubuntu 18.0-1.pgdg24.04+3))
starting vacuum...end.
progress: 10.0 s, 704.3 tps, lat 27.942 ms stddev 8.731, 0 failed
progress: 20.0 s, 730.3 tps, lat 27.394 ms stddev 7.605, 0 failed
progress: 30.0 s, 696.4 tps, lat 28.727 ms stddev 9.399, 0 failed
progress: 40.0 s, 723.5 tps, lat 27.633 ms stddev 8.206, 0 failed
progress: 50.0 s, 721.2 tps, lat 27.726 ms stddev 7.625, 0 failed
progress: 60.0 s, 736.5 tps, lat 27.146 ms stddev 8.296, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 200
query mode: simple
number of clients: 20
number of threads: 4
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 43141
number of failed transactions: 0 (0.000%)
latency average = 27.755 ms
latency stddev = 8.339 ms
initial connection time = 139.397 ms
tps = 720.286808 (without initial connection time)

postgres@pg4:~$ pgbench -c 20 -j 4 -P 10 -T 60 test
pgbench (18.0 (Ubuntu 18.0-1.pgdg24.04+3))
starting vacuum...end.
progress: 10.0 s, 686.7 tps, lat 28.715 ms stddev 9.886, 0 failed
progress: 20.0 s, 712.8 tps, lat 28.050 ms stddev 8.153, 0 failed
progress: 30.0 s, 705.2 tps, lat 28.355 ms stddev 8.475, 0 failed
progress: 40.0 s, 690.1 tps, lat 28.975 ms stddev 8.991, 0 failed
progress: 50.0 s, 700.0 tps, lat 28.564 ms stddev 8.841, 0 failed
progress: 60.0 s, 730.0 tps, lat 27.345 ms stddev 7.532, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 200
query mode: simple
number of clients: 20
number of threads: 4
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 42266
number of failed transactions: 0 (0.000%)
latency average = 28.338 ms
latency stddev = 8.711 ms
initial connection time = 130.353 ms
tps = 705.342802 (without initial connection time)
```

#### Итого средний показатель tps после переезда кластера в RAM и отказа от настроек durability: 713

#### Это +49% к первоначальным настройкам (по умолчанию)



#### Вывод. Наибольшее влияние на производительность кластера оказало его перемещение в ОЗУ. Конечно, в этом случае ни о какой долговечности речи не идёт.