# Idempotent generator script  

Create `scripts/gen_secrets.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

dir="${1:-secrets}"
mkdir -p "$dir"
chmod 700 "$dir"

gen() {
  local name="$1"
  local path="$dir/$name"
  if [[ -s "$path" ]]; then
    echo "✔ $name exists; skipping"
    return 0
  fi
  # 64-ish chars, URL-safe (no newlines). Use -hex if you prefer only [0-9a-f].
  umask 177
  openssl rand -base64 48 | tr -d '\n' > "$path"
  echo "✓ wrote $path"
}

# cluster admin + replication
gen POSTGRES_PASSWORD
gen REPL_PASSWORD
gen PGADMIN_DEFAULT_PASSWORD

# app users (add more here as needed)
gen fundusApp_PASSWORD
gen APP_A_PASSWORD
gen APP_B_PASSWORD
gen fundusApp_PASSWORD4
gen fundusApp_PASSWORD4
# Add_New_Above_Here


# sanity: show lengths (not contents)
for f in "$dir"/*; do
  [[ -f "$f" ]] || continue
  printf "% -24s %4s chars\n" "$(basename "$f")" "$(wc -c <"$f")"
done
```

Then:

```bash
chmod +x scripts/gen_secrets.sh
./scripts/gen_secrets.sh        # creates any missing secrets, leaves existing ones untouched
```

# Notes

* **Safe characters:** Base64 includes `+/=`; we already pass app passwords into SQL using `psql`’s `%L` (literal) in the template, so special chars are handled correctly. If you *really* want alphanumerics only, switch to `openssl rand -hex 32`.
* **Permissions:** Docker only cares that the files exist; we keep `0600` to avoid accidental exposure.
* **Adding new apps:** Add `gen APP_X_PASSWORD` to the script, re-run it, then run your `dbtool` one-shot to provision that app.