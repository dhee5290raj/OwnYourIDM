#!/usr/bin/env bash
# ================================================================
# Adyaka IAM – Local Server Deployment Script
# ================================================================
# Deploys Adyaka branding directly into an existing midPoint
# installation on this server. No Docker required.
#
# Usage:
#   ./branding/adyaka/deploy.sh [options] [command]
#
# Commands:
#   deploy    (default) Copy brand assets + apply system config
#   start     Start midPoint after deploying
#   stop      Stop midPoint
#   restart   Stop, deploy branding, start midPoint
#   status    Show midPoint process + URL health check
#   logs      Tail the midPoint log
#
# Options:
#   -h, --home DIR    midPoint home dir (default: /opt/midpoint/var)
#   -u, --url  URL    midPoint base URL (default: http://localhost:8080/midpoint)
#   -p, --pass PASS   administrator password (default: Adyaka@2024!)
#
# Examples:
#   ./branding/adyaka/deploy.sh
#   ./branding/adyaka/deploy.sh -h /opt/midpoint/var -u http://myserver:8080/adyaka restart
# ================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BRAND_STATIC="${SCRIPT_DIR}/static"
BRAND_CSS="${SCRIPT_DIR}/static/static/css/adyaka-custom.css"
BRAND_SYSCONFIG="${SCRIPT_DIR}/config/systemConfiguration.xml"

# ── Defaults (override with flags or env vars) ────────────────────
MP_HOME="${MP_HOME:-/Users/dheerajkumar/adyaka/var}"
MP_BIN="${MP_BIN:-/Users/dheerajkumar/adyaka/bin}"
MP_URL="${MP_URL:-http://localhost:8083/adyaka}"
MP_ADMIN_PASS="${MP_ADMIN_PASS:-Adyaka@2024!}"
MP_PORT="${MP_PORT:-8083}"

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-adyaka}"
DB_USER="${DB_USER:-adyaka}"
DB_PASS="${DB_PASS:-adyaka.db.secret}"

# ── Auto-detect Java 17+ ──────────────────────────────────────────
detect_java() {
    if [[ -n "${JAVA_HOME:-}" ]] && "${JAVA_HOME}/bin/java" -version 2>&1 | grep -q 'version "1[7-9]\|version "2[0-9]'; then
        return  # already set to a valid version
    fi
    # Try java_home utility on macOS
    for ver in 25 21 17; do
        local jh
        jh=$(/usr/libexec/java_home -v "${ver}" 2>/dev/null) && \
            export JAVA_HOME="${jh}" && return
    done
    # Fallback: scan common locations
    for jh in \
        /Users/dheerajkumar/Library/Java/JavaVirtualMachines/openjdk-25.0.2/Contents/Home \
        /Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home \
        /Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home \
        /opt/homebrew/opt/openjdk@21 \
        /opt/homebrew/opt/openjdk@17; do
        if [[ -x "${jh}/bin/java" ]]; then
            export JAVA_HOME="${jh}"
            return
        fi
    done
    error "Java 17 or newer not found. Install with: brew install openjdk@21"
    error "Then set: export JAVA_HOME=\$(/usr/libexec/java_home -v 21)"
    exit 1
}

# ── Colours ──────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[adyaka]${NC} $*"; }
warn()  { echo -e "${YELLOW}[adyaka]${NC} $*"; }
error() { echo -e "${RED}[adyaka]${NC} $*" >&2; }
step()  { echo -e "${BOLD}▶ $*${NC}"; }

# ── Parse flags ───────────────────────────────────────────────────
CMD="deploy"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--home)  MP_HOME="$2";       shift 2 ;;
        -u|--url)   MP_URL="$2";        shift 2 ;;
        -p|--pass)  MP_ADMIN_PASS="$2"; shift 2 ;;
        deploy|start|stop|restart|status|logs|diag) CMD="$1"; shift ;;
        *) echo "Unknown option: $1"; echo "Usage: $0 [-h DIR] [-u URL] [-p PASS] [deploy|start|stop|restart|status|logs|diag]"; exit 1 ;;
    esac
done

# ── Auto-detect midPoint install ──────────────────────────────────
detect_bin() {
    if [[ -n "${MP_BIN}" ]]; then return; fi
    local candidates=(
        "$(dirname "${MP_HOME}")/bin"
        "/opt/midpoint/bin"
        "/usr/local/midpoint/bin"
        "/usr/share/midpoint/bin"
        "${HOME}/midpoint/bin"
    )
    for d in "${candidates[@]}"; do
        if [[ -f "${d}/midpoint.sh" ]]; then
            MP_BIN="${d}"
            return
        fi
    done
    # Also check if running as systemd service
    if systemctl list-units --type=service 2>/dev/null | grep -qi midpoint; then
        MP_BIN="__systemd__"
        return
    fi
    return 0
}

