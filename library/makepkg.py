#!/usr/bin/python -tt
# -*- coding: utf-8 -*-

# (c) 2015, Ross Williams <http://github.com/gunzy83>
#
# This file is part of Ansible
#
# Ansible is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ansible is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ansible.  If not, see <http://www.gnu.org/licenses/>.

DOCUMENTATION = '''
---
module: makepkg
short_description: Build and install packages with I(makepkg) and I(pacman)
description:
    - Build  packages with the I(makepkg) and install with I(pacman) package manager, which is used by
      Arch Linux and its variants.
version_added: "1.8.2"
author: Ross Williams
notes: []
requirements: [base-devel]
options:
    name:
        description:
            - Name of the AUR package to build and install or remove. Can also
              be the path to a source package to be built.
        required: true
        default: null
    state:
        description:
            - Desired state of the package.
        required: true
        default: "present"
        choices: ["present", "absent"]
    recurse:
        description:
            - When removing a package, also remove its dependencies, provided
              that they are not required by other packages and were not
              explicitly installed by a user.
        required: false
        default: "no"
        choices: ["yes", "no"]
    as_deps:
        description:
            - Whether or not to install the package with the **--asdeps** flag.
              Useful for installing optional or AUR dependencies of AUR packages.
        required: false
        default: "no"
        choices: ["yes", "no"]
    build_dir:
        description:
            - Directory to extract source tarball for building the package
        required: false
        default: "/var/cache/pacman/pkg"
'''

EXAMPLES = '''
# Build and Install package aurvote
- makepkg: name=aurvote state=present
# Remove package aurvote
- makepkg: name=aurvote state=absent
# Recursively remove package aurvote
- makepkg: name=aurvote state=absent recurse=yes
# Build and Install package aurvote as a dependency
- makepkg: name=aurvote state=present as_deps=yes
# Build in a custom build directory
- makepkg: name=aurvote state=present build_dir="~/builds"
'''

import json
import os
import re
import pwd
import grp
import shutil
import urllib
from ansible.module_utils.six.moves.urllib.parse import urlparse, urlunparse

PACMAN_PATH = "/usr/bin/pacman"
MAKEPKG_PATH = "/usr/bin/makepkg"
PACKAGE_CACHE = "/var/cache/pacman/pkg"
AUR_SCHEME = "https"
AUR_NETLOC = "aur.archlinux.org"
AUR_RPC_PATH = "rpc.php"
AUR_SNAPSHOT_PATH = "cgit/aur.git/snapshot"

def query_package_dir(module, name, version):

    matcher = re.compile('%s-%s[\.xany0-9_-]*\.pkg\.tar\.xz$' % (name,version))
    for filename in os.listdir(PACKAGE_CACHE):
        if matcher.match(filename):
            return os.path.join(PACKAGE_CACHE,filename)

    return None

def query_package(module, name):
    # pacman -Q returns 0 if the package is installed,
    # 1 if it is not installed
    cmd = "pacman -Q %s" % (name)
    rc, stdout, stderr = module.run_command(cmd, check_rc=False)

    if rc == 0:
        return True

    return False

def get_package_current_version(module, name):
    # pacman -Q returns the name, a space and the version
    cmd = "pacman -Q %s" % (name)
    rc, stdout, stderr = module.run_command(cmd, check_rc=False)
    if rc == 0:
        return stdout.split()[1]
    return "0-0"

def remove_package(module, pkg):
    # Query the package first, to see if we even need to remove
    if not query_package(module, pkg):
        module.exit_json(changed=False, msg="package(s) already absent")

    if module.params["recurse"]:
        args = "Rs"
    else:
        args = "R"

    cmd = "pacman -%s %s --noconfirm" % (args, pkg)
    rc, stdout, stderr = module.run_command(cmd, check_rc=False)

    if rc != 0:
        module.fail_json(msg="failed to remove package %s" % pkg)

    module.exit_json(changed=True, msg="removed package %s" % pkg)

