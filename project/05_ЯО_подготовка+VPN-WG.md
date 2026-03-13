
 vpn-wg |	10.50.10.200   |			   |  VPN WireGuard	
 dr-ha1 |	10.50.10.31    | 10.50.10.30   |  HAproxy+keepalived
 dr-ha2 |	10.50.10.32    | 10.50.10.30   |  HAproxy+keepalived
 dr-pg1 |	10.50.10.21	   |   		       |  leader standby
 dr-pg2 |	10.50.20.21    |   		       |  replica
 ETCD1  |	10.50.10.11    |			   |  key-value store
 ETCD2  |	10.50.20.11    |			   |  key-value store
 ETCD3  |	10.50.30.11    |			   |  key-value store

## Создание и настройка Яндекс-облака
### На yandex cloud создаю сервисный аккаунт:
yandex.cloud -> Identity and Access Management -> Создать сервисный аккаунт standby-sa
### Добавляю ему роли:
1) Для создания/изменения ВМ: compute.editor
2) Для подключения через yc CLI: compute.operator
3) Для сетей: vpc.admin
4) Чтобы Ansible мог делать become: true - роль compute.osAdminLogin

### Подготовка WSL как Ansible-control-host
sudo apt update
sudo apt install -y ansible openssh-client python3 python3-venv
### Установка yc
curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash

### Подключаюсь к Яндекс.Облаку и выполняю конфигурацию окружения с помощью команды:
yc init
## Аутентификация от имени сервисного аккаунта с помощью авторизованного ключа
### Создал профиль OS Login:
yc organization-manager oslogin profile create \
  --organization-id bpfkn4kuj8b1tf2mjev4 \
  --subject-id ajevs0jp48o3b5fbsr63 \
  --login otus-sb \
  --uid 100500

### Сгенерирую ключ:
ssh-keygen -t ed25519 -f ~/.ssh/otus-sb
### Добавлю public key в профиль моего service account и в организацию:
yc organization-manager oslogin user-ssh-key create \
  --name ssh-otus-sb \
  --organization-id bpfkn4kuj8b1tf2mjev4 \
  --subject-id ajevs0jp48o3b5fbsr63 \
  --data "$(cat ~/.ssh/otus-sb.pub)"
  
### Проверка что ключ добавился:
yc organization-manager oslogin user-ssh-key list \
  --organization-id bpfkn4kuj8b1tf2mjev4 \
  --subject-id ajevs0jp48o3b5fbsr63

### В WSL создал рабочую папку проекта и файл инвентаря:
mkdir -p ~/standby-ansible
cd ~/standby-ansible
mcedit inventory.ini

[yc:vars]
ansible_connection=ssh
ansible_user=otus-sb
ansible_ssh_private_key_file=~/.ssh/otus-sb
[yc]
158.160.55.185

### Проверка связи успешна
ansible -i inventory.ini -m ping yc
158.160.55.185 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
## Создание сетей и подсетей
yc vpc network create \
  --name dr-net \
  --description "DR standby: 3AZ, patroni+etcd+proxy"
 
### Проверка
yc vpc network list
yc vpc network get dr-net

### Создаю таблицу маршрутизации в сети dr-net и добавляю маршрут:
### destination: 192.168.1.0/24
### next-hop: 10.50.10.200 (внутренний IP моей будущей VPN-WG)
yc vpc route-table create \
  --name dr-rt \
  --network-name dr-net \
  --route destination=192.168.1.0/24,next-hop=10.50.10.200
  
### Проверка
yc vpc route-table list
yc vpc route-table get dr-rt

### Создать 3 подсети по зонам и сразу привязать route table (зона С была недоступна на момент создания)
dr-a — 10.50.10.0/24 — зона ru-central1-a
dr-b — 10.50.20.0/24 — зона ru-central1-b
dr-d — 10.50.30.0/24 — зона ru-central1-d

