 aHA1     |	192.168.1.171  | 192.168.1.170 |  HAproxy+keepalived
 aHA2     |	192.168.1.172  | 192.168.1.170 |  HAproxy+keepalived
 aPG1     |	192.168.1.181  |    		       |  leader/synchronius replica
 aPG2     |	192.168.1.182  |    		       |  leader/synchronius replica
 aPG3     |	192.168.1.183  |    		       |  asynchronius replica
 aETCD1 |	192.168.1.191  |			   |  key-value store
 aETCD2 |	192.168.1.192  |			   |  key-value store
 aETCD3 |	192.168.1.193  |			   |  key-value store

### Задача: развернуть 8 виртуалок в VirtualBOX с ОС Astra SE "Воронеж" для создания на них кластера ETCD, кластера Patroni и HAProxy
Установка ОС Astra SE "Воронеж" производилась с технологического установочного диска installation-1.8.4.48-30.10.25_09.18.iso
Первоначально был создан шаблон Astra1, который затем 7 раз клонировался
Виртуалкам aETCD1, aETCD2, aETCD3, aHA1, aHA2 были выданы ресурсы 1 ЦПУ, 1 Гб ОЗУ, 20 ГБ HDD.
Виртуалкам aPG1, aPG2, aPG3 были выданы ресурсы 1 ЦПУ, 2 Гб ОЗУ, 20 ГБ HDD.
При установке ОС Astra предупреждала, что объема 2 Гб ОЗУ мало для корректной работы, но в дальнейшем проблем не возникло.
Скриншоты процесса установки прикладываю. 

