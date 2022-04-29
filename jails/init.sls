{% from "jails/map.jinja" import jails with context %}

include:
  - jails.jail_conf
  - jails.freebsd_update
  {%- if jails.use_zfs %}
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
    {% if jails.use_zfs %}
    - require:
      - sls: zfs.fs
    {% endif %}

jail_enable:
  sysrc.managed:
    - name: jail_enable
    - value: "YES"

{% for jail, cfg in jails.instances.items() %}

{% if cfg.present %}

###################
# JAIL IS PRESENT #
###################

#######################
# JAIL ROOT DIRECTORY #
#######################

{{ jail }}_directory:
  file.managed:
    - name: {{ jails.root | path_join(jail, '.saltstack') }}
    - contents_pillar: jails:instances:{{ jail }}:version
    - mode: 600
    - user: root
    - group: wheel
    {%- if not jails.use_zfs %}
    - makedirs: True
    {%- endif %}
    - unless: 
      - test -f {{ jails.root | path_join(jail, '.saltstack') }}

########
# SETS #
########

{% for set in cfg.sets %}

{{ jail }}_set_{{ set }}:
  cmd.run:
    - name: fetch {{ cfg.get('fetch_url', 'https://download.freebsd.org/ftp/releases/' ~ cfg.arch).rstrip('/') ~ '/' ~ cfg.version ~ '/' ~ set }} -4 -q -o - | tar -x -C {{ jails.root | path_join(jail) }} -f -
    - cwd: /tmp
    - onchanges:
      - file: {{ jail }}_directory
    - onchanges_in:
      - cmd: {{ jail }}_freebsd_update_fetch_install
    - watch_in:
      - file: jail_etc_jail_conf

{% endfor %}  # SETS

#####################
# JAIL /etc/rc.conf #
#####################

# Workaround PR 240875

{{ jail }}_rc_conf:
  file.managed:
    - name: {{ jails.root | path_join(jail, 'etc', 'rc.conf') }}
    - user: root
    - group: wheel
    - mode: 644
    - require:
      {% for set in cfg.sets %}
      - cmd: {{ jail }}_set_{{ set }}
      {% endfor %}

{% for rc_param, rc_value in cfg.rc_conf.items() %}

{{ jail }}_rc_conf_{{ rc_param }}:
  sysrc.managed:
    - name: {{ rc_param }}
    - value: {{ rc_value }}
    - file: {{ jails.root | path_join(jail, 'etc', 'rc.conf') }}
    - require_in:
      - cmd: {{ jail }}_start
    - require:
      - file: {{ jail }}_rc_conf
      - file: {{ jail }}_directory
    - onchanges:
      - file: {{ jail }}_directory

{% endfor %}  # RC_CONF

#########################
# JAIL /etc/resolv.conf #
#########################

{% if cfg.resolv_conf is defined %} 

{{ jail }}_resolv_conf:
  file.managed:
    - name: {{ jails.root | path_join(jail, 'etc', 'resolv.conf') }}
    - user: root
    - group: wheel
    - mode: 644
    - contents: |
        {{ cfg.resolv_conf|indent(8) }}
    - require_in:
      - cmd: {{ jail }}_start
    - require:
      - file: {{ jail }}_directory
    - onchanges:
      - file: {{ jail }}_directory

{% endif %}

###########
# PATCHES #
###########

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

#################################
# JAIL /etc/freebsd-update.conf #
#################################

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
      - cmd: {{ jail }}_freebsd_update_fetch_install

####################
# PKG REPOSITORIES #
####################

{{ jail }}_pkg_repos:
  file.directory:
    - name: {{ jails.root | path_join(jail, 'usr', 'local', 'etc', 'pkg', 'repos') }}
    - user: root
    - group: wheel
    - makedirs: True
    - mode: 755
    - onchanges:
      - file: {{ jail }}_directory

{% for rname, rconfig in cfg.get('pkg', {}).items() %}

{{ jail }}_pkg_repo_{{ rname }}:
  file.managed:
    - name: {{ jails.root | path_join(jail, 'usr', 'local', 'etc', 'pkg', 'repos', rname ~ '.conf') }}
    - user: root
    - group: wheel
    - mode: 644
    - contents: |
        {{ rname }}: {
          {%- for rkey, rvalue in rconfig.items() %}
            {%- if rkey in ('url', 'mirror_type', 'signature_type', 'pubkey', 'fingerprints') %}
              {{ rkey }}: "{{ rvalue.strip('"') }}",
            {%- elif rkey in ('ip_version', 'priority') %}
              {{ rkey }}: {{ rvalue }},
            {%- elif rkey in ('enabled', ) %}
              {{ rkey }}: {{ 'yes' if rvalue else 'no' }},
            {%- endif %}
          {%- endfor %}
        }
    - onchanges:
      - file: {{ jail }}_pkg_repos

{% endfor %}

##############
# JAIL FSTAB #
##############

{% for fstab in cfg.get('fstab', ()) %}

{% if fstab.get('present', True) %}

{%- if fstab.fstype == 'nullfs' %}

