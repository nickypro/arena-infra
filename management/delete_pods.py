#!/usr/bin/env python3
import runpod
import os
import sys
import time

from mydotenv import load_env
load_env()

def delete_stopped_pods(include_list, exclude_list):
    """
    Finds all stopped RunPod pods (excluding those in exclude_list)
    and prompts the user for confirmation before deleting them.
    """
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
            print("No pods found.")
            return

        # Filter for stopped pods
        stopped_pods = [
            pod for pod in pods if pod["desiredStatus"] == "EXITED"
        ]

        if not stopped_pods:
            print("No stopped pods found.")
            return

        # Filter out pods in the exclude list
        pods_to_delete = []
        excluded_count = 0
        print("\nFound stopped pods:")
        for pod in stopped_pods:
            if pod["name"] in exclude_list:
                print(f"- {pod['name']} (ID: {pod['id']}) - SKIPPING (in exclude list)")
                excluded_count += 1
                continue
            print(f"- {pod['name']} (ID: {pod['id']}) - Marked for deletion")
            pods_to_delete.append(pod)

        if not pods_to_delete:
            print("\nNo stopped pods to delete after applying exclude list.")
            return

        print(f"\nTotal stopped pods found: {len(stopped_pods)}")
        print(f"Pods excluded: {excluded_count}")
        print(f"Pods to be deleted: {len(pods_to_delete)}")

        # Confirm before deleting
        confirmation = input(
            f"\nAre you sure you want to delete these {len(pods_to_delete)} stopped pods? (y/N): "
        )
        if confirmation.lower() != "y":
            print("Operation cancelled.")
            return

        # Delete each pod
        print("\nDeleting pods...")
        deleted_count = 0
        error_count = 0
        for pod in pods_to_delete:
            try:
                print(f"Deleting {pod['name']} (ID: {pod['id']})...", end=" ")
                # Use terminate_pod to delete
                runpod.terminate_pod(pod["id"])
                print("✓")
                deleted_count += 1
                time.sleep(1)  # Small delay between deletions
            except Exception as e:
                print(f"\nError deleting pod {pod['name']} (ID: {pod['id']}): {str(e)}")
                error_count += 1

        print(f"\nDeletion process completed.")
        print(f"Successfully sent delete commands for {deleted_count} pods.")
        if error_count > 0:
            print(f"Encountered errors for {error_count} pods.")
        print("\nNote: Pods may take a few moments to be fully terminated.")

    except Exception as e:
        print(f"An error occurred: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description='Delete RunPod instances')
    parser.add_argument('--include', nargs='+', help='Include specific pods by name', default=[])
    parser.add_argument('--exclude', nargs='+', help='Exclude specific pods by name', default=[])
    args = parser.parse_args()

    delete_stopped_pods(args.include, args.exclude)