yc vpc subnet create dr-a \
  --network-name dr-net \
  --zone ru-central1-a \
  --range 10.50.10.0/24 \
  --route-table-name dr-rt
  
yc vpc subnet create dr-b \
  --network-name dr-net \
  --zone ru-central1-b \
  --range 10.50.20.0/24 \
  --route-table-name dr-rt
  
yc vpc subnet create dr-d \
  --network-name dr-net \
  --zone ru-central1-d \
  --range 10.50.30.0/24 \
  --route-table-name dr-rt

### Создаю NAT gateway, так как часть ВМ будет без public IP, но им нужен apt update/apt install
yc vpc gateway create \
  --name dr-nat
  
yc vpc gateway list
+----------------------+--------+-------------+
|          ID          |  NAME  | DESCRIPTION |
+----------------------+--------+-------------+
| enpkq1jeaepr8fk00jqb | dr-nat |             |
+----------------------+--------+-------------+

### Добавляю default route 0.0.0.0/0 через NAT gateway (добавляются оба маршрута сразу)
### Добавляется только при уже созданной ВМ 10.50.10.200
yc vpc route-table update dr-rt \
  --route destination=192.168.1.0/24,next-hop=10.50.10.200 \
  --route destination=0.0.0.0/0,gateway-name=dr-nat
### Арендовал публичный IP адрес у яндекса

## Создание security groups

### SGs для всех ВМ
yc vpc security-group create sg-all \
  --network-name dr-net \
  --description "Common for DR VMs (VPC+onprem+internet+dns+metadata)"

### Внутри VPC (TCP/UDP любые порты)
yc vpc security-group update-rules sg-all \
  --add-rule "direction=egress,protocol=tcp,from-port=0,to-port=65535,v4-cidrs=[10.50.0.0/16]" \
  --add-rule "direction=egress,protocol=udp,from-port=0,to-port=65535,v4-cidrs=[10.50.0.0/16]"

### В on-prem (TCP/UDP любые порты)
yc vpc security-group update-rules sg-all \
  --add-rule "direction=egress,protocol=tcp,from-port=0,to-port=65535,v4-cidrs=[192.168.1.0/24]" \
  --add-rule "direction=egress,protocol=udp,from-port=0,to-port=65535,v4-cidrs=[192.168.1.0/24]"

### Интернет: 80/443 + NTP
yc vpc security-group update-rules sg-all \
  --add-rule "direction=egress,protocol=tcp,port=80,v4-cidrs=[0.0.0.0/0]" \
  --add-rule "direction=egress,protocol=tcp,port=443,v4-cidrs=[0.0.0.0/0]" \
  --add-rule "direction=egress,protocol=udp,port=123,v4-cidrs=[0.0.0.0/0]"

### DNS (внутренний DNS в подсетях YC)
yc vpc security-group update-rules sg-all \
  --add-rule "direction=egress,protocol=udp,port=53,v4-cidrs=[10.50.0.0/16]"

### Metadata service (важно для стабильной работы сервисов)
yc vpc security-group update-rules sg-all \
  --add-rule "direction=egress,protocol=tcp,port=80,v4-cidrs=[169.254.169.254/32]"

### SG sg-admin-ssh для доступа по SSH (порт 22) только из on-prem ко всем ВМ
yc vpc security-group create sg-admin-ssh \
  --network-name dr-net \
  --description "SSH from on-prem over VPN only" \
  --rule "direction=ingress,protocol=tcp,port=22,v4-cidrs=[192.168.1.0/24]" \
  --rule "direction=ingress,protocol=tcp,port=22,v4-cidrs=[212.220.***.***/32]"

### Только VPN VM, SSH с моего домашнего IP
MY_IP="$(curl -s ifconfig.me)/32"
echo "$MY_IP"
yc vpc security-group create sg-bastion-ssh \
  --network-name dr-net \
  --description "Temporary SSH to VPN VM from my public IP" \
  --rule "direction=ingress,protocol=tcp,port=22,v4-cidrs=[$MY_IP]"

