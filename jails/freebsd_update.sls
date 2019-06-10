# freebsd-update

{% set jails = salt.pillar.get('jails') %}

{% for jail, cfg in jails.instances.items() %}

{{ jail }}_freebsd_update_fetch:
  cmd.run:
    - name: freebsd-update --not-running-from-cron --currently-running {{ cfg.version }} -b {{ jails.root | path_join(jail) }} fetch || exit 0
    - cwd: /tmp
    - require_in:
      - cmd: {{ jail }}_freebsd_update_install

{{ jail }}_freebsd_update_install:
  cmd.run:
    - name: freebsd-update --not-running-from-cron --currently-running {{ cfg.version }} -b {{ jails.root | path_join(jail) }} install
    - cwd: /tmp
    - onchanges:
      - cmd: {{ jail }}_freebsd_update_fetch

{% endfor %}
