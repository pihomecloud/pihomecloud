import os

import testinfra.utils.ansible_runner

testinfra_hosts = testinfra.utils.ansible_runner.AnsibleRunner(
    os.environ['MOLECULE_INVENTORY_FILE']).get_hosts('all')


def test_samba_installe(host):
    assert host.run('pacman -Qi samba').rc == 0


def test_samba_configure(host):
    f = host.file('/etc/samba/smb.conf')
    assert f.exists
    assert f.user == 'root'
    assert f.group == 'root'
    assert f.mode == 0500


def test_samba_demmarre(host):
    s = host.service('smbd')
    assert s.is_running
    assert s.is_enabled


def test_le_partage_de_test_est_present(host):
    assert host.run('smbclient -L 127.0.0.1 -U%| grep test_molecule').rc == 0


def test_mount_localhost(host):
    with host.sudo():
        mount = host.run('mount -t cifs //127.0.0.1/test_molecule /mnt')
    assert mount.rc == 0
