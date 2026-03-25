## Разворачивание Managed PostgreSQL кластера в YandexCloud

### Минимально доступные ресурсы под Managed PostgreSQL в ЯО следующие:
2 vCPU, 100% vCPU rate, 4 ГБ RAM

### Создаю кластер, в котором будет мастер в зоне ru-central1-a и реплика в зоне ru-central1-d
yc managed-postgresql cluster create OtusCluster \
		--network-name default \
		--security-group-ids enpgeo4cbg3t23ffktrv \
		--postgresql-version 18 \
		--resource-preset c3-c2-m4 \
		--user name=otus,password=Otus_pass \
		--database name=OtusDB,owner=otus \
		--host zone-id=ru-central1-a,assign-public-ip=true,subnet-name=default-ru-central1-a \
		--host zone-id=ru-central1-d,assign-public-ip=true,subnet-name=default-ru-central1-d

### Для подключения понадобится локальный сертификат
mkdir -p ~/.postgresql && \
wget "https://storage.yandexcloud.net/cloud-certs/CA.pem" \
     --output-document ~/.postgresql/root.crt && \
chmod 0655 ~/.postgresql/root.crt

### Подключение с паролем Otus_pa$$ не проходило, решил заменой пароля на Otus_pass
psql "host=rc1a-m0bntscs0pdnsekm.mdb.yandexcloud.net,rc1d-g0ofj1vm1ru947qo.mdb.yandexcloud.net \
    port=6432 \
    sslmode=verify-full \
    dbname=OtusDB \
    user=otus \
    target_session_attrs=read-write"
Password for user otus: 
psql (16.13 (Ubuntu 16.13-0ubuntu0.24.04.1), server 18.0 (Ubuntu 18.0-201-yandex.61907.ef91e8757e))
WARNING: psql major version 16, server major version 18.
         Some psql features might not work.
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)

Тесты latency в Managed PostgreSQL кластере на яндекс облаке:

### Тест1 - лёгкий:
cat > /tmp/test1.sql <<'EOF'
SELECT now();
SELECT current_setting('server_version');
EOF

PGSSLMODE=verify-full PGTARGETSESSIONATTRS=read-write \
pgbench -h c-c9qr2letr2thgoqq9nmn.rw.mdb.yandexcloud.net -p 6432 -U otus -d OtusDB -c 1 -j 1 -T 30 -P 5 -n -r -f /tmp/test1.sql

progress: 30.0 s, 7.2 tps, lat 139.689 ms stddev 48.049, 0 failed
pgbench: client 0 receiving
transaction type: /tmp/test1.sql
duration: 30 s
number of transactions actually processed: 259
number of failed transactions: 0 (0.000%)
latency average = 114.121 ms
latency stddev = 49.399 ms
initial connection time = 511.783 ms
tps = 8.759708 (without initial connection time)
statement latencies in milliseconds and failures:
        56.988           0  SELECT now();
        57.133           0  SELECT current_setting('server_version');

#### Результат теста можно взять начальную точку. 
#### Получается, что 57 мс - это задержка сети, SSH подключения, протокола и т.д.

### Тест2 - посложнее:
cat > /tmp/test2.sql <<'EOF'
SELECT sum(length(md5(i::text)))
FROM generate_series(1, 200000) AS gs(i);
EOF

PGSSLMODE=verify-full PGTARGETSESSIONATTRS=read-write \
pgbench -h c-c9qr2letr2thgoqq9nmn.rw.mdb.yandexcloud.net -p 6432 -U otus -d OtusDB -c 1 -j 1 -T 30 -P 5 -n -r -M prepared -f /tmp/test2.sql

pgbench: client 0 executing script "/tmp/test2.sql"
duration: 30 s
number of transactions actually processed: 96
number of failed transactions: 0 (0.000%)
latency average = 308.578 ms
latency stddev = 44.347 ms
initial connection time = 645.263 ms
tps = 3.240147 (without initial connection time)
statement latencies in milliseconds and failures:
       308.578           0  SELECT sum(length(md5(i::text)))

#### Более сложный запрос занял уже 308 мс, из которых около 250 мс - собственно работа PostgreSQL

## Разворачивание Managed PostgreSQL кластера на Cloud.ru, также в конфигурации мастер-реплика

