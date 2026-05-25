#!/usr/bin/env python3
import runpod
import os
import sys
import time

from mydotenv import load_env
load_env()

def kill_pods(include_list, exclude_list, wait_timeout=300):
    """
    Stops all running pods and then deletes them.
    
    Args:
        include_list: List of pod names to include (if empty, includes all)
        exclude_list: List of pod names to exclude
        wait_timeout: Maximum time to wait for pods to stop (seconds)
    """
    # Get API key from environment
    api_key = os.getenv("RUNPOD_API_KEY")
    if not api_key:
        print("Error: RUNPOD_API_KEY environment variable not set")
        sys.exit(1)

    runpod.api_key = api_key

    try:
        # Step 1: Get all pods and filter running ones
        print("Fetching all pods...")
        pods = runpod.get_pods()

        if not pods:
            print("No pods found")
            return

        # Filter for running pods
        running_pods = [pod for pod in pods if pod['desiredStatus'] == 'RUNNING']
        
        if not running_pods:
            print("No running pods found")
            return

        # Apply exclude list
        filtered_pods = []
        for pod in running_pods:
            if pod["name"] in exclude_list:
                continue
            filtered_pods.append(pod)

        # Apply include list (whitelist)
        if len(include_list) > 0:
            pods_to_kill = []
            for pod in filtered_pods:
                if pod["name"] in include_list:
                    pods_to_kill.append(pod)
            filtered_pods = pods_to_kill

        running_pods = filtered_pods

        if not running_pods:
            print("No pods match the specified criteria")
            return

        print(f"\nFound {len(running_pods)} running pods to kill:")
        for pod in running_pods:
            print(f"- {pod['name']} (ID: {pod['id']})")

        # Confirm before proceeding
        confirmation = input(f"\nAre you sure you want to KILL (stop and delete) these {len(running_pods)} pods? (y/N): ")
        if confirmation.lower() != 'y':
            print("Operation cancelled")
            return

        # Step 2: Stop all running pods
        print("\n=== STOPPING PODS ===")
        pod_ids_to_delete = []
        
        for pod in running_pods:
            try:
                print(f"Stopping {pod['name']} (ID: {pod['id']})...", end=' ')
                runpod.stop_pod(pod['id'])
                pod_ids_to_delete.append(pod['id'])
                print("✓")
                time.sleep(1)  # Small delay between stops
            except Exception as e:
                print(f"\nError stopping pod {pod['name']}: {str(e)}")

        if not pod_ids_to_delete:
            print("No pods were successfully stopped")
            return

        print(f"\nSent stop commands for {len(pod_ids_to_delete)} pods")

        # Step 3: Wait for pods to stop
        print(f"\nWaiting for pods to stop (timeout: {wait_timeout}s)...")
        start_time = time.time()
        
        while time.time() - start_time < wait_timeout:
            print("Checking pod statuses...", end=' ')
            
            # Get current pod statuses
            current_pods = runpod.get_pods()
            stopped_pods = []
            still_running = []
            
            for pod_id in pod_ids_to_delete:
                pod_status = None
                for current_pod in current_pods:
                    if current_pod['id'] == pod_id:
                        pod_status = current_pod['desiredStatus']
                        break
                
                if pod_status == 'EXITED':
                    stopped_pods.append(pod_id)
                elif pod_status == 'RUNNING':
                    still_running.append(pod_id)
            
            print(f"{len(stopped_pods)} stopped, {len(still_running)} still running")
            
            if len(stopped_pods) == len(pod_ids_to_delete):
                print("All pods have stopped!")
                break
            
            if len(still_running) > 0:
                time.sleep(10)  # Wait 10 seconds before checking again
        else:
            print(f"\nTimeout reached. Some pods may still be stopping.")
            print("Proceeding to delete pods that have stopped...")

        # Step 4: Get final pod statuses and delete stopped ones
        print("\n=== DELETING STOPPED PODS ===")
        final_pods = runpod.get_pods()
        pods_to_delete = []
        
        for pod_id in pod_ids_to_delete:
            for pod in final_pods:
                if pod['id'] == pod_id and pod['desiredStatus'] == 'EXITED':
                    pods_to_delete.append(pod)
                    break

        if not pods_to_delete:
            print("No stopped pods ready for deletion")
            return

        print(f"Found {len(pods_to_delete)} stopped pods ready for deletion:")
        for pod in pods_to_delete:
            print(f"- {pod['name']} (ID: {pod['id']})")

        # Final confirmation for deletion
        delete_confirmation = input(f"\nProceed with deleting these {len(pods_to_delete)} stopped pods? (y/N): ")
        if delete_confirmation.lower() != 'y':
            print("Deletion cancelled")
            return

        # Delete the stopped pods
        deleted_count = 0
        error_count = 0
        
        for pod in pods_to_delete:
            try:
                print(f"Deleting {pod['name']} (ID: {pod['id']})...", end=' ')
                runpod.terminate_pod(pod['id'])
                print("✓")
                deleted_count += 1
                time.sleep(1)  # Small delay between deletions
            except Exception as e:
                print(f"\nError deleting pod {pod['name']}: {str(e)}")
                error_count += 1

        # Final summary
        print(f"\n=== OPERATION COMPLETE ===")
        print(f"Pods stopped and queued for deletion: {len(pod_ids_to_delete)}")
        print(f"Pods successfully deleted: {deleted_count}")
        if error_count > 0:
            print(f"Deletion errors: {error_count}")
        print("\nNote: Deletion may take a few moments to complete on RunPod's end")

    except Exception as e:
        print(f"Error: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='Kill (stop and delete) RunPod instances')
    parser.add_argument('--include', nargs='+', help='Include only specific pods by name', default=[])
    parser.add_argument('--exclude', nargs='+', help='Exclude specific pods by name', default=[])
    parser.add_argument('--timeout', type=int, default=300, help='Timeout in seconds to wait for pods to stop (default: 300)')
    args = parser.parse_args()

    kill_pods(args.include, args.exclude, args.timeout)
