#FROM debian:trixie-slim
FROM archlinux:base-20260628.0.549485
LABEL Name=fog Version=0.0.1

# envs
ENV FOG_VERSION=1.5.10.1870
ENV MARIADB_HOST database
ENV MARIADB_DATABASE fog
ENV MARIADB_USER fog
ENV MARIADB_PASSWORD fog
ENV WEB_USER fog
ENV WEB_PWD fog

# install needed packages
#RUN DEBIAN_FRONTEND=noninteractive apt install --update -y --no-install-recommends \
#    apt-transport-https ca-certificates wget iproute2

RUN pacman --noconfirm -Syyu && pacman -S --noconfirm wget inetutils

RUN wget https://github.com/FOGProject/fogproject/archive/refs/tags/${FOG_VERSION}.tar.gz \
    && tar xvfz ${FOG_VERSION}.tar.gz

#RUN cd fogproject-${FOG_VERSION}/bin && bash ./installfog.sh --autoaccept

# entry point
COPY entry.sh /usr/sbin/entry.sh
RUN chmod +x /usr/sbin/entry.sh

# run
ENTRYPOINT ["/usr/sbin/entry.sh"]
