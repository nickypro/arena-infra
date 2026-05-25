#!/usr/bin/env python3
import runpod
import os
from datetime import datetime

from mydotenv import load_env
load_env()

def generate_ssh_config(verbose=False):
    # Get API key from environment
    api_key = os.getenv("RUNPOD_API_KEY")
    if not api_key:
        print("# Error: RUNPOD_API_KEY environment variable not set")
        return
    runpod.api_key = api_key

    # Get SSH configuration from environment
    machine_name_prefix: str = os.getenv("MACHINE_NAME_PREFIX")
    ssh_user: str = os.getenv("SSH_USER")
    ssh_key_path: str = os.getenv("SHARED_SSH_KEY_PATH")

    try:
        # Get all pods
        if verbose:
            print("# Fetching pods...")
        pods = runpod.get_pods()

        if not pods:
            print("# No pods found")
            return

        # Sort pods by name
        pods = sorted(pods, key=lambda x: x['name'])

        # Generate SSH config header
        ssh_config = f"""Host {machine_name_prefix}*
    User {ssh_user}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    IdentityFile {ssh_key_path}
"""

        # Generate SSH config for each pod
        for pod in pods:
            try:
                # Get the public IP and port for SSH (type 'tcp')
                ssh_port = next((str(p['publicPort']) for p in pod['runtime']['ports']
                               if p['type'] == 'tcp' and p['isIpPublic']), None)
                public_ip = next((p['ip'] for p in pod['runtime']['ports']
                                if p['type'] == 'tcp' and p['isIpPublic']), None)

                if ssh_port and public_ip:
                    ssh_config += f"""
Host {pod['name']}
    HostName {public_ip}
    Port {ssh_port}"""

            except Exception as e:
                print(f"# Error processing pod {pod.get('name', 'unknown')}: {e}")

        print(ssh_config)

    except Exception as e:
        print(f"# Error: {str(e)}")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Generate SSH config for RunPod pods")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose output")
    args = parser.parse_args()
    generate_ssh_config(args.verbose)
