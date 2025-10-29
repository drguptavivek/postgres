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
gen appUser1Password
gen APP_B_PASSWORD
gen fundusApp_PASSWORD4
gen fundusApp_PASSWORD4
# Add_New_Above_Here


# sanity: show lengths (not contents)
for f in "$dir"/*; do
  [[ -f "$f" ]] || continue
  printf "%-24s %4s chars\n" "$(basename "$f")" "$(wc -c <"$f")"
done