# Check midPoint is actually installed; print clear error if not
require_install() {
    detect_bin
    if [[ -z "${MP_BIN}" ]]; then
        error "midPoint installation not found on this machine."
        error ""
        error "Searched for midpoint.sh in:"
        error "  $(dirname "${MP_HOME}")/bin"
        error "  /opt/midpoint/bin, /usr/local/midpoint/bin, ~/midpoint/bin"
        error ""
        error "Fix options:"
        error "  1. Set MP_BIN to your bin dir:"
        error "     MP_BIN=/path/to/midpoint/bin $0 $CMD"
        error "  2. Set MP_HOME to your midPoint home:"
        error "     MP_HOME=/path/to/midpoint/var $0 $CMD"
        error "  3. Run '$0 diag' to see a full environment report."
        exit 1
    fi
}

# ── Check PostgreSQL ──────────────────────────────────────────────
check_postgres() {
    if ! command -v psql &>/dev/null; then
        error "PostgreSQL client (psql) not found."
        error "Install with: brew install postgresql@16"
        error "Then start:   brew services start postgresql@16"
        exit 1
    fi
    if ! psql "postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}" \
              -c "SELECT 1" &>/dev/null; then
        error "Cannot connect to PostgreSQL at ${DB_HOST}:${DB_PORT}/${DB_NAME}"
        error ""
        error "Run these once to set it up:"
        error "  brew install postgresql@16"
        error "  brew services start postgresql@16"
        error "  psql postgres -c \"CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';\""
        error "  psql postgres -c \"CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};\""
        exit 1
    fi
    info "PostgreSQL connection OK: ${DB_HOST}:${DB_PORT}/${DB_NAME}"
}

# ── Write midPoint config.xml ─────────────────────────────────────
write_config() {
    local cfg="${MP_HOME}/config.xml"
    if [[ -f "${cfg}" ]]; then
        # Only rewrite if it still has the placeholder H2/no-DB config
        if grep -q "H2\|ENTER_REPOSITORY_URL\|Couldn't figure out" "${cfg}" 2>/dev/null; then
            warn "Overwriting incomplete config.xml with PostgreSQL settings."
        else
            info "config.xml already exists — skipping."
            return
        fi
    fi
    mkdir -p "${MP_HOME}"
    cat > "${cfg}" <<EOF
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<configuration>
  <midpoint>
    <repository>
      <type>native</type>
      <jdbcUrl>jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}</jdbcUrl>
      <jdbcUsername>${DB_USER}</jdbcUsername>
      <jdbcPassword>${DB_PASS}</jdbcPassword>
    </repository>
    <audit>
      <auditService>
        <auditServiceFactoryClass>com.evolveum.midpoint.audit.impl.LoggerAuditServiceFactory</auditServiceFactoryClass>
      </auditService>
      <auditService>
        <auditServiceFactoryClass>com.evolveum.midpoint.repo.sqale.audit.SqaleAuditServiceFactory</auditServiceFactoryClass>
      </auditService>
    </audit>
    <administrator>
      <initialPassword>${MP_ADMIN_PASS}</initialPassword>
    </administrator>
  </midpoint>
</configuration>
EOF
    info "Written ${cfg}"
}

# ── Write application.properties (port + context path + branding) ─
write_app_properties() {
    local props="${MP_HOME}/application.properties"
    local static_loc="file:${MP_HOME}/adyaka-static/,classpath:/static/"
    cat > "${props}" <<EOF
# Adyaka IAM – generated by deploy.sh
server.port=${MP_PORT}
server.servlet.context-path=/adyaka
spring.application.name=Adyaka
spring.web.resources.static-locations=${static_loc}
EOF
    info "Written ${props}"
}

# ── Initialize DB schema via ninja ────────────────────────────────
init_schema() {
    if "${MP_BIN}/ninja.sh" -B info &>/dev/null 2>&1; then
        info "DB schema already initialised."
        return
    fi
    step "Initialising database schema"
    "${MP_BIN}/ninja.sh" run-sql --create --mode REPOSITORY 2>&1 | tail -3
    "${MP_BIN}/ninja.sh" run-sql --create --mode AUDIT      2>&1 | tail -3
    info "Schema created."
}

