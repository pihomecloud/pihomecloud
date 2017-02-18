#!/usr/bin/python


def main():
  module = AnsibleModule(
    argument_spec = dict(
      set_ntp = dict(required=True, type='bool'),
    ),
  )

  result, stdout, stderr = module.run_command("timedatectl  status --no-pager")
  if re.match(r'.*Network time on: yes', stdout, re.S|re.M):
    ntp_enabled=True
  else:
    ntp_enabled=False
  
  set_ntp = module.params['set_ntp']
  
  if set_ntp == ntp_enabled:
    module.exit_json(changed = False, result = "Success")
  else:
    if module.check_mode:
      module.exit_json(changed = true)
    else:
      change_ntp(set_ntp)
      module.exit_json(changed = True, result = "Success")

def change_ntp(set_ntp):
  command = "timedatectl set-ntp "
  if set_ntp:
    command += "true"
  else:
    command += "false"
  rc = os.system(command)
  if rc != 0:
    return dict(failed=True, msg="Failed do set date witch "+command)
  else:
    return dict(changed=True)

# import module snippets
from ansible.module_utils.basic import *
main()
