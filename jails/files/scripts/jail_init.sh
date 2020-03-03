#!/bin/sh

jexec "${JAIL_NAME}" pkg install pkg

[ -z "${PKG_SALT}" ] && PKG_SALT="$(jexec ${JAIL_NAME} pkg search -q -x '^py.*-salt'|sort -ur|head -1)"

jexec "${JAIL_NAME}" << EOF
pkg install ${PKG_SALT}
pkg install ca_root_nss
pkg lock -y ${PKG_SALT}
cp /usr/local/etc/salt/minion.sample /usr/local/etc/salt/minion
mkdir -p /usr/local/etc/salt/minion.d
sed -i '' "s/^#default_include:.*/default_include: minion.d\/\*.conf/" /usr/local/etc/salt/minion
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
