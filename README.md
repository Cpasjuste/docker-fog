# docker-fog

This is a docker image for running a [fog imaging server](https://github.com/FOGProject/fogproject). 

Two nfs server choice is available in this image:

- **[unfs3](https://github.com/unfs3/unfs3)**: An userland nfs server. This prevent the need for running the image in privileged mode and should improve security. This seems to works very fine, but needs more testing.
- **nfs-kernel-server**: fog (and linux) default choice. The nfs-kernel-server needs privileged mode for loading kernel modules and mounting.

The image can be run with three networking mode:

- **host**: The host network interface is mounted inside the container. All seems to works fine, including multicasting. The ports needs to be free on the host. A firewall should probably be configured on the host (see the *Ports* section).
- **macvlan**: A custom network interface is created in the container with it's own ip and mac address on the existing network (which allow multicast). All seems to works fine, including multicasting.
- **bridge**: Only the ports specified in the compose file (or docker cmd) are accessible to the host. While [bridge multicasting should be possible](https://oneuptime.com/blog/post/2026-02-08-how-to-configure-docker-containers-for-multicast-traffic/view), no work have been done in this direction and so **multicasting is not working** in this mode.

Docker environment variables are explained in the following compose file.

## docker compose sample


```yaml
services:
  fog:
    image: cpasjuste/fog
    restart: unless-stopped
    #privileged: true # for nfs-kernel-server mode
    environment:
      HTTP_ADDRESS: ${HTTP_ADDRESS:-192.168.0.1} # also used for ftp/tftp/nfs/...
      HTTP_PORT: ${HTTP_PORT:-9445} # you can use a custom http port
      PHP_FPM_PORT: ${PHP_FPM_PORT:-9444} # listen on localhost, no need to open port in firewall
      INTERFACE_NAME: ${INTERFACE_NAME:-eth0} # interface name for multicast, wol, etc...
      WEB_PASSWORD: ${WEB_PASSWORD:-password} # web user (fog) password
      MYSQL_PASSWORD: ${MYSQL_PASSWORD:-dockerfogsql} # mysql user (fog) password
      # builtin storage (shell/nfs/ftp/tftp...) password
      # use alphanumeric because it is not handled correctly by fog (php?)
      STORAGE_PASSWORD: ${STORAGE_PASSWORD:-dockerfogstorage}
      USE_UNFS3: true # use userland nfs server (no need for privileged mode)
    volumes:
      - database:/var/lib/mysql
      - /images:/images
      #- /lib/modules:/lib/modules:ro # for nfs-kernel-server mode
    ports:
      - "${HTTP_PORT:-9445}:${HTTP_PORT:-9445}" # web
      - "21:21"                                 # ftp
      - "69:69/udp"                             # tftp
      - "111:111"                               # nfs
      - "2049:2049"                             # nfs
      - "20048:20048"                           # nfs
      #- "55000-60000:55000-60000/udp"          # multicast (not working in bridged network)

volumes:
  database:
```

## Host mode networking
Multicast is working in host networking mode

### Ports
Web port 80 and php-fpm port 9000 are configurable via docker environment variable. The php-fpm port doesn't need to be exposed (listen on localhost).

    | PORT            | SERVICE |
    |-----------------|---------|
    | 21/tcp          | ftp     |
    | 80/tcp          | web     |
    | 69/udp          | tftp    |
    | 111/tcp         | nfs     |
    | 2049/tcp        | nfs     |
    | 9000/tcp        | php-fpm |
    | 20048/tcp       | nfs     |
    | 55000:60000/udp | udpcast |

## Bridge mode networking
Multicast is not working in bridge networking mode

### Ports
Web port 80 is configurable.

    | PORT            | SERVICE |
    |-----------------|---------|
    | 21/tcp          | ftp     |
    | 80/tcp          | web     |
    | 69/udp          | tftp    |
    | 111/tcp         | nfs     |
    | 2049/tcp        | nfs     |
    | 20048/tcp       | nfs     |