# We mount_nullfs a directory from the HOST, ensure that the directory exists.
# If you need a separate ZFS dataset, ensure that it is created before.

{{ jail }}_{{ fstab.device }}_fstab_device:
  file.directory:
    - name: {{ fstab.device }}
    - user: {{ fstab.get('user', 'root') }}
    - group: {{ fstab.get('group', 'wheel') }}
    - mode: {{ fstab.get('mode', 755) }}
    - makedirs: True
    - require_in:
      - file: {{ jail }}_fstab
    - require:
      - file: {{ jail }}_directory
    {% if jails.use_zfs %}
      - sls: zfs.fs
    {% endif %}

{%- endif %}

# The mountpoint directory in the jail.

{{ jail }}_{{ fstab.device }}_fstab_mount_point:
  file.directory:
    - name: {{ fstab.mount_point }}
    {% if not salt.mount.is_mounted(fstab.mount_point) %}
    - user: {{ fstab.get('user', 'root') }}
    - group: {{ fstab.get('group', 'wheel') }}
    - mode: {{ fstab.get('mode', 755) }}
    {% endif %}
    {%- if fstab.fstype in ('nfs', 'nullfs') %}
    - makedirs: True
    {%- endif %}
    - require:
      - file: {{ jail }}_directory
    - require_in:
      - file: {{ jail }}_fstab

{% endif %}  # fstab.present

{% endfor %}

{{ jail }}_fstab:
  file.managed:
    - name: /etc/fstab.{{ jail }}
    - user: root
    - group: wheel
    - mode: 644
    - contents: |
        # File managed by Saltstack, do not modify!
        {% for fstab in cfg.get('fstab', ()) if fstab.get('present', True) %}
        {{ fstab.device }} {{ fstab.mount_point }} {{ fstab.fstype }} {{ fstab.opts }} 0 0
        {%- endfor %}
    - require_in:
      - cmd: {{ jail }}_start

{{ jail }}_fstab_stop:
  cmd.run:
    - name: service jail onestop {{ jail }}
    - cwd: /tmp
    - prereq:
      - file: {{ jail }}_fstab
    - onlyif:
      - fun: jail.status
        args:
          - {{ jail }}

##############
# START JAIL #
##############

{% if cfg.boot_start %}

# Start on boot, add to rc.conf jail_list

{{ jail }}_jail_list:
  cmd.run:
    - name: sysrc jail_list+={{ jail }}
    - cwd: /tmp
    - unless:
      - sysrc -n jail_list|egrep -q '(^|[[:space:]]){{ jail }}($|[[:space:]])'

{% else %}

# Do not start on boot, remove from rc.conf jail_list

{{ jail }}_jail_list:
  cmd.run:
    - name: sysrc jail_list-={{ jail }}
    - cwd: /tmp
    - onlyif:
      - sysrc -n jail_list|egrep -q '(^|[[:space:]]){{ jail }}($|[[:space:]])'

{% endif %}

{{ jail }}_start:
  cmd.run:
    - name: service jail onestart {{ jail }}
    - cwd: /tmp
    - require:
      - file: jail_etc_jail_conf
      - cmd: {{ jail }}_jail_list
    - onchanges:
      - file: {{ jail }}_directory
      - cmd: {{ jail }}_fstab_stop

#####################
# JAIL INIT SCRIPTS #
#####################

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
      - PKG_SALT: {{ cfg.salt.pkg|default('') }}
    - require:
      - cmd: {{ jail }}_start
    - onchanges:
      - file: {{ jail }}_directory

{% endfor %}  # INIT SCRIPTS

{% else %}

##################
# JAIL IS ABSENT #
##################

#############
# STOP JAIL #
#############

{{ jail }}_stop:
  cmd.run:
    - name: service jail onestop {{ jail }}
    - cwd: /tmp
    - require_in:
      - file: jail_etc_jail_conf
      - cmd: {{ jail }}_jail_list
    - onlyif:
      - fun: jail.status
        args:
          - {{ jail }}

{{ jail }}_jail_list:
  cmd.run:
    - name: sysrc jail_list-={{ jail }}
    - cwd: /tmp
    - onlyif:
      - sysrc -n jail_list|egrep -q '(^|[[:space:]]){{ jail }}($|[[:space:]])'

{{ jail }}_fstab:
  file.absent:
    - name: /etc/fstab.{{ jail }}
    - require:
      - cmd: {{ jail }}_stop

{% if cfg.purge_if_absent|default(False) %}

{% if jails.use_zfs %}

{% else %}

{{ jail }}_chflags_noschg:
  cmd.run:
    - name: /bin/chflags -R noschg {{ jails.root | path_join(jail) }}
    - cwd: /tmp
    - require:
      - cmd: {{ jail }}_stop

{{ jail }}_remove_directory:
  file.absent:
    - name: {{ jails.root | path_join(jail) }}
    - require:
      - cmd: {{ jail }}_chflags_noschg

{% endif %}  # jails.use_zfs

{% endif %}  # jail.purge_if_absent

{% endif %}  # IF PRESENT
 
{% endfor %}  # JAILS LIST
