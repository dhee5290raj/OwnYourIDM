# Adyaka IAM – Branding Guide

All upstream (OOTB) source files are **untouched**.
Branding is applied entirely through files in this directory, layered on top
of the base evolveum/midpoint image at Docker build time.

---

## Directory Layout

```
branding/adyaka/
├── Dockerfile                    ← builds adyaka-iam:latest on top of evolveum base
├── docker-compose.yml            ← full stack (Postgres + Adyaka IAM)
├── BRANDING.md                   ← this file
│
├── static/                       ← copied to ${MP_HOME}/var/static/ in the image
│   ├── img/
│   │   ├── adyaka_logo_white.svg ← sidebar logo (white, for dark sidebar)
│   │   ├── adyaka_logo_icon.svg  ← sidebar logo icon-only (collapsed sidebar)
│   │   └── adyaka_logo_color.svg ← full-colour logo (docs, email, external)
│   └── css/
│       └── adyaka-custom.css     ← brand colour / sidebar / button overrides
│
└── config/
    └── systemConfiguration.xml   ← Adyaka IAM system config (auto-imported on startup)
```

---

## How It Works

Three mechanisms, zero OOTB file changes:

### 1 — Spring Boot env vars (Docker image ENV)
Overrides `application.yml` at runtime without touching it.

| Variable | Value | Effect |
|---|---|---|
| `SPRING_APPLICATION_NAME` | `Adyaka` | Spring app name / `<title>` fallback |
| `SERVER_SERVLET_CONTEXT_PATH` | `/adyaka` | Context root (e.g. `http://host:8082/adyaka`) |
| `SERVER_SERVLET_APPLICATION_DISPLAY_NAME` | `Adyaka IAM Platform` | Display name |
| `SPRING_WEB_RESOURCES_STATIC_LOCATIONS` | `file:${MP_DIR}/var/static/,classpath:/static/` | Serves our brand assets **before** OOTB classpath assets |

### 2 — Static asset overlay
`COPY branding/adyaka/static/ /opt/midpoint/var/static/` puts logos and CSS into
the image. Spring serves files from `var/static/` first, so our files take
precedence over any OOTB classpath resource with the same name (zero OOTB file changes).

### 3 — Adyaka IAM System Configuration (auto-imported)
`100-systemConfiguration.xml` is placed in `post-initial-objects/`. The IAM engine
auto-imports files from that directory after schema initialisation on first boot.

**Real schema fields used** (`DeploymentInformationType`):

| Field | Value | Effect |
|---|---|---|
| `name` | `Adyaka` | Deployment name shown in UI & About page |
| `systemName` | `Adyaka IAM Platform` | System name label |
| `headerColor` | `#1B2080` | Inline `background-color` on sidebar header band |
| `logo.imageUrl` | `/adyaka/static/img/adyaka_logo_white.svg` | Shows `<img>` in sidebar; **automatically hides the OOTB PNG background-image logo** |
| `customerName` | `Adyaka Infosec` | Shown in About page |
| `customerUrl` | `https://www.adyakainfosec.com` | Linked in About page |
| `additionalFooter` | base64(`<link rel="stylesheet" href=".../adyaka-custom.css"/>`) | Injects brand CSS after `</body>` on every page |

---

## Build & Run

```bash
# From the repo root:
docker compose -f branding/adyaka/docker-compose.yml up -d --build
```

| URL | Value |
|---|---|
| Application | http://localhost:8082/adyaka |
| Default login | `administrator` / `Adyaka@2024!` |
| First boot | ~3 minutes (schema initialisation) |

---

## Customising the Brand

### Change colours
Edit `:root` custom properties at the top of [static/css/adyaka-custom.css](static/css/adyaka-custom.css):

```css
:root {
  --adyaka-navy:      #1B2080;   /* sidebar, header, buttons */
  --adyaka-navy-dark: #0D1147;   /* sidebar body background  */
  --adyaka-blue:      #1565C0;   /* links and accent colour  */
}
```

### Change the logo
Replace `static/img/adyaka_logo_white.svg` (sidebar) and `static/img/adyaka_logo_icon.svg`
(collapsed sidebar) with your own files. PNG and JPEG also work — update the `imageUrl`
in `config/systemConfiguration.xml` if you change the filename.

### Change the header band colour
Edit `<headerColor>` in `config/systemConfiguration.xml`.

### Change product name / context path
Edit the `ENV` lines in [Dockerfile](Dockerfile):

```dockerfile
ENV SPRING_APPLICATION_NAME="Adyaka" \
    SERVER_SERVLET_CONTEXT_PATH="/adyaka"
```

Also update the `additionalFooter` base64 in `systemConfiguration.xml` if the context
path changes (the CSS `href` includes the context path):

```bash
python3 -c "
import base64
html = '<link rel=\"stylesheet\" type=\"text/css\" href=\"/YOUR_PATH/static/css/adyaka-custom.css\"/>'
print(base64.b64encode(html.encode()).decode())
"
```

### Change the port
Edit `docker-compose.yml` → `adyaka_server.ports`: `"XXXX:8080"`.

---

## Upgrading the IAM Engine Version

Change the `BASE_VERSION` build arg — OOTB files are never modified so there
is nothing to merge:

```bash
docker compose -f branding/adyaka/docker-compose.yml build --build-arg BASE_VERSION=4.10
docker compose -f branding/adyaka/docker-compose.yml up -d
```

> **Volume note**: Docker initialises named volumes from image content on **first run only**.
> If you rebuild the image with new branding but the volume `adyaka_home` already exists,
> run `docker exec adyaka-server cp -r /opt/midpoint/var/static /opt/midpoint/var/`
> or recreate the volume (`docker compose down -v && docker compose up -d --build`).
> Recreating the volume resets all midPoint configuration — re-import objects afterward.
