#!/usr/bin/env python3
import os
import ast
from mydotenv import load_env
load_env()

machine_name_prefix: str = os.getenv("MACHINE_NAME_PREFIX")
machine_name_list: list[str] = ast.literal_eval(os.getenv("MACHINE_NAME_LIST"))
proxy_starting_port: int = int(os.getenv("SSH_PROXY_STARTING_PORT"))
ssh_user: str = os.getenv("SSH_PROXY_USER")
ssh_host: str = os.getenv("SSH_PROXY_HOST")
ssh_key_path: str = os.getenv("SHARED_SSH_KEY_PATH")

ssh_config = f"""Host {machine_name_prefix}*
  User {ssh_user}
  HostName {ssh_host}
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  IdentityFile {ssh_key_path}
"""

for i, machine_name in enumerate(machine_name_list):
    ssh_config += f"""
Host {machine_name_prefix}-{machine_name}
    Port {proxy_starting_port + i}"""

print(ssh_config)
