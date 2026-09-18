# Home Assistant Port Redirect

A small Home Assistant app repository:

| App | What it does |
| --- | --- |
| [`port_redirect`](port_redirect/DOCS.md) | nginx answers on Home Assistant's previous HTTP port (8123 by default) with permanent HTTP redirects to the port it runs on now (80 by default), so old bookmarks, companion app logins and API clients keep working after Home Assistant moves. |

Redirects only — no proxying, no kernel NAT, no extra privileges.

## Install

1. Settings → Apps → *Install app* → ⋮ → **Repositories**.
2. Add `https://github.com/megakid/ha-app-port-redirect` and close the dialog.
3. *Port Redirect* appears in the store — install it.

The Supervisor builds the image on your machine the first time (a few seconds,
well under 20 MB).

## Move Home Assistant to port 80 (the reason this exists)

```yaml
# configuration.yaml
http:
  server_port: 80
```

Restart Core. Then install — or just keep — the app, which starts serving as soon
as it sees Home Assistant on 80 and 8123 free:

```sh
curl -sI http://<host>:8123/ | head -1     # HTTP/1.1 308 Permanent Redirect
curl -sI http://<host>:8123/ | grep -i location   # Location: http://<host>/
curl -sL -o /dev/null -w '%{http_code}\n' http://<host>:8123/   # 200 from Home Assistant
```

`308` is the default because it preserves the HTTP method: a `POST` to the old
port (companion app login, `/api/…`, a webhook) still works. Set `status: "301"`
for the classic permanent redirect if you only care about `GET`s.

More: [`port_redirect/DOCS.md`](port_redirect/DOCS.md) — options, the migration
checklist, the Supervisor's port handling, troubleshooting, and rollback
(`stop the app first — while it runs, it owns 8123`).

## Development

```sh
# the app is plain shell; check it before installing
shellcheck port_redirect/run.sh

# install straight from this checkout (copies the app into the local app folder)
ssh root@<ha-host> 'mkdir -p /addons/port_redirect'
scp -r port_redirect/. root@<ha-host>:/addons/port_redirect/
ssh root@<ha-host> 'ha store reload && ha apps install local_port_redirect && ha apps start local_port_redirect'
ssh root@<ha-host> 'ha apps logs -f local_port_redirect'
```

To exercise the redirect without moving Home Assistant first, point it at a spare
port and something that does listen: `listen_port: 18123`, `target_port: 80` with
any listener on 80 starts nginx immediately.

Bump `version` in `port_redirect/config.yaml` and add a `CHANGELOG.md` entry for
each release; the Supervisor offers the update as soon as the repository is
re-read.

## License

MIT — see [LICENSE](LICENSE).