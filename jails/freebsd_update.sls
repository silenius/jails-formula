# freebsd-update

{% from "jails/map.jinja" import jails with context %}

{% for jail, cfg in jails.instances.items() if cfg.present %}

{{ jail }}_freebsd_update_fetch_install:
  cmd.run:
    - name: freebsd-update --not-running-from-cron --currently-running {{ cfg.version }} -b {{ jail.root }} -f {{ jail.root | path_join('etc', 'freebsd-update.conf') }} -d {{ jail.root | path_join('var', 'db', 'freebsd-update') }} fetch install
    - cwd: /tmp
    - parallel: True

{% endfor %}
