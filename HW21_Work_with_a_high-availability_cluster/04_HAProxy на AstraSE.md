
 aHA1   |	192.168.1.171  | 192.168.1.170 |  HAproxy+keepalived
 aHA2   |	192.168.1.172  | 192.168.1.170 |  HAproxy+keepalived
 aPG1   |	192.168.1.181  |   		       |  leader/synchronius replica
 aPG2   |	192.168.1.182  |   		       |  leader/synchronius replica
 aPG3   |	192.168.1.183  |   		       |  asynchronius replica
 aETCD1 |	192.168.1.191  |			   |  key-value store
 aETCD2 |	192.168.1.192  |			   |  key-value store
 aETCD3 |	192.168.1.193  |			   |  key-value store

## Установка и конфигурирование HAproxy
### Какая версия доступна в apt?
	sudo apt update
	apt show haproxy
Version: 2.6.23-1astra4
### Хочу версию 3.2, от 2025-05-28: https://www.haproxy.org/

sudo install -d -m 0755 /usr/share/keyrings
sudo wget -qO /usr/share/keyrings/HAPROXY-key-community.asc \
  https://pks.haproxy.com/linux/community/RPM-GPG-KEY-HAProxy

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/HAPROXY-key-community.asc] \
https://www.haproxy.com/download/haproxy/performance/debian/ha32 bookworm main" \
| sudo tee /etc/apt/sources.list.d/haproxy.list

sudo apt update
sudo apt install haproxy-awslc

sudo haproxy -v
HAProxy version 3.2.12-0+ha32+deb12u1

### Установка keepalived

sudo apt update
sudo apt install keepalived
sudo keepalived --version
Keepalived v2.2.7 (01/16,2022)

### Настройка HAProxy
#### под root на aHA1 и aHA2:
systemctl stop haproxy
#### Конфиг HAProxy
cat > /etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms
    retries 3
    option redispatch
    timeout check 5000ms

#### Статистика HAProxy
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /monitor
    stats refresh 5s
    stats auth admin:password

#### Бэкенд для записи - ТОЛЬКО лидер
backend postgres_write
    mode tcp
    balance first
    option tcp-check
    tcp-check connect port 5432
    server apg1 192.168.1.181:5432 check inter 2s fall 3 rise 2
    server apg2 192.168.1.182:5432 check inter 2s fall 3 rise 2 backup

#### Бэкенд для чтения - реплики
backend postgres_read
    mode tcp
    balance leastconn
    option tcp-check
    tcp-check connect port 5432
    server apg1 192.168.1.181:5432 check inter 2s fall 3 rise 2 weight 100
    server apg2 192.168.1.182:5432 check inter 2s fall 3 rise 2 weight 100

#### Бэкенд для мониторинга состояния всех нод
backend postgres_monitoring
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 5432
    server apg1 192.168.1.181:5432 check inter 5s fall 2 rise 1
    server apg2 192.168.1.182:5432 check inter 5s fall 2 rise 1
    server apg3 192.168.1.183:5432 check inter 5s fall 2 rise 1

#### Фронтенд для операций записи
frontend postgres_write_frontend
    bind *:5432
    mode tcp
    option tcplog
    default_backend postgres_write

#### Фронтенд для операций чтения
frontend postgres_read_frontend
    bind *:5433
    mode tcp
    option tcplog
    default_backend postgres_read

#### Фронтенд для мониторинга
frontend postgres_monitor
    bind *:5434
    mode tcp
    option tcplog
    default_backend postgres_monitoring

#### Фронтенд для администрирования
frontend postgres_admin
    bind *:5435
    mode tcp
    option tcplog
    default_backend postgres_write
EOF

#### проверил, что установлен пакет psmisc для killall
#### установил apt install tcpdump
#### Для того чтобы выбор мастера происходил корректно, необходимо прописать в конфиге отправку VRRP-объявлений не один-группе (multicast), а один-одному (unicast)
#### Иначе (если фаервол включен) VRRP-объявления блокируются, узлы не видят друг друга, и каждый думает "сосед умер" → оба становились MASTER (split-brain).
root@aha1:/home/otus# sudo systemctl status keepalived
фев 19 14:47:26 aha1 Keepalived_vrrp[7511]: (VI_1) Entering MASTER STATE
root@aha2:/home/otus# systemctl status keepalived
фев 19 14:47:41 aha2 Keepalived_vrrp[5841]: (VI_1) Entering MASTER STATE
#### Секция global defs необходима для устранения проблемы безопасности:
фев 19 13:36:15 aha1 Keepalived_vrrp[3894]: Script user 'keepalived_script' does not exist
фев 19 13:36:15 aha1 Keepalived_vrrp[3894]: SECURITY VIOLATION - scripts are being executed but script_security not enabled.

