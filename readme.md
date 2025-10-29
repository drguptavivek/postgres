# Setting up a Postgres 18 container 

This repository contains configuration for running PostgreSQL 18 in Docker containers.
See [official PostgreSQL Docker image](https://hub.docker.com/_/postgres) for more details.

Features:
- [Bind mounted configs](config/)
- PGAdmin web interface
- [Automated backups](docs/backups.md)
- [Application-specific databases](docs/App%20Dbs.md) within same PostgreSQL container with dedicated users, DBs and passwords

## Documentation
- [Setting up Application Databases](docs/App%20Dbs.md)
- [Backup Configuration and Management](docs/backups.md)
- [Generating Secrets](docs/Generate-secrets.md)
- [Rotating Secrets](docs/Rotate-secrets.md)

## Scripts and Configuration Files
- [Scripts](scripts/) - Utility scripts for database management
- [Configuration Files](config/) - PostgreSQL configuration files
- [Docker Compose Files](docker-compose.init.yml) - Container orchestration


## Clone the repo

```bash
git clone https://github.com/drguptavivek/postgres.git
```

## Secrets




```bash
cd secrets
touch PGADMIN_DEFAULT_EMAIL
nano PGADMIN_DEFAULT_EMAIL
# Type the email ID, save, exit
```

Generate the basic secrets
- POSTGRES_PASSWORD
- REPL_PASSWORD
- PGADMIN_DEFAULT_PASSWORD

See: [./scripts/gen_secrets.sh](scripts/gen_secrets.sh)

```bash
# SCRIPT - idempotent - does not overwrite existing secrets
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

## Replication User

See: [scripts/02_create_rotate_replication_user.sh](scripts/02_create_rotate_replication_user.sh)

```bash
chmod +x scripts/02_create_rotate_replication_user.sh
scripts/02_create_rotate_replication_user.sh
```


## After editing config files:

```bash
docker restart pgdb
# Or reload when supported:

# show hba_file path
docker exec -u postgres   -e PGPASSWORD="$(tr -d '\r\n' < secrets/POSTGRES_PASSWORD)"   pgdb psql -h pgdb -U postgres -d postgres -c "SHOW hba_file;"

# show effective HBA rules
docker exec -u postgres   -e PGPASSWORD="$(tr -d '\r\n' < secrets/POSTGRES_PASSWORD)"   pgdb psql -h pgdb -U postgres -d postgres -c "SELECT * FROM pg_hba_file_rules;"

# show paths
docker exec -u postgres   -e PGPASSWORD="$(tr -d '\r\n' < secrets/POSTGRES_PASSWORD)"  pgdb psql -h pgdb -U postgres -d postgres -c "SHOW config_file; SHOW hba_file; SHOW ident_file; SHOW data_directory;"

# show file-sourced settings and whether applied
docker exec -u postgres   -e PGPASSWORD="$(tr -d '\r\n' < secrets/POSTGRES_PASSWORD)"   pgdb psql -h pgdb -U postgres -d postgres -c "SELECT sourcefile, sourceline, name, setting, applied, error FROM pg_file_settings ORDER BY sourcefile, sourceline;"

# show settings that need restart
docker exec -u postgres   -e PGPASSWORD="$(tr -d '\r\n' < secrets/POSTGRES_PASSWORD)"   pgdb psql -h pgdb -U postgres -d postgres -c "SELECT name, setting, pending_restart FROM pg_settings WHERE pending_restart;"


docker exec -u postgres -e PGPASSWORD="$(tr -d '\r\n' < secrets/POSTGRES_PASSWORD)"  pgdb psql -h pgdb -U postgres -d postgres -c "SHOW search_path;"
```

## RUN a SQL Script inside container

```bash
docker exec -i -u postgres -e PGPASSWORD="$(tr -d '\r\n' < secrets/POSTGRES_PASSWORD)"  pgdb psql -h pgdb -U postgres \
  -d DataBaseName   -c "SET search_path TO ;" \
  -v ON_ERROR_STOP=1 -f - \
   < script_To_Run.sql
```

## Ensure correct network in hba.conf

See: [config/pg_hba.conf](config/pg_hba.conf)

```bash
docker inspect  pgdb | grep IPAddress
grep "replication" config/pg_hba.conf
```
Both network series should match



### Notes & gotchas
- First init vs existing data: If you already initialized PGDATA with different settings, Postgres will still honor the config_file we pass in command:. That’s why we explicitly set config_file — it works both on a fresh and an existing data directory.
- Permissions: Files are mounted :ro; Postgres only needs read access. Keep them owned by you on the host.
- Network CIDR: Adjust the 172.18.0.0/16 in [config/pg_hba.conf](config/pg_hba.conf) to match docker network inspect pgnet.
- Conf.d strategy: put most of your tunables in [config/conf.d/*.conf](config/conf.d/). Keep [config/postgresql.conf](config/postgresql.conf) short and stable (paths + includes).
 

## UPGRADE to Postgres 18 from 17.3
Postgres major versions aren’t binary-compatible, so the 18 server won’t start on a 17 data directory. 
The container stays unhealthy because Postgres itself never comes up.

So data format needs to be upgraded.
Also data mount needs to change to /var/lib/postgresql

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