#!/bin/bash
set -e

# create ca/certs if pki is empty
if [ -z "$(ls -A /etc/fog/pki)" ]; then
    # set custom settings for fog installer
    sed -i "s/0.0.0.0/${HOST_ADDRESS}/g" "/opt/fog/.fogsettings"
    sed -i "s/NET_hostname='localhost'/NET_hostname='${HOST_NAME}'/g" "/opt/fog/.fogsettings"
    sed -i "s/eth0/${INTERFACE_NAME}/g" "/opt/fog/.fogsettings"
    # install fog
    echo "running fog installer..."
    cd /root/fogproject-${FOG_VERSION}
    bin/installfog.sh \
        --autoaccept \
        --hostname ${HOST_NAME:-localhost} \
        --netboot-proto https \
        --install-mode embed-ca \
        --recreate-CA \
        --rebuild-ipxe-with-my-ca
fi

# restore a default database when the "database" volume is new
echo "importing (default) database if needed" # mariadb not yet started
if [ -z "$(ls -A /var/lib/mysql)" ]; then
    echo "import needed, restoring fog_default.sql.tar.gz"
    tar -zxf /root/fog_default.sql.tar.gz -C /
fi

# restore a default images directory when the "images" volume is new
echo "restoring images data if needed"
if [ -z "$(ls -A /images)" ]; then
    echo "restoring images.tar.gz..."
    tar -zxf /root/images.tar.gz -C /
fi

# ensure proper permissions on images
echo "setting up proper images permissions"
chown -R fogproject:www-data /images
chmod -R 775 /images

echo "setting up fog settings"
SETTINGS="/opt/fog/.fogsettings"
sed -i "s/#docker-fog-db-pwd#/${MYSQL_PASSWORD}/g" ${SETTINGS}
sed -i "s/#docker-fog-storage-pwd#/${STORAGE_PASSWORD}/g" ${SETTINGS}
sed -i "s/0.0.0.0/${HOST_ADDRESS}/g" "/opt/fog/.fogsettings"
sed -i "s/NET_hostname='localhost'/NET_hostname='${HOST_NAME}'/g" "/opt/fog/.fogsettings"
sed -i "s/eth0/${INTERFACE_NAME}/g" "/opt/fog/.fogsettings"
sed -i "s/FOG_installed=0/FOG_installed=1/g" "/opt/fog/.fogsettings"

echo "setting up fogproject password"
printf '%s:%s\n' 'fogproject' "${STORAGE_PASSWORD}" | chpasswd

echo "setting ssh server to listen to localhost only"
sed -i "s/#ListenAddress 0.0.0.0/ListenAddress 127.0.0.1/g" /etc/ssh/sshd_config
TASK_PATH="/var/www/html/fog/src/TaskHandling/TaskQueue.php"
sed -i "s|self::\$FOGSSH->host = \$this->StorageNode->get('ip');|if (intval(\$this->StorageNode->get('id')) === 1) { self::\$FOGSSH->host = '127.0.0.1'; } else { self::\$FOGSSH->host = \$this->StorageNode->get('ip'); }|g" $TASK_PATH

echo "fixing configs"
CFG_PATH="/var/www/html/fog/commons/config.class.php"
perl -0pi -e 's/\Q#docker-fog-storage-pwd#\E/$ENV{STORAGE_PASSWORD}/g;' "$CFG_PATH"
perl -0pi -e 's/\Q#docker-fog-db-pwd#\E/$ENV{MYSQL_PASSWORD}/g;' "$CFG_PATH"
sed -i "s/('MULTICASTINTERFACE', 'eth0')/('MULTICASTINTERFACE', '${INTERFACE_NAME:-eth0}')/g" "$CFG_PATH"
#sed -i "s/('TFTP_HOST', \"0.0.0.0\")/('TFTP_HOST', \"${HOST_ADDRESS}\")/g" "$CFG_PATH"
sed -i "s/('STORAGE_HOST', \"0.0.0.0\")/('STORAGE_HOST', \"${HOST_NAME}\")/g" "$CFG_PATH"
sed -i "s/('STORAGE_INTERFACE', 'eth0')/('STORAGE_INTERFACE', '${INTERFACE_NAME:-eth0}')/g" "$CFG_PATH"
sed -i "s/('WEB_HOST', \"0.0.0.0\")/('WEB_HOST', \"${HOST_NAME}\")/g" "$CFG_PATH"
#sed -i "s/('WOL_HOST', \"0.0.0.0\")/('WOL_HOST', \"${HOST_ADDRESS}\")/g" "$CFG_PATH"
sed -i "s/('WOL_INTERFACE', \"eth0\")/('WOL_INTERFACE', \"${INTERFACE_NAME:-eth0}\")/g" "$CFG_PATH"
sed -i "s/('NFS_ETH_MONITOR', \"eth0\")/('NFS_ETH_MONITOR', \"${INTERFACE_NAME:-eth0}\")/g" "$CFG_PATH"
sed -i "s/('UDPCAST_INTERFACE', \"eth0\")/('UDPCAST_INTERFACE', \"${INTERFACE_NAME:-eth0}\")/g" "$CFG_PATH"
sed -i "s/('UDPCAST_STARTINGPORT', 63100)/('UDPCAST_STARTINGPORT', \"55000\")/g" "$CFG_PATH"

