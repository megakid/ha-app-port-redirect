# Home Assistant App: Port Redirect

_Answers on Home Assistant's previous HTTP port with permanent redirects to its
new one, so old URLs keep working after a port change._

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]

Pure redirects, no proxying and no kernel NAT: nginx replies
`308 http://<same host><same path>` and the client reconnects to Home Assistant
directly, so client IP addresses, `ip_bans` and `trusted_proxies` keep working
exactly as before.

It starts only once Home Assistant serves the new port and the old one is free, so
it is safe to install before the move and cannot lock you out of Home Assistant.
See [DOCS.md](DOCS.md) for options, the migration steps, verification and
troubleshooting.

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg