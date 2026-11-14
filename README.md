# docker-fog

A single-container [FOG Project](https://github.com/FOGProject/fogproject) imaging server (FOG 1.6.x, Debian trixie), served over **HTTPS only**.

Everything FOG needs runs inside the container under [supervisord](http://supervisord.org/): MariaDB, Apache + PHP-FPM, TFTP, FTP, NFS, and the FOG daemons (multicast, replicators, scheduler, and so on).

- **No privileged mode by default**: images are exported with [unfs3](https://github.com/unfs3/unfs3), a userland NFS server.
- **Self-configuring**: on first start the FOG installer runs again with your hostname and IP address. It generates the CA and certificates and rebuilds iPXE with that CA.
- **Persistent**: the database, snapins, PKI and images are stored in volumes. Empty volumes are seeded with defaults on first start.

> DHCP is **not** provided. Point your existing DHCP server at the FOG server (option 66 `next-server` = `HOST_ADDRESS`, option 67 `bootfile`, e.g. `ipxe.efi` / `undionly.kpxe`).

---

## Quick start

```sh
curl -O https://raw.githubusercontent.com/Cpasjuste/docker-fog/main/compose.yaml
# edit HOST_ADDRESS (and passwords), or put them in a .env file next to compose.yaml
docker compose up -d
docker compose logs -f   # wait for "[docker-fog] all done, fog is ready"
```

Then open `https://<HOST_ADDRESS>/fog/` and log in as `fog` / `WEB_PASSWORD`.

The first start takes a few minutes because the installer runs and iPXE is rebuilt. Later starts are fast.

Example `.env`:

```env
HOST_NAME=fog
HOST_ADDRESS=192.168.1.10
INTERFACE_NAME=eth0
WEB_PASSWORD=changeme
MYSQL_PASSWORD=changemeSql
STORAGE_PASSWORD=changemeStorage
```

---

## Configuration

### Environment variables

| Variable           | Default            | Description |
|--------------------|--------------------|-------------|
| `HOST_NAME`        | `fog`              | Server hostname, used for the web UI URL and in certificates. Clients must be able to resolve it. |
| `HOST_ADDRESS`     | `192.168.0.1`      | Server LAN IP, used for TFTP, FTP, NFS and certificate SANs. |
| `INTERFACE_NAME`   | `eth0`             | Network interface used for multicast, WOL and NFS monitoring. In host mode this is the **host** interface name. |
| `WEB_PASSWORD`     | `password`         | Password of the `fog` web UI user. It is reapplied on every start. |
| `MYSQL_PASSWORD`   | `dockerfogsql`     | Password of the `fogmaster` MariaDB user. |
| `STORAGE_PASSWORD` | `dockerfogstorage` | Password of the `fogproject` system user (storage node: FTP, SSH, NFS). **Alphanumeric only.** |
| `USE_UNFS3`        | `true`             | `true`: userland NFS server (unfs3). `false`: `nfs-kernel-server` (see below). |

All of these values are reapplied to the FOG configuration and database on every container start. To change one, edit it and restart the container.

> `HOST_NAME` and `HOST_ADDRESS` are written into the certificates during the **first** start. To change them later, empty the `pki` volume so that the CA and iPXE are generated again. Clients that already trust the old CA must then be updated.

### Volumes

| Path                | Content |
|---------------------|---------|
| `/var/lib/mysql`    | FOG database |
| `/images`           | Captured / deployed images (a bind mount is recommended) |
| `/opt/fog/snapins`  | Snapins and the client CA |
| `/etc/fog/pki`      | Generated CA, web, client and secure-boot certificates. **Back it up.** |

If `/var/lib/mysql` or `/images` is empty at start, it is filled with the default content captured at build time. If `/etc/fog/pki` is empty, the installer runs again.

Logs of all services are written to `/opt/fog/log` inside the container.

---

## NFS server

| Mode | `USE_UNFS3` | Privileged | Notes |
|------|-------------|------------|-------|
| **unfs3** (default) | `true` | no | Userland server. NFS runs on 2049/tcp and mountd on 20048/tcp. It works well but has had less testing. |
| **nfs-kernel-server** | `false` | **yes** | The standard FOG setup. It needs `privileged: true` and `/lib/modules:/lib/modules:ro` to load the kernel modules. mountd runs on 32767 and statd on 32765. |

`/images` is exported read-only (deploy) and `/images/dev` read-write (capture).

---

## Networking modes

| Mode | Multicast | Notes |
|------|-----------|-------|
| **host** | ✅ | The container uses the host network stack, so the ports below must be free on the host. Consider a host firewall. See [`compose.debug-host.yaml`](compose.debug-host.yaml). |
| **macvlan** | ✅ | The container gets its own IP and MAC address on the LAN. |
| **bridge** | ❌ | Only the published ports are reachable. [Multicast over a bridge is possible](https://oneuptime.com/blog/post/2026-02-08-how-to-configure-docker-containers-for-multicast-traffic/view) but not implemented. See [`compose.yaml`](compose.yaml). |

### Host

```yaml
services:
  fog:
    image: cpasjuste/fog:latest
    network_mode: host
    # environment / volumes: same as compose.yaml, no "ports:" section
```

### Macvlan

```yaml
services:
  fog:
    image: cpasjuste/fog:latest
    # environment / volumes: same as compose.yaml, no "ports:" section
    # HOST_ADDRESS must be the ipv4_address below
    networks:
      lan:
        ipv4_address: 192.168.1.10

networks:
  lan:
    driver: macvlan
    driver_opts:
      parent: eth0          # host interface
    ipam:
      config:
        - subnet: 192.168.1.0/24
          gateway: 192.168.1.1
```

> With macvlan the Docker host itself cannot reach the container's IP. This is a Linux macvlan limitation. Other machines on the LAN are not affected.

### Ports

| Port              | Service | Bridge | Notes |
|-------------------|---------|:------:|-------|
| 443/tcp           | HTTPS (web UI, iPXE) | ✅ | |
| 21/tcp            | FTP     | ✅ | |
| 69/udp            | TFTP    | ✅ | |
| 111/tcp           | rpcbind | ✅ | |
| 2049/tcp          | NFS     | ✅ | |
| 20048/tcp         | mountd  | ✅ | unfs3 only |
| 32765, 32767      | statd / mountd | — | nfs-kernel-server only |
| 55000-60000/udp   | udpcast (multicast) | ❌ | host / macvlan only |

SSH is used internally by FOG and only listens on `127.0.0.1`.

---

## Building

```sh
# development image (cpasjuste/fog:dev), host networking
docker compose -f compose.debug-host.yaml up -d --build

# or bridge networking
docker compose -f compose.debug-bridge.yaml up -d --build

# plain build, optionally choosing the FOG release
docker build --build-arg FOG_VERSION=1.6.0.158 -t cpasjuste/fog:dev .
```

To use custom settings for testing, copy [`.env.example`](.env.example) to `.env` and uncomment what you need. Docker compose loads `.env` automatically, and git ignores it. The debug compose files also read these build settings from it:

| Variable        | Default             | Description |
|-----------------|---------------------|-------------|
| `IMAGE_NAME`    | `cpasjuste/fog:dev` | Tag of the built image |
| `FOG_VERSION`   | `1.6.0.158`         | [FOG release tag](https://github.com/FOGProject/fogproject/tags) to build |
| `UNFS3_VERSION` | `0.11.0`            | [unfs3 release](https://github.com/unfs3/unfs3/releases) to build |

The runtime variables (`HOST_ADDRESS`, passwords and so on) and `USE_UNFS3` can be set in the same file.

### How the image works

```
build  : apt install deps → build unfs3 → download FOG → installfog.sh (placeholder settings)
         → delete PKI → snapshot /var/lib/mysql and /images
start  : (empty pki)      installfog.sh with real HOST_NAME/HOST_ADDRESS, rebuild iPXE
         (empty volumes)  restore default database / images
         inject settings into .fogsettings, config.class.php and the database
         supervisord → NFS server → FOG daemons
```

| File | Role |
|------|------|
| [`Dockerfile`](Dockerfile) | Image build |
| [`resources/entry.sh`](resources/entry.sh) | Entrypoint: first-start install, runtime configuration, service start |
| [`resources/supervisord.conf`](resources/supervisord.conf) | Definitions of all services |
| [`resources/fogsettings`](resources/fogsettings) | Pre-seeded FOG installer answers, with placeholders replaced at runtime |
| [`resources/systemctl`](resources/systemctl) | No-op `systemctl` stub so the FOG installer runs without systemd |

---

## Troubleshooting

- **Clients fail to boot over HTTPS / certificate errors**: check that `HOST_NAME` resolves to `HOST_ADDRESS` from the clients. If either value changed after the first start, empty the `pki` volume.
- **Service status**: `docker exec fog supervisorctl status`
- **Logs**: `docker exec fog ls /opt/fog/log`, then `docker exec fog tail -f /opt/fog/log/<file>`
- **Multicast does not start**: use host or macvlan networking, and check `INTERFACE_NAME`.