# ── Bundle CSS ────────────────────────────────────────────────────
# Extracts the OOTB midpoint.css from the installed midpoint JAR,
# then appends Adyaka overrides to produce the final bundle.
bundle_css() {
    step "Building CSS bundle"

    # Find the midpoint.jar
    local mp_jar
    mp_jar="$(find "$(dirname "${MP_HOME}")" /opt/midpoint /usr/share/midpoint \
        -name "midpoint.jar" -maxdepth 4 2>/dev/null | head -1)"

    if [[ -z "${mp_jar}" ]]; then
        warn "midpoint.jar not found – skipping OOTB CSS extraction."
        warn "Using pre-built bundle at ${BRAND_STATIC}/static/midpoint.css (may be stale)."
        return 0
    fi

    info "Found midpoint.jar: ${mp_jar}"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "${tmp_dir}"' EXIT

    # Extract admin-gui JAR from nested Spring Boot JAR, then extract CSS
    local css_out="${tmp_dir}/midpoint-ootb.css"
    unzip -p "${mp_jar}" "BOOT-INF/lib/admin-gui-*.jar" > "${tmp_dir}/admin-gui.jar" 2>/dev/null || {
        warn "Could not extract admin-gui JAR – keeping existing CSS bundle."
        return 0
    }
    unzip -p "${tmp_dir}/admin-gui.jar" "static/static/midpoint.css" > "${css_out}" 2>/dev/null || {
        warn "Could not extract midpoint.css from admin-gui JAR – keeping existing CSS bundle."
        return 0
    }

    if [[ ! -s "${css_out}" ]]; then
        warn "Extracted CSS is empty – keeping existing bundle."
        return 0
    fi

    # Write final bundle: OOTB + Adyaka overrides
    {
        cat "${css_out}"
        printf '\n/* ================================================================ */\n'
        printf '/* Adyaka Infosec branding overrides                                  */\n'
        printf '/* ================================================================ */\n'
        cat "${BRAND_CSS}"
    } > "${BRAND_STATIC}/static/midpoint.css"

    local size
    size=$(wc -c < "${BRAND_STATIC}/static/midpoint.css" | tr -d ' ')
    info "CSS bundle: ${size} bytes  →  ${BRAND_STATIC}/static/midpoint.css"
}

# ── Copy brand assets ─────────────────────────────────────────────
deploy_assets() {
    step "Copying brand assets to midPoint home"

    local dest="${MP_HOME}/adyaka-static"
    mkdir -p "${dest}"

    cp -r "${BRAND_STATIC}/." "${dest}/"
    info "Assets deployed: ${dest}"

    # Write Spring static-locations property so midPoint serves our files first.
    # This goes into application.properties inside MP_HOME.
    local app_props="${MP_HOME}/application.properties"
    local prop_key="spring.web.resources.static-locations"
    local prop_val="file:${dest}/,classpath:/static/"

    if [[ -f "${app_props}" ]]; then
        # Update existing key or append
        if grep -q "^${prop_key}" "${app_props}"; then
            sed -i.bak "s|^${prop_key}=.*|${prop_key}=${prop_val}|" "${app_props}"
            rm -f "${app_props}.bak"
            info "Updated ${prop_key} in application.properties"
        else
            echo "${prop_key}=${prop_val}" >> "${app_props}"
            info "Added ${prop_key} to application.properties"
        fi
    else
        cat > "${app_props}" <<EOF
# Adyaka IAM branding – generated by deploy.sh
${prop_key}=${prop_val}
server.servlet.context-path=/adyaka
spring.application.name=Adyaka
EOF
        info "Created ${app_props}"
    fi
}

# ── Import system configuration ───────────────────────────────────
import_sysconfig() {
    step "Importing Adyaka system configuration"

    detect_bin

    if [[ -n "${MP_BIN}" && -f "${MP_BIN}/ninja.sh" ]]; then
        info "Importing via ninja..."
        "${MP_BIN}/ninja.sh" import \
            --input "${BRAND_SYSCONFIG}" \
            --overwrite 2>&1 | grep -E "INFO.*import|Processed|error" | tail -5
        info "System config imported."
    else
        # Fallback: copy to post-initial-objects for next startup
        local pio_dir="${MP_HOME}/post-initial-objects"
        mkdir -p "${pio_dir}"
        cp "${BRAND_SYSCONFIG}" "${pio_dir}/100-systemConfiguration.xml"
        info "Copied to ${pio_dir}/100-systemConfiguration.xml (applied on next first-start)."
        warn "To apply immediately to a running server, run ninja manually:"
        warn "  \${MP_BIN}/ninja.sh import --input ${BRAND_SYSCONFIG} --overwrite"
    fi
}

