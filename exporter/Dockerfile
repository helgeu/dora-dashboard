# Exporter image: runs the vendored ADO DORA scripts + the Postgres loader on a
# schedule. PAT auth means no `az` CLI is needed, so the image stays tiny.
#
# Multi-arch: build with `docker buildx build --platform linux/amd64,linux/arm64`.
# Pin the base by digest in CI if you want full reproducibility.
FROM python:3.12-slim

# psycopg[binary] is the only runtime dependency (loader -> Postgres). The
# exporters themselves use only the Python standard library.
RUN pip install --no-cache-dir "psycopg[binary]==3.2.3"

# Vendored ADO exporters + the loader, all on PATH.
COPY bin/ /usr/local/bin/
COPY dora-load /usr/local/bin/dora-load
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/ado-* /usr/local/bin/dora-load /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
