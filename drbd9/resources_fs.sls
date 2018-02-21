# -*- coding: utf-8 -*-
# vim: ft=sls

{% from "drbd9/map.jinja" import drbd9 with context %}

{% set node_ids = drbd9.nodes.keys()|sort %}
{% set admin_node_id = node_ids[0] %}
{% set my_id = grains['id'] %}
# node_ids: {{node_ids}}
# admin_node_id: {{admin_node_id}}
# my_id: {{my_id}}

{% if my_id in [ admin_node_id ] %}

  {% for resource, resource_data in drbd9.resources.items()|sort %}
    {% for volume, volume_data in resource_data.volumes.items()|sort %}
      {% if volume_data.get('fstype', False) %}
        {% set initfs_done = salt['grains.get']('drbd9:resources:' + resource|string + ':' + volume|string + ':initfs', False) %}
# resource={{resource}}, volume={{volume}}, initfs_done={{ initfs_done }}
        {% if not initfs_done %}

drbd9_resources_fs__{{ resource }}_{{ volume }}_create_fs:
  cmd.run:
    - name: blkid -c /dev/null -o value -s TYPE /dev/drbd/by-res/{{ resource }}/{{ volume }} || mkfs.{{volume_data.fstype}} {% if volume_data.mkfsopts is defined and volume_data.mkfsopts %} {{volume_data.mkfsopts}} {% endif %} /dev/drbd/by-res/{{ resource }}/{{ volume }} && sync && udevadm settle && blkid -c /dev/null -o value -s TYPE /dev/drbd/by-res/{{ resource }}/{{ volume }} | grep -w {{volume_data.fstype}}
    - onlyif: test -b /dev/drbd/by-res/{{ resource }}/{{ volume }} && test -w /dev/drbd/by-res/{{ resource }}/{{ volume }} && drbdadm role {{ resource }}|grep -w Secondary
    - unless: '! dd if=/dev/drbd/by-res/{{ resource }}/{{ volume }} of=/dev/null bs=1 count=1 ||  blkid -c /dev/null -o value -s TYPE /dev/drbd/by-res/{{ resource }}/{{ volume }}|grep -w {{volume_data.fstype}}'
    - require_in:
      - grains: drbd9_resources_fs__{{ resource }}_{{ volume }}_set_grain_successful

          {% if volume_data.get('directories', False) %}
drbd9_resources_fs__{{ resource }}_{{ volume }}_mount:
  mount.mounted:
    - name: /tmp{{ volume_data.get('mountpoint') }}
    - device: /dev/drbd/by-res/{{ resource }}/{{ volume }}
    - fstype: {{ volume_data.get('fstype') }}
    - opts: {% if volume_data.get('mountopts', False) %} {{volume_data.mountopts}} {% else %} rw,defaults {% endif %}
    - mkmnt: True
    - persist: False
    - match_on:
      - name
      - device
    - onlyif: test -b /dev/drbd/by-res/{{ resource }}/{{ volume }} && test -w /dev/drbd/by-res/{{ resource }}/{{ volume }} && drbdadm role {{ resource }}|grep -w Secondary && dd if=/dev/drbd/by-res/{{ resource }}/{{ volume }} of=/dev/null bs=1 count=1 && test -z "`(mount |grep -w /dev/drbd/by-res/{{ resource }}/{{ volume }} || mount |grep -w $(drbdadm sh-dev {{ resource }}/{{ volume }}) )`"
    - require:
      - cmd: drbd9_resources_fs__{{ resource }}_{{ volume }}_create_fs
    - require_in:
      - grains: drbd9_resources_fs__{{ resource }}_{{ volume }}_set_grain_successful

            {% for directory, directory_data in volume_data.get('directories').items()|sort %}
drbd9_resources_fs__{{ resource }}_{{ volume }}_mkdirs_{{ directory }}:
  file.directory:
    - name: /tmp{{ volume_data.get('mountpoint') }}/{{ directory }}
    - user: {{ directory_data.get('user', 'root') }}
    - group: {{ directory_data.get('group', 'root') }}
    - mode: {{ directory_data.get('mode', '"0755"') }}
    - makedirs: True
    - onlyif: dd if=/dev/drbd/by-res/{{ resource }}/{{ volume }} of=/dev/null bs=1 count=1 && (mount |grep -w /dev/drbd/by-res/{{ resource }}/{{ volume }} || mount |grep -w `drbdadm sh-dev {{ resource }}/{{ volume }}`)|grep -w /tmp{{ volume_data.get('mountpoint') }}
    - require:
      - mount: drbd9_resources_fs__{{ resource }}_{{ volume }}_mount
    - require_in:
      - mount: drbd9_resources_fs__{{ resource }}_{{ volume }}_umount
      - grains: drbd9_resources_fs__{{ resource }}_{{ volume }}_set_grain_successful
            {% endfor %}

drbd9_resources_fs__{{ resource }}_{{ volume }}_umount:
  mount.unmounted:
    - name: /tmp{{ volume_data.get('mountpoint') }}
    - persist: False
    - require:
      - cmd: drbd9_resources_fs__{{ resource }}_{{ volume }}_create_fs
      - mount: drbd9_resources_fs__{{ resource }}_{{ volume }}_mount
    - require_in:
      - grains: drbd9_resources_fs__{{ resource }}_{{ volume }}_set_grain_successful
          {% endif %}

drbd9_resources_fs__{{ resource }}_{{ volume }}_set_grain_successful:
  grains.present:
    - name: drbd9:resources:{{ resource }}:{{ volume }}:initfs
    - value: True

        {% endif %}
      {% endif %}
    {% endfor %}
  {% endfor %}
{% endif %}

drbd9_resources_fs__empty_sls_prevent_error:
  cmd.run:
    - name: true
    - unless: true

