## cluster Patroni on-prem

 aHA1   |	192.168.1.171  | 192.168.1.170 |  HAproxy+keepalived
 aHA2   |	192.168.1.172  | 192.168.1.170 |  HAproxy+keepalived
 aPG1   |	192.168.1.181  |    		   |  leader/synchronius replica
 aPG2   |	192.168.1.182  |    		   |  leader/synchronius replica
 aPG3   |	192.168.1.183  |    		   |  asynchronius replica
 aETCD1 |	192.168.1.191  |			   |  key-value store
 aETCD2 |	192.168.1.192  |			   |  key-value store
 aETCD3 |	192.168.1.193  |			   |  key-value store

## sb-in-cloud Patroni

 vpn-wg |	10.50.10.200   |			   |  VPN WireGuard	
 dr-ha1 |	10.50.10.31    | 10.50.10.30   |  HAproxy+keepalived
 dr-ha2 |	10.50.10.32    | 10.50.10.30   |  HAproxy+keepalived
 dr-pg1 |	10.50.10.21	   |   		       |  leader standby
 dr-pg2 |	10.50.20.21    |   		       |  replica
 ETCD1  |	10.50.10.11    |			   |  key-value store
 ETCD2  |	10.50.20.11    |			   |  key-value store
 ETCD3  |	10.50.30.11    |			   |  key-value store

## Настройка коннекта между on-prem Patroni и Patroni в облаке

### Принимаю следующие решения:
1) У cloud-стендбая будет список on-prem нод, с которых он может реплицироваться: aPG1 (192.168.1.181) и aPG2 (192.168.1.182)
2) replication slot пока использовать не буду
3) Что произойдёт при аварии on-prem - облачный Patroni останется standby и будет ждать восстановления primary
4) Отставание лидер-стендбая в минуты - допустимо
5) Promotion на кластере в облаке может быть выполнен только вручную администратором
6) Пока только streaming replication, без WAL archive
	
#### Удаление существующего стендбая в облаке:
patronictl -c /etc/patroni/patroni.yml remove dr-cloud
sudo rm -rf /var/lib/postgresql/18/main
sudo mkdir -p /var/lib/postgresql/18/main
sudo chown -R postgres:postgres /var/lib/postgresql/18/main
sudo chmod 700 /var/lib/postgresql/18/main

#### В конфиг Patroni на dr-pg1 и dr-pg2 добавил секцию:
bootstrap:
  dcs:
    standby_cluster:
      host: 192.168.1.181,192.168.1.182
      port: 5432
      create_replica_methods:
        - basebackup

#### В конфигах нод облачных Patroni указал УЗ репликации:
postgresql:
  authentication:
    replication:
      username: repl_dr
      password: "123"
	  
#### На 192.168.1.181 и 192.168.1.182 (лидер и стендбай on-prem) добавил правила: 
sudo ufw allow from 10.60.0.0/24 to any port 5432 proto tcp 
sudo ufw allow from 10.50.0.0/16 to any port 5432 proto tcp

#### В конфиг pg_hba.conf на aPG1 и aPG2, dr-pg1 и dr-pg2 добавил секцию:
postgresql:
  pg_hba:
    - "host replication repl_dr 10.50.0.0/16 scram-sha-256"
    - "host all all 10.50.0.0/16 scram-sha-256" 

### Пробный старт Patroni на dr-pg1 (лидер-стендбае) неудачен:

