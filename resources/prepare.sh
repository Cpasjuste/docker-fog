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

echo "installing nfs server (unfs3)..."
wget https://github.com/unfs3/unfs3/releases/download/unfs3-0.11.0/unfs3-0.11.0.tar.gz \
    && tar -zxf unfs3-0.11.0.tar.gz -C /root \
    && cd /root/unfs3-0.11.0 && ./configure && make && make install \
    && rm -rf /root/unfs3-0.11.0 /root/unfs3-0.11.0.tar.gz

echo "installing fog..."
/root/fogproject-${FOG_VERSION}/bin/installfog.sh --autoaccept \
    && rm -rf /root/fogproject-${FOG_VERSION}

echo "backup default fog database"
tar -czf /root/fog_default.sql.tar.gz /var/lib/mysql

echo "backup images data"
tar -czf /root/images.tar.gz /images

echo "done..."
rm -rf /root/resources
