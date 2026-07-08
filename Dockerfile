FROM debian:trixie-slim
LABEL Name=fog Version=1.0.0

# envs
ENV FOG_VERSION=1.5.10.1870 \
    HTTP_ADDRESS=0.0.0.0 \
    HTTP_PORT=80

# install needed packages
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        apt-transport-https ca-certificates nano wget iproute2 sysv-rc-conf \
        build-essential mariadb-client mariadb-server \
        systemd systemd-timesyncd kmod \
        autoconf bison flex pkg-config libtirpc-dev \
    && rm -rf /var/lib/apt/lists/*
# systemd systemd-timesyncd > prevent /usr/bin/systemctl hook override
# kmod > nfs-kernel-server modules loading (modprobe)

# retrieve fog tarball
RUN wget https://github.com/FOGProject/fogproject/archive/refs/tags/${FOG_VERSION}.tar.gz \
    && tar xvfz ${FOG_VERSION}.tar.gz -C /root \
    && rm ${FOG_VERSION}.tar.gz

# handle needed resources
COPY resources /root/resources
RUN cp /root/resources/entry.sh /usr/bin/entry.sh \
    && chmod +x /usr/bin/entry.sh /root/resources/prepare.sh \
    && /root/resources/prepare.sh

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s \
    CMD wget --spider --quiet http://localhost:${HTTP_PORT}/ || exit 1

# entry point
ENTRYPOINT ["/usr/bin/entry.sh"]