### sg-vpn-wg (WireGuard на VPN VM)
ONPREM_PUB="212.220.***.***/32"
yc vpc security-group create sg-vpn-wg \
  --network-name dr-net \
  --description "WireGuard VPN endpoint + minimal transit" \
  --rule "direction=ingress,protocol=udp,port=51820,v4-cidrs=[$ONPREM_PUB]" \
  --rule "direction=ingress,protocol=tcp,port=5432,v4-cidrs=[10.50.0.0/16]"

### sg-proxy (2 proxy VM за NLB)
yc vpc security-group create sg-proxy \
  --network-name dr-net \
  --description "Proxy nodes: PgBouncer port + NLB health checks" \
  --rule "direction=ingress,protocol=tcp,port=6432,v4-cidrs=[192.168.1.0/24,10.50.0.0/16]" \
  --rule "direction=ingress,protocol=tcp,port=6432,predefined=loadbalancer_healthchecks"
  
### sg-patroni (2 patroni VM), используя id группы sg-proxy (иначе ошибка)
yc vpc security-group create sg-patroni \
  --network-name dr-net \
  --description "Patroni nodes: Postgres + Patroni REST" \
  --rule "direction=ingress,protocol=tcp,port=5432,security-group-id=enpt54korlm8v7go11bc" \
  --rule "direction=ingress,protocol=tcp,port=8008,security-group-id=enpt54korlm8v7go11bc" \
  --rule "direction=ingress,protocol=tcp,port=5432,predefined=self_security_group" \
  --rule "direction=ingress,protocol=tcp,port=8008,predefined=self_security_group"
  
### sg-etcd (3 etcd VM), используя id группы sg-patroni (иначе ошибка)
PATRONI_SG_ID="$(yc vpc security-group get sg-patroni --format json --jq .id)"
echo "$PATRONI_SG_ID"
	
yc vpc security-group create sg-etcd \
  --network-name dr-net \
  --description "etcd cluster ports (2379 client, 2380 peer)" \
  --rule "direction=ingress,protocol=tcp,port=2379,security-group-id=$PATRONI_SG_ID" \
  --rule "direction=ingress,protocol=tcp,port=2379,predefined=self_security_group" \
  --rule "direction=ingress,protocol=tcp,port=2380,predefined=self_security_group"

### Получить IDs security groups - для последующего создания ВМ
SG_ALL="$(yc vpc security-group get sg-all --format json --jq .id)"
SG_ADMIN_SSH="$(yc vpc security-group get sg-admin-ssh --format json --jq .id)"
SG_BASTION_SSH="$(yc vpc security-group get sg-bastion-ssh --format json --jq .id)"
SG_VPN_WG="$(yc vpc security-group get sg-vpn-wg --format json --jq .id)"
SG_PROXY="$(yc vpc security-group get sg-proxy --format json --jq .id)"
SG_PATRONI="$(yc vpc security-group get sg-patroni --format json --jq .id)"
SG_ETCD="$(yc vpc security-group get sg-etcd --format json --jq .id)"

### Пробное создание ВМ VPN-WG
yc compute instance create \
  --name vpn-wg \
  --zone ru-central1-a \
  --hostname vpn-wg \
  --network-interface "subnet-name=dr-a,ipv4-address=10.50.10.200,nat-ip-version=ipv4,nat-address=84.201.132.86,security-group-ids=[$SG_ALL,$SG_ADMIN_SSH,$SG_BASTION_SSH,$SG_VPN_WG]" \
  --create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts \
  --cores 2 --memory 2G \
  --metadata enable-oslogin=true \
  --metadata-from-file user-data="/mnt/d/Synodrive/otus/yc_create_user/yc_create_user.conf"
  
### Подключение успешно:
ssh -i ~/.ssh/otus-sb otus-sb@84.201.132.86

## Создание инфраструктуры с помощью Terraform

### При установке Terraform возник нюанс:
terraform is not currently available in your region
### Решение: включить зеркало провайдеров Yandex Cloud:

