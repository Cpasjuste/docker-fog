FROM debian:trixie-slim
#FROM archlinux:base-devel-20260628.0.549485
LABEL Name=fog Version=0.0.1

# envs
ENV FOG_VERSION=1.5.10.1870
ENV MARIADB_HOST database
ENV MARIADB_DATABASE fog
ENV MARIADB_USER fog
ENV MARIADB_PASSWORD fog
ENV MARIADB_ROOT_PASSWORD fog
ENV WEB_USER fog
ENV WEB_PWD fog

# install needed packages
RUN DEBIAN_FRONTEND=noninteractive apt install --update -y --no-install-recommends \
    apt-transport-https ca-certificates nano wget iproute2 sysv-rc-conf \
    build-essential mariadb-client mariadb-server

#RUN pacman --noconfirm -Syyu \
#    && pacman -S --noconfirm nano wget inetutils diffutils mariadb-clients

RUN wget https://github.com/FOGProject/fogproject/archive/refs/tags/${FOG_VERSION}.tar.gz \
    && tar xvfz ${FOG_VERSION}.tar.gz -C /root \
    && rm ${FOG_VERSION}.tar.gz

# run fog installer with hooks
COPY resources /root/resources
RUN chmod a+x /root/resources/prepare.sh \
    && /root/resources/prepare.sh

# entry point
RUN chmod +x /root/resources/entry.sh
ENTRYPOINT ["/root/resources/entry.sh"]
