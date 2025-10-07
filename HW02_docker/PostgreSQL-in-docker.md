### Домашнее задание № 2

1. ##### Создал otus-zimin - ВМ в Яндекс.Облаке

   Параметры: 4 ядра, 8 ГБ ОЗУ, 20 Gb SSD, ОС Ubuntu 20.4. Пользователь otus. 

2. ##### Установил docker по доке https://docs.docker.com/engine/install/ubuntu/

   `ssh -l otus 51.250.27.154`

   ###### Подготовка:

   `sudo apt-get install ca-certificates curl`

   `sudo install -m 0755 -d /etc/apt/keyrings`

   `sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc`

   `sudo chmod a+r /etc/apt/keyrings/docker.asc`

   `echo \`

   `"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \`
   `$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \`
   `sudo tee /etc/apt/sources.list.d/docker.list > /dev/null`

   ###### Установка:

   `sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`

   ###### Проверка:

   `sudo systemctl status docker`

   `sudo docker run hello-world`

   Hello from Docker! This message shows that your installation appears to be working correctly.

3. ##### Создал каталог /var/lib/postgres для хранения данных.

   `sudo mkdir /var/lib/postgres`

4. ##### Развернул контейнер pg-server с PostgreSQL 14 и смонтировал в него /var/lib/postgres.

   Предварительно создал сеть в docker

   ​	`sudo docker network create pg-net`

   ​	`sudo docker run --name pg-server --network pg-net -e POSTGRES_PASSWORD=postgres -d -p 5432:5432 -v /var/lib/postgres:/var/lib/postgresql/data postgres:14`

   ​	Здесь ключ -v монтирует локальную директорию `/var/lib/postgres` в контейнер для хранения данных PostgreSQL.

5. ##### Развернул контейнер pg-client с клиентом PostgreSQL.

   `sudo docker run -it --network pg-net --name pg-client postgres:14 psql -h pg-server -U postgres`

6. ##### Подключился из контейнера с клиентом к контейнеру с сервером и создал таблицу с данными о перевозках.

​	`sudo docker run -it --network pg-net --name pg-client postgres:14 psql -h pg-server -U postgres`

​	Здесь ключи `-it` создают виртуальный терминал и позволяют интерактивно взаимодействовать с контейнером.

​	Ключ `--network pg-net` указывает, что нужно использовать ранее созданную сеть pg-net.

​	Параметр `-h pg-server` указывает имя сервера, к которому я подключаюсь

​	Создал БД otus и подконнектился к ней:

​	`postgres=# create database otus;`

​	`postgres=# \c otus`

Создал таблицу **shipments** и наполнил её данными:

create table shipments(id serial, product_name text, quantity int, destination text);
insert into shipments(product_name, quantity, destination) values('bananas', 1000, 'Europe');
insert into shipments(product_name, quantity, destination) values('bananas', 1500, 'Asia');
insert into shipments(product_name, quantity, destination) values('bananas', 2000, 'Africa');
insert into shipments(product_name, quantity, destination) values('coffee', 500, 'USA');
insert into shipments(product_name, quantity, destination) values('coffee', 700, 'Canada');
insert into shipments(product_name, quantity, destination) values('coffee', 300, 'Japan');
insert into shipments(product_name, quantity, destination) values('sugar', 1000, 'Europe');
insert into shipments(product_name, quantity, destination) values('sugar', 800, 'Asia');
insert into shipments(product_name, quantity, destination) values('sugar', 600, 'Africa');
insert into shipments(product_name, quantity, destination) values('sugar', 400, 'USA');

7. ##### Подключился к контейнеру с ноутбука (предварительно пришлось установить Postgres 18 на Windows). Заодно проверил совместимость 18 версии клиента и 14 версии СУБД.

`C:\Users\Adm>psql -p 5432 -U postgres -h 51.250.27.154 -d otus -W`

psql (18.0, сервер 14.19 (Debian 14.19-1.pgdg13+1))

Подключился к базе otus:

otus=# \c otus

otus=# select count (*) from shipments;

(10 rows)

8. ##### Удалил контейнер с СУБД и создал его заново

   `sudo docker ps`
   `sudo docker stop pg-server`
   `sudo docker rm pg-server`
   `sudo docker run --name pg-server --network pg-net -e POSTGRES_PASSWORD=postgres -d -p 5432:5432 -v /var/lib/postgres:/var/lib/postgresql/data postgres:14`

9. ##### Данные остались на месте, так как хранились на хосте, а не в контейнере:

   postgres=# \c otus

   otus=# select count (*) from shipments;

   (10 rows)

   