cat > ~/.terraformrc <<'EOF'
provider_installation {
  network_mirror {
    url     = "https://terraform-mirror.yandexcloud.net/"
    include = ["registry.terraform.io/*/*"]
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}
EOF

### Создать service account для Terraform
yc iam service-account create --name tf-sa
### выдать права на folder
FOLDER_ID="$(yc config get folder-id)"
SA_ID="$(yc iam service-account get tf-sa --format json --jq .id)"
yc resource-manager folder add-access-binding "$FOLDER_ID" \
  --role editor \
  --subject "serviceAccount:$SA_ID"
### создать ключ (json) для Terraform
yc iam key create \
  --service-account-id "$SA_ID" \
  --output key.json
  
## Terraform: подготовка
mkdir -p dr-vpn/terraform
cd dr-vpn/terraform
### Конфиги Terraform находятся в приложении к проекту
### Версия Ubuntu на всех ВМ - 24.04 характеристиками: 2 ЦПУ, 2 Гб ОЗУ, 15 ГБ network-HDD

#### Как получить свой public IP:
curl -s ifconfig.me
#### Как получить cloud-id и folder-id
yc config get cloud-id
yc config get folder-id

### Импортирование статического IP и route-table

#### Найти ID зарезервированного IP по адресу
ADDR_ID="$(yc vpc address list --format json \
  | jq -r '.[] | select(.external_ipv4_address.address=="84.201.132.86") | .id' \
  | head -n1)"
#### Импорт IP адреса
terraform import yandex_vpc_address.vpn_public "$ADDR_ID"

### Импортировать route-table dr-rt
RT_ID="$(yc vpc route-table get dr-rt --format json --jq .id)"
terraform import yandex_vpc_route_table.dr_rt "$RT_ID"

#### Автоформатировние, инициализация и валидация проекта
terraform fmt
terraform init
terraform validate
Success! The configuration is valid.

### Разворачивание VPN-WG
terraform -chdir=~/sb-proekt/terraform/environments/dr/vpn plan
terraform -chdir=~/sb-proekt/terraform/environments/dr/vpn apply

### Для удобства буду использовать Makefile
#### Его конфиг находится среди других файлов проекта
make terraform-vpn-plan
make terraform-vpn-apply
make ansible-vpn

### Подключение к VPN-WG:
ssh -i ~/.ssh/otus-sb otus-sb@84.201.132.86

## Ansible: настройка WireGuard на VPN-ВМ
### Подготовить Ansible структуру
cd $HOME
mkdir -p ansible/{inventory,group_vars,playbooks,roles/wireguard/{tasks,templates}}
### Конфиги Ansible выложены в каталоге проекта на github

#### Сеть road-warrior (клиенты)
wg_server_address: "10.60.0.1/24"
wg_clients_cidr: "10.60.0.0/24"

#### Куда клиенту разрешено ходить через VPN
wg_forward_cidrs:
  - "10.50.0.0/16"
  - "192.168.1.0/24"

#### Клиенты WireGuard
wg_clients:
  - name: laptop
    public_key: ""
    allowed_ips: "10.60.0.2/32"

### Запуск плейбука с настройкой VPN-WG
cd ~/sb-proekt
make ansible-vpn

### Подключение через WireGuard
#### На vpn-wg:
sudo cat /etc/wireguard/keys/server.key | wg pubkey
это будет <SERVER_PUBLIC_KEY>

#### В приложении WireGuard вижу PrivateKey
#### Конфиг клиента
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY_ИЗ_Windows>
Address = 10.60.0.2/32
DNS = 10.50.10.2
[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
Endpoint = 84.201.132.***:51820
AllowedIPs = 10.60.0.0/24, 10.50.0.0/16, 192.168.1.0/24
PersistentKeepalive = 25

### На ноутбуке установил клиент WireGuard, настроил в соотвествии с настройками выше, подключился.
