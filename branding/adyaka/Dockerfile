# ================================================================
# Adyaka Infosec – Adyaka IAM Docker Image
# ================================================================
# Builds on the upstream evolveum/midpoint image with ZERO changes to
# upstream source. All branding is applied by:
#   1. Copying static assets (logos, CSS) into ${MP_HOME}/static/
#   2. Setting Spring Boot env vars (app name, context path, etc.)
#   3. Copying the systemConfiguration.xml for auto-import on startup
#
# Build:
#   docker build -f branding/adyaka/Dockerfile -t adyaka-iam:latest .
#
# Run:
#   docker compose -f branding/adyaka/docker-compose.yml up -d
# ================================================================

ARG BASE_VERSION=4.12
ARG BASE_IMAGE=evolveum/midpoint:${BASE_VERSION}-alpine

FROM ${BASE_IMAGE}

# ── Metadata ─────────────────────────────────────────────────────
LABEL org.opencontainers.image.title="Adyaka IAM"
LABEL org.opencontainers.image.description="Identity & Access Management – powered by Adyaka Infosec"
LABEL org.opencontainers.image.vendor="Adyaka Infosec"
LABEL org.opencontainers.image.url="https://www.adyakainfosec.com"

# ── Brand identity via Spring Boot env overrides ─────────────────
# These override application.yml without touching any source file.
ENV SPRING_APPLICATION_NAME="Adyaka" \
    SERVER_SERVLET_CONTEXT_PATH="/adyaka" \
    SERVER_SERVLET_APPLICATION_DISPLAY_NAME="Adyaka IAM Platform"

# ── Serve brand assets from a path OUTSIDE the var volume ────────
# The volume adyaka_home is mounted at ${MP_DIR}/var, which means
# anything COPYd there in the Dockerfile is hidden by the volume after
# the first run (Docker does not re-initialise existing volumes).
# Using ${MP_DIR}/adyaka-static ensures every rebuild serves fresh
# brand assets because this path is never mounted as a volume.
ENV SPRING_WEB_RESOURCES_STATIC_LOCATIONS="file:${MP_DIR}/adyaka-static/,classpath:/static/"

# ── Copy Adyaka brand assets (outside the volume path) ───────────
COPY branding/adyaka/static/ ${MP_DIR}/adyaka-static/

# ── Auto-import system configuration on first startup ────────────
# The IAM engine processes files in post-initial-objects/ after schema init.
# This sets the product name, logo URL, header colour, and customer info.
RUN mkdir -p ${MP_DIR}/var/post-initial-objects
COPY branding/adyaka/config/systemConfiguration.xml \
     ${MP_DIR}/var/post-initial-objects/100-systemConfiguration.xml

# ── Expose branded port ───────────────────────────────────────────
EXPOSE 8080

CMD [ "/opt/midpoint/bin/midpoint.sh", "container" ]