echo "starting supervisord and required services"
supervisord -c "/etc/supervisor/conf.d/supervisord.conf" &
SUPERVISOR_PID=$!
until supervisorctl pid >/dev/null 2>&1; do sleep 0.5; done

# nfs
fogid=$(id -u fogproject)
if [ "$USE_UNFS3" = true ] ; then
    echo "starting unfs3 server"
    echo "/images (ro,root_squash,anonuid=$fogid,anongid=33)" > /etc/exports
    echo "/images/dev (rw,root_squash,anonuid=$fogid,anongid=33)" >> /etc/exports
    supervisorctl start unfsd
else
    echo "starting nfs-kernel server"
    echo "/images *(ro,sync,no_wdelay,subtree_check,insecure_locks,root_squash,anonuid=$fogid,anongid=33,fsid=0)" > /etc/exports
    echo "/images/dev *(rw,async,no_wdelay,subtree_check,root_squash,anonuid=$fogid,anongid=33,fsid=1)" >> /etc/exports
    supervisorctl start rpc-statd
    supervisorctl start nfs-kernel-server
fi

echo "fixing databse"
until mysqladmin ping --silent >/dev/null 2>&1; do sleep 0.5; done;
mysql -hlocalhost -uroot -e "ALTER USER 'fogmaster'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';"
mysql -hlocalhost -uroot -D fog -e ";
UPDATE users SET uPass = MD5('${WEB_PASSWORD}') WHERE uName = 'fog';
UPDATE globalSettings SET settingValue = '${HOST_ADDRESS}' WHERE settingKey = 'FOG_TFTP_HOST';
UPDATE globalSettings SET settingValue = '${HOST_NAME}' WHERE settingKey = 'FOG_WEB_HOST';
UPDATE globalSettings SET settingValue = '${STORAGE_PASSWORD}' WHERE settingKey = 'FOG_TFTP_FTP_PASSWORD';
UPDATE globalSettings SET settingValue = '${INTERFACE_NAME:-eth0}' WHERE settingKey = 'FOG_UDPCAST_INTERFACE';
UPDATE globalSettings SET settingValue = '${INTERFACE_NAME:-eth0}' WHERE settingKey = 'FOG_NFS_ETH_MONITOR';
UPDATE globalSettings SET settingValue = '${INTERFACE_NAME:-eth0}' WHERE settingKey = 'FOG_WOL_INTERFACE';
UPDATE globalSettings SET settingValue = '55000' WHERE settingKey = 'FOG_UDPCAST_STARTINGPORT';
UPDATE globalSettings SET settingValue = '55000' WHERE settingKey = 'FOG_MULTICAST_PORT_OVERRIDE';
UPDATE nfsGroupMembers SET ngmHostname = '${HOST_NAME}' WHERE ngmID = 1;
UPDATE nfsGroupMembers SET ngmPass = '${STORAGE_PASSWORD}' WHERE ngmID = 1;
UPDATE nfsGroupMembers SET ngmInterface = '${INTERFACE_NAME:-eth0}' WHERE ngmID = 1;
"

echo "starting fog services"
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

echo "all done..."
wait $SUPERVISOR_PID

