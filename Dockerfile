FROM debian:trixie-slim
LABEL Name=fog Version=1.0.0

# envs
ENV FOG_VERSION=1.6.0.158 \
    HOST_ADDRESS=0.0.0.0 \
    INTERFACE_NAME=eth0

# install needed packages
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        apt-transport-https ca-certificates \
        nano iproute2 sysv-rc-conf supervisor \
        systemd systemd-timesyncd kmod lsb-release \
        autoconf bison flex pkg-config libtirpc-dev \
        apache2 attr bc build-essential cpp curl efitools g++ gawk gcc gcc-aarch64-linux-gnu \
        genisoimage git gzip htmldoc isolinux jq lftp libapache2-mod-php libc6 libcurl4t64 \
        liblzma-dev m4 mariadb-client mariadb-server net-tools nfs-kernel-server openssh-server \
        php php-bcmath php-cli php-curl php-fpm php-gd php-json php-ldap php-mbstring php-mysql php8.4-ssh2 \
        sbsigntool sudo tar tftpd-hpa tftp-hpa unzip vsftpd wget zlib1g \
        iputils-ping \
    && rm -rf /var/lib/apt/lists/*
# systemd systemd-timesyncd > prevent /usr/bin/systemctl hook override
# kmod > nfs-kernel-server modules loading (modprobe)

# copy needed resources
COPY resources /root/resources
RUN cp /root/resources/entry.sh /usr/bin/entry.sh \
    && chmod +x /usr/bin/entry.sh 
#/root/resources/prepare.sh \
#    && /root/resources/prepare.sh

# echo "supervisor"
RUN cp /root/resources/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

#echo "systemctl hook"
RUN cp /usr/bin/systemctl /usr/bin/systemctl.stock \
    && cp /root/resources/systemctl /usr/bin/systemctl \
    && chmod a+x /usr/bin/systemctl

#echo "mariadb mysql init.d fix (?!)"
RUN ln -sf /etc/init.d/mariadb /etc/init.d/mysql

#echo "installing nfs server (unfs3)..."
RUN wget https://github.com/unfs3/unfs3/releases/download/unfs3-0.11.0/unfs3-0.11.0.tar.gz \
    && tar -zxf unfs3-0.11.0.tar.gz -C /root \
    && cd /root/unfs3-0.11.0 && ./configure && make && make install \
    && rm -rf /root/unfs3-0.11.0 /unfs3-0.11.0.tar.gz
    
# retrieve fog tarball
RUN wget https://github.com/FOGProject/fogproject/archive/refs/tags/${FOG_VERSION}.tar.gz \
    && tar xvfz ${FOG_VERSION}.tar.gz -C /root \
    && rm ${FOG_VERSION}.tar.gz

# fog install, will be re-run on first container run to recreate CA, certs and such
RUN mkdir -p /opt/fog \
    && cp /root/resources/fogsettings /opt/fog/.fogsettings \
    && sed -i "s/#docker-fog-version#/${FOG_VERSION}/g" /opt/fog/.fogsettings \
    && sed -i 's/checkInternetConnection//g' /root/fogproject-${FOG_VERSION}/bin/installfog.sh \
    && cd /root/fogproject-${FOG_VERSION} \
    && bin/installfog.sh \
        --autoaccept \
        --hostname localhost \
        --netboot-proto https \
        --install-mode embed-ca \
        --no-rebuild-ipxe-with-my-ca

# delete certs, will be generated on first container run
RUN rm -rf /etc/fog/pki

# backup default fog database
RUN systemctl stop mysql \
    && tar -czf /root/fog_default.sql.tar.gz /var/lib/mysql

# backup images data
RUN tar -czf /root/images.tar.gz /images

# done...
RUN rm -rf /root/resources

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s \
    CMD wget --spider --quiet https://${HOST_ADDRESS}/ || exit 1

# entry point
ENTRYPOINT ["/usr/bin/entry.sh"]
