#!/usr/bin/env python3
import csv
import subprocess
import shlex
import os # For path joining
import concurrent.futures

from mydotenv import load_env
load_env()

# --- Configuration ---
# Gets script's directory and goes up one level to get the base directory 
# ie: [ /root/arena_infra/ ] /management/copy_api_keys.py -> [/root/arena_infra/]
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))# Gets script's directory
# BASE_DIR = "./"
OPENAI_CSV_PATH = os.path.join(BASE_DIR, "keys/openai_api_keys.csv")
ANTHROPIC_CSV_PATH = os.path.join(BASE_DIR, "keys/anthropic_api_keys.csv")
OPENROUTER_CSV_PATH = os.path.join(BASE_DIR, "keys/openrouter_api_keys.csv")

OPENAI_ENV_VAR = "OPENAI_API_KEY"
ANTHROPIC_ENV_VAR = "ANTHROPIC_API_KEY"
OPENROUTER_ENV_VAR = "OPENROUTER_API_KEY"
SHELL_RC_FILES = ["~/.bashrc", "~/.zshrc"]
# --- End Configuration ---

def read_api_keys(csv_filepath):
    """Reads hostname-API key pairs from a CSV file."""
    keys = {}
    try:
        with open(csv_filepath, "r", newline="") as f:
            reader = csv.reader(f)
            for i, row in enumerate(reader):
                if not row: continue
                if len(row) == 2 and row[0].strip() and row[1].strip():
                    keys[row[0].strip()] = row[1].strip()
                else:
                    print(
                        f"Warning: Skipping malformed row {i+1} in {csv_filepath}: {row}"
                    )
    except FileNotFoundError:
        print(f"Info: CSV file not found, skipping: {csv_filepath}")
    except Exception as e:
        print(f"Error reading {csv_filepath}: {e}")
    return keys

def add_key_to_remote(hostname, env_var_name, api_key, rc_file):
    """SSHs and appends an API key export to a remote shell rc file."""
    export_line = f'export {env_var_name}="{api_key}"'
    # Check if line already exists (optional, makes script idempotent but slower)
    # check_command = f"grep -qFx {shlex.quote(export_line)} {rc_file}"
    # add_command = f"( {check_command} || echo {shlex.quote(export_line)} >> {rc_file} )"
    # For simplicity as requested, always append:
    add_command = f"echo {shlex.quote(export_line)} >> {rc_file}"

    ssh_cmd = ["ssh", hostname, add_command]
    action = f"Add {env_var_name} to {rc_file}"
    try:
        # Using check=True will raise CalledProcessError on non-zero exit
        # Set a timeout to prevent hanging indefinitely
        result = subprocess.run(
            ssh_cmd,
            capture_output=True,
            text=True,
            check=False, # Handle error manually for better logging
            timeout=30
        )
        if result.returncode == 0:
            print(f"  SUCCESS: {action} on {hostname}")
            return True
        else:
            err_msg = result.stderr.strip() or result.stdout.strip() or "No output"
            print(f"  ERROR: {action} on {hostname}. Code: {result.returncode}. Msg: {err_msg}")
            return False
    except subprocess.TimeoutExpired:
        print(f"  ERROR: Timeout during {action} on {hostname}")
        return False
    except FileNotFoundError: # 'ssh' command not found
        print("FATAL ERROR: 'ssh' command not found. Is it installed and in your PATH?")
        exit(1) # Exit script if ssh is not found
    except Exception as e:
        print(f"  ERROR: Unexpected issue during {action} on {hostname}: {e}")
        return False

def main():
    print("--- Starting API Key Deployment Script ---")
    print(f"OpenAI keys from: {OPENAI_CSV_PATH}")
    print(f"Anthropic keys from: {ANTHROPIC_CSV_PATH}")
    print(f"Openrouter keys from: {OPENROUTER_CSV_PATH}")
    print("IMPORTANT: Assumes SSH key-based auth. Keys are appended.\n")

    openai_keys = read_api_keys(OPENAI_CSV_PATH)
    anthropic_keys = read_api_keys(ANTHROPIC_CSV_PATH)
    openrouter_keys = read_api_keys(OPENROUTER_CSV_PATH)

    all_hosts = sorted(list(set(openai_keys.keys()) | set(anthropic_keys.keys() | set(openrouter_keys.keys()))))

    if not all_hosts:
        print("No hosts found in any CSV files. Exiting.")
        return

    # Determine parallelism level
    # Environment variable to control concurrency
    max_workers_env = os.getenv("API_KEYS_MAX_PARALLEL")
    try:
        max_workers = int(max_workers_env) if max_workers_env else 50
    except ValueError:
        max_workers = 10

    print(f"Running in parallel with up to {max_workers} workers...")

    # Define per-host work
    def process_host(host):
        print(f"\nProcessing host: {host}")
        if host in openai_keys:
            for rc_file in SHELL_RC_FILES:
                add_key_to_remote(
                    host, OPENAI_ENV_VAR, openai_keys[host], rc_file
                )
        if host in anthropic_keys:
            for rc_file in SHELL_RC_FILES:
                add_key_to_remote(
                    host, ANTHROPIC_ENV_VAR, anthropic_keys[host], rc_file
                )
        if host in openrouter_keys:
            for rc_file in SHELL_RC_FILES:
                add_key_to_remote(
                    host, OPENROUTER_ENV_VAR, openrouter_keys[host], rc_file
                )
        print("-" * 20)

    # Execute in parallel and wait for completion
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [executor.submit(process_host, host) for host in all_hosts]
        for _ in concurrent.futures.as_completed(futures):
            pass

    print("\n--- Script Finished ---")

if __name__ == "__main__":
    main()

