# Port Redirect

Answers on the port Home Assistant used to run on with **permanent HTTP
redirects** to the port it runs on now. Old bookmarks, companion app logins,
dashboards and API clients keep working after Home Assistant moves - they get told
where Home Assistant lives now and reconnect to it directly.

This app is the second half of moving Home Assistant to port 80:

```
before:  http://home:8123/  ->  Home Assistant (bound to 8123)
after:   http://home:80/    ->  Home Assistant (bound to 80)
         http://home:8123/  ->  308  http://home/  ->  Home Assistant
```

Nothing is proxied and no kernel NAT is involved: nginx only sends the redirect,
and the client talks to Home Assistant itself, so Home Assistant keeps seeing real
client IP addresses.

## Why 308 and not 301

Both are permanent. They differ in what happens to a redirected request that is
not a `GET`:

| | 301 Moved Permanently | 308 Permanent Redirect (default) |
| --- | --- | --- |
| Bookmark / dashboard `GET` | redirected | redirected |
| `POST` (companion app login, `/api/…`, webhooks) | most clients turn it into a `GET` and drop the body, so it fails | method and body are kept, so it works |
| Cached permanently by clients | yes | yes |

Set `status: "301"` if you specifically want the classic code and know your
clients only do `GET`s.

## Order of operations

The app only starts nginx once **Home Assistant is serving the new port and the
old port is free**. It is safe to install it before the move - it just waits and
says so in its log:

```
Waiting: TCP 8123 is still in use (Home Assistant has not moved off it yet).
Waiting: nothing is listening on TCP 80 yet (Home Assistant has not moved to it yet).
Serving permanent 308 redirects on TCP 8123 to Home Assistant on TCP 80.
```

