# Web-only Docker deployment

Uses Tucano's existing experimental server mode, without changing application code.
No Electron binary, display server, Chromium, or local model is needed at runtime.
The base image runs the UI and core; agents need a harness installed and signed in
inside the container. See [server.md](server.md) for server-mode limitations.

## Start

```sh
docker compose up -d --build
docker compose logs tucano
```

Open the printed `http://localhost:7337/?token=…` link. Treat that token as a password.
The port is bound to localhost only. For remote access use an SSH tunnel or an HTTPS
reverse proxy (disable buffering for `/events`). Do not publish HTTP directly to the internet.

## Harnesses

Host CLIs and logins are not automatically available inside containers. Install a
Linux-compatible harness as the container's non-root user into the persistent home:

```sh
# Example: Codex. Pin a package version when deploying reproducibly.
docker compose exec tucano npm install --prefix /home/node/.local -g @openai/codex
docker compose exec tucano /home/node/.local/bin/codex login --device-auth
```

Codex agents use Tucano's isolated Codex home, not the default CLI home. Use the exact
login command shown by **Settings → Models → Sign in** inside a container shell:

```sh
docker compose exec tucano sh
```

Other harnesses (including OpenCode) can be installed under `/home/node/.local/bin`
or `/home/node/.opencode/bin`. They must support the container's Linux architecture.
Sign in there, then refresh Models in Tucano. Do not mount your whole host home or
copy unverified host binaries into the image. For reproducible deployments, build a
derived image with a pinned harness version rather than installing it interactively.

### OpenCode sign-in inside Docker

`opencode auth login` starts an OAuth callback listener inside the container, but your
browser runs on the host, so the redirect never reaches Docker and OAuth logins hang.
There are two ways to add access; neither logs into Tucano itself — Tucano reads the
container's OpenCode accounts when running agents.

**Easy way (API-key providers, no browser):** log in directly inside the container.
OpenCode prompts for the secret in the terminal:

```sh
docker compose exec tucano opencode auth login <provider> --method key
```

Example: `docker compose exec tucano opencode auth login nvidia --method key`. The
provider's form field appears in the prompt; paste your key and press Enter. Saved in
`/home/node/.local/share/opencode/opencode.db`, which lives in the persistent
`tucano-home` volume. Verify with `docker compose exec tucano opencode auth list`.

**OAuth providers (OpenAI, etc.):** log in **on the host** (browser flow works there),
then copy OpenCode v2's credential database into the container:

```sh
# Host: stop any OpenCode server, then copy the credential DB
docker compose stop tucano
docker cp ~/.local/share/opencode/opencode.db* tucano-tucano-1:/home/node/.local/share/opencode/
docker compose start tucano
```

OpenCode v2 stores accounts in `~/.local/share/opencode/opencode.db` (XDG default),
which lives in the persistent `tucano-home` volume, so accounts survive restarts,
recreation, and image rebuilds.

The container already has OpenCode 2.2.5 installed in that same volume, so the CLI
and credentials persist across `docker compose down` (never use `-v`, which deletes
the volumes).

## Persistent data and backups

- `tucano-data` → `/data`: SQLite database, backups, artifacts, computers' files,
  `server.key`, `server-token`, isolated harness state.
- `tucano-home` → `/home/node`: installed CLIs, logins, configuration and files
  created under the container user's home.

Both survive container recreation, image rebuilds, and `docker compose down`.
**Never use `docker compose down -v` unless intentionally deleting all data.**
Files created outside these two locations are not persistent. Keep projects under
`/home/node/projects` or explicitly mount their folders. Container paths refer to
the container, not your desktop. Never run two Tucano processes on the same database.

Stop the service for a consistent backup of both volumes (including SQLite WAL
files and `server.key`). Backups and harness credentials are sensitive:

```sh
mkdir -m 700 -p backups
docker compose stop tucano
docker compose run --rm --no-deps -T tucano tar -czf - -C /data . > backups/data.tar.gz
docker compose run --rm --no-deps -T tucano tar -czf - -C /home/node . > backups/home.tar.gz
chmod 600 backups/*.tar.gz
docker compose start tucano
```

Restore both archives to the corresponding volumes as UID/GID 1000, with the
service stopped. Copying a desktop database alone is not a migration: desktop
secrets use the OS keychain, while server secrets require `server.key`.

## Memory and portability

The runtime is Debian slim with plain Node, not Electron. Compose defaults to a
**1 GiB total container limit**, a 384 MiB heap limit per Node process, and 1 CPU.
These are limits, not expected RAM consumption. CLIs add processes and memory;
too small a limit can kill an active turn. Upstream recommends a host with at least
2 GB RAM. Increase limits for parallel agents, heavy connectors, or large projects:

```sh
TUCANO_MEMORY=2g TUCANO_HEAP_MB=768 TUCANO_CPUS=2 docker compose up -d
docker stats --no-stream
```

Builds use more resources than the running server. The image can be built for Linux
amd64 or arm64 where the base image and chosen harness support that architecture;
other hosts need a Linux container engine. This is not a guarantee every harness
works on every CPU.

Chromium and Docker-in-Docker are deliberately omitted to keep the runtime small.
Agent desktop interaction is unavailable. Enabling "this computer" gives an agent
the container, not the host. Do not mount `/var/run/docker.sock`: it grants powerful
host access. Agent browser/isolated-computer features need a separate, explicit setup.

## Update

```sh
git pull --ff-only
docker compose up -d --build
```

Volumes are reused. Back them up before upgrades; database migrations may not be
reversible. No desktop database or host credentials are modified by this setup.
