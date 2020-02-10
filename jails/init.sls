{% from "jails/map.jinja" import jails with context %}

include:
  - jails.jail_conf
  - jails.freebsd_update
  {%- if salt.pillar.get('zfs:fs') %}
  - zfs.fs
  {%- endif %}

# Root directory for all jails

jail_root:
  file.directory:
    - name: {{ jails.root }}
    - user: root
    - group: wheel
    - require_in:
      - file: jail_etc_jail_conf
    {% if salt.pillar.get('zfs:fs') %}
    - require:
      - sls: zfs.fs
    {% endif %}

{% for jail, cfg in jails.instances.items() %}

# Jail directory

{{ jail }}_directory:
  file.managed:
    - name: {{ jails.root | path_join(jail, '.saltstack') }}
    - contents_pillar: jails:instances:{{ jail }}:version
    - mode: 600
    - user: root
    - group: wheel
    {%- if not jails.get('use_zfs', True) %}
    - makedirs: True
    {%- endif %}
    - unless: 
      - ls -A {{ jails.root | path_join(jail) }} | grep -q .

{% for set in cfg.sets %}

# Create jail

{{ jail }}_set_{{ set }}:
  cmd.run:
    - name: fetch {{ cfg.get('fetch_url', 'https://download.freebsd.org/ftp/releases/amd64/').rstrip('/') }}/{{ cfg.version }}/{{ set }} -4 -q -o - | tar -x -C {{ jails.root | path_join(jail) }} -f -
    - cwd: /tmp
    - onchanges:
      - file: {{ jail }}_directory
    - onchanges_in:
      - cmd: {{ jail }}_freebsd_update_fetch
    - watch_in:
      - file: jail_etc_jail_conf

{% endfor %}  # SETS

# Minimal rc.conf

{% for rc_param, rc_value in cfg.rc_conf.items() %}

{{ jail }}_rc_conf_{{ rc_param }}:
  sysrc.managed:
    - name: {{ rc_param }}
    - value: {{ rc_value }}
    - file: {{ jails.root | path_join(jail, 'etc', 'rc.conf') }}
    - require_in:
      - cmd: {{ jail }}_start
    - require:
      - file: {{ jail }}_directory
      {% for set in cfg.sets %}
      - cmd: {{ jail }}_set_{{ set }}
      {% endfor %}

{% endfor %}  # RC_CONF

# Patches 

{% for patch in cfg.get('patches', ()) %}

{{ jail }}_patch_{{ patch.target }}_{{ loop.index }}:
  file.patch:
    - name: {{ jails.root | path_join(jail, patch.target) }} 
    - source: salt://jails/files/patches/{{ cfg.version | path_join(patch.diff) }}
    - onchanges:
      - file: {{ jail }}_directory

{% if patch.target == '/etc/login.conf' %}

{{ jail }}_cap_mkdb_{{ loop.index }}:
  cmd.run:
    - name: cap_mkdb {{ jails.root | path_join(jail, 'etc', 'login.conf') }} 
    - cwd: {{ jails.root | path_join(jail) }} 
    - onchanges:
      - file: {{ jail }}_patch_{{ patch.target }}_{{ loop.index }}

{% endif %}

{% endfor %}

# Adapt Components of freebsd-update.conf

{{ jail }}_freebsd_update_conf:
  file.replace:
    - name: {{ jails.root | path_join(jail, 'etc', 'freebsd-update.conf') }}
    - pattern: |
        ^Components\s+.*
    - repl: |
        Components world
    - backup: False
    - onchanges:
      - cmd: {{ jail }}_set_base.txz
    - require_in:
      - cmd: {{ jail }}_freebsd_update_fetch
      - cmd: {{ jail }}_freebsd_update_install

# pkg repos

{{ jail }}_pkg_repos:
  file.directory:
    - name: {{ jails.root | path_join(jail, 'usr', 'local', 'etc', 'pkg', 'repos') }}
    - user: root
    - group: wheel
    - makedirs: True
    - mode: 755
    - onchanges:
      - file: {{ jail }}_directory

{% for repo in cfg.get('pkg', {}) %}

{{ jail }}_pkg_repo_{{ repo }}:
  file.managed:
    - name: {{ jails.root | path_join(jail, 'usr', 'local', 'etc', 'pkg', 'repos', repo) }}
    - user: root
    - group: wheel
    - mode: 644
    - contents_pillar: jails:instances:{{ jail }}:pkg:{{ repo }}
    - onchanges:
      - file: {{ jail }}_pkg_repos

{% endfor %}

# /etc/fstab.xxx

{{ jail }}_fstab:
  file.touch:
    - name: /etc/fstab.{{ jail }}
    - require_in:
      - cmd: {{ jail }}_start

{% for jail_mount in cfg.get('fstab', ()) %}

{%- if not jails.get('use_zfs', True) %}

{{ jail }}_{{ jail_mount.jail_path }}_host_directory:
  file.directory:
    - name: {{ jail_mount.jail_path }}
    - user: root
    - group: wheel
    - makedirs: True
    - require_in:
      - file: {{ jail }}_{{ jail_mount.jail_path }}_directory

{%- endif %}

{{ jail }}_{{ jail_mount.jail_path }}_directory:
  file.directory:
    - name: {{ jail_mount.host_path }}
    - user: {{ jail_mount.get('user', 'root') }}
    - group: {{ jail_mount.get('group', 'wheel') }}
    - mode: {{ jail_mount.get('mode', 755) }}
    {%- if not jails.get('use_zfs', True) %}
    - makedirs: True
    {%- endif %}
    - require:
      - file: {{ jail }}_directory

{{ jail }}_{{ jail_mount.jail_path }}_fstab:
  mount.mounted:
    - name: {{ jail_mount.host_path }}
    - config: /etc/fstab.{{ jail }}
    - device: {{ jail_mount.jail_path }}
    - fstype: {{ jail_mount.fstype }}
    - opts: {{ jail_mount.opts }}
    - persist: True
    - mount: False
    - require_in:
      - cmd: {{ jail }}_start
    - require:
      - file: {{ jail }}_{{ jail_mount.jail_path }}_directory

{% endfor %}

{{ jail }}_start:
  cmd.run:
    - name: service jail onestart {{ jail }}
    - cwd: /tmp
    - require:
      - file: jail_etc_jail_conf
    - onchanges:
      - file: {{ jail }}_directory

{% for init_script in cfg.init_scripts %}

{{ jail }}_{{ init_script }}:
  cmd.script:
    - name: {{ init_script }}
    - env:
      - ASSUME_ALWAYS_YES: "YES"
      - JAILS_ROOT: {{ jails.root }}
      - JAIL_ROOT: {{ jails.root | path_join(jail) }}
      - JAIL_RELEASE: {{ cfg.version }}
      - JAIL_NAME: {{ jail }}
      - SALT_MASTER: {{ cfg.salt.master }}
      - MINION_ID: {{ cfg.salt.minion_id }}
      - PKG_SALT: {{ cfg.salt.pkg|default('py36-salt') }}
    - require:
      - cmd: {{ jail }}_start
    - onchanges:
      - file: {{ jail }}_directory

{% endfor %}  # INIT SCRIPTS
 
{% endfor %}  # JAILS LIST