def prepare_build_dir(module, pkg_name, sudo_user):
    build_dir = module.params['build_dir']
    uid = pwd.getpwnam(sudo_user).pw_uid
    gid = grp.getgrnam('users').gr_gid

    directory = os.path.join(build_dir, pkg_name)
    if not os.path.exists(directory):
        try:
            os.mkdir(directory, 0755)
        except OSError:
            module.fail_json(msg="failed to create build directory %s" % (directory))

    if os.stat(directory).st_uid != uid:
        try:
            os.chown(directory,uid,gid)
        except OSError as e:
            module.fail_json(msg="failed to change owner of build directory %s" % (e.strerror))

    return directory

def prepare_git_dir(module, build_dir, pkg):
    git_source = module.params['git_source']
    sudo_user = os.environ.get('SUDO_USER')
    command_prefix = "sudo -u %s " % sudo_user
    build_dir = prepare_build_dir(module, pkg, sudo_user)
    clone = True
    #need to update subdirectory if not removed
    if os.path.exists(build_dir+'/.git'):
      if 'url = '+git_source in open(build_dir+'/.git/config').read():
        clone = False
        cmd = '%sgit reset --hard HEAD' % (command_prefix)
        rc, stdout, stderr = module.run_command(cmd, check_rc=False, cwd=build_dir)
        if rc != 0:
          module.fail_json(msg="failed to pull %s for pkg %s, is git present and in the PATH ? Command: %s" % (git_source, pkg, cmd), stderr=stderr)
        else:
          cmd = '%sgit pull' % (command_prefix)
          rc, stdout, stderr = module.run_command(cmd, check_rc=False, cwd=build_dir)
          if rc != 0:
            module.fail_json(msg="failed to pull %s for pkg %s, is git present and in the PATH ? Command: %s" % (git_source, pkg, cmd), stderr=stderr)

    if clone:
      #ckeaning in case of change of source
      if os.path.exists(build_dir):
        try:
            shutil.rmtree(build_dir)
        except Exception, err:
            module.fail_json(msg="failed to remove temporary build directory %s: %s" % (build_dir, str(err)))
        build_dir = prepare_build_dir(module, pkg, sudo_user)

      #cloning repo
      cmd = '%sgit clone "%s" %s' % (command_prefix, git_source, build_dir)
      rc, stdout, stderr = module.run_command(cmd, check_rc=False, cwd=build_dir)
      if rc != 0:
          module.fail_json(msg="failed to clone %s for pkg %s, is git present and in the PATH ? %s exists, so i issued the following command : %s" % (git_source, pkg, build_dir+'/.git', cmd), stderr=stderr)

