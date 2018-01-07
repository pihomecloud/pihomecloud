import os

import testinfra.utils.ansible_runner

testinfra_hosts = testinfra.utils.ansible_runner.AnsibleRunner(
    os.environ['MOLECULE_INVENTORY_FILE']).get_hosts('all')


def test_munin_installe(host):
    assert host.run("pacman -Q munin").rc == 0


def test_munin_node_installe(host):
    assert host.run("munin-node").rc == 0


def test_munin_root_cree(host):
    assert host.file("/srv/http/munin").is_directory
    assert host.file("/srv/http/munin").user == "munin"
    assert host.file("/srv/http/munin").group == "http"


def test_html_dir_dans_la_conf(host):
    cmd = host.run("grep '^htmldir /srv/http/munin' /etc/munin/munin.conf")
    assert cmd.rc == 0

def test_conf_munin_nodehost):
    cmd = host.run("grep '^host 127.0.0.1' /etc/munin/munin-node.conf")
    assert cmd.rc == 0

