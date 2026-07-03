#!/bin/bash
set -e

echo "importing (default) database if needed"
if mysql -hlocalhost -uroot -e "USE \`${MARIADB_DATABASE}\`" >/dev/null 2>&1; then
    echo "import needed, restoring fog_default.sql.tar.gz"
    tar -zxf /root/fog_default.sql.tar.gz -C /
fi

echo "fixing tftpboot"
sed -i "s/0.0.0.0/${HTTP_ADDRESS}:${HTTP_PORT}/g" /tftpboot/default.ipxe
#sed -i "s/-s/-s --port-range 35000:40000/g" /etc/default/tftpd-hpa

echo "starting required services"
/etc/init.d/mariadb start
/etc/init.d/php8.4-fpm start
/etc/init.d/apache2 start
/etc/init.d/vsftpd start
/etc/init.d/tftpd-hpa start

echo "fixing database addresses"
mysql -hlocalhost -uroot -D ${MARIADB_DATABASE} -e "
UPDATE globalSettings
SET settingValue = '${HTTP_ADDRESS}'
WHERE settingKey = 'FOG_TFTP_HOST';
UPDATE globalSettings
SET settingValue = '${HTTP_ADDRESS}:${HTTP_PORT}'
WHERE settingKey = 'FOG_WEB_HOST';
"
#UPDATE nfsGroupMembers
#SET ngmHostname = '${HTTP_ADDRESS}'
#WHERE ngmID = 1;

# sleep...
while true
do
    sleep infinity
done
