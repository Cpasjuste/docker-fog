#!/bin/bash
set -e

echo "systemctl hook"
#cp /usr/bin/systemctl /usr/bin/systemctl.stock \
#    && cp /root/resources/systemctl /usr/bin/systemctl \
#    && chmod a+x /usr/bin/systemctl
#mv /usr/bin/systemctl /usr/bin/systemctl.stock

echo "use custom fog settings"
mkdir /opt/fog \
    && cp /root/resources/fogsettings.debian /opt/fog/.fogsettings

#echo "importing (default) database if needed"
#mysql -h${MARIADB_HOST} -uroot -p${MARIADB_ROOT_PASSWORD} ${MARIADB_DATABASE} < /root/resources/fogbackup-arch.sql
#mysql -hlocalhost -uroot ${MARIADB_DATABASE} < /root/resources/fogbackup-debian.sql

echo "installing fog..."
# speed-up things...
sed -i 's/checkInternetConnection/#checkInternetConnection/g' /root/fogproject-${FOG_VERSION}/bin/installfog.sh
ln -sf /etc/init.d/mariadb /etc/init.d/mysql
cp /root/resources/systemctl /usr/bin/systemctl && chmod a+x /usr/bin/systemctl
#/root/fogproject-${FOG_VERSION}/bin/installfog.sh --autoaccept

echo "creating default image path"
mkdir /image
