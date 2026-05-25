#!/usr/bin/env python3
import json
import os
import sys
import ast
import urllib.request
import urllib.error
import urllib.parse
from datetime import datetime

from mydotenv import load_env
load_env()

def make_graphql_request(query, api_key):
    """Make a GraphQL request to RunPod API"""
    # URL encode the API key to handle special characters
    encoded_api_key = urllib.parse.quote(api_key, safe='')
    url = f"https://api.runpod.io/graphql?api_key={encoded_api_key}"

    data = json.dumps({"query": query}).encode('utf-8')
    headers = {
        'Content-Type': 'application/json',
        'Content-Length': str(len(data)),
        'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'application/json',
        'Accept-Language': 'en-US,en;q=0.9',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache'
    }

    request = urllib.request.Request(url, data=data, headers=headers, method='POST')

    try:
        with urllib.request.urlopen(request) as response:
            return json.loads(response.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8')
        if 'error code: 1010' in error_body:
            print("Cloudflare is blocking the request. This might be due to:")
            print("1. Invalid API key")
            print("2. API key needs to be URL encoded if it contains special characters")
            print("3. RunPod API might require specific headers or authentication method")
            print()
            print("Debug info:")
            print(f"URL: {url[:50]}...")  # Show partial URL for security
            print(f"API Key length: {len(api_key)}")
        print(f"HTTP Error {e.code}: {error_body}")
        raise
    except Exception as e:
        print(f"Error making request: {str(e)}")
        raise

def get_pods(api_key):
    """Get all pods from RunPod API"""
    query = """
    query Pods {
        myself {
            pods {
                id
                name
                costPerHr
                lastStatusChange
                gpuCount
                imageName
                machine {
                    gpuDisplayName
                }
                runtime {
                    ports {
                        ip
                        isIpPublic
                        publicPort
                        type
                    }
                }
            }
        }
    }
    """

    result = make_graphql_request(query, api_key)

    if 'errors' in result:
        print(f"GraphQL Errors: {result['errors']}")
        return []

    return result.get('data', {}).get('myself', {}).get('pods', [])

def list_pods(verbose=False):
    # Get API key from environment
    api_key = os.getenv("RUNPOD_API_KEY")
    if not api_key:
        print("# Error: RUNPOD_API_KEY environment variable not set")
        return

    try:
        # Get all pods
        if verbose:
            print("# Fetching pods...")
        pods = get_pods(api_key)

        if not pods:
            if verbose:
                print("# No pods found")
            return

        # Sort pods by name
        pods = sorted(pods, key=lambda x: x.get('name', ''))

        # Generate Nginx configuration first
        print("# Nginx Configuration")
        print("# -----------------")
        print()
        print("log_format ssh '$remote_addr [$time_local] $protocol $status $bytes_sent $bytes_received $session_time \"$upstream_addr\"';")
        print("access_log /var/log/nginx/ssh_access.log ssh;")
        print("error_log /var/log/nginx/ssh_error.log;")
        print()

        # NATO phonetic alphabet for pod names
        machine_name_prefix: str = os.getenv("MACHINE_NAME_PREFIX")
        machine_name_list: list[str] = ast.literal_eval(os.getenv("MACHINE_NAME_LIST"))
        proxy_starting_port: int = int(os.getenv("SSH_PROXY_STARTING_PORT"))
        # print(f"{machine_name_list=}", len(machine_name_list))
        # Map for storing found pods
        found_pods = {}

        # Find pods that match the NATO naming pattern
        for pod in pods:
            pod_name = pod.get('name', '')
            for i, machine_name in enumerate(machine_name_list):
                pod_name_to_check = f"{machine_name_prefix}-{machine_name}"
                if pod_name == pod_name_to_check:
                    try:
                        # Get runtime ports
                        runtime = pod.get('runtime', {})
                        ports = runtime.get('ports', [])

                        # Find SSH port and IP
                        ssh_port = None
                        public_ip = None

                        for port in ports:
                            if port.get('type') == 'tcp' and port.get('isIpPublic'):
                                ssh_port = str(port.get('publicPort'))
                                public_ip = port.get('ip')
                                break

                        if public_ip and ssh_port:
                            found_pods[machine_name] = {
                                "ip": public_ip,
                                "port": ssh_port,
                                "listen_port": proxy_starting_port + i  # 12000 + index for consistent port numbering
                            }
                    except Exception as e:
                        if verbose:
                            print(f"# Error processing pod {pod_name}: {e}")

        # Generate Nginx configuration for found pods
        for machine_name in sorted(found_pods.keys(), key=lambda x: machine_name_list.index(x)):
            data = found_pods[machine_name]
            print(f"upstream {machine_name} {{ server {data['ip']}:{data['port']}; }}")
            print(f"server {{ listen {data['listen_port']}; proxy_pass {machine_name}; }}")
            print()

        # Print table if verbose mode (after nginx config)
        if verbose:
            print("\n" + "="*140)
            print(f"{'IP':<16} {'SSH Port':<10} {'Cost/hr':<10} {'Last Status Change':<28} {'Name':<15} {'Status':<15} {'GPUs':<6} {'GPU Type':<20} {'Image':<30}")
            print("="*140)

            for pod in pods:
                try:
                    # Get SSH port and IP
                    runtime = pod.get('runtime', {})
                    ports = runtime.get('ports', [])

                    ssh_port = 'N/A'
                    public_ip = 'N/A'

                    for port in ports:
                        if port.get('type') == 'tcp' and port.get('isIpPublic'):
                            ssh_port = str(port.get('publicPort', 'N/A'))
                            public_ip = port.get('ip', 'N/A')
                            break

                    # Format the status time (remove year)
                    status_time = pod.get('lastStatusChange', '')
                    if ': ' in status_time:
                        # Extract date and time, remove year
                        date_time = status_time.split(': ')[1].split(' GMT')[0]
                        # Parse and reformat without year
                        if ' 2025 ' in date_time or ' 2024 ' in date_time:
                            parts = date_time.split()
                            if len(parts) >= 5:
                                # Remove year (index 3)
                                status_time = f"{parts[0]} {parts[1]} {parts[2]} {parts[4]}"
                            else:
                                status_time = date_time
                        else:
                            status_time = date_time

                    # Get the status
                    status = pod.get('lastStatusChange', '')
                    if ': ' in status:
                        status = status.split(': ')[0]

                    # Format cost
                    cost = f"${pod.get('costPerHr', 0)}"

                    # Get GPU count
                    gpu_count = pod.get('gpuCount', 0)
                    gpu_count_str = f"{gpu_count}x" if gpu_count > 0 else "0"

                    # Get GPU name
                    gpu_name = 'N/A'
                    if pod.get('machine'):
                        gpu_name = pod['machine'].get('gpuDisplayName', 'N/A')

                    # Get image name (truncate if too long)
                    image_name = pod.get('imageName', 'N/A')
                    if len(image_name) > 29:
                        image_name = image_name[:26] + "..."

                    print(f"{public_ip:<16} {ssh_port:<10} {cost:<10} {status_time:<28} {pod.get('name', 'N/A'):<15} {status:<15} {gpu_count_str:<6} {gpu_name:<20} {image_name:<30}")
                except Exception as e:
                    print(f"# Error processing pod: {e}")
                    print(pod)

            print("="*140 + "\n")

    except Exception as e:
        print(f"# Error: {str(e)}")

if __name__ == "__main__":
    # Check for -v flag
    verbose = '-v' in sys.argv
    list_pods(verbose=verbose)
