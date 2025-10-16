Пользовался докой Yandex.Cloud [Подключить диск к виртуальной машине](https://yandex.cloud/ru/docs/compute/operations/vm-control/vm-attach-disk#cli_1)

## 1. Создание VM и установка PostgreSQL:
`yc compute instance create --name otus-vm --hostname otus-vm --cores 2 --memory 4 --create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts --network-interface subnet-name=otus-subnet,nat-ip-version=ipv4 --metadata-from-file user-data="/mnt/d/otus/yc_create_user/yc_create_user.conf"`

### Подключение к VM:
`vm_ip_address=$(yc compute instance show --name otus-vm | grep -E ' +address' | tail -n 1 | awk '{print $2}') && ssh -o StrictHostKeyChecking=no -i ~/ssh-keys/id_rsa otus@$vm_ip_address`

### Установка PostgreSQL:
`sudo apt update && sudo apt upgrade -y -q && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo apt-get update && sudo apt -y install postgresql mc`

### Проверка в порядке ли PostgreSQL
`pg_lsclusters`

`18  main    5432 online postgres /var/lib/postgresql/18/main /var/log/postgresql/postgresql-18-main.log`

## 2. Подключаюсь, создаю БД и таблицу

`sudo -u postgres psql`

`create database otus;`

`c\ otus`

`create table shipments(id serial, product_name text, quantity int, destination text);`

`insert into shipments(product_name, quantity, destination) values('bananas', 1000, 'Europe');
insert into shipments(product_name, quantity, destination) values('bananas', 1500, 'Asia');
insert into shipments(product_name, quantity, destination) values('bananas', 2000, 'Africa');
insert into shipments(product_name, quantity, destination) values('coffee', 500, 'USA');
insert into shipments(product_name, quantity, destination) values('coffee', 700, 'Canada');
insert into shipments(product_name, quantity, destination) values('coffee', 300, 'Japan');
insert into shipments(product_name, quantity, destination) values('sugar', 1000, 'Europe');
insert into shipments(product_name, quantity, destination) values('sugar', 800, 'Asia');
insert into shipments(product_name, quantity, destination) values('sugar', 600, 'Africa');
insert into shipments(product_name, quantity, destination) values('sugar', 400, 'USA');`

### Добываю ID созданной ВМ

`yc compute instances list`

`fhmqlaj312ala1p5umb7    otus-vm`

### Пытаюсь создать диск размером 1 ГБ для кластера PostgreSQL

`yc compute disk create \
  --name PG-disk \
  --size 1 \
  --description "disk-for-PostgreSQL"`

### Получаю ошибку про неудачное имя

  `ERROR: rpc error: code = InvalidArgument desc = Request validation error: Name: invalid resource name`

### Изменяю имя диска на "pg-disk" - и диск успешно создался:

  `yc compute disk create \
  --name pg-disk \
  --size 1 \
  --description "disk-for-PostgreSQL"`

### Получаю список имеющихся дисков, среди них вижу новый
  `yc compute disk list`

### Подключаю диск к ВМ:
  `yc compute instance attach-disk otus-vm \
  --disk-name pg-disk \
  --mode rw`
### Отключаю диск от ВМ (забыл ключ auto-delete)::
  `yc compute instance detach-disk otus-vm \
  --disk-name pg-disk`

### Снова подключаю диск к ВМ:
  `yc compute instance attach-disk otus-vm \
  --disk-name pg-disk \
  --auto-delete \
  --mode rw`

### Получаю ID нового диска
  `yc compute disk list`

  `----- ID: fhm6rjl7tsdschai9qhc`
### По ID нового диска нахожу его метку - это vdb
  `ls -la /dev/disk/by-id`

  `virtio-fhm6rjl7tsdschai9qhc -> ../../vdb`
## Создание раздела, форматирование, монтирование:
  `sudo fdisk /dev/vdb`

  `sudo mkfs.ext4 /dev/vdb`

  `sudo mkdir /mnt/pgdisk && sudo mount /dev/vdb /mnt/pgdisk`

  `sudo chmod a+w /mnt/pgdisk`

### Определяю UUID диска:
  `ls -la /dev/disk/by-uuid/`

  `0ad97583-c933-49b8-9812-bc779d9f6f73 -> ../../vdb`

### Для автомонтирования добавляю раздел в fstab

  `UUID=0ad97583-c933-49b8-9812-bc779d9f6f73 /mnt/pgdisk ext4 defaults 0 2`

### Проверяю - раздел доступен:
  `df -h`

## 3. Приступаю к переносу кластера PostgreSQL на новый диск

  `SHOW data_directory;`

  `/var/lib/postgresql/18/main`

### Останавливаю кластер
  `sudo pg_ctlcluster 18 main stop`

  `pg_lsclusters`

  `18  main    5432 online postgres /var/lib/postgresql/18/main /var/log/postgresql/postgresql-18-main.log`

### Рсинкаю кластер в новое место
  `sudo rsync -av /var/lib/postgresql /mnt/pgdisk`

### На случай форс-мажора делаю бэкап кластера по старому пути
  `sudo mv /var/lib/postgresql/18/main /var/lib/postgresql/18/main.bak`

## 4. Добавляю новое значение параметра data_directory в postgresql.conf 
  `sudo su postgres`

  `echo "data_directory = '/mnt/pgdisk/postgresql/18/main'" | tee -a /etc/postgresql/18/main/postgresql.conf`

### Стартую кластер и проверяю его местонахождение
  `sudo pg_ctlcluster 18 main start`

  `pg_lsclusters`

  `18  main    5432 online postgres /mnt/pgdisk/postgresql/18/main /var/log/postgresql/postgresql-18-main.log`

  `sudo -u postgres psql`

  `SHOW data_directory;`

  `/mnt/pgdisk/postgresql/18/main`

## 5. Проверяю наличие данных
  `postgres=# \c otus`

  `select * from shipments order by random() limit 1;`

  `id | product_name | quantity | destination `

  `5 | coffee       |      700 | Canada`

### P.S. Осваивая Visual Studio Code, наткнулся на то, что её терминал по умолчанию хранит всего 1000 строк истории. Обнаружил это, когда начал оформлять ДЗ. Половина сделанного уже ушла "за горизонт" истории )) 
### Нашёл параметр terminal.integrated.scrollback (Файл > Настройки > Параметры), выставил значение 10000. 
