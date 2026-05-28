#!/bin/bash
set -e

# Run as root first: fix volume ownership and write config with expanded env vars
if [ "$(id -u)" = "0" ]; then
  chown -R spinta:www-data /opt/spinta/config /opt/spinta/logs /opt/spinta/var
  cat > /opt/spinta/var/config.yml <<EOF
config_path: /opt/spinta/config
default_auth_client: default
env: production
manifest: default

keymaps:
  default:
    type: sqlalchemy
    dsn: sqlite:////opt/spinta/var/keymap.db

backends:
  default:
    type: postgresql
    dsn: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}/${POSTGRES_DB}

manifests:
  default:
    type: tabular
    path: /opt/spinta/manifest.csv
    backend: default
    mode: internal

accesslog:
  type: file
  file: /opt/spinta/logs/access.log
EOF
  chmod 644 /opt/spinta/var/config.yml

  # Inject NOTICE into the HTML template
  NOTICE_HTML=""
  if [ -n "${NOTICE:-}" ]; then
    NOTICE_HTML="<div class=\"warning\">${NOTICE}</div>"
  fi
  sed "s|NOTICE_PLACEHOLDER|${NOTICE_HTML}|" \
    /opt/spinta/templates/base.html \
    > /opt/spinta/env/lib/python3.11/site-packages/spinta/templates/base.html

  exec su -s /bin/bash spinta "$0" "$@"
fi

SPINTA=/opt/spinta/env/bin/spinta

# Wait for postgres
echo "Waiting for PostgreSQL..."
until pg_isready -h "${POSTGRES_HOST:-db}" -U "${POSTGRES_USER:-spinta}" -q; do
  sleep 1
done

# Generate keys if they don't exist yet
if [ ! -f /opt/spinta/config/keys/private.json ]; then
  echo "Generating cryptographic keys..."
  $SPINTA genkeys
fi

# Create default read-only client (ignore error if already exists)
echo "Creating default client..."
$SPINTA client add -n default --add-secret --scope - <<EOF || true
spinta_getone
spinta_getall
spinta_search
spinta_changes
EOF

# Create write client (ignore error if already exists)
echo "Creating write client..."
$SPINTA client add -n writer --add-secret --secret writer123 --scope - <<EOF || true
spinta_getone
spinta_getall
spinta_search
spinta_changes
spinta_insert
spinta_upsert
spinta_update
spinta_patch
spinta_delete
spinta_set_meta_fields
EOF

# Bootstrap database schema
echo "Bootstrapping database..."
$SPINTA wait 30
$SPINTA bootstrap

export AUTHLIB_INSECURE_TRANSPORT=1
echo "Starting Gunicorn..."
exec /opt/spinta/env/bin/gunicorn \
  -b 0.0.0.0:8000 \
  -k uvicorn.workers.UvicornWorker \
  --workers "${GUNICORN_WORKERS:-2}" \
  --access-logfile - \
  --error-logfile - \
  spinta.asgi:app
