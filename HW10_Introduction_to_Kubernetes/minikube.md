
### Действую по доке https://minikube.sigs.k8s.io/docs/start/?arch=%2Fwindows%2Fx86-64%2Fstable%2F.exe+download
### Установил minikube на Windows, прописал переменные в Path:
$oldPath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::Machine)
if ($oldPath.Split(';') -inotcontains 'C:\minikube'){
  [Environment]::SetEnvironmentVariable('Path', $('{0};C:\minikube' -f $oldPath), [EnvironmentVariableTarget]::Machine)
}

### Попытка стартовать его:
minikube start
### Minicube сам выбрал драйвер hyperv, но вылетел с ошибкой:
Exiting due to PR_HYPERV_MODULE_NOT_INSTALLED: Failed to start host: creating host: create: precreate: Hyper-V PowerShell Module is not available
Failed to start virtualbox VM. Running "minikube delete" may fix it

### Что ж, варианты с hyperv и virtualbox не взлетели, выбираю использовать Docker Desktop на Windows
### Устанавливал по официальной доке: https://docs.docker.com/desktop/setup/install/windows-install/
### После установки включил интеграцию со своей WSL 2 здесь: Settings - Resources - WSL Integration, думаю, это будет удобно - иметь доступ к Docker-контейнерам из WSL
### Создал манифест postgres.yaml

### Применил манифест
cd ~/minikube
minikube.exe kubectl -- apply -f postgres.yaml



serq@Note3:~/minikube$ minikube.exe kubectl -- apply -f postgres.yaml
deployment.apps/postgres created
service/postgres created
serq@Note3:~/minikube$ minikube.exe kubectl -- get deployment
NAME       READY   UP-TO-DATE   AVAILABLE   AGE
postgres   0/1     1            0           3m21s
serq@Note3:~/minikube$ minikube.exe kubectl -- get pods -o wide
NAME                        READY   STATUS   RESTARTS      AGE     IP           NODE       NOMINATED NODE   READINESS GATES
postgres-69487c65cf-h2vvz   0/1     Error    4 (79s ago)   3m25s   10.244.0.3   minikube   <none>           <none>
serq@Note3:~/minikube$ minikube.exe kubectl -- get deployment
NAME       READY   UP-TO-DATE   AVAILABLE   AGE
postgres   0/1     1            0           2m5s
serq@Note3:~/minikube$ minikube.exe kubectl -- logs deployment/postgres
Error: Database is uninitialized and superuser password is not specified.
       You must specify POSTGRES_PASSWORD to a non-empty value for the
       superuser. For example, "-e POSTGRES_PASSWORD=password" on "docker run".

       You may also use "POSTGRES_HOST_AUTH_METHOD=trust" to allow all
       connections without a password. This is *not* recommended.

       See PostgreSQL documentation about "trust":
       https://www.postgresql.org/docs/current/auth-trust.html

### Как оказалось, необходимо указывать переменную POSTGRES_PASSWORD именно с таким именем (у меня было другое)
### Изменил манифест, применил его:
minikube.exe kubectl -- apply -f postgres.yaml
### PostgreSQL 18 поднялся:
minikube.exe kubectl -- get pods -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE       NOMINATED NODE   READINESS GATES
postgres-7977cb9f4-kbjvh   1/1     Running   0          98s   10.244.0.4   minikube   <none>           <none>

minikube.exe kubectl -- logs deployment/postgres
2026-03-15 09:37:59.927 UTC [1] LOG:  starting PostgreSQL 18.3 (Debian 18.3-1.pgdg13+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
2026-03-15 09:37:59.929 UTC [1] LOG:  listening on IPv4 address "0.0.0.0", port 5432
2026-03-15 09:37:59.929 UTC [1] LOG:  listening on IPv6 address "::", port 5432
2026-03-15 09:37:59.935 UTC [1] LOG:  listening on Unix socket "/var/run/postgresql/.s.PGSQL.5432"
2026-03-15 09:37:59.945 UTC [74] LOG:  database system was shut down at 2026-03-15 09:37:59 UTC
2026-03-15 09:37:59.952 UTC [1] LOG:  database system is ready to accept connections

### Пробросил порт:
minikube.exe kubectl -- port-forward service/postgres 5432:5432
Forwarding from 127.0.0.1:5432 -> 5432
Forwarding from [::1]:5432 -> 5432

### Пробую подключиться:
PG_PASSWORD=pass123 psql -h 127.0.0.1 -p 5432 -U pguser -d pgdb
psql: error: connection to server at "127.0.0.1", port 5432 failed: Connection refused
        Is the server running on that host and accepting TCP/IP connections?

### Тут необходимо узнать IP адрес хоста
ip route show
default via 172.22.128.1 dev eth0 proto kernel
### Подключение успешно:
PGPASSWORD=pass123 psql -h 172.22.128.1 -p 5432 -U pguser -d pgdb
psql (16.13 (Ubuntu 16.13-0ubuntu0.24.04.1), server 18.3 (Debian 18.3-1.pgdg13+1))
WARNING: psql major version 16, server major version 18.
         Some psql features might not work.
Type "help" for help.

pgdb=#

### Добавил ещё 2 пода:
minikube.exe kubectl -- scale deployment/postgres --replicas=3
deployment.apps/postgres scaled

PGPASSWORD=pass123 psql -h 172.22.128.1 -p 5432 -U pguser -d pgdb -c "select version();"
                                                      version                                                       
--------------------------------------------------------------------------------------------------------------------
 PostgreSQL 18.3 (Debian 18.3-1.pgdg13+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
(1 row)

minikube.exe kubectl -- get pods
NAME                       READY   STATUS    RESTARTS   AGE
postgres-7977cb9f4-kbjvh   1/1     Running   0          3h52m
postgres-7977cb9f4-rx8hl   1/1     Running   0          48m
postgres-7977cb9f4-xqw4f   1/1     Running   0          48m

### Скриншоты прилагаю