def get_build_current_version(module, pkg, pkg_file):
    git_source = module.params['git_source']
    sudo_user = os.environ.get('SUDO_USER')
    build_dir = prepare_build_dir(module, pkg, sudo_user)
    pkgver_parse = module.params['pkgver_parse']
    force_https = module.params['force_https']
    command_prefix = "sudo -u %s " % sudo_user
    current_version = "0-0"
    if git_source:
        #Custom git repo
        prepare_git_dir(module, build_dir, pkg)
    elif pkg_file:
        #tar.gz archive
        extract_pkg(module, pkg, pkg_file_dest, build_dir)
    else:
        #AUR package
        prepare_aur_dir(module, build_dir, pkg)

    if not os.path.exists(build_dir+'/PKGBUILD'):
        module.fail_json(msg="failed to find %s" % (build_dir+'/PKGBUILD'))
    else:
        #getting version and release from PKGBUILD
        for line in open(build_dir+'/PKGBUILD'):
            if 'pkgver=' in line:
               pkgver = line.split('=')[1].strip()
            if 'pkgrel=' in line:
               pkgrel = line.split('=')[1].strip()
        if 'pkgver()' in open(build_dir+'/PKGBUILD').read() and pkgver_parse != 'never':
            eval_pkgver = False
            if pkgver_parse == 'always':
              eval_pkgver = True
              pkgver_parse = 0
            else:
              #Convert pkgver_parse in relative timestamp
              cmd = 'date --date="-'+ str(pkgver_parse)+'" "+%s"'
              rc, stdout, stderr = module.run_command(cmd, check_rc=False, cwd=build_dir)
              if rc != 0:
                module.fail_json(msg="failed to convert %s in seconds for %s (%s)" %(pkgver_parse,pkg,cmd), stderr=stderr)
              else:
                pkgver_parse = int(stdout)
            
            #Get last update
            cmd = "/usr/bin/pacman -Qi '"+pkg+"'"
            rc, stdout, stderr = module.run_command(cmd, use_unsafe_shell=True, check_rc=False, cwd=build_dir, environ_update={'LANG':'C', 'LC_ALL':'C','LC_MESSAGES':'C'})
            #If not installed, no need for parse
            if "package '"+pkg+"' was not found" not in stderr:
              if rc != 0 or 'Install Date' not in stdout:
                  #Not installed
                  last_update = 0
                  module.fail_json(msg="cmd=%s, rc=%s, stdout=%s stderr=%s" %(cmd,rc, stdout, stderr), stderr=stderr)
              else:
                  timestamp_installed ="0"
                  for line in stdout.split('\n'):
                    if ':' in line and 'Install Date' in line :
                      match = line.split(':',1)
                      #perhaps the Packager is "Install Date', I neede to check if it's before the ':'
                      if 'Install Date' in match[0]:
                        timestamp_installed = match[1]
                  if timestamp_installed =="0":
                      module.fail_json(msg="failed to find Install Date for %s (%s : %s)" %(pkg,cmd,stdout), stderr=stderr)
                  else:
                    cmd = 'date --date="'+timestamp_installed+'" "+%s"'
                    rc, stdout, stderr = module.run_command(cmd, check_rc=False, cwd=build_dir)
                    if rc != 0 or not stdout or stderr or timestamp_installed =="0":
                        module.fail_json(msg="failed to convert %s in seconds for %s (%s : %s)" %(timestamp_installed,pkg,cmd,stdout), stderr=stderr)
                    else:
                        last_update = int(stdout)
              #pkgver gives the version, see https://wiki.archlinux.org/index.php/VCS_package_guidelines
              #pkgver is in PKGBUILD, but optionnal, I need to download, extract files and run the prepare()
              #       in order to find version
              if last_update <= pkgver_parse or pkgver_parse == 0:
                if force_https:
                    cmd="sed -i \"s,git://,git+https://,g\" %s/PKGBUILD" % (build_dir)
                    rc, stdout, stderr = module.run_command(cmd, check_rc=False, cwd=build_dir)
                    if rc != 0:
                        module.fail_json(msg="failed to force https in %s/PKGBUILD : %s " % (build_dir, cmd), stderr=stderr)
                cmd = '%smakepkg -od' % (command_prefix)
                rc, stdout, stderr = module.run_command(cmd, check_rc=False, cwd=build_dir)
                if rc != 0:
                    module.fail_json(msg="failed to download, extract files and run the prepare() for %s" %(pkg), stderr=stderr)
                else:
                    cmd='%s bash -c "source PKGBUILD && pkgver"' % (command_prefix)
                    rc, stdout, stderr = module.run_command(cmd, check_rc=False, cwd=build_dir)
                    if rc != 0:
                        module.fail_json(msg="failed to execute pkgver function for %s" %(pkg), stderr=stderr)
                    pkgver = stdout.strip()
        current_version = pkgver + '-' + pkgrel
    if os.path.exists(build_dir):
      try:
          shutil.rmtree(build_dir)
      except Exception, err:
          module.fail_json(msg="failed to remove temporary build directory %s: %s" % (build_dir, str(err)))
  
    return str(current_version)

