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

echo "starting required services"
/etc/init.d/mariadb start
/etc/init.d/php8.4-fpm start
/etc/init.d/apache2 start
/etc/init.d/vsftpd start
/etc/init.d/tftpd-hpa start
/etc/init.d/rpcbind start

echo "starting nfs server"
#umount -f /proc/fs/nfsd
#rmmod {nfs,nfsd,rpcsec_gss_krb5}
#modprobe {nfs,nfsd,rpcsec_gss_krb5}
echo "/images *(ro,sync,no_wdelay,subtree_check,insecure_locks,all_squash,anonuid=1000,anongid=1000,fsid=0)" > /etc/exports
echo "/images/dev *(rw,async,no_wdelay,subtree_check,all_squash,anonuid=1000,anongid=1000,fsid=1)" >> /etc/exports
/etc/init.d/nfs-kernel-server start

echo "starting fog services"
/etc/init.d/FOGImageReplicator start
/etc/init.d/FOGImageSize start
/etc/init.d/FOGMulticastManager start
/etc/init.d/FOGPingHosts start
/etc/init.d/FOGScheduler start
/etc/init.d/FOGSnapinHash start
/etc/init.d/FOGSnapinReplicator start

echo "fixing tftpboot"
sed -i "s/0.0.0.0/${HTTP_ADDRESS}:${HTTP_PORT}/g" /tftpboot/default.ipxe

echo "fixing databse and passwords"
echo "fogproject:${STORAGE_PASSWORD}" | chpasswd
sed -i "s/#docker-fog-password#/${STORAGE_PASSWORD}/g" /var/www/fog/lib/fog/config.class.php
sed -i "s/#docker-fog-snmysqlpass#/${MYSQL_PASSWORD}/g" /var/www/fog/lib/fog/config.class.php
mysql -hlocalhost -uroot -e "ALTER USER 'fog'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';"
mysql -hlocalhost -uroot -D fog -e "
UPDATE globalSettings SET settingValue = '${HTTP_ADDRESS}' WHERE settingKey = 'FOG_TFTP_HOST';
UPDATE globalSettings SET settingValue = '${HTTP_ADDRESS}:${HTTP_PORT}' WHERE settingKey = 'FOG_WEB_HOST';
UPDATE globalSettings SET settingValue = '${STORAGE_PASSWORD}' WHERE settingKey = 'FOG_TFTP_FTP_PASSWORD';
UPDATE nfsGroupMembers SET ngmHostname = '${HTTP_ADDRESS}' WHERE ngmID = 1;
UPDATE nfsGroupMembers SET ngmPass = '${STORAGE_PASSWORD}' WHERE ngmID = 1;
"

# sleep...
echo "all done..."
while true
do
    sleep infinity
done