#### Корректный конфиг keepalived на MASTER-ноде aHA1 (192.168.1.171)
#### /etc/keepalived/keepalived.conf:

cat > /etc/keepalived/keepalived.conf <<EOF
global_defs {
    script_user root
    enable_script_security
}
vrrp_script chk_haproxy {
    script "/usr/bin/killall -0 haproxy"  #### Проверка что процесс существует
    interval 2
    weight 2
    fall 2
    rise 2
}
vrrp_instance VI_1 {
    state MASTER
    interface enp0s3
    virtual_router_id 51
    priority 101    #### Выше чем у BACKUP
    advert_int 1
    unicast_src_ip 192.168.1.171
    unicast_peer {
        192.168.1.172
    }
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress {
        192.168.1.170/24 dev enp0s3
    }
    track_script {
        chk_haproxy
    }
    #### Уведомления для логирования
    notify "/etc/keepalived/notify.sh"
}
EOF

#### Корректный конфиг keepalived на BACKUP-ноде aHA2 (192.168.1.172)
#### /etc/keepalived/keepalived.conf:

cat > /etc/keepalived/keepalived.conf <<EOF

global_defs {
    script_user root
    enable_script_security
}
vrrp_script chk_haproxy {
    script "/usr/bin/killall -0 haproxy"
    interval 2
    weight 2
    fall 2
    rise 2
}
vrrp_instance VI_1 {
    state BACKUP
    interface enp0s3
    virtual_router_id 51
    priority 100    # Ниже чем у MASTER
    advert_int 1
    unicast_src_ip 192.168.1.172
    unicast_peer {
      192.168.1.171
    }
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress {
        192.168.1.170/24 dev enp0s3 
    }
    track_script {
        chk_haproxy
    }
    notify "/etc/keepalived/notify.sh"
}
EOF

#### Универсальный скрипт уведомлений /etc/keepalived/notify.sh (одинаковый на обеих нодах):

cat > /etc/keepalived/notify.sh <<EOF
#!/bin/bash
TYPE=$1
NAME=$2
STATE=$3
log_message() {
    echo "$(date): $1" >> /var/log/keepalived-notifications.log
    logger -t keepalived "$1"
}
case $STATE in
    "MASTER")
        log_message "Переход в состояние MASTER на $HOSTNAME. VIP 192.168.1.170 активирован."
        #### Убедимся что HAProxy запущен
        systemctl is-active --quiet haproxy || systemctl start haproxy
        ;;
    "BACKUP")
        log_message "Переход в состояние BACKUP на $HOSTNAME. VIP 192.168.1.170 деактивирован."
        #### НЕ останавливаем HAProxy - он должен быть готов принять роль
        ;;
    "FAULT")
        log_message "Переход в состояние FAULT на $HOSTNAME. Проблема с сервисом."
        #### В состоянии fault можно остановить HAProxy
        systemctl stop haproxy
        ;;
    *)
        log_message "Неизвестное состояние: $STATE"
        ;;
esac
EOF

#### Делаем исполняемым
sudo chmod +x /etc/keepalived/notify.sh
chown root:root /etc/keepalived/notify.sh
chmod 755 /etc/keepalived/notify.sh

Открыть порты на aHA1, aHA2:
sudo ufw allow 5432,5433,5434,5435,8404,8405/tcp

#### Разрешить протокол VRRP только между HA нодами
sudo ufw allow from 192.168.1.171 to 192.168.1.172 proto vrrp
sudo ufw allow from 192.168.1.172 to 192.168.1.171 proto vrrp

#### Включение автозапуска
sudo systemctl enable keepalived
sudo systemctl enable haproxy

#### На обеих нодах:
#### Запуск
sudo systemctl start haproxy
sudo systemctl start keepalived

#### Проверка статуса
sudo systemctl status keepalived
sudo systemctl status haproxy

### Проверка работоспособности HAProxy + keepalived
#### 1) Проверка статуса сервисов 
#### На обеих нодах:
sudo systemctl status haproxy --no-pager | grep "Active:"
sudo systemctl status keepalived --no-pager | grep "Active:"
	Active: active (running) since Fri 2026-03-13 15:40:29 +05; 3h 28min ago
    Active: active (running) since Fri 2026-03-13 15:15:53 +05; 3h 53min ago

#### 2) Проверка VIP распределения
#### На aHA1:
echo "aHA1: $(ip addr show | grep -q 192.168.1.170 && echo 'MASTER' || echo 'BACKUP')"
	HA1: MASTER
#### На aHA2:  
echo "aHA2: $(ip addr show | grep -q 192.168.1.170 && echo 'MASTER' || echo 'BACKUP')"
	HA2: BACKUP

### Приложил видео проверки отказоустойчивости кластера
