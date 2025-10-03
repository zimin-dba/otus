#### Домашнее задание №1. Работа с уровнями изоляции транзакции в PostgreSQL

Для удобства прикладываю скрины первой и второй сессий, находятся в \project\HW1

1) Создал ВМ postgres2025-zimin-sergey
2) Воспользовался своей парой ключей для коннекта к ВМ
3) Установил Postgres командой
      `sudo apt update && sudo apt upgrade -y && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo apt-get update && sudo apt-get -y install postgresql`


4. Создал две сессии psql

  #### Уровень изоляции read committed 

5. Выключил авто коммит в обеих сессиях:

​	postgres=# \set AUTOCOMMIT off

​	Создал таблицу servers и две записи в ней:

​	`postgres=*# create table servers (id int, place text, vendor text);`
​	`	postgres=*# insert into servers values (101, 'DC1', 'IBM');`
​	`	postgres=*# insert into servers values (102, 'DC1', 'Hitachi');`
​	`	postgres=*# commit;`

6. Текущий уровень изоляции:

​	`postgres=# show transaction isolation level;`

​	read committed

​	Начал новую транзакцию в обеих сессиях с уровнем изоляции по умолчанию:

​	`postgres=# begin;`

​	В первой сессии добавил новую запись:

​	`postgres=*# insert into servers values (103, 'DC1', 'Dell');`

​	Во второй сессии делаю селект:

​	`postgres=*# select * from servers;`

**Вторая сессия не видит запись c id=103, созданную первой сессией, так как может видеть 	только те данные, которые были зафиксированы на момент начала селекта во второй сессии, 	что соответствует уровню изоляции "read committed".**

​	Завершил первую транзакцию:

​	`postgres=*# commit;`

​	Во второй сессии проверяю:

​	`postgres=*# select * from servers;`

**После завершения транзакции в первой сессии - вторая сессия увидела запись c id=103, так как селект видит снимок базы данных на момент начала выполнения запроса.**

#### Уровень изоляции repeatable read

Начал новые транзакции в обеих сессиях с уровнем изоляции repeatable read

​	`postgres=# begin;`

​	`	postgres=*# set transaction isolation level repeatable read;`

В первой сессии добавил запись с id=104

​	`postgres=*# insert into servers values (104, 'DC1', 'Fujitsu');`

Во второй сессии выполнил селект

​	`postgres=*# select * from servers;`

**Вторая сессия не видит запись c id=104, созданную первой сессией, так как в соответствии с уровнем изоляции "Repeatable Read" не может видеть данные, незафиксированные другими транзакциями.** 

Завершил первую транзакцию (commit) и снова выполняю селект во второй сессии

​	`postgres=*# select * from servers;`

**Вторая сессия по прежнему не видит запись c id=104, созданную первой сессией, так как видит данные на момент начала транзакции второй сессии.** 

Завершил вторую транзакцию во второй сессии и снова выполнил select

​	`postgres=*# select * from servers;`

**После завершения транзакции во второй сессии она увидела запись c id=104, так как по завершении первой транзакции обновился снимок данных.**

