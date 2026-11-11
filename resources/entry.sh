#!/bin/bash
set -e

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
    chown -R fogproject:www-data /images
    chmod -R 775 /images
fi

echo "setting up web port"
sed -i "s/:80/:${HTTP_PORT}/g" /etc/apache2/sites-enabled/001-fog.conf
sed -i "s/Listen 80/Listen ${HTTP_PORT}/g" /etc/apache2/ports.conf
sed -i "s/Listen 443//g" /etc/apache2/ports.conf

# add custom http port to dashboardpage for storage node id 1 (builtin storage node)
echo "fixing storage node web port"
DASH_PATH="/var/www/fog/src/Pages/DashboardPage.php"
sed -i "s|\$ip = \$StorageNode->ip;|if (intval(\$StorageNode->id) === 1) { \$ip = \$StorageNode->ip . \":$HTTP_PORT\"; } else { \$ip = \$StorageNode->ip; }|g" "$DASH_PATH"
sed -i "s|\$this->obj->get('ip')|\$ip|g" "$DASH_PATH"
sed -i -f - "$DASH_PATH" <<EOF
/public function diskusage()/{
N
c\
public function diskusage()\\
    {\\
        \$ip = \$this->obj->get('ip');\\
        \$id = \$this->obj->get('id');\\
        if (intval(\$id) === 1) { \$ip = \$ip . ":${HTTP_PORT}"; }
}
EOF
SRVINFO_PATH="/var/www/fog/src/Pages/ServerInfo.php"
sed -i "s|\$this->obj->get('ip')|\$ip|g" "$SRVINFO_PATH"
sed -i -f - "$SRVINFO_PATH" <<EOF
/\$url = sprintf/i\\
        \$ip = \$this->obj->get('ip');\\
        \$id = \$this->obj->get('id');\\
        if (intval(\$id) === 1) { \$ip = \$ip . ":${HTTP_PORT}"; }
EOF
NODE_PATH="/var/www/fog/src/Items/StorageNode.php"
sed -i "s|\$ip = \$this->get('ip');|if (intval(\$this->get('id')) === 1) { \$ip = \$this->get('ip') . \":$HTTP_PORT\"; } else { \$ip = \$this->get('ip'); }|g" "$NODE_PATH"
TASK_PATH="/var/www/html/fog/src/TaskHandling/TaskQueue.php"
sed -i "s|self::\$FOGSSH->host = \$this->StorageNode->get('ip');|if (intval(\$this->StorageNode->get('id')) === 1) { self::\$FOGSSH->host = '127.0.0.1'; } else { self::\$FOGSSH->host = \$this->StorageNode->get('ip'); }|g" $TASK_PATH

echo "setting up tftpboot address"
sed -i "s/0.0.0.0/${HTTP_ADDRESS}:${HTTP_PORT}/g" /tftpboot/default.ipxe

echo "setting up php-fpm custom port"
sed -i "s/:9000/:${PHP_FPM_PORT}/g" /etc/apache2/sites-enabled/001-fog.conf
sed -i "s/:9000/:${PHP_FPM_PORT}/g" /etc/php/8.4/fpm/pool.d/www.conf

echo "setting ssh server to listen to localhost only"
sed -i "s/#ListenAddress 0.0.0.0/ListenAddress 127.0.0.1/g" /etc/ssh/sshd_config

echo "fixing multicast"
# add host (HTTP_ADDRESS) address to "know ips"
# https://github.com/FOGProject/fogproject/blob/stable/packages/web/lib/fog/fogbase.class.php
#sed -i "s/127.0.1.1')/127.0.1.1'), array('${HTTP_ADDRESS}', '${HTTP_ADDRESS}')/g" /var/www/fog/lib/fog/fogbase.class.php

echo "fixing configs"
CFG_PATH="/var/www/fog/commons/config.class.php"
perl -0pi -e 's/\Q#docker-fog-password#\E/$ENV{STORAGE_PASSWORD}/g;' "$CFG_PATH"
perl -0pi -e 's/\Q#docker-fog-snmysqlpass#\E/$ENV{MYSQL_PASSWORD}/g;' "$CFG_PATH"
sed -i "s/('MULTICASTINTERFACE', 'eth0')/('MULTICASTINTERFACE', '${HTTP_ADDRESS:-eth0}')/g" "$CFG_PATH"
sed -i "s/('TFTP_HOST', \"0.0.0.0\")/('TFTP_HOST', \"${HTTP_ADDRESS:-0.0.0.0}\")/g" "$CFG_PATH"
sed -i "s/('STORAGE_HOST', \"0.0.0.0\")/('STORAGE_HOST', \"${HTTP_ADDRESS:-0.0.0.0}\")/g" "$CFG_PATH"
sed -i "s/('STORAGE_INTERFACE', 'eth0')/('STORAGE_INTERFACE', '${INTERFACE_NAME:-eth0}')/g" "$CFG_PATH"
sed -i "s/('WEB_HOST', \"0.0.0.0\")/('WEB_HOST', \"${HTTP_ADDRESS:-0.0.0.0}:${HTTP_PORT:-80}\")/g" "$CFG_PATH"
sed -i "s/('WOL_HOST', \"0.0.0.0\")/('WOL_HOST', \"${HTTP_ADDRESS:-0.0.0.0}\")/g" "$CFG_PATH"
sed -i "s/('WOL_INTERFACE', \"eth0\")/('WOL_INTERFACE', \"${INTERFACE_NAME:-eth0}\")/g" "$CFG_PATH"
sed -i "s/('NFS_ETH_MONITOR', \"eth0\")/('NFS_ETH_MONITOR', \"${INTERFACE_NAME:-eth0}\")/g" "$CFG_PATH"
sed -i "s/('UDPCAST_INTERFACE', \"eth0\")/('UDPCAST_INTERFACE', \"${INTERFACE_NAME:-eth0}\")/g" "$CFG_PATH"
sed -i "s/('UDPCAST_STARTINGPORT', 63100)/('UDPCAST_STARTINGPORT', \"${INTERFACE_NAME:-eth0}\")/g" "$CFG_PATH"

echo "starting required services"
/etc/init.d/mariadb start
/etc/init.d/php8.4-fpm start
/etc/init.d/apache2 start
/etc/init.d/vsftpd start
/etc/init.d/tftpd-hpa start
/etc/init.d/rpcbind start
/etc/init.d/ssh start

# nfs
fogid=$(id -u fogproject)
if [ "$USE_UNFS3" = true ] ; then
    echo "starting unfs3 server"
    echo "/images (ro,root_squash,anonuid=$fogid,anongid=33)" > /etc/exports
    echo "/images/dev (rw,root_squash,anonuid=$fogid,anongid=33)" >> /etc/exports
    unfsd -t -n 2049 -m 20048
else
    echo "starting nfs-kernel server"
    echo "/images *(ro,sync,no_wdelay,subtree_check,insecure_locks,root_squash,anonuid=$fogid,anongid=33,fsid=0)" > /etc/exports
    echo "/images/dev *(rw,async,no_wdelay,subtree_check,root_squash,anonuid=$fogid,anongid=33,fsid=1)" >> /etc/exports
    /etc/init.d/nfs-kernel-server start
fi

echo "fixing databse"
printf '%s:%s\n' 'fogproject' "${STORAGE_PASSWORD}" | chpasswd
mysql -hlocalhost -uroot -e "ALTER USER 'fog'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';"
mysql -hlocalhost -uroot -D fog -e "UPDATE users SET uPass = MD5('NEW_PASSWORD') WHERE uName = 'fog';"
mysql -hlocalhost -uroot -D fog -e "
UPDATE globalSettings SET settingValue = '${HTTP_ADDRESS}' WHERE settingKey = 'FOG_TFTP_HOST';
UPDATE globalSettings SET settingValue = '${HTTP_ADDRESS}:${HTTP_PORT}' WHERE settingKey = 'FOG_WEB_HOST';
UPDATE globalSettings SET settingValue = '${STORAGE_PASSWORD}' WHERE settingKey = 'FOG_TFTP_FTP_PASSWORD';
UPDATE globalSettings SET settingValue = '55000' WHERE settingKey = 'FOG_UDPCAST_STARTINGPORT';
UPDATE globalSettings SET settingValue = '55000' WHERE settingKey = 'FOG_MULTICAST_PORT_OVERRIDE';
UPDATE globalSettings SET settingValue = '${INTERFACE_NAME:-eth0}' WHERE settingKey = 'FOG_UDPCAST_INTERFACE';
UPDATE globalSettings SET settingValue = '${INTERFACE_NAME:-eth0}' WHERE settingKey = 'FOG_NFS_ETH_MONITOR';
UPDATE globalSettings SET settingValue = '${INTERFACE_NAME:-eth0}' WHERE settingKey = 'FOG_WOL_INTERFACE';
UPDATE nfsGroupMembers SET ngmHostname = '${HTTP_ADDRESS}' WHERE ngmID = 1;
UPDATE nfsGroupMembers SET ngmPass = '${STORAGE_PASSWORD}' WHERE ngmID = 1;
UPDATE nfsGroupMembers SET ngmInterface = '${INTERFACE_NAME:-eth0}' WHERE ngmID = 1;
UPDATE users SET uPass = MD5('${WEB_PASSWORD}') WHERE uName = 'fog';
"

echo "starting fog services"
sleep 10 # not sure why i need to delay fog services start
/etc/init.d/FOGImageReplicator restart
/etc/init.d/FOGImageSize restart
/etc/init.d/FOGMulticastManager restart
/etc/init.d/FOGPingHosts restart
/etc/init.d/FOGScheduler restart
/etc/init.d/FOGSnapinHash restart
/etc/init.d/FOGSnapinReplicator restart
/etc/init.d/FOGFileDeleter restart
/etc/init.d/FOGPluginRunner restart
/etc/init.d/FOGRetentionRunner restart
/etc/init.d/FOGAgentReleaseSync restart

# sleep...
echo "all done..."
while true
do
    sleep infinity
done
