
## ADDING A NEW APP
 To add **one new app** (say `myapp`) to `docker-compose.apps.yml`, make **exactly these edits**:

You need to define:
- myapp_user < -- User for myapp
- myapp_db <--- db for myapp
- myapp <- SCHEMA for myapp


See: [./apps/dbtool.sh](../apps/dbtool.sh)

```bash
chmod +x ./apps/dbtool.sh
```

1. Generate the app passwords

See: [./scripts/gen_secrets.sh](../scripts/gen_secrets.sh)

```bash
# add app name to /scripts/gen_secrets.sh after line 25
#    gen fundusApp_PASSWORD4
awk '($0=="# Add_New_Above_Here" && !r){print "gen fundusApp_PASSWORD4"} {print} $0=="# Add_New_Above_Here"{r=1}' ./scripts/gen_secrets.sh > ./scripts/.gen_secrets.sh.tmp && mv ./scripts/.gen_secrets.sh.tmp ./scripts/gen_secrets.sh

chmod +x ./scripts/gen_secrets.sh

./scripts/gen_secrets.sh

```

2. Add Apps DB schema username to `services.dbtool.secrets`:


```yaml
services:
  dbtool:
    image: postgres:18
    container_name: dbtool
    restart: "no"
    environment:
      PGHOST: pgdb
      PGPORT: 5432
      PGUSER: ${POSTGRES_USER:-postgres}
      PGPASSWORD_FILE: /run/secrets/POSTGRES_PASSWORD
      # >>> App-specific variables <<<
      APP_USER: fundusAppUser4        # <-- Change this
      APP_DB: fundusAppDb4            # <-- Change this
      APP_SCHEMA: fundusAppSchema4    # <-- Change this

    entrypoint: ["/bin/bash","-lc","/sql/dbtool.sh"]
    volumes:
      - ./apps/create_app.sql:/sql/create_app.sql:ro
      - ./apps/dbtool.sh:/sql/dbtool.sh:ro
    secrets:
      - POSTGRES_PASSWORD
      - APP_PASSWORD       
    networks:
      - pgnet

networks:
  pgnet:
    external: true
    name: pgnet

secrets:
  POSTGRES_PASSWORD:
    file: ./secrets/POSTGRES_PASSWORD
  APP_PASSWORD:
    file: ./secrets/fundusApp_PASSWORD4 # <-- Change this

 
```

---

### Add the db with user and privileges

```bash
# Run the one-shot job: use the same project name as your main stack
docker compose -p pgstack \
  -f docker-compose.init.yml \
  -f docker-compose.fundusApp.yml \
  run --rm dbtool
```

### Your app connects with

```bash
docker exec -u postgres -e PGPASSWORD="$(tr -d '\r\n' < secrets/fundusApp_PASSWORD4)"  pgdb psql -h pgdb -U fundusAppUser4 -d fundusAppDb4 -c "SHOW search_path;"

#      search_path       
#------------------------
# "fundusAppSchema4", public
#(1 row)

postgresql://fundusAppUser4:<contents_of_secret_fundusApp_PASSWORD4>@pgdb:5432/fundusAppDb4?search_path=fundusAppSchema4

docker exec -it pgdb psql -h pgdb -p 5432 -U fundusAppUser4 -d fundusAppDb4 -v ON_ERROR_STOP=1 -c 'SHOW search_path;'

```