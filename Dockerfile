FROM centos:8
MAINTAINER Chad Sailer

# Configuration variables.
ENV container=docker
ENV CONFLUENCE_HOME     /var/atlassian/confluence
ENV CONFLUENCE_INSTALL  /opt/atlassian/confluence
ENV CONFLUENCE_VERSION  7.7.2

# Install systemd -- See https://hub.docker.com/_/centos/
RUN dnf -y update; dnf clean all; \
(cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -f $i; done); \
rm -f /lib/systemd/system/multi-user.target.wants/*;\
rm -f /etc/systemd/system/*.wants/*;\
rm -f /lib/systemd/system/local-fs.target.wants/*; \
rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
rm -f /lib/systemd/system/basic.target.wants/*;\
rm -f /lib/systemd/system/anaconda.target.wants/*;

# Install Ansible and other requirements.
RUN dnf -y install epel-release initscripts \
 && dnf -y update \
 && dnf -y install \
      ansible \
      sudo \
      which \
      zip \
      unzip \
      python2-pip \
 && dnf clean all

RUN ansible-galaxy install\
    v0rts.java

RUN mkdir /tmp/ansible
WORKDIR /tmp/ansible
ADD java.yml /tmp/ansible/java.yml
RUN ansible-playbook -i localhost, java.yml

# Disable requiretty.
RUN sed -i -e 's/^\(Defaults\s*requiretty\)/#--- \1/'  /etc/sudoers

# Install Ansible inventory file.
RUN echo -e '[local]\nlocalhost ansible_connection=local' > /etc/ansible/hosts

VOLUME ["/sys/fs/cgroup"]
CMD ["/usr/sbin/init"]


# Install Atlassian CONFLUENCE and helper tools and setup initial home
# directory structure.
RUN set -x \
    && mkdir -p                "${CONFLUENCE_HOME}" \
    && mkdir -p                "${CONFLUENCE_HOME}/caches/indexes" \
    && chmod -R 700            "${CONFLUENCE_HOME}" \
    && chown -R daemon:daemon  "${CONFLUENCE_HOME}" \
    && mkdir -p                "${CONFLUENCE_INSTALL}/conf/Catalina" \
    && curl -Ls                "https://www.atlassian.com/software/confluence/downloads/binary/atlassian-confluence-7.7.2.tar.gz" | tar -xz --directory "${CONFLUENCE_INSTALL}" --strip-components=1 --no-same-owner \
    && chmod -R 700            "${CONFLUENCE_INSTALL}/conf" \
    && chmod -R 700            "${CONFLUENCE_INSTALL}/logs" \
    && chmod -R 700            "${CONFLUENCE_INSTALL}/temp" \
    && chmod -R 700            "${CONFLUENCE_INSTALL}/work" \
    && chown -R daemon:daemon  "${CONFLUENCE_INSTALL}/conf" \
    && chown -R daemon:daemon  "${CONFLUENCE_INSTALL}/logs" \
    && chown -R daemon:daemon  "${CONFLUENCE_INSTALL}/temp" \
    && chown -R daemon:daemon  "${CONFLUENCE_INSTALL}/work" \
    && echo -e                 "\nconfluence.home=$CONFLUENCE_HOME" >> "${CONFLUENCE_INSTALL}/confluence/WEB-INF/classes/confluence-init.properties" \
    && touch -d "@0"           "${CONFLUENCE_INSTALL}/conf/server.xml"

# Use the default unprivileged account. This could be considered bad practice
# on systems where multiple processes end up being executed by 'daemon' but
# here we only ever run one process anyway.
USER daemon:daemon

# Expose default HTTP connector port.
EXPOSE 8080

# Set volume mount points for installation and home directory. Changes to the
# home directory needs to be persisted as well as parts of the installation
# directory due to eg. logs.
VOLUME ["/var/atlassian/confluence", "/opt/atlassian/confluence/logs"]

# Set the default working directory as the installation directory.
WORKDIR /var/atlassian/confluence

# Run Atlassian CONFLUENCE as a foreground process by default.
CMD ["/opt/atlassian/confluence/bin/catalina.sh", "run"]
