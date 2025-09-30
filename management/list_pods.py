#!/usr/bin/env python3
import runpod
import os
from datetime import datetime

from mydotenv import load_env
load_env()

def _get_ports(runtime):
    if not isinstance(runtime, dict):
        return []
    ports = runtime.get('ports') or []
    return ports if isinstance(ports, list) else []

def _get_public_ip_and_ssh_port(pod):
    ports = _get_ports(pod.get('runtime'))
    public_tcp = [
        p for p in ports
        if isinstance(p, dict) and p.get('type') == 'tcp' and p.get('isIpPublic')
    ]
    if public_tcp:
        p = public_tcp[0]
        ip = p.get('ip') or 'N/A'
        port = str(p.get('publicPort') or 'N/A')
        return ip, port
    # Fallback: if top-level 'ports' string indicates 22/tcp, show port 22 without IP
    top_ports = pod.get('ports') or ''
    if isinstance(top_ports, str) and '22/tcp' in top_ports:
        return 'N/A', '22'
    return 'N/A', 'N/A'

def _format_status_and_time(last_status_change):
    if not isinstance(last_status_change, str):
        return 'N/A', 'N/A'
    if ': ' in last_status_change:
        status, rest = last_status_change.split(': ', 1)
        status_time = rest.split(' GMT')[0]
        return status, status_time
    return last_status_change, 'N/A'

def list_pods():
    # Get API key from environment
    api_key = os.getenv("RUNPOD_API_KEY")
    if not api_key:
        print("Error: RUNPOD_API_KEY environment variable not set")
        return
    runpod.api_key = api_key

    try:
        # Get all pods
        print("Fetching pods...")
        pods = runpod.get_pods()

        if not pods:
            print("No pods found")
            return

        # Sort pods by name safely
        try:
            pods = sorted(pods, key=lambda x: (x.get('name') or ''))
        except Exception:
            pass

        # Print header
        print("\n" + "="*120)
        print(f"{'IP':<16} {'SSH Port':<10} {'Cost/hr':<10} {'Last Status Change'} {'Name':<15} {'Status':<12} {'GPU':<8} ")
        print("="*120)

        # Print each pod's information
        for pod in pods:
            try:
                public_ip, ssh_port = _get_public_ip_and_ssh_port(pod)

                status, status_time = _format_status_and_time(pod.get('lastStatusChange'))

                cost_val = pod.get('costPerHr')
                cost = f"${cost_val}" if cost_val is not None else "$0.00"

                name = pod.get('name') or 'N/A'
                gpu = (pod.get('machine') or {}).get('gpuDisplayName') or 'N/A'

                print(f"{public_ip:<16} {ssh_port:<10} {cost:<10} {status_time} {name:<15} {status:<12} {gpu:<8}")
            except Exception as e:
                print(f"Warning: failed to render a pod entry: {e}")
                continue

        print("="*120 + "\n")

    except Exception as e:
        print(f"Error: {str(e)}")

if __name__ == "__main__":
    list_pods()