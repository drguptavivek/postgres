You usually **can’t “extract”** original passwords from Postgres (DB only stores hashes). 
What you *can* do:

1. **Recover** the values if they’re still present in the running container (e.g., Docker **secrets** under `/run/secrets/*` or env vars).
2. **Rotate** (generate new strong passwords), `ALTER ROLE …` in Postgres, and re-write your `./secrets/*` files.

Below is a single script that does both.

---

# `scripts/recover_or_rotate_secrets.sh`

* Tries to **recover**:

  * `POSTGRES_PASSWORD` from `/run/secrets/POSTGRES_PASSWORD` or `printenv`
  * `REPL_PASSWORD` from `/run/secrets/REPL_PASSWORD` or `printenv`
* For **app users** (e.g., `appA_user`, `appB_user`) it **rotates** (cannot recover originals unless you mounted their secrets into the DB container).
* Writes/repairs files under `./secrets/` with **0600**.
* Uses local socket auth inside the container (`-u postgres`) so no current password is needed to rotate.

```bash
#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
CONTAINER="${CONTAINER:-pgdb}"      # name of your Postgres container
SECDIR="${SECDIR:-secrets}"         # local secrets directory
APP_ROLES=(${APP_ROLES:-appA_user appB_user})  # space-separated app roles to rotate if missing
# ----------------

mkdir -p "$SECDIR"
chmod 700 "$SECDIR"

# Helpers
perm600() { chmod 600 "$1" 2>/dev/null || true; }
gen_secret() { umask 177; openssl rand -base64 48 | tr -d '\n'; }
write_if_missing() { # name value
  local name="$1" val="$2" path="$SECDIR/$name"
  if [[ -s "$path" ]]; then
    echo "✔ $name exists → $path"
  else
    printf "%s" "$val" > "$path"
    perm600 "$path"
    echo "✓ wrote $path"
  fi
}

need_container() {
  if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "ERROR: container '$CONTAINER' is not running." >&2
    exit 1
  fi
}

recover_secret() { # docker_secret_name env_var file_name
  local dsec="$1" envv="$2" fname="$3" val=""
  # Try Docker secret file first
  if docker exec "$CONTAINER" test -f "/run/secrets/$dsec" 2>/dev/null; then
    val="$(docker exec "$CONTAINER" cat "/run/secrets/$dsec")" || true
  fi
  # Fallback to container env
  if [[ -z "${val}" ]]; then
    val="$(docker exec "$CONTAINER" /bin/sh -lc "printenv $envv" 2>/dev/null || true)"
  fi
  if [[ -n "${val}" ]]; then
    write_if_missing "$fname" "$val"
    return 0
  fi
  return 1
}

alter_role_pw() { # role newPassword
  local role="$1" pw="$2"
  docker exec -u postgres "$CONTAINER" psql -qAt -d postgres -c \
    "ALTER ROLE \"$role\" WITH PASSWORD '$pw';" >/dev/null
}

rotate_role_to_file() { # role fileName
  local role="$1" fname="$2" newpw
  newpw="$(gen_secret)"
  alter_role_pw "$role" "$newpw"
  write_if_missing "$fname" "$newpw"
  echo "✓ rotated role '$role' and saved to $SECDIR/$fname"
}

echo "== Secret recovery / rotation for container: $CONTAINER =="
need_container

# 1) Superuser + replication recovery (or rotate if not recoverable)
echo "-- cluster credentials --"
if recover_secret "POSTGRES_PASSWORD" "POSTGRES_PASSWORD" "POSTGRES_PASSWORD"; then
  echo "✔ recovered POSTGRES_PASSWORD"
else
  echo "… could not recover POSTGRES_PASSWORD; rotating now"
  rotate_role_to_file "${POSTGRES_USER:-postgres}" "POSTGRES_PASSWORD"
fi

if recover_secret "REPL_PASSWORD" "REPL_PASSWORD" "REPL_PASSWORD"; then
  echo "✔ recovered REPL_PASSWORD"
else
  echo "… could not recover REPL_PASSWORD; rotating now"
  rotate_role_to_file "replicator" "REPL_PASSWORD"
fi

# 2) App roles: usually not recoverable → rotate
echo "-- app roles --"
for r in "${APP_ROLES[@]}"; do
  rotate_role_to_file "$r" "$(echo "$r" | tr '[:lower:]' '[:upper:]')_PASSWORD"
done

# 3) Show lengths only (not the secrets)
echo "-- summary --"
for f in "$SECDIR"/*; do
  [[ -f "$f" ]] || continue
  # linux vs mac stat
  if stat -c '%a %n' "$f" >/dev/null 2>&1; then
    perms="$(stat -c '%a' "$f")"
  else
    perms="$(stat -f '%OLp' "$f")"
  fi
  printf "%-28s %s chars, mode %s\n" "$(basename "$f")" "$(wc -c <"$f")" "$perms"
done

echo "Done. Update any dependent services with new passwords (env, configs)."
```

## Usage

```bash
chmod +x scripts/recover_or_rotate_secrets.sh

# Default: container=pgdb, roles appA_user/appB_user, secrets dir ./secrets
scripts/recover_or_rotate_secrets.sh

# Customize:
CONTAINER=pgdb SECDIR=secrets APP_ROLES="appX_user appY_user" scripts/recover_or_rotate_secrets.sh
```

### What it does (and why)

* **Recover when possible**: If you mounted Docker **secrets** into the `pgdb` container (e.g., `POSTGRES_PASSWORD`, `REPL_PASSWORD`), the script copies them out. If you used **env vars** instead, it will grab those via `printenv`.
* **Rotate when not possible**: App user secrets aren’t usually present in the DB container, so the script **generates a new strong password**, runs `ALTER ROLE … WITH PASSWORD …`, and saves it to `./secrets/<ROLE>_PASSWORD` (0600). That’s the safest, standard approach—no plain-text recovery exists from Postgres.

> After rotation, update any apps / pgAdmin saved connections with the new passwords. If you’re also running replication or backup jobs, make sure they pick up the rotated `REPL_PASSWORD`.
