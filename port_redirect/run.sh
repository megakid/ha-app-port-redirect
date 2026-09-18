#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
#
# Port Redirect
#
# After Home Assistant has moved to a new HTTP port, this app answers on the port
# it used before with permanent HTTP redirects, so old bookmarks, companion app
# logins and API clients find Home Assistant again. Nothing is proxied and no
# kernel NAT is involved: the client is told where Home Assistant now lives and
# reconnects to it directly.
#
set -euo pipefail

readonly NGINX_CONF=/data/nginx.conf
readonly WAIT_INTERVAL=15    # seconds between checks while waiting for the move
readonly RESTART_INTERVAL=10 # seconds before retrying nginx after it exits

LISTEN_PORT="$(bashio::config 'listen_port')"
TARGET_PORT="$(bashio::config 'target_port')"
STATUS="$(bashio::config 'status')"
readonly LISTEN_PORT TARGET_PORT STATUS

nginx_pid=''

cleanup() {
    if [ -n "${nginx_pid}" ]; then
        kill "${nginx_pid}" 2>/dev/null || true
    fi
}

shutdown() {
    bashio::log.info "Stopped, TCP ${LISTEN_PORT} is free again."
    cleanup
    exit 0
}

trap cleanup EXIT
trap shutdown TERM INT

# These values are interpolated into the nginx configuration, so they have to be
# exactly what the schema promised.
for port in "${LISTEN_PORT}" "${TARGET_PORT}"; do
    if ! [[ "${port}" =~ ^[0-9]{1,5}$ ]] || ((port < 1 || port > 65535)); then
        bashio::log.fatal "Not a valid TCP port: '${port}'."
        exit 1
    fi
done
if [ "${STATUS}" != 301 ] && [ "${STATUS}" != 308 ]; then
    bashio::log.fatal "status must be 301 or 308, not '${STATUS}'."
    exit 1
fi
if ((LISTEN_PORT == TARGET_PORT)); then
    bashio::log.fatal "listen_port and target_port are both ${LISTEN_PORT}, nothing to redirect."
    exit 1
fi

# Is any socket in the host network namespace listening on this port?
host_listens_on() {
    local needle
    needle=":$(printf '%04X' "$1")"
    awk -v needle="${needle}" '
        $4 == "0A" && substr($2, length($2) - length(needle) + 1) == needle { found = 1 }
        END { exit found ? 0 : 1 }
    ' /proc/net/tcp /proc/net/tcp6
}

target_port_suffix=''
if [ "${TARGET_PORT}" != 80 ]; then
    target_port_suffix=":${TARGET_PORT}"
fi

# Only add the IPv6 listener when the kernel has IPv6 at all, otherwise nginx
# refuses to start.
ipv6_listen=''
if [ -s /proc/net/if_inet6 ]; then
    ipv6_listen="        listen [::]:${LISTEN_PORT} default_server;"
fi

cat > "${NGINX_CONF}" <<EOF
worker_processes 1;
pid /tmp/port-redirect-nginx.pid;
error_log /dev/stderr warn;

events { worker_connections 64; }

http {
    access_log off;
    client_body_temp_path /tmp/port-redirect-body;
    proxy_temp_path /tmp/port-redirect-proxy;
    fastcgi_temp_path /tmp/port-redirect-fastcgi;
    uwsgi_temp_path /tmp/port-redirect-uwsgi;
    scgi_temp_path /tmp/port-redirect-scgi;

    server {
        listen ${LISTEN_PORT} default_server;
${ipv6_listen}
        server_name _;

        # \$host is the requested name without its port, \$request_uri keeps the
        # path and query string exactly as the client sent them.
        return ${STATUS} http://\$host${target_port_suffix}\$request_uri;
    }
}
EOF

if ! nginx -t -c "${NGINX_CONF}" 2>&1; then
    bashio::log.fatal "The generated nginx configuration is invalid, not starting."
    exit 1
fi

last_notice=''
notice() {
    if [ "${last_notice}" != "$1" ]; then
        bashio::log.info "$1"
        last_notice="$1"
    fi
}

bashio::log.info "Watching for Home Assistant to move from TCP ${LISTEN_PORT} to TCP ${TARGET_PORT}."

# nginx only starts once Home Assistant is actually serving the new port and the
# old port is free. That way the app can be installed before the move, it never
# races Home Assistant for the port it has not left yet, and it can never block
# Home Assistant from binding a port it is going back to.
while true; do
    if host_listens_on "${LISTEN_PORT}"; then
        notice "Waiting: TCP ${LISTEN_PORT} is still in use (Home Assistant has not moved off it yet)."
    elif ! host_listens_on "${TARGET_PORT}"; then
        notice "Waiting: nothing is listening on TCP ${TARGET_PORT} yet (Home Assistant has not moved to it yet)."
    else
        last_notice=''
        bashio::log.info "Serving permanent ${STATUS} redirects on TCP ${LISTEN_PORT} to Home Assistant on TCP ${TARGET_PORT}."
        nginx -c "${NGINX_CONF}" -g 'daemon off;' &
        nginx_pid=$!
        wait "${nginx_pid}" || bashio::log.warning "nginx exited, retrying in ${RESTART_INTERVAL}s."
        nginx_pid=''
        sleep "${RESTART_INTERVAL}" & wait $! || true
        continue
    fi
    sleep "${WAIT_INTERVAL}" & wait $! || true
done