2026-03-12 16:58:10 INFO [patroni.__main__] no action. I am (dr-pg1), the standby leader with the lock
2026-03-12 16:58:14 INFO [patroni.ha] Lock owner: dr-pg1; I am dr-pg1
2026-03-12 16:58:14 INFO [patroni.postgresql.rewind] Local timeline=37 lsn=1/AC2BDD98
2026-03-12 16:58:20 ERROR [patroni.postgresql.rewind] Exception when working with leader
Traceback (most recent call last):
  File "/usr/lib/python3/dist-packages/patroni/postgresql/rewind.py", line 82, in check_leader_is_not_in_recovery
    with get_connection_cursor(connect_timeout=3, options='-c statement_timeout=2000', **conn_kwargs) as cur:
  File "/usr/lib/python3.12/contextlib.py", line 137, in __enter__
    return next(self.gen)
           ^^^^^^^^^^^^^^
  File "/usr/lib/python3/dist-packages/patroni/postgresql/connection.py", line 158, in get_connection_cursor
    conn = psycopg.connect(**kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3/dist-packages/patroni/psycopg.py", line 136, in connect
    ret = _connect(*args, **kwargs)
          ^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3/dist-packages/psycopg2/__init__.py", line 122, in connect
    conn = _connect(dsn, connection_factory=connection_factory, **kwasync)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
psycopg2.OperationalError: connection to server at "192.168.1.181", port 5432 failed: timeout expired
connection to server at "192.168.1.182", port 5432 failed: timeout expired

#### Причина - нет коннекта по 5432 порту:
otus-sb@dr-pg1:~$ telnet 192.168.1.181 5432
Trying 192.168.1.181...
telnet: Unable to connect to remote host: Connection timed out
otus-sb@dr-pg2:~$ telnet 192.168.1.181 5432
Trying 192.168.1.181...
telnet: Unable to connect to remote host: Connection timed out

#### Проверка маршрутизации
otus-sb@dr-pg1:~$ ip route get 192.168.1.181
192.168.1.181 via 10.50.10.1 dev eth0 src 10.50.10.21 uid 1000
otus-sb@dr-pg1:~$ traceroute -n 192.168.1.181
traceroute to 192.168.1.181 (192.168.1.181), 30 hops max, 60 byte packets
 1  10.50.10.1  0.371 ms  0.347 ms  0.348 ms
 2  * * *
 3  * * *
 4  * * *
 5  * * *
#### В ЯО отсутствует маршрут до сети on-prem 192.168.1.0/24. Поэтому пакеты даже не доходят до vpn-wg.
#### Требуется апдейт таблицы маршрутизации в ЯО:
yc vpc route-table update dr-to-onprem \
  --route destination=192.168.1.0/24,next-hop=10.50.10.200 \
  --route destination=10.60.0.0/24,next-hop=10.50.10.200
  
#### Коннекта по-прежнему нет:
otus-sb@dr-pg1:~$ nc -vz -w 2 192.168.1.181 5432
nc: connect to 192.168.1.181 port 5432 (tcp) timed out: Operation now in progress

#### Выполнил апдейт правил:

yc vpc security-group update-rules enpu***8vfqfr4 \
  --add-rule "direction=egress,protocol=tcp,v4-cidrs=[192.168.1.0/24],from-port=5432,to-port=5432"
yc vpc security-group update-rules enp0006***67p \
  --add-rule "direction=ingress,protocol=tcp,v4-cidrs=[10.50.0.0/16],from-port=5432,to-port=5432"

#### route-table работает, SG-правила начали пропускать, дальше проблема на уровне транзита через vpn-wg -> WireGuard -> on-prem.
otus-sb@vpn-wg:~$ sudo tcpdump -ni eth0 "host 192.168.1.181 and tcp port 5432"
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
13:12:47.798382 IP 10.50.10.21.45492 > 192.168.1.181.5432: Flags [S], seq 974587943, win 64240, options [mss 1460,sackOK,TS val 1617746387 ecr 0,nop,wscale 7], length 0
13:12:47.798422 IP 10.50.10.21.45492 > 192.168.1.181.5432: Flags [S], seq 974587943, win 64240, options [mss 1460,sackOK,TS val 1617746387 ecr 0,nop,wscale 7], length 0
13:12:47.798975 IP 10.50.10.21.45492 > 192.168.1.181.5432: Flags [S], seq 974587943, win 64240, options [mss 1460,sackOK,TS val 1617746387 ecr 0,nop,wscale 7], length 0

#### включил роутинг на vpn-wg (почему раньше это не сделал?):
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.all.rp_filter=0
sudo sysctl -w net.ipv4.conf.default.rp_filter=0
#### Разрешил форвардинг:
sudo iptables -A FORWARD -i eth0 -o wg0 -s 10.50.0.0/16 -d 192.168.1.0/24 -j ACCEPT
sudo iptables -A FORWARD -i wg0 -o eth0 -s 192.168.1.0/24 -d 10.50.0.0/16 -j ACCEPT

#### Ответа (SYN-ACK) нет вообще — в дампе только SYN. Значит, проблема уже на on-prem стороне: пакет либо не принимается/не доставляется до 192.168.1.181, либо доставка есть, но обратный путь/фильтрация рвут ответ:
otus-sb@vpn-wg:~$ sudo tcpdump -ni wg0 "host 192.168.1.181 and tcp port 5432"
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on wg0, link-type RAW (Raw IP), snapshot length 262144 bytes
13:53:04.216105 IP 10.50.10.21.34906 > 192.168.1.181.5432: Flags [S], seq 3484222161, win 64240, options [mss 1460,sackOK,TS val 1620162805 ecr 0,nop,wscale 7], length 0
13:53:05.232814 IP 10.50.10.21.34906 > 192.168.1.181.5432: Flags [S], seq 3484222161, win 64240, options [mss 1460,sackOK,TS val 1620163823 ecr 0,nop,wscale 7], length 0
13:53:24.643421 IP 10.50.10.21.45376 > 192.168.1.181.5432: Flags [S], seq 3726116173, win 64240, options [mss 1460,sackOK,TS val 1620183233 ecr 0,nop,wscale 7], length 0
13:53:25.648976 IP 10.50.10.21.45376 > 192.168.1.181.5432: Flags [S], seq 3726116173, win 64240, options [mss 1460,sackOK,TS val 1620184239 ecr 0,nop,wscale 7], length 0
4 packets captured
4 packets received by filter
0 packets dropped by kernel
otus-sb@vpn-wg:~$ ip route get 192.168.1.181
192.168.1.181 dev wg0 src 10.60.0.1 uid 1000

#### Прописал NAT на vpn-wg
sudo iptables -t nat -A POSTROUTING -s 10.50.0.0/16 -d 192.168.1.0/24 -o wg0 -j MASQUERADE

#### Заработал маршрут облако -> vpn-wg -> wg0
otus-sb@vpn-wg:~$ sudo tcpdump -ni wg0 "host 192.168.1.181 and tcp port 5432"
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on wg0, link-type RAW (Raw IP), snapshot length 262144 bytes
14:18:28.770693 IP 10.60.0.1.43490 > 192.168.1.181.5432: Flags [S], seq 2251680531, win 64240, options [mss 1460,sackOK,TS val 1621687358 ecr 0,nop,wscale 7], length 0
14:18:29.779538 IP 10.60.0.1.43490 > 192.168.1.181.5432: Flags [S], seq 2251680531, win 64240, options [mss 1460,sackOK,TS val 1621688367 ecr 0,nop,wscale 7], length 0
#### Но до aPG1 (192.168.1.181) пакеты не доходят.
#### Windows, на которой работает мой on-prem кластер, не маршрутизирует трафик из WireGuard в LAN
otus@apg1:~$ sudo timeout 15 tcpdump -ni any "tcp port 5432 and (host 10.50.10.21 or host 10.60.0.1)"
tcpdump: data link type LINUX_SLL2
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on any, link-type LINUX_SLL2 (Linux cooked v2), snapshot length 262144 bytes
0 packets captured
2 packets received by filter
0 packets dropped by kernel

#### Оказалось, что в клиенте WireGuard на Windows была прописана подсеть 192.168.1.0/24. Убрал её
[Peer]
PublicKey = ***
AllowedIPs = 10.60.0.0/24, 10.50.0.0/16, 192.168.1.0/24
Endpoint = 84.201.132.86:51820
PersistentKeepalive = 25

#### Плюс необходим маршрут на on-prem кластере (192.168.1.63 - ip Windows хоста, на котором работает мой on-prem кластер): 
sudo ip route add 10.60.0.0/24 via 192.168.1.63
#### Коннект появился!!
otus-sb@dr-pg1:~$ nc -vz -w 2 192.168.1.181 5432
Connection to 192.168.1.181 5432 port [tcp/postgresql] succeeded!

### Снова стартовал службу Patroni на dr-pg1 
#### Контроль:
sudo systemctl start patroni
sudo journalctl -u patroni -f
patronictl -c /etc/patroni/patroni.yml list
### Должна появиться роль Standby Leader
#### Однако ошибки:
Mar 09 08:40:26 dr-pg1 systemd[1]: Started patroni.service - Patroni PostgreSQL High Availability. 
Mar 09 08:40:32 dr-pg1 patroni[20657]: 2026-03-09 13:40:32.334 +05 [20657] LOG: invalid value for parameter "lc_messages": "ru_RU.UTF-8" 
Mar 09 08:40:32 dr-pg1 patroni[20657]: 2026-03-09 13:40:32.334 +05 [20657] LOG: invalid value for parameter "lc_monetary": "ru_RU.UTF-8" 
Mar 09 08:40:32 dr-pg1 patroni[20657]: 2026-03-09 13:40:32.334 +05 [20657] LOG: invalid value for parameter "lc_numeric": "ru_RU.UTF-8" 
Mar 09 08:40:32 dr-pg1 patroni[20657]: 2026-03-09 13:40:32.334 +05 [20657] LOG: invalid value for parameter "lc_time": "ru_RU.UTF-8" 
Mar 09 08:40:32 dr-pg1 patroni[20657]: 2026-03-09 13:40:32.334 +05 [20657] FATAL: configuration file "/var/lib/postgresql/18/patroni/postgresql.base.conf" contains errors

#### Причина - на dr-pg1 отсутствует локаль ru_RU.UTF-8
#### Исправление:
sudo apt-get update
sudo apt-get install -y locales
sudo locale-gen ru_RU.UTF-8

#### Удаляю существующий стендбай в облаке:
patronictl -c /etc/patroni/patroni.yml remove dr-cloud
sudo rm -rf /var/lib/postgresql/18/main
sudo mkdir -p /var/lib/postgresql/18/main
sudo chown -R postgres:postgres /var/lib/postgresql/18/main
sudo chmod 700 /var/lib/postgresql/18/main

#### И стартую службу
sudo systemctl start patroni

### Стартую dr-pg2 - он должен клонироваться с dr-pg1
### И снова проверки:
sudo systemctl start patroni
sudo journalctl -u patroni -f

### После добавления локали postgresql стартовал с предупреждениями:
### Связаны они с тем, что на on-prem кластере стоит ОС Astra, а в облаке - ОС Ubuntu, а точнее - из-за разности версий библиотеки glibc

Mar 09 09:05:03 dr-pg1 patroni[21244]: localhost:5432 - no response
Mar 09 09:05:03 dr-pg1 patroni[21243]: 2026-03-09 14:05:03.869 +05 [21243] СООБЩЕНИЕ:  передача вывода в протокол процессу сбора протоколов
Mar 09 09:05:03 dr-pg1 patroni[21243]: 2026-03-09 14:05:03.869 +05 [21243] ПОДСКАЗКА:  В дальнейшем протоколы будут выводиться в каталог "/var/log/postgresql".
Mar 09 09:05:04 dr-pg1 patroni[21253]: ПРЕДУПРЕЖДЕНИЕ:  несовпадение версии для правила сортировки в базе данных "postgres"
Mar 09 09:05:04 dr-pg1 patroni[21253]: DETAIL:  База данных была создана с версией правила сортировки 2.36, но операционная система предоставляет версию 2.39.
Mar 09 09:05:04 dr-pg1 patroni[21253]: HINT:  Перестройте все объекты в этой базе, задействующие основное правило сортировки, и выполните ALTER DATABASE postgres REFRESH COLLATION VERSION, либо соберите PostgreSQL с правильной версией библиотеки.
Mar 09 09:05:04 dr-pg1 patroni[21253]: localhost:5432 - accepting connections

### Стартовал сервис Patroni на реплике dr-pg2

postgres@dr-pg2:~$ patronictl -c /etc/patroni/patroni.yml list
+ Cluster: dr-cloud (7605590651610384754) ----------+----+-------------+-----+------------+-----+-----------------+---------------------------+
| Member | Host        | Role           | State     | TL | Receive LSN | Lag | Replay LSN | Lag | Pending restart | Pending restart reason    |
+--------+-------------+----------------+-----------+----+-------------+-----+------------+-----+-----------------+---------------------------+
| dr-pg1 | 10.50.10.21 | Standby Leader | streaming | 35 |             |     |            |     | *               | max_connections: 500->100 |
| dr-pg2 | 10.50.20.21 | Replica        | running   | 35 |  1/3E000000 |  32 | 1/3E000060 |  32 | *               | max_connections: 500->100 |
+--------+-------------+----------------+-----------+----+-------------+-----+------------+-----+-----------------+---------------------------+

#### Почему запланировано изменение параметра max_connections: 500->100 ? Ведь у меня на on-prem выставлено max_connections: 500
#### Причина в том, что в bootstrap.dcs.postgresql.parameters не зафиксирован этот параметр, и срртветственно применяется значение по умолчанию: max_connections: 100
#### Прописал корректное значение параметра max_connections: 500 и вновь запустил сервис Patroni

postgres@dr-pg1:~$  patronictl -c /etc/patroni/patroni.yml list
+ Cluster: dr-cloud (7605590651610384754) ----------+----+-------------+-----+------------+-----+
| Member | Host        | Role           | State     | TL | Receive LSN | Lag | Replay LSN | Lag |
+--------+-------------+----------------+-----------+----+-------------+-----+------------+-----+
| dr-pg1 | 10.50.10.21 | Standby Leader | running   | 37 |             |     |            |     |
| dr-pg2 | 10.50.20.21 | Replica        | streaming | 37 |  1/AC2BDD98 |   0 | 1/AC2BDD98 |   0 |
+--------+-------------+----------------+-----------+----+-------------+-----+------------+-----+
Успех!
