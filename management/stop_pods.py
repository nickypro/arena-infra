#!/usr/bin/env python3
import runpod
import os
import sys
import time

from mydotenv import load_env
load_env()

def stop_all_pods(include_list, exclude_list):
    # Get API key from environment
    api_key = os.getenv("RUNPOD_API_KEY")
    if not api_key:
        print("Error: RUNPOD_API_KEY environment variable not set")
        sys.exit(1)

    runpod.api_key = api_key

    try:
        # Get all pods
        print("Fetching all pods...")
        pods = runpod.get_pods()

        if not pods:
            print("No pods found")
            return

        # Count running pods
        running_pods = [pod for pod in pods if pod['desiredStatus'] == 'RUNNING']
        if not running_pods:
            print("No running pods found")
            return

        running_pods_new = []
        for pod in running_pods:
            if pod["name"] in exclude_list:
                continue
            running_pods_new.append(pod)
        running_pods = running_pods_new

        # Whitelist
        if len(include_list) > 0:
            running_pods_new = []
            for pod in running_pods:
                if pod["name"] in include_list:
                    running_pods_new.append(pod)
                continue
            running_pods = running_pods_new


        print(f"\nFound {len(running_pods)} running pods:")
        for pod in running_pods:
            print(f"- {pod['name']} (ID: {pod['id']})")

        # Confirm before stopping
        confirmation = input("\nAre you sure you want to stop all pods? (y/N): ")
        if confirmation.lower() != 'y':
            print("Operation cancelled")
            return

        # Stop each pod
        print("\nStopping pods...")
        for pod in running_pods:
            try:
                print(f"Stopping {pod['name']} (ID: {pod['id']})...", end=' ')
                runpod.stop_pod(pod['id'])
                print("✓")
                time.sleep(1)  # Small delay between stops to avoid rate limiting
            except Exception as e:
                print(f"\nError stopping pod {pod['name']}: {str(e)}")

        print("\nAll stop commands sent successfully")
        print("\nNote: Pods may take a few moments to fully stop")

    except Exception as e:
        print(f"Error: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description='Stop RunPod instances')
    parser.add_argument('--include', nargs='+', help='Include specific pods by name', default=[])
    parser.add_argument('--exclude', nargs='+', help='Exclude specific pods by name', default=[])
    args = parser.parse_args()

    stop_all_pods(args.include, args.exclude)
