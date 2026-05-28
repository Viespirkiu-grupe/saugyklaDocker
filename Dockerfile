FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -g 33 www-data-grp 2>/dev/null || true \
 && useradd --system --gid www-data --create-home --home-dir /opt/spinta spinta

WORKDIR /opt/spinta

RUN python -m venv env \
 && env/bin/pip install --no-cache-dir spinta "starlette<0.36" gunicorn uvloop httptools

RUN mkdir -p config logs var \
 && chown -R spinta:www-data /opt/spinta/config /opt/spinta/logs /opt/spinta/var

EXPOSE 8000

COPY --chown=spinta:www-data docker-entrypoint.sh /opt/spinta/docker-entrypoint.sh

ENTRYPOINT ["/opt/spinta/docker-entrypoint.sh"]
