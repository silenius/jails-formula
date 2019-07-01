#!/bin/sh

jexec "${JAIL_NAME}" << EOF
pkg install pkg
pkg install py27-salt
pkg install ca_root_nss
pkg lock -y py27-salt
cp /usr/local/etc/salt/minion.sample /usr/local/etc/salt/minion
mkdir -p /usr/local/etc/salt/minion.d
sed -i '' "s/^#default_include:.*/default_include: minion.d\/\*.conf/" /usr/local/etc/salt/minion
sed -i '' "s/^Components .*/Components world/" /etc/freebsd-update.conf
EOF

cat << EOF > "${JAIL_ROOT}/usr/local/etc/salt/minion.d/10-main.conf"
id: ${MINION_ID}
master: ${SALT_MASTER}
ipv6: False
log_file: /var/log/salt/minion
log_level: warning
log_level_logfile: info
hash_type: sha256
EOF

service -j "${JAIL_NAME}" salt_minion start
