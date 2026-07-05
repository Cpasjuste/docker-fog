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
fi

echo "fixing web port"
sed -i "s/:80/:${HTTP_PORT}/g" /etc/apache2/sites-enabled/001-fog.conf
sed -i "s/Listen 80/Listen ${HTTP_PORT}/g" /etc/apache2/ports.conf

echo "fixing tftpboot"
sed -i "s/0.0.0.0/${HTTP_ADDRESS}:${HTTP_PORT}/g" /tftpboot/default.ipxe

echo "fixing multicast"
# add host (HTTP_ADDRESS) address to "know ips"
# https://github.com/FOGProject/fogproject/blob/stable/packages/web/lib/fog/fogbase.class.php
sed -i "s/127.0.1.1')/127.0.1.1'), array('${HTTP_ADDRESS}', '${HTTP_ADDRESS}')/g" /var/www/fog/lib/fog/fogbase.class.php

echo "starting required services"
/etc/init.d/mariadb start
/etc/init.d/php8.4-fpm start
/etc/init.d/apache2 start
/etc/init.d/vsftpd start
/etc/init.d/tftpd-hpa start
/etc/init.d/rpcbind start

echo "starting nfs server"
echo "/images *(ro,sync,no_wdelay,subtree_check,insecure_locks,all_squash,anonuid=1000,anongid=1000,fsid=0)" > /etc/exports
echo "/images/dev *(rw,async,no_wdelay,subtree_check,all_squash,anonuid=1000,anongid=1000,fsid=1)" >> /etc/exports
/etc/init.d/nfs-kernel-server start

echo "fixing databse and passwords"
printf '%s:%s\n' 'fogproject' "${STORAGE_PASSWORD}" | chpasswd
perl -0pi -e 's/\Q#docker-fog-password#\E/$ENV{STORAGE_PASSWORD}/g;' /var/www/fog/lib/fog/config.class.php
perl -0pi -e 's/\Q#docker-fog-snmysqlpass#\E/$ENV{MYSQL_PASSWORD}/g;' /var/www/fog/lib/fog/config.class.php
mysql -hlocalhost -uroot -e "ALTER USER 'fog'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';"
mysql -hlocalhost -uroot -D fog -e "UPDATE users SET uPass = MD5('NEW_PASSWORD') WHERE uName = 'fog';"
mysql -hlocalhost -uroot -D fog -e "
UPDATE globalSettings SET settingValue = '${HTTP_ADDRESS}' WHERE settingKey = 'FOG_TFTP_HOST';
UPDATE globalSettings SET settingValue = '${HTTP_ADDRESS}:${HTTP_PORT}' WHERE settingKey = 'FOG_WEB_HOST';
UPDATE globalSettings SET settingValue = '${STORAGE_PASSWORD}' WHERE settingKey = 'FOG_TFTP_FTP_PASSWORD';
UPDATE globalSettings SET settingValue = '55000' WHERE settingKey = 'FOG_UDPCAST_STARTINGPORT';
UPDATE globalSettings SET settingValue = '55000' WHERE settingKey = 'FOG_MULTICAST_PORT_OVERRIDE';
UPDATE nfsGroupMembers SET ngmHostname = '${HTTP_ADDRESS}' WHERE ngmID = 1;
UPDATE nfsGroupMembers SET ngmPass = '${STORAGE_PASSWORD}' WHERE ngmID = 1;
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

# sleep...
echo "all done..."
while true
do
    sleep infinity
done
