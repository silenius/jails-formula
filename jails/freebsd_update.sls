# freebsd-update

{% from "jails/map.jinja" import jails with context %}

{% for jail, cfg in jails.instances.items() if cfg.present %}

{{ jail }}_freebsd_update_fetch_install:
  cmd.run:
    {% if salt.cmd.retcode("freebsd-update --help|grep -E '^\s -j jail'") %}
    - name: freebsd-update --not-running-from-cron -j {{ jail }} -f {{ cfg.root | path_join('etc', 'freebsd-update.conf') }} fetch install
    {% else %}
    - name: freebsd-update --not-running-from-cron --currently-running {{ cfg.version }} -b {{ cfg.root }} -f {{ cfg.root | path_join('etc', 'freebsd-update.conf') }} fetch install
    {% endif %}
    - cwd: /tmp
    - env:
      - PAGER: cat
{% endfor %}
