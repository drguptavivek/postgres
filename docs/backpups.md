# Setting up pg_base_backup in a second container


### Create backup directory

```bash
sudo mkdir -p backups && sudo chown -R 999:999 backups
```

REPL_PASSWORD already should exist from a previous run of `gen_secrets.sh`

### Create backup User in main container
```bash
./scripts/02_create_rotate_replication_user.sh   
```

### Bring up the backup runner container
```bash
docker compose -p pgstack -f docker-compose.backup.yml up -d

# watch for logs
docker logs -f pg_basebackup_runner
```
## Confirm the IP address is in same  range as 

```bash
docker inspect  pgdb | grep IPAddress
docker inspect  pg_basebackup_runner | grep IPAddress
grep "replication" config/pg_hba.conf 

```
In our case, all were on 172.18.0.2 network.
If the network range of containers is dfferent, edit the `config/pg_hba.conf` to match the cintainers IP range


## Test a Backup

```bash
docker exec -u root pg_basebackup_runner /usr/local/bin/pg_do_basebackup.sh

tree backups/full

```

## Check Logs in main PG container

```bash
docker logs --tail 20 -f pgdb


 
2025-10-29 10:46:02.575 GMT [243] [unknown]@[unknown] LOG:  connection received: host=172.18.0.5 port=58656
2025-10-29 10:46:02.581 GMT [243] replicator@[unknown] LOG:  connection authenticated: identity="replicator" method=scram-sha-256 (/var/lib/postgresql/18/docker/pg_hba.conf:12)
2025-10-29 10:46:02.581 GMT [243] replicator@[unknown] LOG:  replication connection authorized: user=replicator application_name=pg_basebackup
2025-10-29 10:46:02.628 GMT [30] @ LOG:  checkpoint starting: force wait
2025-10-29 10:46:02.650 GMT [30] @ LOG:  checkpoint complete: wrote 0 buffers (0.0%), wrote 0 SLRU buffers; 0 WAL file(s) added, 0 removed, 0 recycled; write=0.005 s, sync=0.001 s, total=0.023 s; sync files=0, longest=0.000 s, average=0.000 s; distance=32768 kB, estimate=32768 kB; lsn=0/6000080, redo lsn=0/6000028
2025-10-29 10:46:02.657 GMT [244] [unknown]@[unknown] LOG:  connection received: host=172.18.0.5 port=58672
2025-10-29 10:46:02.660 GMT [244] replicator@[unknown] LOG:  connection authenticated: identity="replicator" method=scram-sha-256 (/var/lib/postgresql/18/docker/pg_hba.conf:12)
2025-10-29 10:46:02.660 GMT [244] replicator@[unknown] LOG:  replication connection authorized: user=replicator application_name=pg_basebackup
2025-10-29 10:46:03.036 GMT [243] replicator@[unknown] LOG:  disconnection: session time: 0:00:00.461 user=replicator database= host=172.18.0.5 port=58656
2025-10-29 10:46:03.038 GMT [244] replicator@[unknown] LOG:  disconnection: session time: 0:00:00.380 user=replicator database= host=172.18.0.5 port=58672
2025-10-29 10:46:07.268 GMT [251] [unknown]@[unknown] LOG:  connection received: host=[local]
```
 





### Restore (example)

```bash
# Stop Postgres and move aside old data dir
docker stop pgdb
mv ./pgdata ./pgdata.bak.$(date +%s)

# Extract a chosen base backup into a fresh data dir
mkdir -p ./pgdata
tar -xzf ./backups/full/2025-10-29_03-00-00/base.tar.gz -C ./pgdata

# Ensure ownership (host varies; in container it's postgres:postgres)
sudo chown -R 999:999 ./pgdata   # 999 is the postgres UID in the image

# Start the DB; it will use recovery settings created by -R
docker start pgdb
```

> If you want **per-database logical dumps** too (easy restore & portability), you can additionally run a `pg_dump` sidecar; but you asked specifically for **pg_basebackup**, so the above gives you **physical full backups**.

---

## Notes & knobs you can tweak

* **Docker subnet in `01_append_pg_hba.sh`**: Confirm your bridge network CIDR (e.g. `docker network inspect pgnet`). Update `DOCKER_SUBNET` if needed.
* **Security**: All passwords come from `./secrets/*` files (chmod 600). Never commit them.
* **Retention**: The `pg_basebackup_runner` above doesn’t prune old backups; prune with a host cron or add a small cleanup step after the backup runs (tell me your retention policy and I’ll wire it in).
* **RPO**: `pg_basebackup` once nightly means you can lose up to a day’s data. If you need tighter RPO, add **WAL archiving** (e.g., WAL-G to S3/MinIO) alongside or increase frequency.

---

You don’t need hard-coded `echo` lines—generate strong random secrets safely and idempotently.

# Quick one-liners (Linux/macOS)

```bash
# Creates ./secrets if missing, sets 600 perms, and generates strong, newline-free secrets

./scripts/gen_secrets.sh  


# Superuser + replication (for compose.init.yml)
umask 177; openssl rand -base64 48 | tr -d '\n' > secrets/POSTGRES_PASSWORD
umask 177; openssl rand -base64 48 | tr -d '\n' > secrets/REPL_PASSWORD

# App users (for compose.apps.yml)
umask 177; openssl rand -base64 48 | tr -d '\n' > secrets/APP_A_PASSWORD
umask 177; openssl rand -base64 48 | tr -d '\n' > secrets/APP_B_PASSWORD
```

* `umask 177` ⇒ files created with `0600`.
* `-base64 48` ⇒ ~64 chars; high entropy.
* `tr -d '\n'` strips newline so the password is a single line.


