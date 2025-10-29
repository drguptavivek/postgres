# setting up a Postgres 18 container 

- bind mounted configs
- PGAdmin
- Backups
- Applciatiopn spceific Dbs within same Postgres container with deicated userss, Dbs and passwords


## ecrets


```bash
cd secrets
touch PGADMIN_DEFAULT_EMAIL
nano PGADMIN_DEFAULT_EMAIL
# Type the enail ID, save, exit
```

Generate the basic secrets
- POSTGRES_PASSWORD
- REPL_PASSWORD
- PGADMIN_DEFAULT_PASSWORD

```bash
# SCRIPT - idempotent - does not owerwrite existing secrets
chmod +x ./scripts/gen_secrets.sh 
./scripts/gen_secrets.sh 

# OR CMDLINE
umask 177; openssl rand -base64 48 | tr -d '\n' > secrets/POSTGRES_PASSWORD
umask 177; openssl rand -base64 48 | tr -d '\n' > secrets/REPL_PASSWORD
umask 177; openssl rand -base64 48 | tr -d '\n' > secrets/PGADMIN_DEFAULT_PASSWORD

```

---

##  `docker-compose.init.yml`

*(Postgres 18 + Adminer + pgAdmin)*

bind-mounts editable Postgres config files from your host. We point Postgres to those files explicitly, so you can tweak them without rebuilding the container.


 ```bash

# Start / restart POSTGRES and PGAMDIN AND ADMINER containers
docker compose -p pgstack -f docker-compose.init.yml up -d
```

## Replciation User

```bash
chmod +x scripts/create_or_rotate_replicator.sh
scripts/create_or_rotate_replicator.sh
```


## After editing config files:

```bash
docker restart pgdb
# Or reload when supported:
docker exec -it pgdb psql -U postgres -c "SELECT pg_reload_conf();"
```


## Ensure correct network in hba.conf

```bash
docker inspect  pgdb | grep IPAddress
grep "replication" config/pg_hba.conf 
```
Both network series should match



### Notes & gotchas
- First init vs existing data: If you already initialized PGDATA with different settings, Postgres will still honor the config_file we pass in command:. That’s why we explicitly set config_file — it works both on a fresh and an existing data directory.
- Permissions: Files are mounted :ro; Postgres only needs read access. Keep them owned by you on the host.
- Network CIDR: Adjust the 172.18.0.0/16 in pg_hba.conf to match docker network inspect pgnet.
- Conf.d strategy: put most of your tunables in conf.d/*.conf. Keep postgresql.conf short and stable (paths + includes).
 

 


## UPGRADE to Postgres 18 from 17.3
Postgres major versions aren’t binary-compatible, so the 18 server won’t start on a 17 data directory. 
The container stays unhealthy because Postgres itself never comes up.

So data formaty needs to be upgraded
Also data mount also needs to chnage /var/lib/postgresql

### Upgrade data to version 18

```bash
docker  stop pgdb
docker volume create pgdata18 
docker run --rm   -v pgdata:/var/lib/postgresql/old/data   -v pgdata18:/var/lib/postgresql/new/data   tianon/postgres-upgrade:17-to-18
```

Location of configs also is changed

- /var/lib/postgresql/18/docker/postgresql.conf
- /var/lib/postgresql/18/docker/pg_hba.conf
- /var/lib/postgresql/18/docker/conf.d


Edit these in docker-compose.init.yml

```yml
    volumes:
      - pgdata18:/var/lib/postgresql
      - ./config/postgresql.conf:/var/lib/postgresql/18/docker/postgresql.conf
      - ./config/pg_hba.conf:/var/lib/postgresql/18/docker/pg_hba.conf
      - ./config/conf.d:/var/lib/postgresql/18/docker/conf.d

volumes:
  pgdata18:
  pgadmindata:

```
Bring up container

```bash
docker compose -f docker-compose.init.yml up -d
docker logs --tail 50 -f pgdb
```