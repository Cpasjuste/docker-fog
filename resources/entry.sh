#!/bin/bash
# =============================================================================
# docker-fog entrypoint
#
# Runs on every container start:
#   1. First start only (empty PKI volume): re-run the FOG installer with the
#      real host settings to generate the CA / certificates and rebuild iPXE.
#   2. Restore the default database and /images into empty volumes.
#   3. Inject runtime settings (addresses, interface, passwords) into the FOG
#      config files and the database.
#   4. Start supervisord, the NFS server of choice, then the FOG services.
#
# Environment (see README.md):
#   HOST_NAME, HOST_ADDRESS, INTERFACE_NAME,
#   WEB_PASSWORD, MYSQL_PASSWORD, STORAGE_PASSWORD, USE_UNFS3
# =============================================================================
set -e

FOG_SETTINGS="/opt/fog/.fogsettings"
FOG_CONFIG="/var/www/html/fog/commons/config.class.php"
FOG_TASKQUEUE="/var/www/html/fog/src/TaskHandling/TaskQueue.php"
SUPERVISOR_CONF="/etc/supervisor/conf.d/supervisord.conf"

INTERFACE_NAME="${INTERFACE_NAME:-eth0}"

log() {
    echo "[docker-fog] $*"
}

# Replace the network placeholders of .fogsettings with the runtime values.
# Idempotent: once replaced, the placeholders are gone.
apply_network_settings() {
    sed -i \
        -e "s/0.0.0.0/${HOST_ADDRESS}/g" \
        -e "s/NET_hostname='localhost'/NET_hostname='${HOST_NAME}'/g" \
        -e "s/eth0/${INTERFACE_NAME}/g" \
        "$FOG_SETTINGS"
}

# -----------------------------------------------------------------------------
# 1. First start: generate the PKI (CA, web/client certs, iPXE with our CA)
# -----------------------------------------------------------------------------
if [ -z "$(ls -A /etc/fog/pki)" ]; then
    log "empty pki, running fog installer..."
    apply_network_settings
    cd "/root/fogproject-${FOG_VERSION}"
    bin/installfog.sh \
        --autoaccept \
        --hostname "${HOST_NAME:-localhost}" \
        --netboot-proto https \
        --install-mode embed-ca \
        --recreate-CA \
        --rebuild-ipxe-with-my-ca
    cd /
    # The installer started its own instances of these services (outside of
    # supervisord, which is not running yet): stop them so supervisord can
    # bind the ports. systemctl is a no-op stub here, use the init scripts.
    # "|| true": a service that is already stopped must not abort (set -e).
    log "stopping services started by the installer..."
    for svc in php8.4-fpm apache2 tftpd-hpa vsftpd mariadb; do
        "/etc/init.d/${svc}" stop || true
    done
fi

# -----------------------------------------------------------------------------
# 2. Seed empty volumes (mariadb is not running yet)
# -----------------------------------------------------------------------------
if [ -z "$(ls -A /var/lib/mysql)" ]; then
    log "empty database volume, restoring default fog database..."
    tar -zxf /root/fog_default.sql.tar.gz -C /
fi

if [ -z "$(ls -A /images)" ]; then
    log "empty images volume, restoring default images directory..."
    tar -zxf /root/images.tar.gz -C /
fi

log "setting /images permissions"
chown -R fogproject:www-data /images
chmod -R 775 /images

# -----------------------------------------------------------------------------
# 3. Runtime configuration
# -----------------------------------------------------------------------------
log "updating fog settings"
apply_network_settings
sed -i \
    -e "s/#docker-fog-db-pwd#/${MYSQL_PASSWORD}/g" \
    -e "s/#docker-fog-storage-pwd#/${STORAGE_PASSWORD}/g" \
    -e "s/FOG_installed=0/FOG_installed=1/g" \
    "$FOG_SETTINGS"

log "setting fogproject system user password"
printf '%s:%s\n' 'fogproject' "${STORAGE_PASSWORD}" | chpasswd

# sshd is only used by FOG itself to reach the local storage node: listen on
# localhost, and make FOG connect to 127.0.0.1 for the default node (id 1).
log "restricting ssh server to localhost"
sed -i "s/#ListenAddress 0.0.0.0/ListenAddress 127.0.0.1/g" /etc/ssh/sshd_config
if ! grep -qF "self::\$FOGSSH->host = '127.0.0.1'" "$FOG_TASKQUEUE"; then
    sed -i "s|self::\$FOGSSH->host = \$this->StorageNode->get('ip');|if (intval(\$this->StorageNode->get('id')) === 1) { self::\$FOGSSH->host = '127.0.0.1'; } else { self::\$FOGSSH->host = \$this->StorageNode->get('ip'); }|g" "$FOG_TASKQUEUE"
fi