1. Point Home Assistant at the new port (see
   [Moving Home Assistant](#moving-home-assistant-to-a-new-port)) and restart it.
2. Install this app (it can also be installed first and will wait).
3. Clients hitting the old port are redirected from then on.

Two things that follow from that rule, both deliberate:

* The app can never grab the old port while Home Assistant is still on it, so a
  failed move cannot lock you out of Home Assistant.
* **While the app is running it owns the old port.** If you ever move Home
  Assistant back, stop this app first.

## Options

| Option | Default | Description |
| --- | --- | --- |
| `listen_port` | `8123` | The port Home Assistant used to run on. |
| `target_port` | `80` | The port Home Assistant runs on now. |
| `status` | `"308"` | `308` (method-preserving) or `301`. |
| `log_requests` | `true` | One line per hit in the app log - see [Watching the migration](#watching-the-migration). |

The redirect keeps the requested host, path and query string:

```
http://home:8123/lovelace/0?edit=1
   -> 308 http://home/lovelace/0?edit=1
```

The host comes from the request, so LAN addresses, `homeassistant.local`, a
Tailscale name and IPv6 literals all work without configuration. IPv6 is served
whenever the host has IPv6 enabled; if your new port is not 80, the redirect
carries it (`http://home:8443/…`).

## Moving Home Assistant to a new port

In `configuration.yaml`:

```yaml
http:
  server_port: 80
```

then restart Home Assistant Core (`ha core restart`). Home Assistant Core runs as
root in a host-networked container on Home Assistant OS, so binding a privileged
port like 80 needs nothing else.

The Supervisor does not hardcode 8123: it learns Core's HTTP port from Core's own
HTTP config (it logs `Updating Core connection parameters from its HTTP config:
port 80, ssl False` and persists it) and uses that for its core API proxy, health
checks and reachability checks. Apps that use `homeassistant_api` keep working,
because they talk to `http://supervisor/core/api` rather than to the port.

After the move, remember the URLs that point at the old port elsewhere:
`internal_url`/`external_url` in Settings → System → Network, reverse proxies,
port forwards, dashboards, Node-RED flows, host-side scripts, and integrations
with hardcoded `http://…:8123` URLs.

## Verifying

```sh
curl -sI  http://<host>:8123/ | head -1        # HTTP/1.1 308 Permanent Redirect
curl -sI  http://<host>:8123/ | grep -i location
# Location: http://<host>/
curl -sL -o /dev/null -w '%{http_code}\n' http://<host>:8123/    # 200 from Home Assistant
curl -s  "http://<host>:8123/lovelace/0?x=1" -o /dev/null -w '%{redirect_url}\n'  # path+query kept
```

## Watching the migration

Every hit is logged by default, one line per request, so you can see who is still
arriving on the old port and retire the redirect only once nothing is:

```
2026-09-18T21:42:07+01:00 192.168.4.118 GET 308 host=192.168.4.55:8123 target="http://192.168.4.55/lovelace/0?edit=1" uri="/lovelace/0?edit=1" ua="Mozilla/5.0 (iPhone; CPU iPhone OS 19_0 like Mac OS X) HomeAssistant/2026.9"
```

| Field | What it tells you |
| --- | --- |
| `2026-09-18T21:42:07+01:00` | when it happened (sortable, timezone included) |
| `192.168.4.118` | the client's address |
| `GET` / `POST` | the method used - a `POST` only survives because the status is `308` |
| `308` | the status that was sent |
| `host=…` | the name or address the client used, e.g. an IP, `homeassistant.local:8123`, a Tailscale name |
| `target=…` | where the client was sent |
| `uri=…` | what it asked for |
| `ua=…` | the client itself: browser, companion app, script, integration |

Follow it live, or dump the history and triage (`2f3d8d14_` is the repository-id
prefix the Supervisor gives apps installed from this repo; check `ha apps` if you
installed it as a local app instead):

```sh
ha apps logs -f 2f3d8d14_port_redirect
ha apps logs 2f3d8d14_port_redirect -n 100000 > /tmp/redirect.log

grep -o 'ua="[^"]*"'     /tmp/redirect.log | sort | uniq -c | sort -rn  # which clients
grep -o 'host=[^ ]*'      /tmp/redirect.log | sort | uniq -c | sort -rn  # which names they use
awk '/target=/{print $2}' /tmp/redirect.log | sort | uniq -c | sort -rn  # which addresses
grep -o 'uri="[^"]*"'    /tmp/redirect.log | sort | uniq -c | sort -rn  # which pages/endpoints
awk '/POST|PUT|PATCH|DELETE/{print}' /tmp/redirect.log                   # non-GET traffic
```

When the lines stop - give it a couple of weeks, phones and tablets come home
only occasionally - the migration is done and the app can go. Set
`log_requests: false` to keep only the app's own state changes in the log.

Treat this log as sensitive: it records the request line verbatim, so webhook
tokens (`/api/webhook/<id>`) and query strings appear in it in full. Redact before
pasting it anywhere. A client whose WebSocket connection still arrives here
(`uri="/api/websocket"`) is one whose configured URL has not been updated -
WebSocket handshakes are not followed on a redirect, so that client needs its new
URL set on the device.

## Troubleshooting

**Log keeps saying the old port is in use** — something still listens there.
Check with `ss -ltnp | grep 8123`; your move has not taken effect yet (see the
Core log for `Address already in use`).

**Log keeps saying nothing listens on the new port** — Home Assistant is not
listening there yet, or not at all. Check `ss -ltnp | grep ':80'`. The app
deliberately refuses to take the old port until then.

**App stops right after starting** — invalid options; the log names them.

**"Address already in use" from nginx** — the old port became busy between the
check and the bind. The app retries every 10 seconds until it succeeds.

**Redirect loops** — that only happens if Home Assistant is bound to the *old*
port (then the app should not be running). Check `target_port`.

**HTTPS on the old port** — not supported. This app speaks plain HTTP; a client
asking for `https://host:8123` fails at the TLS handshake before any redirect.

## Removing

Settings → Apps → Port Redirect → Uninstall. Stopping or removing the app frees
the old port immediately; nothing else on the system is modified. Do it once the
per-request log has been quiet for a while.