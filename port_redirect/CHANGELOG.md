<!-- https://developers.home-assistant.io/docs/apps/presentation#keeping-a-changelog -->
## 1.1.0

* Log every hit (`log_requests`, default on): one line per request with client
  address, method, status, the host name the client used, the target URL, the
  requested path and the user agent - the trail you follow to find the last
  clients still using the old port.
* The log line is written by nginx to stdout, so it lands in the app log next to
  the app's own messages and can be dumped with `ha apps logs -n`.

## 1.0.0

* Initial release.
* nginx answers on Home Assistant's previous HTTP port (default 8123) with
  permanent `<status> http://<same-host>:<new-port><same-path>` redirects to the
  port Home Assistant runs on now (default 80). IPv4 and IPv6.
* Starts only once Home Assistant is serving the new port and the old one is free,
  so it can be installed before the move, never races Home Assistant for its port
  and never blocks a rollback.
* No proxying, no kernel NAT, no extra privileges: `host_network` only.