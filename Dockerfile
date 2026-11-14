# =============================================================================
# docker-fog - FOG Project imaging server in a single container
#
# Build strategy:
#   1. Install every package the FOG installer needs (so it never calls apt).
#   2. Build unfs3, a userland NFS server (no privileged mode required).
#   3. Run the FOG installer once at build time with placeholder settings.
#   4. Strip the generated PKI and snapshot the default database and /images.
#
# On first start, entry.sh re-runs the installer with the real host settings
# (to generate the CA / certificates and rebuild iPXE), restores the default
# database and /images into empty volumes, then starts everything through
# supervisord.
# =============================================================================
FROM debian:trixie-slim
LABEL Name=fog Version=1.0.0

ARG DEBIAN_FRONTEND=noninteractive
ARG UNFS3_VERSION=0.11.0
# FOG release tag, override with `--build-arg FOG_VERSION=...`
ARG FOG_VERSION=1.6.0.158

# FOG_VERSION is kept at runtime (entry.sh needs the sources path).
# HOST_ADDRESS / INTERFACE_NAME are defaults, overridden at run / compose time.
ENV FOG_VERSION=${FOG_VERSION} \
    HOST_ADDRESS=0.0.0.0 \
    INTERFACE_NAME=eth0

# -----------------------------------------------------------------------------
# System packages
#   - container tooling : nano iproute2 iputils-ping sysv-rc-conf supervisor
#   - systemd + systemd-timesyncd : installed so that later package installs
#     never replace our fake /usr/bin/systemctl (see resources/systemctl)
#   - kmod : modprobe, needed by nfs-kernel-server
#   - autoconf bison flex pkg-config libtirpc-dev : unfs3 build dependencies
#   - the remaining packages are the exact list the FOG installer expects
#     (keep in sync with FOG_packages in resources/fogsettings)
# -----------------------------------------------------------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        apt-transport-https ca-certificates \
        nano iproute2 iputils-ping sysv-rc-conf supervisor \
        systemd systemd-timesyncd kmod lsb-release \
        autoconf bison flex pkg-config libtirpc-dev \
        apache2 attr bc build-essential cpp curl efitools g++ gawk gcc gcc-aarch64-linux-gnu \
        genisoimage git gzip htmldoc isolinux jq lftp libapache2-mod-php libc6 libcurl4t64 \
        liblzma-dev m4 mariadb-client mariadb-server net-tools nfs-kernel-server openssh-server \
        php php-bcmath php-cli php-curl php-fpm php-gd php-json php-ldap php-mbstring php-mysql php8.4-ssh2 \
        sbsigntool sudo tar tftpd-hpa tftp-hpa unzip vsftpd wget zlib1g \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# unfs3: userland NFS server (used when USE_UNFS3=true)
# -----------------------------------------------------------------------------
RUN cd /tmp \
    && wget -q https://github.com/unfs3/unfs3/releases/download/unfs3-${UNFS3_VERSION}/unfs3-${UNFS3_VERSION}.tar.gz \
    && tar -zxf unfs3-${UNFS3_VERSION}.tar.gz \
    && cd unfs3-${UNFS3_VERSION} \
    && ./configure && make && make install \
    && rm -rf /tmp/unfs3-${UNFS3_VERSION} /tmp/unfs3-${UNFS3_VERSION}.tar.gz

# -----------------------------------------------------------------------------
# FOG sources (kept in /root, the installer is re-run on first container start)
# The internet connectivity check is removed so the installer works offline.
# -----------------------------------------------------------------------------
RUN wget -q https://github.com/FOGProject/fogproject/archive/refs/tags/${FOG_VERSION}.tar.gz \
    && tar -zxf ${FOG_VERSION}.tar.gz -C /root \
    && rm ${FOG_VERSION}.tar.gz \
    && sed -i 's/checkInternetConnection//g' /root/fogproject-${FOG_VERSION}/bin/installfog.sh

# -----------------------------------------------------------------------------
# Container plumbing
# -----------------------------------------------------------------------------
# There is no systemd in the container: replace systemctl by a no-op stub so
# the FOG installer can "manage" services. The real binary is kept aside.
RUN mv /usr/bin/systemctl /usr/bin/systemctl.stock
COPY --chmod=755 resources/systemctl /usr/bin/systemctl

# The FOG installer refers to the MariaDB init script as "mysql"
RUN ln -sf /etc/init.d/mariadb /etc/init.d/mysql

# supervisord runs every service in the foreground (see supervisord.conf)
COPY resources/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Pre-seeded installer answers. Placeholders (0.0.0.0, eth0, localhost,
# #docker-fog-*#) are replaced by entry.sh at runtime.
COPY resources/fogsettings /opt/fog/.fogsettings
RUN sed -i "s/#docker-fog-version#/${FOG_VERSION}/g" /opt/fog/.fogsettings

COPY --chmod=755 resources/entry.sh /usr/bin/entry.sh

# -----------------------------------------------------------------------------
# Build-time FOG install
# Installs the web UI, services, database schema, TFTP files... The PKI is
# deleted right after: it is regenerated on first start with the real
# hostname / address (and iPXE rebuilt with that CA).
# -----------------------------------------------------------------------------
RUN cd /root/fogproject-${FOG_VERSION} \
    && bin/installfog.sh \
        --autoaccept \
        --hostname localhost \
        --netboot-proto https \
        --install-mode embed-ca \
        --no-rebuild-ipxe-with-my-ca \
    && rm -rf /etc/fog/pki

# Snapshot the pristine database and /images, restored by entry.sh when the
# corresponding volumes are mounted empty
RUN tar -czf /root/fog_default.sql.tar.gz /var/lib/mysql \
    && tar -czf /root/images.tar.gz /images

# Documentation only, see README.md for details (host networking ignores this)
#   443 https | 21 ftp | 69/udp tftp | 111 rpcbind | 2049 nfs | 20048 mountd (unfs3)
EXPOSE 443 21 69/udp 111 2049 20048

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s \
    CMD wget --spider --quiet --no-check-certificate https://${HOST_ADDRESS}/ || exit 1

ENTRYPOINT ["/usr/bin/entry.sh"]
