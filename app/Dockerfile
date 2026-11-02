# syntax=docker/dockerfile:1

# ---- build stage: install pinned dependencies into a virtualenv ----
FROM python:3.12-slim-bookworm AS build
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1
RUN python -m venv /opt/venv
COPY requirements.txt /tmp/requirements.txt
RUN /opt/venv/bin/pip install -r /tmp/requirements.txt

# ---- runtime stage: no build tools, non-root, nothing writable needed ----
FROM python:3.12-slim-bookworm AS runtime
ARG APP_VERSION=dev
ARG GIT_SHA=unknown
ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=${APP_VERSION} \
    GIT_SHA=${GIT_SHA}
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin app
COPY --from=build /opt/venv /opt/venv
WORKDIR /srv
COPY labapi ./labapi
USER 10001:10001
EXPOSE 8080
# No HEALTHCHECK on purpose: Kubernetes runs the startup, liveness and readiness probes.
CMD ["uvicorn", "labapi.main:app", "--host", "0.0.0.0", "--port", "8080", "--no-server-header"]