def prepare_aur_dir(module, build_dir, pkg):
    pkg_file_basename = "%s.tar.gz" % pkg
    pkg_file_dest = os.path.join(build_dir, pkg_file_basename)
    aur_req = urlunparse((AUR_SCHEME, AUR_NETLOC, "%s/%s" % (AUR_SNAPSHOT_PATH, pkg_file_basename), "", "", ""))
    rsp, info = fetch_url(module, aur_req)

    if info['status'] != 200:
        module.fail_json(msg="Request failed", url=aur_req, status_code=info['status'], response=info['msg'])
    # save response to archive
    f = open(pkg_file_dest, 'wb')
    try:
        shutil.copyfileobj(rsp, f)
    except Exception, err:
        os.remove(pkg_file_dest)
        module.fail_json(msg="failed to create package archive file: %s" % str(err))
    f.close()
    rsp.close()
    extract_pkg(module, pkg, pkg_file_dest, build_dir)

def extract_pkg(module, pkg, pkg_file, build_dir):
    sudo_user = os.environ.get('SUDO_USER')
    command_prefix = "sudo -u %s " % sudo_user
    if pkg_file:
        cmd = '%star --strip-components=1 -xf %s.tar.gz' % (command_prefix, pkg)
        rc, stdout, stderr = module.run_command(cmd, check_rc=False, cwd=build_dir)
        if rc != 0:
            module.fail_json(msg="failed to extract %s for pkg %s" % (pkg_file, pkg), stderr=stderr)

def make_package(module, pkg, pkg_file_src):
    sudo_user = os.environ.get('SUDO_USER')

    # Build as user, not as root
    command_prefix = "sudo -u %s " % sudo_user

    build_dir = prepare_build_dir(module, pkg, sudo_user)
    git_source = module.params['git_source']
    force_arch = module.params['force_arch']
    force_https = module.params['force_https']

    cmd = ""
    pkg_file_basename = "%s.tar.gz" % pkg
    pkg_file_dest = os.path.join(build_dir, pkg_file_basename)

    if pkg_file_src:
        # copy file to build directory
        try:
            shutil.copy2(pkg_file_src, build_dir)
        except Exception, err:
            module.fail_json(msg="failed to copy package %s to build directory %s: %s" % (pkg_file_src, build_dir, str(err)))
        extract_pkg(module, pkg, pkg_file_dest, build_dir)
    elif git_source:
        prepare_git_dir(module, build_dir, pkg)
    else:
        prepare_aur_dir(module, build_dir, pkg)


    pkg_file = pkg_file_dest

    if force_arch:
        cmd="sed -i \"s/^arch=(/arch=('%s' /\" %s/PKGBUILD" % (force_arch, build_dir)
        rc, stdout, stderr = module.run_command(cmd, check_rc=False, cwd=build_dir)
        if rc != 0:
            module.fail_json(msg="failed to add arch '%s' in %s/PKGBUILD : %s " % (force_arch, build_dir, cmd), stderr=stderr)
    if force_https:
        cmd="sed -i \"s,git://,git+https://,g\" %s/PKGBUILD" % (build_dir)
        rc, stdout, stderr = module.run_command(cmd, check_rc=False, cwd=build_dir)
        if rc != 0:
            module.fail_json(msg="failed to force https in %s/PKGBUILD : %s " % (build_dir, cmd), stderr=stderr)
    cmd = '%smakepkg -scf --noconfirm' % command_prefix
    rc, stdout, stderr = module.run_command(cmd, check_rc=False, cwd=build_dir)
    if rc != 0:
        module.fail_json(msg="failed to build package %s in %s from %s" % (pkg, pkg_file, build_dir), stderr=stderr)

    found_file = None
    matcher = re.compile('%s-.*\.pkg\.tar\.xz$' % pkg)
    for filename in os.listdir(build_dir):
        # check if filename not found, if not we need to fail out
        if matcher.match(filename):
            found_file = filename

    if not found_file:
        module.fail_json(msg="failed to find the built package for %s" % pkg)

    # Keep package in cache for downgrades later.  Use shutil.copy since we
    # don't care about preserving permissions.
    try:
        shutil.copy(os.path.join(build_dir, found_file), PACKAGE_CACHE)
    except Exception, err:
        module.fail_json("Failed to copy package %s to cache %s: %s" % (found_file, PACKAGE_CACHE, str(err)))

    # Don't leave build files lying around
    try:
        shutil.rmtree(build_dir)
    except Exception, err:
        module.fail_json(msg="failed to remove temporary build directory %s: %s" % (build_dir, str(err)))

    return os.path.join(PACKAGE_CACHE,found_file)


