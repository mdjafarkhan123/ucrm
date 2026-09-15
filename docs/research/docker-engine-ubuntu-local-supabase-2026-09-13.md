# Docker Engine setup for local Supabase testing

Research date: 2026-09-13

## Recommendation

This computer is running Ubuntu 26.04.1 LTS (`resolute`) on x86_64. Docker officially supports Ubuntu Resolute 26.04 and this architecture.

Install **Docker Engine** from Docker's official `apt` repository. Docker Desktop is not required for this project's command-line workflow. Supabase needs a Docker-compatible container runtime; Docker Engine provides that runtime, while the Compose plugin included below also prepares the computer for normal Docker Compose commands.

This local Supabase stack is disposable development/test infrastructure. It does not replace the managed remote Supabase project and must not be exposed to the internet.

## Before installing

Check whether conflicting packages exist:

```bash
dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc 2>/dev/null
```

If that command lists any package as `install`, stop and review it before removal. Docker's official guide requires conflicting packages to be removed, but removal should not be done blindly if the computer already has containers or Podman in use.

## Installation commands

Copy and run each block in Terminal. Ubuntu will ask for the computer password; typed password characters are intentionally invisible.

Add Docker's official signing key:

```bash
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

Add Docker's official Ubuntu repository:

```bash
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
```

Install Docker Engine and its official Compose/Build plugins:

```bash
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

## Verify the installation

```bash
sudo systemctl status docker --no-pager
sudo docker run --rm hello-world
docker compose version
```

The important success message is `Hello from Docker!`. On Ubuntu, Docker normally starts automatically now and after reboot.

## Allow project commands without `sudo`

The Supabase CLI needs to call Docker as the logged-in user. Docker's standard workstation setup is:

```bash
sudo usermod -aG docker "$USER"
```

Then **sign out of Ubuntu completely and sign back in**. Opening only a new Terminal is not always enough. Verify afterward:

```bash
docker run --rm hello-world
docker compose version
```

Important: membership in the `docker` group effectively grants root-level control of this computer. It is standard and convenient for a trusted single-user development machine, but should not be granted to untrusted accounts.

## What happens next in this project

Once the two verification commands work without `sudo`, Codex can start the disposable local Supabase containers and run the migration/database tests. The managed remote Supabase database remains unchanged unless a later, separate remote deployment is explicitly approved.

## Official sources

- [Docker Engine installation on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Docker Engine Linux post-installation](https://docs.docker.com/engine/install/linux-postinstall/)
- [Supabase CLI local development setup](https://supabase.com/docs/guides/local-development/cli/getting-started)
- [Supabase local development workflow and safety warning](https://supabase.com/docs/guides/local-development/cli-workflows)
