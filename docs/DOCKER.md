# Docker deployment on an Ubuntu VPS

The Compose service uses Linux host networking. BombSquad listens on the
`config.json` port over UDP, and the optional web manager uses the same port
over TCP. Host networking exposes both without maintaining two port mappings.

## First deployment

Install Docker Engine and its Compose plugin using Docker's instructions for
your Ubuntu release. Then clone the repository and enter it:

```bash
git clone --depth=1 --branch main https://github.com/ainahrm/aina-bombsquad-server.git
cd aina-bombsquad-server
```

Edit `config.json` and `dist/ba_root/mods/setting.json` before starting. In
particular, replace the example passwords and admin account ID.

Open the configured port (43211 in the checked-in `config.json`) in both the
VPS firewall and the cloud provider firewall/security group:

```bash
sudo ufw allow 43211/udp
# Only needed when the web manager is enabled and should be public:
sudo ufw allow 43211/tcp
```

Build and start the server:

```bash
docker compose up -d --build
docker compose logs -f --tail=100
```

The checkout is mounted at `/app` and the container's `HOME` is set to `/app`,
so runtime data remains on the VPS when the container is replaced. Back up at least `config.json`,
`dist/ba_root/mods/setting.json`, `dist/ba_root/mods/playersdata/`, and
`shared_bcs_data/` if it is created.

## Routine commands

```bash
docker compose ps
docker compose logs -f --tail=100
docker compose restart
docker compose down
docker compose up -d
```

To update the code and rebuild the runtime image:

```bash
git pull --ff-only
docker compose up -d --build
```

Do not run the repository's `setup.sh` on the same deployment: it installs a
systemd service which would compete with Docker for the same server port.
