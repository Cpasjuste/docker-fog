#!/bin/bash
set -e

echo "importing (default) database if needed"
if mysql -hlocalhost -uroot -e "USE \`${MARIADB_DATABASE}\`" >/dev/null 2>&1; then
    echo "import needed, restoring fog_default.sql.tar.gz"
    tar -zxf /root/fog_default.sql.tar.gz -C /
fi

echo "restoring images data if needed"
if [ -z "$(ls -A /images)" ]; then
    echo "restoring images data..."
    tar -zxf /root/images.tar.gz -C /
fi

echo "fixing tftpboot"
sed -i "s/0.0.0.0/${HTTP_ADDRESS}:${HTTP_PORT}/g" /tftpboot/default.ipxe

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
/etc/init.d/nfs-kernel-server start

echo "starting fog services"
/etc/init.d/FOGImageReplicator start
/etc/init.d/FOGImageSize start
/etc/init.d/FOGMulticastManager start
/etc/init.d/FOGPingHosts start
/etc/init.d/FOGScheduler start
/etc/init.d/FOGSnapinHash start
/etc/init.d/FOGSnapinReplicator start

echo "fixing database addresses"
mysql -hlocalhost -uroot -D ${MARIADB_DATABASE} -e "
UPDATE globalSettings
SET settingValue = '${HTTP_ADDRESS}'
WHERE settingKey = 'FOG_TFTP_HOST';
UPDATE globalSettings
SET settingValue = '${HTTP_ADDRESS}:${HTTP_PORT}'
WHERE settingKey = 'FOG_WEB_HOST';
UPDATE nfsGroupMembers
SET ngmHostname = '${HTTP_ADDRESS}'
WHERE ngmID = 1;
"

# sleep...
echo "all done..."
while true
do
    sleep infinity
done
