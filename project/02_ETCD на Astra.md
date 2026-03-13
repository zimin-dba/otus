
 HA1   |	192.168.1.171  | 192.168.1.170 |  HAproxy+keepalived
 HA2   |	192.168.1.172  | 192.168.1.170 |  HAproxy+keepalived
 PG1   |	192.168.1.181  |    		   |  leader/synchronius replica
 PG2   |	192.168.1.182  |    		   |  leader/synchronius replica
 PG3   |	192.168.1.183  |    		   |  asynchronius replica
 ETCD1 |	192.168.1.191  |			   |  key-value store
 ETCD2 |	192.168.1.192  |			   |  key-value store
 ETCD3 |	192.168.1.193  |			   |  key-value store

## Установка и конфигурирование ETCD ===============
sudo apt update

### Какие репозитории доступны:
#### предпочтительнее устанавливать из "frozen" репозиториев, так как репозиторий stable — движущийся. Сегодня он может указывать на одно оперативное обновление, а позже — на следующее. Но у меня в пути /astra/stable/1.8_x86-64 четко зафиксирована версия 1.8, так что норм.
otus@atemplate:~$ cat /etc/apt/sources.list
deb https://download.astralinux.ru/astra/stable/1.8_x86-64/repository-extended/ 1.8_x86-64 main contrib non-free non-free-firmware
deb https://download.astralinux.ru/astra/stable/1.8_x86-64/repository-main/ 1.8_x86-64 main contrib non-free non-free-firmware
#deb cdrom:[OS Astra Linux 1.8.4.48 1.8_x86-64 DVD]/ 1.8_x86-64 contrib main non-free non-free-firmware

sudo apt install -y etcd-server etcd-client

### Проверка (на ubuntu ставил версию 3.6, ну да ладно):
etcd --version
etcd Version: 3.5.16

### Служба etcd уже стартована:
sudo systemctl status etcd
### Её листинг
systemctl cat etcd

sudo ufw allow 2379
sudo ufw allow 2380
sudo systemctl stop etcd

### Заменяю конфиг службы etcd на этот:
### Увеличил таймаут TimeoutStartSec=180 на всякий случай, чтобы у службы была возможность дольше ждать старта других ETCD-нод

[Unit]
Description=etcd key-value store
Documentation=https://etcd.io/docs
After=network-online.target
Wants=network-online.target

[Service]
User=etcd
Type=notify
Environment=ETCD_DATA_DIR=/var/lib/etcd/p-cluster
EnvironmentFile=-/etc/etcd/etcd.conf
ExecStart=/usr/bin/etcd
Restart=on-failure
RestartSec=10s
TimeoutStartSec=180
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target

### Проверяю, что служба работоспособна
sudo systemctl daemon-reload
sudo systemctl start etcd
sudo systemctl status etcd

### Создание конфигов etcd на каждой ноде
####1
cat > /etc/etcd/etcd.conf <<EOF
ETCD_NAME="aetcd1"
ETCD_DATA_DIR="/var/lib/etcd/p-cluster"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://192.168.1.191:2380"
ETCD_INITIAL_CLUSTER="aetcd1=http://192.168.1.191:2380,aetcd2=http://192.168.1.192:2380,aetcd3=http://192.168.1.193:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="p-cluster"
ETCD_ADVERTISE_CLIENT_URLS="http://192.168.1.191:2379"
ETCD_ELECTION_TIMEOUT="10000"
ETCD_HEARTBEAT_INTERVAL="2000"
EOF

####2
cat > /etc/etcd/etcd.conf <<EOF
ETCD_NAME="aetcd2"
ETCD_DATA_DIR="/var/lib/etcd/p-cluster"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://192.168.1.192:2380"
ETCD_INITIAL_CLUSTER="aetcd2=http://192.168.1.191:2380,aetcd2=http://192.168.1.192:2380,aetcd3=http://192.168.1.193:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="p-cluster"
ETCD_ADVERTISE_CLIENT_URLS="http://192.168.1.192:2379"
ETCD_ELECTION_TIMEOUT="10000"
ETCD_HEARTBEAT_INTERVAL="2000"
EOF

####3
cat > /etc/etcd/etcd.conf <<EOF
ETCD_NAME="aetcd3"
ETCD_DATA_DIR="/var/lib/etcd/p-cluster"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:2379"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://192.168.1.193:2380"
ETCD_INITIAL_CLUSTER="aetcd1=http://192.168.1.191:2380,aetcd2=http://192.168.1.192:2380,aetcd3=http://192.168.1.193:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="p-cluster"
ETCD_ADVERTISE_CLIENT_URLS="http://192.168.1.193:2379"
ETCD_ELECTION_TIMEOUT="10000"
ETCD_HEARTBEAT_INTERVAL="2000"
EOF

### Проверка кластера ETCD
### Подготовка переменных (API v3)
export ETCDCTL_API=3
ENDPOINTS="http://192.168.1.191:2379,http://192.168.1.192:2379,http://192.168.1.193:2379"

### Health-check всех нод
etcdctl --endpoints="$ENDPOINTS" endpoint health --cluster

### Статус всех нод “таблицей”
etcdctl --endpoints="$ENDPOINTS" endpoint status -w table --cluster

### Членство в кластере
etcdctl --endpoints="$ENDPOINTS" member list -w table

### Проверка “нет ли скрытых проблем” (alarms)
etcdctl --endpoints="$ENDPOINTS" alarm list

### Проверка согласованности данных (KV hash)
### Это один из самых полезных тестов: показывает, что история KV на узлах совпадает.
etcdctl --endpoints="$ENDPOINTS" endpoint hashkv --cluster

#### Выводит только самое важное: число нод, имена, лидер
#### показывает:
#### members= — сколько в кластере по конфигурации
#### alive= — сколько сейчас реально отвечают
#### names= — имена всех членов
#### leader= — кто лидер среди живых
#### down= — кто не отвечает
ENDPOINTS="http://192.168.1.191:2379,http://192.168.1.192:2379,http://192.168.1.193:2379"; ETCDCTL_API=3 awk -F', *' 'NR==FNR{m++;id[m]=$1;nm[$1]=$3;next} {a++;up[nm[$2]]=1} $5=="true"{L=nm[$2]} END{printf "members=%d alive=%d names=",m,a; for(i=1;i<=m;i++) printf "%s%s",nm[id[i]],(i<m?",":""); printf " leader=%s", (L?L:"?"); d=""; for(i=1;i<=m;i++){n=nm[id[i]]; if(!up[n]) d=(d?d","n:n)} if(d) printf " down=%s", d; print ""}' <(etcdctl --endpoints="$ENDPOINTS" member list -w simple 2>/dev/null) <( (etcdctl --endpoints="$ENDPOINTS" endpoint status -w simple --cluster 2>/dev/null || true) )
