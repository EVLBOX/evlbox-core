# evlbox-core

Base layer for [EVLBOX Stacks](https://evlbox.com) — pre-configured open-source server stacks on VPS.

## What This Does

Every EVLBOX Stack builds on this core. It installs:

- **Docker + Docker Compose** — container runtime
- **UFW + fail2ban** — firewall and brute-force protection
- **Diun** — container update notifications
- **unattended-upgrades** — automatic OS security patches
- **Gum** — pretty terminal UI ([Charm](https://charm.sh))
- **`evlbox` CLI** — manage your stack from the command line
- **Branded MOTD** — welcome message with getting-started instructions

> Caddy (reverse proxy) runs in Docker as part of each stack's `compose.yml`, not in core.

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

## For Stack Developers

Your stack's `provision.sh` installs core first:

```bash
curl -fsSL https://raw.githubusercontent.com/evlbox/evlbox-core/main/install.sh | bash
```

Then your stack provisions its files to `/opt/evlbox/stack/`:

| File | Required | Purpose |
|------|----------|---------|
| `compose.yml` | Yes | Docker Compose services |
| `setup.sh` | Yes | First-time setup wizard (TUI) |
| `backup.sh` | Yes | Backup script |
| `.env.example` | Yes | Default environment variables |

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

TBD

---

*Maintained by [EVLBOX](https://evlbox.com)*
