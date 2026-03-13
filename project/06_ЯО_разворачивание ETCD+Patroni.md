 
 vpn-wg |	10.50.10.200   |			   |  VPN WireGuard	
 dr-ha1 |	10.50.10.31    | 10.50.10.30   |  HAproxy+keepalived
 dr-ha2 |	10.50.10.32    | 10.50.10.30   |  HAproxy+keepalived
 dr-pg1 |	10.50.10.21	   |   		       |  leader standby
 dr-pg2 |	10.50.20.21    |   		       |  replica
 ETCD1  |	10.50.10.11    |			   |  key-value store
 ETCD2  |	10.50.20.11    |			   |  key-value store
 ETCD3  |	10.50.30.11    |			   |  key-value store

## Разворачивание ETCD-кластера
### Разворачивать буду по уже изученной методике, но на этот раз всё будет автоматизировано
### Создание недостающих каталогов
cd ~/sb-proekt
mkdir -p \
  terraform/environments/dr/etcd \
  ansible/playbooks \
  ansible/roles/etcd/tasks \
  ansible/roles/etcd/handlers \
  ansible/roles/etcd/templates \
  ansible/roles/etcd/defaults \
  ansible/roles/etcd/files \
  generated/inventory \
  generated/outputs

### Конфиги terraform для разворачивания кластера ETCD в Яндекс.Облаке выложены в каталоге проекта на github

### Получение айдишников для конфигов
yc config get token
yc config get cloud-id
yc config get folder-id

echo "sg_all_id=$(yc vpc security-group get --name sg-all --format json | jq -r '.id')"
echo "sg_admin_ssh_id=$(yc vpc security-group get --name sg-admin-ssh --format json | jq -r '.id')"
echo "sg_etcd_id=$(yc vpc security-group get --name sg-etcd --format json | jq -r '.id')"

### Ansible playbook для ETCD - также выложил на github

### Команды создания инфраструктуры ETCD
cd ~/sb-proekt
make terraform-etcd-plan
make terraform-etcd-apply
make ansible-etcd
### Либо вообще одной командой
make etcd

ssh -i /mnt/D/work/ssh/otus-sb otus-sb@10.50.10.11

### Не удавалось зайти на 10.50.10.11 (ETCD1)

### Решение проблемы - добавление правил:
yc vpc security-group update-rules sg-admin-ssh \
  --add-rule "direction=ingress,protocol=tcp,port=22,v4-cidrs=[10.50.10.200/32]"
yc vpc security-group update-rules sg-admin-ssh \
  --add-rule "direction=ingress,protocol=tcp,port=22,v4-cidrs=[10.60.0.0/24]"
### Также понадобилось добавление следующих правил:
yc vpc security-group update-rules sg_all \
  --add-rule direction=ingress,protocol=tcp,port=5432,v4-cidrs=10.50.0.0/16 \
  --add-rule direction=ingress,protocol=tcp,port=8008,v4-cidrs=10.50.0.0/16
## Разворачивание Patroni
### Также автоматизировал до одной-двух команд
### Bootstrap нод Patroni будет происходить строго последовательно: сначала стендбай-лидер, затем реплика 
#### Порядок следующий:
1) Подготовить оба узла;
2) Стартовать только dr-pg1;
3) Дождаться, что он стал standby leader;
4) Проверить streaming от on-prem;
5) Стартовать dr-pg2;
6) Дождаться, состояния реплики у dr-pg2.
#### Версии ПО задал следующие: PostgreSQL не ниже 18.0, Patroni - минимум 4.0. Устанавливаться будут из репозитория PGDG.
### Пригодилась (и не раз) чистка DCS после неуспешного старта кластера Patroni:
1) Остановить Patroni на обеих нодах
sudo systemctl stop patroni
2) Удалить ключи Patroni из etcd (только метаданные кластера)
export ETCDCTL_API=3
etcdctl --endpoints=http://10.50.10.11:2379,http://10.50.20.11:2379,http://10.50.30.11:2379 \
  del --prefix /service/dr-cloud
3) Очистить data_dir PostgreSQL Patroni на обеих нодах
sudo rm -rf /var/lib/postgresql/18/patroni/*
sudo chown -R postgres:postgres /var/lib/postgresql/18/patroni
sudo chmod 700 /var/lib/postgresql/18/patroni
#### Заметка на будущее - средствами Terraform+Ansible настроить удаление кластеров ETCD и Patroni 
### В разрешения фаервола на on-prem лидере Patroni (aPG1=192.168.1.181) добавил:
sudo ufw allow from 10.60.0.0/24 to any port 5432 proto tcp
sudo ufw allow from 10.50.0.0/16 to any port 5432 proto tcp

### pg_hba.conf там же:
host replication replicator 10.60.0.0/24 md5
host replication replicator 10.50.0.0/24 md5

### Конфиги создания кластера выложил на github
make terraform-patroni-plan
make terraform-patroni-apply
make ansible-patroni
