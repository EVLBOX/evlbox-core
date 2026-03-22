# evlbox-core

> **⚠️ Work in Progress.** This project is under active development and not yet production-ready. Use at your own risk. EVLBOX provides no warranty, support, or liability for damages arising from use of this software. See [LICENSE](LICENSE).

Shared base layer for [EVLBOX](https://evlbox.com) server deployments.

## What This Does

Sets up a secure, Docker-ready Debian server with a management CLI:

- **Docker + Docker Compose** — container runtime
- **UFW + fail2ban** — firewall and brute-force protection
- **Diun** — container update notifications
- **unattended-upgrades** — automatic OS security patches
- **Gum** — terminal UI toolkit ([Charm](https://charm.sh))
- **`evlbox` CLI** — server management from the command line

## evlbox CLI

```
evlbox status          Show services, system info, and backup status
evlbox setup           Run the first-time setup wizard
evlbox update          Pull latest images and restart (backs up first)
evlbox backup          Create a backup snapshot
evlbox backup list     List available backup snapshots
evlbox rollback        Restore from a backup snapshot
evlbox restart [svc]   Restart all services (or one)
evlbox logs [svc]      Tail service logs (or one)
evlbox secure-ssh      Disable password auth after adding your SSH key
evlbox help            Show all commands
```

## Development

```bash
# Lint (requires shellcheck)
make lint

# Run tests (requires bats)
make test

# Install CLI locally
sudo make install
```

## License

GPL-3.0 — see [LICENSE](LICENSE)

---

*[EVLBOX](https://evlbox.com)*