# ── Rename admin user (midPoint → Adyaka) ─────────────────────────
rename_admin() {
    step "Patching administrator display name"

    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X PATCH \
        -H "Content-Type: application/xml" \
        -u "administrator:${MP_ADMIN_PASS}" \
        "${MP_URL}/ws/rest/users/00000000-0000-0000-0000-000000000002" \
        -d '<?xml version="1.0" encoding="UTF-8"?>
<objectModification
    xmlns="http://midpoint.evolveum.com/xml/ns/public/common/api-types-3"
    xmlns:c="http://midpoint.evolveum.com/xml/ns/public/common/common-3">
  <itemDelta>
    <modificationType>replace</modificationType>
    <path>c:givenName</path>
    <value>Adyaka</value>
  </itemDelta>
  <itemDelta>
    <modificationType>replace</modificationType>
    <path>c:fullName</path>
    <value>Adyaka Administrator</value>
  </itemDelta>
</objectModification>' 2>/dev/null)

    if [[ "${code}" == "204" ]]; then
        info "Administrator renamed to 'Adyaka Administrator'."
    else
        warn "Could not rename admin user (HTTP ${code}) – server may not be running yet."
    fi
}

# ── midPoint process control ──────────────────────────────────────
mp_start() {
    require_install
    detect_java
    info "Using Java: ${JAVA_HOME}"
    info "Starting midPoint..."
    if [[ "${MP_BIN}" == "__systemd__" ]]; then
        sudo systemctl start midpoint
    else
        JAVA_HOME="${JAVA_HOME}" "${MP_BIN}/midpoint.sh" start
    fi
    wait_for_app
}

mp_stop() {
    require_install
    info "Stopping midPoint..."
    if [[ "${MP_BIN}" == "__systemd__" ]]; then
        sudo systemctl stop midpoint
    else
        "${MP_BIN}/midpoint.sh" stop
    fi
    info "Stopped."
}

wait_for_app() {
    info "Waiting for Adyaka IAM to become ready (first start takes ~3 minutes)..."
    local max=300 i=0
    until curl -s -o /dev/null -w "%{http_code}" "${MP_URL}/login" 2>/dev/null | grep -q "200\|302"; do
        sleep 10
        i=$((i + 10))
        if [[ $i -ge $max ]]; then
            warn "Timed out after ${max}s."
            warn "Check logs: ${MP_HOME}/../logs/midpoint.log (or run: $0 logs)"
            return 1
        fi
        printf '.'
    done
    echo ""
    info "Application is up: ${MP_URL}"
    info "Login: administrator / ${MP_ADMIN_PASS}"
}

cmd_status() {
    echo ""
    detect_bin
    if [[ "${MP_BIN}" == "__systemd__" ]]; then
        systemctl status midpoint 2>/dev/null || true
    elif [[ -n "${MP_BIN}" && -f "${MP_BIN}/midpoint.sh" ]]; then
        "${MP_BIN}/midpoint.sh" status 2>/dev/null || true
    else
        local pid
        pid=$(pgrep -f "midpoint.jar" 2>/dev/null | head -1 || true)
        if [[ -n "${pid}" ]]; then
            info "midPoint process running (PID ${pid})"
        else
            warn "midPoint not found – is it installed? Run: $0 diag"
        fi
    fi
    echo ""
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "${MP_URL}/login" 2>/dev/null)
    if [[ "${code}" == "200" || "${code}" == "302" ]]; then
        info "Application is RUNNING at ${MP_URL}"
        info "Login: administrator / ${MP_ADMIN_PASS}"
    else
        warn "Application is NOT responding at ${MP_URL} (HTTP ${code:-no response})"
    fi
}

