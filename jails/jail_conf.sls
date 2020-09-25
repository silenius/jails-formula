{% from "jails/map.jinja" import jails with context %}

# /etc/jail.conf

jail_etc_jail_conf:
  file.managed:
    - name: {{ jails.jail_conf }}
    - source: {{ jails.jail_conf_template }}
    - user: root
    - group: wheel
    - mode: 644
    - template: jinja