def check_build_environment(module):
    user = os.environ.get('USER')
    sudo_user = os.environ.get('SUDO_USER')
    build_dir = module.params['build_dir']

    # We want to build as user, not as root
    if not sudo_user:
        module.fail_json(msg="building as root not permitted, run as user and use sudo")

    # Check if we need to be able to install pkg and fail out if we can't
    if user != 'root':
        module.fail_json(msg="sudo required to install packages")

    if not os.path.exists(build_dir):
        module.fail_json(msg="base build directory %s does not exist" % build_dir)

    if not os.access(build_dir, os.W_OK):
        module.fail_json(msg="base build directory %s is not accessible" % build_dir)

def install_package(module, pkg, pkg_file, upgrade):
    check_build_environment(module)
    git_source = module.params['git_source']
    gpg_key = module.params['gpg_key']

    if not upgrade and query_package(module, pkg):
        module.exit_json(changed=False, msg="package already installed", package=pkg)

    if gpg_key:
         if should_add_gpg_key(module, gpg_key):
             add_gpg_key(module, gpg_key)

    if git_source:
      pkg_path = make_package(module, pkg, None)
    elif not pkg_file:
        # this is an aur pkg
        rpc_params = urllib.urlencode({"type": "info", "arg": pkg})
        rpc_req = urlunparse((AUR_SCHEME, AUR_NETLOC, AUR_RPC_PATH, "", rpc_params, ""))
        rsp, info = fetch_url(module, rpc_req)

        # create a temporary file and copy content to do checksum-based replacement
        if info['status'] != 200:
            module.fail_json(msg="Request failed", status_code=info['status'], response=info['msg'], url=rpc_req)

        pkg_info = json.load(rsp)

        if pkg_info['resultcount'] < 1:
            module.fail_json(msg="AUR query found no matching packages", package=pkg)

        # check pkg cache before install
        pkg_ver = pkg_info['results']['Version']
        pkg_path = query_package_dir(module, pkg, pkg_ver)
        if not pkg_path:
            pkg_path = make_package(module, pkg, None)

    else:
        pkg_path = make_package(module, pkg, pkg_file)

    if module.params['as_deps']:
        params = '-U --asdeps %s' % pkg_path
    else:
        params = '-U %s' % pkg_path

    cmd = "pacman %s --noconfirm" % (params)
    rc, stdout, stderr = module.run_command(cmd, check_rc=False)

    if rc != 0:
        module.fail_json(msg="failed to install package", pkg=pkg, stderr=stderr)

    module.exit_json(changed=True, msg="installed package", pkg=pkg)

def check_package(module, pkg, state, pkg_file):

    changed = False
    installed = query_package(module, pkg)
    git_source = module.params['git_source']

    if ((state == "present" or state == "latest") and not installed):
        # if the build would fail because of the state of the system we want to know
        check_build_environment(module)
        state = "installed"
        changed = True

    if (state == "absent" and installed):
        state = "removed"
        changed = True

    if (state == "latest" and installed):
        upgrade, current_version, next_version = should_be_upgraded(module, pkg, pkg_file)
        if upgrade:
           state = "upgraded to %s (actually : %s)" % (next_version, current_version)
           changed = True
        else:
           state = "at latest version : %s >= %s" % (current_version, next_version)

    if module.params['gpg_key'] and not changed:
         if should_add_gpg_key(module, module.params['gpg_key']):
             changed=True
    if changed:
        module.exit_json(changed=True, msg="package would be %s" % state, package=pkg)
    else:
        module.exit_json(changed=False, msg="package already %s" % state, package=pkg)

def str_to_int_tuple(s):
    return tuple(int(x) for x in re.split('[^0-9]+', s) if x)