log "updating fog web config"
# perl is used for passwords so that any character is taken literally
perl -0pi -e 's/\Q#docker-fog-storage-pwd#\E/$ENV{STORAGE_PASSWORD}/g;' "$FOG_CONFIG"
perl -0pi -e 's/\Q#docker-fog-db-pwd#\E/$ENV{MYSQL_PASSWORD}/g;' "$FOG_CONFIG"
sed -i \
    -e "s/('STORAGE_HOST', \"0.0.0.0\")/('STORAGE_HOST', \"${HOST_NAME}\")/g" \
    -e "s/('WEB_HOST', \"0.0.0.0\")/('WEB_HOST', \"${HOST_NAME}\")/g" \
    -e "s/('MULTICASTINTERFACE', 'eth0')/('MULTICASTINTERFACE', '${INTERFACE_NAME}')/g" \
    -e "s/('STORAGE_INTERFACE', 'eth0')/('STORAGE_INTERFACE', '${INTERFACE_NAME}')/g" \
    -e "s/('WOL_INTERFACE', \"eth0\")/('WOL_INTERFACE', \"${INTERFACE_NAME}\")/g" \
    -e "s/('NFS_ETH_MONITOR', \"eth0\")/('NFS_ETH_MONITOR', \"${INTERFACE_NAME}\")/g" \
    -e "s/('UDPCAST_INTERFACE', \"eth0\")/('UDPCAST_INTERFACE', \"${INTERFACE_NAME}\")/g" \
    -e "s/('UDPCAST_STARTINGPORT', 63100)/('UDPCAST_STARTINGPORT', \"55000\")/g" \
    "$FOG_CONFIG"

# -----------------------------------------------------------------------------
# 4. Services
# -----------------------------------------------------------------------------
log "starting supervisord"
supervisord -c "$SUPERVISOR_CONF" &
SUPERVISOR_PID=$!
until supervisorctl pid >/dev/null 2>&1; do sleep 0.5; done

# NFS: /images is exported read-only (deploy), /images/dev read-write (capture)
FOG_UID=$(id -u fogproject)
WWW_GID=33 # www-data
if [ "$USE_UNFS3" = true ]; then
    log "starting unfs3 (userland nfs server)"
    cat > /etc/exports <<EOF
/images (ro,root_squash,anonuid=${FOG_UID},anongid=${WWW_GID})
/images/dev (rw,root_squash,anonuid=${FOG_UID},anongid=${WWW_GID})
EOF
    supervisorctl start unfsd
else
    log "starting nfs-kernel-server"
    cat > /etc/exports <<EOF
/images *(ro,sync,no_wdelay,subtree_check,insecure_locks,root_squash,anonuid=${FOG_UID},anongid=${WWW_GID},fsid=0)
/images/dev *(rw,async,no_wdelay,subtree_check,root_squash,anonuid=${FOG_UID},anongid=${WWW_GID},fsid=1)
EOF
    supervisorctl start rpc-statd
    supervisorctl start nfs-kernel-server
fi

# Database values depending on the runtime environment.
# Note: values are interpolated as-is, keep passwords free of quotes.
log "waiting for mariadb"
until mysqladmin ping --silent >/dev/null 2>&1; do sleep 0.5; done

log "updating fog database"
mysql -hlocalhost -uroot -e "ALTER USER 'fogmaster'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';"
mysql -hlocalhost -uroot -D fog -e "
UPDATE users SET uPass = MD5('${WEB_PASSWORD}') WHERE uName = 'fog';
UPDATE globalSettings SET settingValue = '${HOST_ADDRESS}'     WHERE settingKey = 'FOG_TFTP_HOST';
UPDATE globalSettings SET settingValue = '${HOST_NAME}'        WHERE settingKey = 'FOG_WEB_HOST';
UPDATE globalSettings SET settingValue = '${STORAGE_PASSWORD}' WHERE settingKey = 'FOG_TFTP_FTP_PASSWORD';
UPDATE globalSettings SET settingValue = '${INTERFACE_NAME}'   WHERE settingKey = 'FOG_UDPCAST_INTERFACE';
UPDATE globalSettings SET settingValue = '${INTERFACE_NAME}'   WHERE settingKey = 'FOG_NFS_ETH_MONITOR';
UPDATE globalSettings SET settingValue = '${INTERFACE_NAME}'   WHERE settingKey = 'FOG_WOL_INTERFACE';
UPDATE globalSettings SET settingValue = '55000'               WHERE settingKey = 'FOG_UDPCAST_STARTINGPORT';
UPDATE globalSettings SET settingValue = '55000'               WHERE settingKey = 'FOG_MULTICAST_PORT_OVERRIDE';
UPDATE nfsGroupMembers SET ngmHostname  = '${HOST_NAME}'        WHERE ngmID = 1;
UPDATE nfsGroupMembers SET ngmPass      = '${STORAGE_PASSWORD}' WHERE ngmID = 1;
UPDATE nfsGroupMembers SET ngmInterface = '${INTERFACE_NAME}'   WHERE ngmID = 1;
"

# FOG daemons need the database, so they are started last (autostart=false)
log "starting fog services"
for svc in \
    fog-image-replicator \
    fog-image-size \
    fog-multicast-manager \
    fog-ping-hosts \
    fog-snapin-hash \
    fog-snapin-replicator \
    fog-task-scheduler \
    fog-agent-release-sync \
    fog-file-deleter \
    fog-plugin-runner \
    fog-retention-runner
do
    supervisorctl start "$svc" || true
done

log "all done, fog is ready"
wait $SUPERVISOR_PID
