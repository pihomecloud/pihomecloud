# Ansible playbook for a local raspberry PI webserver, private cloud
- owncloud : no google account
- domoticz : local domotic server with open zwave, working with rasberry daughter card or usb stick
- shinken : open source monitoring
- localca : local certification authority, usefull for client certificate auth
- letsencrypt : free public certificate, with auto renewal
- minidlna : private dlna server
- hardening : lot of modifications, providing security (snort, fail2ban, iptables, kernel paramters)

# Installation
http://archlinuxarm.org/platforms/armv6/raspberry-pi

- on the controller : 
  sudo pacman -Sy python2-netdev
- Intall ansible deps (defaults pass : ssh : alarm ; sudo : root)
```
ssh alarm@raspberrypi 'su -c "pacman -Sy --noconfirm sudo python python2"'
```
- prepare run env
```
ansible-playbook -i raspberrypi init_once.yml --ask-pass --ask-becom-pass
```

- form my PC
```
ssh-copy-id {{localuser}}@raspberrypi
/etc/ansible.cfg
scp_if_ssh = True
```

# Run ansible
```
ansible-playbook -i hosts raspberrypi.yml --ask-become-pass
ansible-playbook -i hosts raspberrypi.yml
```

# TODO
- [ ] finish the playbook
- [ ] correct documentation
