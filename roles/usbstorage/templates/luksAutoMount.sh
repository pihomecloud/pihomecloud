#!/bin/bash
#{{ansible_managed}}
set -o pipefail
startBackup=$(date +%s)
export LANG=fr_FR.UTF-8
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl

watchDir="/media/{{cryptName}}-unencrypted/mount/"
fileWatch="$watchDir/luks.txt"

[[ ! -d "$watchDir" ]] && mkdir "$watchDir"

touch "$fileWatch"

#making data directory accesible and writable for homecloud even if unmounted
if [ -d "{{homecloudDataDir}}" ]
then
  [ ! -e "{{homecloudDataDir}}/.ocdata" ] && touch "{{homecloudDataDir}}/.ocdata" && chmod 777 "{{homecloudDataDir}}/.ocdata"
  chown http: "{{homecloudDataDir}}"
fi

if [[ -s "$fileWatch" ]]
then
  #File is not empty, getting the content and deleting this secured
  password=$(cat "$fileWatch")
  shred -u -n 20 "$fileWatch"
  isLuksDiskOpenned=$(dmsetup ls --target crypt | grep "^{{cryptName}}\s")
  if [ -z "$isLuksDiskOpenned" ]
  then
    echo "$password" | cryptsetup luksOpen "/dev/mapper/vg{{cryptName}}-lvcrypted" {{cryptName}}
    [ $? -ne 0 ] && echo "Unable to open /dev/mapper/vg{{cryptName}}-lvcrypted" && exit
  fi
  if [ -e "/dev/mapper/{{cryptName}}" ]
  then
    mount -a
    [ -z "$(grep ' /media/{{cryptName}}/{{cryptName}}-top-lvl ' /proc/mounts)" ] && mount "/media/{{cryptName}}/{{cryptName}}-top-lvl"
{% for mount in btrfsSubVolumes %}
    [ -z "$(grep ' /media/{{cryptName}}/{{mount.mount}} ' /proc/mounts)" ] && mount "/media/{{cryptName}}/{{mount.mount}}"
{% endfor %}
{% for mount in btrfsSubVolumesAdditionnals %}
    [ -z "$(grep ' /media/{{cryptName}}/{{mount.mount}} ' /proc/mounts)" ] && mount "/media/{{cryptName}}/{{mount.mount}}"
{% endfor %}
  fi
fi

touch "$fileWatch"
chmod 0600 "$fileWatch"
chown http: "$fileWatch"

