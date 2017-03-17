# Ansible playbook for a local raspberry PI webserver, private cloud

This Playbook helps to build a local server, using only software respecting your privacy and security is the target of this repo

roles
- base : base installation of archlinux
- hardened : hardening based of cis
- mysql : mariadb installtion on archlinux (master/slave groups used for replication)
- usbstorage : add an external usb storage with luks encryption
- localca : local pki used for non public serts or users certificates
- letsencrypt : free public certificate, with auto renewal
- webserver : secured nginx server with php-fpm backend installed, naxsi Web Application Firewall included
- nextcloud : no google account, manaing contacts, files, tasks privacy rulezzz
- ssmtp : local sendmail usage, with ssl for external mail account
- snort : Network Intrusion Detection & Prevention System
- domoticz : local domotic server with open zwave, working with razberry daughter card or usb stick
- dlna : private dlna server
- packt : download daily free ebook, putting it in nextcloud
- monit : lightweight monitoring
- iptables : local firewall, preventing unwanted intrusion on your server
- fail2ban : Fail2ban scans log files and bans IPs that show the malicious signs
- read_only_root : used with localstorage, prevents write to your SD card.

# Installation
http://archlinuxarm.org/platforms/armv6/raspberry-pi
https://archlinuxarm.org/platforms/armv7/broadcom/raspberry-pi-2
https://archlinuxarm.org/platforms/armv8/broadcom/raspberry-pi-3

- on the controller :
  sudo pacman -Sy python2-netdev
- Intall ansible deps (defaults pass : ssh : alarm ; sudo : root)
```
ssh alarm@raspberrypi 'su -c "pacman -Sy --noconfirm sudo python python2"'
```
- prepare run env
```
ansible-playbook -i raspberrypi init_once.yml --ask-pass --ask-become-pass
```

- form my PC
```
ssh-copy-id {{ localuser }}@raspberrypi
/etc/ansible.cfg
scp_if_ssh = True
```

# Run ansible
```
ansible-playbook -i hosts raspberrypi.yml --ask-become-pass
ansible-playbook -i hosts raspberrypi.yml
```

# TODO
- [ ] correct documentation

#ME
I'm system administrator building and maintaining security environments under Linux, loving open source software.

This playbook is used for my private servers and maintained on my free time.

"It's not because I am paranoid that they are not all after me." Pierre Desproges, French Humorist.