cmd_diag() {
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  Adyaka IAM – Environment Diagnostics"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "Script variables:"
    echo "  MP_HOME      = ${MP_HOME}"
    echo "  MP_URL       = ${MP_URL}"
    echo "  MP_BIN       = ${MP_BIN:-<not set>}"
    echo "  BRAND_STATIC = ${BRAND_STATIC}"
    echo ""

    echo "── midPoint install detection ──────────────────────────"
    detect_bin
    if [[ -n "${MP_BIN}" && "${MP_BIN}" != "__systemd__" ]]; then
        echo "  midpoint.sh  : FOUND at ${MP_BIN}/midpoint.sh"
    elif [[ "${MP_BIN}" == "__systemd__" ]]; then
        echo "  systemd      : midpoint service found"
    else
        echo "  midpoint.sh  : NOT FOUND"
        echo "  Searched:"
        for d in "$(dirname "${MP_HOME}")/bin" "/opt/midpoint/bin" "/usr/local/midpoint/bin" "${HOME}/midpoint/bin"; do
            echo "    ${d}/midpoint.sh → $([ -f "${d}/midpoint.sh" ] && echo EXISTS || echo missing)"
        done
    fi

    echo ""
    echo "── midPoint home (MP_HOME) ─────────────────────────────"
    if [[ -d "${MP_HOME}" ]]; then
        echo "  EXISTS: ${MP_HOME}"
        echo "  Contents: $(ls "${MP_HOME}" 2>/dev/null | tr '\n' '  ')"
    else
        echo "  MISSING: ${MP_HOME}"
    fi

    echo ""
    echo "── JAR detection ───────────────────────────────────────"
    local jar
    jar="$(find "$(dirname "${MP_HOME}")" /opt /usr/share/midpoint 2>/dev/null \
        -name "midpoint.jar" -maxdepth 5 2>/dev/null | head -1)"
    echo "  midpoint.jar : ${jar:-NOT FOUND}"

    echo ""
    echo "── Running process ─────────────────────────────────────"
    local pid
    pid=$(pgrep -f "midpoint.jar" 2>/dev/null | head -1 || true)
    echo "  Java process : ${pid:-NOT RUNNING}"

    echo ""
    echo "── App URL health check ────────────────────────────────"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "${MP_URL}/login" 2>/dev/null)
    echo "  GET ${MP_URL}/login → HTTP ${code:-no response}"

    echo ""
    echo "── Brand assets ────────────────────────────────────────"
    echo "  BRAND_STATIC  : $([ -d "${BRAND_STATIC}" ] && echo EXISTS || echo MISSING)"
    echo "  midpoint.css  : $([ -f "${BRAND_STATIC}/static/midpoint.css" ] && echo "$(wc -c < "${BRAND_STATIC}/static/midpoint.css") bytes" || echo MISSING)"
    echo "  logo SVG      : $([ -f "${BRAND_STATIC}/static/img/adyaka_logo_white.svg" ] && echo EXISTS || echo MISSING)"
    echo "  system config : $([ -f "${BRAND_SYSCONFIG}" ] && echo EXISTS || echo MISSING)"

    echo ""
    echo "── How to fix ──────────────────────────────────────────"
    if [[ -z "${MP_BIN}" || "${MP_BIN}" == "__systemd__" ]]; then
        echo "  If midPoint is installed at a non-standard path:"
        echo "    MP_HOME=/your/midpoint/var MP_BIN=/your/midpoint/bin $0 deploy"
        echo ""
        echo "  If midPoint is NOT installed yet, download from:"
        echo "    https://download.evolveum.com/midpoint/"
        echo "    Extract and run: bin/midpoint.sh start"
        echo "    Then run this script."
    fi
    echo ""
}

cmd_logs() {
    local log_file
    log_file="$(find "${MP_HOME}/.." /opt/midpoint /usr/share/midpoint \
        -name "midpoint.log" -maxdepth 5 2>/dev/null | head -1)"
    if [[ -z "${log_file}" ]]; then
        error "Log file not found. Try: find / -name midpoint.log 2>/dev/null"
        exit 1
    fi
    info "Tailing ${log_file}"
    tail -f "${log_file}"
}

# ── Main ──────────────────────────────────────────────────────────
echo ""
info "Adyaka IAM – Local Deployment"
info "midPoint home : ${MP_HOME}"
info "App URL       : ${MP_URL}"
echo ""

case "${CMD}" in
    deploy)
        detect_java
        check_postgres
        write_config
        write_app_properties
        bundle_css
        deploy_assets
        import_sysconfig
        rename_admin
        info "Branding deployed. Restart midPoint for changes to take effect."
        ;;
    start)
        detect_java
        check_postgres
        write_config
        write_app_properties
        bundle_css
        deploy_assets
        init_schema
        mp_start
        import_sysconfig
        rename_admin
        ;;
    stop)
        mp_stop
        ;;
    restart)
        mp_stop
        detect_java
        check_postgres
        write_app_properties
        bundle_css
        deploy_assets
        mp_start
        import_sysconfig
        rename_admin
        ;;
    status)
        cmd_status
        ;;
    logs)
        cmd_logs
        ;;
    diag)
        cmd_diag
        ;;
esac
