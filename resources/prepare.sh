#!/bin/bash
set -e

echo "systemctl hook"
cp /usr/bin/systemctl /usr/bin/systemctl.stock \
    && cp /root/resources/systemctl /usr/bin/systemctl \
    && chmod a+x /usr/bin/systemctl

echo "mariadb mysql init.d fix (?!)"
ln -sf /etc/init.d/mariadb /etc/init.d/mysql

echo "use custom fog settings"
mkdir /opt/fog && cp /root/resources/fogsettings.debian /opt/fog/.fogsettings

echo "fog install speedup fix"
sed -i 's/checkInternetConnection/#checkInternetConnection/g' /root/fogproject-${FOG_VERSION}/bin/installfog.sh

echo "installing fog..."
/root/fogproject-${FOG_VERSION}/bin/installfog.sh --autoaccept

echo "backup default fog database"
tar -czf /root/fog_default.sql.tar.gz /var/lib/mysql