def should_add_gpg_key(module, key):
    sudo_user = os.environ.get('SUDO_USER')
    command_prefix = "sudo -u %s " % sudo_user
    cmd="%sgpg --list-keys %s" % (command_prefix, key)
    rc, stdout, stderr = module.run_command(cmd, check_rc=False)
    if rc == 0:
        return False
    if rc == 2:
        return True
    if rc != 0 and rc != 2:
       module.fail_json(msg="failed to list gpg_keys : %s " % (cmd), stderr=stderr)

def add_gpg_key(module, key):
    sudo_user = os.environ.get('SUDO_USER')
    command_prefix = "sudo -u %s " % sudo_user
    gpg_server=module.params['gpg_server']
    cmd="%sgpg " % command_prefix
    if gpg_server:
       cmd+=" --keyserver " + str(gpg_server)
    cmd+=" --recv-keys %s" % key
    rc, stdout, stderr = module.run_command(cmd, check_rc=False)
    if rc != 0:
       module.fail_json(msg="failed to gpg key : %s " % (cmd), stderr=stderr)


def should_be_upgraded(module, pkg, pkg_file):
    check_build_environment(module)
    current_version = get_package_current_version(module, pkg)
    next_version = get_build_current_version(module, pkg, pkg_file)
    upgrade = False
    cur_pkgver, cur_pkgrel = current_version.split('-')
    next_pkgver, next_pkgrel = next_version.split('-')
    #Need to convert to tuple becaus 1.5 > 1.10 or 1.5.10 > 1.10 in string compare
    #In tuple, it gives 1.5 < 1.10 and 1.5.10 < 1.10
    if str_to_int_tuple(cur_pkgver) < str_to_int_tuple(next_pkgver):
         upgrade = True
    elif current_version == next_version and cur_pkgrel < next_pkgrel:
         upgrade = True
    return (upgrade ,current_version, next_version)

def main():

    argument_spec = dict(
        name         = dict(aliases=['pkg'], required=True),
        state        = dict(choices=['installed', 'present', 'absent', 'removed', 'latest'], required=True),
        recurse      = dict(default='no', choices=BOOLEANS, type='bool'),
        as_deps      = dict(default='no', choices=BOOLEANS, type='bool'),
        build_dir    = dict(default=PACKAGE_CACHE),
        force_arch   = dict(default='', required=False),
        git_source   = dict(default='', required=False),
        force_https  = dict(default='no', choices=BOOLEANS, type='bool', required=False),
        gpg_key      = dict(default='', required=False),
        gpg_server   = dict(default='', required=False),
        pkgver_parse = dict(default='always', choices=['always','never','1days','1weeks','1months','3months','6months','1years'], required=False)
    )

    module = AnsibleModule(
        argument_spec = argument_spec,
        required_one_of = [['name']],
        supports_check_mode = True
    )

    if not os.path.exists(PACMAN_PATH):
        module.fail_json(msg="cannot find pacman, looking for %s" % (PACMAN_PATH))
    if not os.path.exists(MAKEPKG_PATH):
        module.fail_json(msg="cannot find makepkg, looking for %s" % (MAKEPKG_PATH))

    p = module.params

    # normalize the state parameter
    if p['state'] in ['present', 'installed']:
        p['state'] = 'present'
    elif p['state'] in ['absent', 'removed']:
        p['state'] = 'absent'

    pkg = p['name']
    pkg_file = None
    if pkg.endswith('.tar.gz'):
        # The package given is a filename, extract the raw pkg name from
        # it and store the filename
        pkg_file = pkg
        pkg = os.path.basename(pkg)[:-1 * len('.tar.gz')]
    
    if module.check_mode:
        check_package(module, pkg, p['state'], pkg_file)
    else:
      if p['state'] == 'present':
          install_package(module, pkg, pkg_file, False)
      elif p['state'] == 'absent':
          remove_package(module, pkg)
      elif p['state'] == 'latest':
          upgrade, current_version, next_version = should_be_upgraded(module, pkg, pkg_file)
          install_package(module, pkg, pkg_file, upgrade)

# Used for downloading packages from the AUR
from ansible.module_utils.urls import *

# import module snippets
from ansible.module_utils.basic import *

main()