#### На Cloud.ru есть аналог утилиты yc - утилита cloud cli доступна только в Cloud.ru Advanced. У меня же в Evolution доступны только REST API и Terraform
#### Использование REST API показалось неудобным, Terraform же в данном ДЗ применять не буду, а буду всё делать кнопочками в веб-интерфейсе, так быстрее.
Evolution -> Managed PostgreSQL -> Создать кластер -> Название кластера: otus-pg -> Название базы данных: otus -> Версия PostgreSQL: 17 -> Реплики Standby: 1 -> Вычислительный ресурс: Баланс (vCPU 1, RAM 4 Гб) -> Диск: 10 Гб -> Включить резервное копирование, Пулер соединений и Логирование -> Подсеть 10.0.0.0/24 (Default_ru.AZ-1) -> Создать
#### Также для подключения к Managed PostgreSQL извне потребовалось создать виртуалку vm-otus:
Evolution -> Виртуальные машины -> Добавить ВМ -> Название: vm-otus -> Зона доступности: ru.AZ-1 -> Образ: Ubuntu 24.04 -> Диски: 10 Gb -> Гарантированная доля vCPU: 10% -> vCPU: 1, RAM: 1 Gb -> VPC: ide-connection-VPC -> Подсеть: 10.0.0.0/24 (Default_ru.AZ-1) -> Внутренний IP: Автоматически -> Публичный IP: Арендовать новый -> Группа безопасности: SSH-access_ru.AZ-1 -> Логин: otus -> Метод аутентификации: Публичный ключ -> Создать
#### Поскольку ВМ и Managed PostgreSQL находятся в разных подсетях (10.0.0.0/24 и 10.10.1.0/24), добавил второй сетевой интерфейс виртуалке vm-otus
#### Также была создана группа безопасности ide-connection, в которой были открыты порты 55432, 5432 и 22 в указание моего домашнего IP адреса

### Тесты на cloud.ru

#### Создание туннеля 
ssh -i ~/.ssh/id_ed25519 \
  -L 55432:10.0.0.6:5432 \
  otus@95.174.93.83

### Тест1 - лёгкий:
PGPASSWORD='nR0I6SmJ6fxIboEHrAMyOmX3GlgqHyU8hjmvQOvvK8iITxjQEKww7sDB6TzfprLL' \
pgbench -h 127.0.0.1 -p 55432 -U dbadmin -d otus \
  -c 1 -j 1 -T 30 -P 5 -n -r -f /tmp/test1.sql
  
progress: 30.0 s, 7.8 tps, lat 127.833 ms stddev 7.647, 0 failed
pgbench: client 0 receiving
transaction type: /tmp/test1.sql
duration: 30 s
number of transactions actually processed: 230
number of failed transactions: 0 (0.000%)
latency average = 128.373 ms
latency stddev = 8.044 ms
initial connection time = 471.802 ms
tps = 7.788611 (without initial connection time)
statement latencies in milliseconds and failures:
        63.969           0  SELECT now();
        64.404           0  SELECT current_setting('server_version');

### Тест2 - посложнее:
PGPASSWORD='nR0I6SmJ6fxIboEHrAMyOmX3GlgqHyU8hjmvQOvvK8iITxjQEKww7sDB6TzfprLL' \
pgbench -h 127.0.0.1 -p 55432 -U dbadmin -d otus \
  -c 1 -j 1 -T 30 -P 5 -n -r -M prepared -f /tmp/test2.sql

progress: 30.0 s, 3.0 tps, lat 323.701 ms stddev 35.383, 0 failed
pgbench: client 0 receiving
transaction type: /tmp/test2.sql
duration: 30 s
number of transactions actually processed: 88
number of failed transactions: 0 (0.000%)
latency average = 337.826 ms
latency stddev = 79.467 ms
initial connection time = 462.623 ms
tps = 2.959761 (without initial connection time)
statement latencies in milliseconds and failures:
       337.826           0  SELECT sum(length(md5(i::text)))

## Выводы по тестированию latency
### По результатам тестирования видим, что Managed PostgreSQL в Яндекс Облаке в моменте оказалось быстрее ~10% что на лёгком, что на более тяжелом тесте
### Свою роль, вероятно, сыграла виртуалка-шлюз в Cloud.ru
### С другой стороны, initial connection time у Яндекс-облако получилось выше
### Однако что та, что другая цифры сопоставимы и вполне могут измениться при замере, выполненном несколькими часами позже

## Выводы по тарифам Managed PostgreSQL и итоговое резюме
### Цена у YandexCloud: 8602 руб/мес
### Цена у Cloud.ru: 4709 руб/мес
### Если учитывать аренду vm-otus в Cloud.ru, то цена вырастет на дополнительные 562 руб. и составит 5271 руб.
### Даже учитывая более высокую цену на Managed PostgreSQL в Яндекс Облаке, я выбираю это решение из-за большего удобства для меня

### Плюсы YandexCloud:
1) Было просто разобраться с утилитой yc
2) Качественный раздел поддержки, документация - топ
3) Тестирование показало меньшую latency нежели у конкурента

### Минусы YandexCloud:
1) Веб-интерфейс показался местами запутанным
2) Более высокая цена

Плюсы SberCloud:
1) Веб-интерфейс интуитивно понятен
2) Цена в ~1.5 раза ниже

Минусы SberCloud:
1) Аналог утилиты yc - утилита 	cloud cli доступна в Cloud.ru Advanced. У меня же в Evolution доступны только REST API и Terraform
2) Не очень дружелюбная справка - иногда выдаются нерелевантные результаты
3) Необходимость создания ВМ-шлюза vm-otus для подключения извне к Managed PostgreSQL
4) Недоступна 18 версия (максимум 17)
5) Тестирование показало более высокий latency нежели у конкурента
6) Поймал какой-то глюк с ssh-ключом для vm-otus, необходимой для подключения извне к Managed PostgreSQL: ключ не работал, помогло пересоздание ВМ. 
