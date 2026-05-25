#!/usr/bin/env python3
import os
import ast

def load_dotenv(env_path):
    """
    Enhanced dotenv file loader that handles key=value pairs and array variables.

    Args:
        env_path (str): Path to the .env file to load
    """
    if not os.path.exists(env_path):
        return

    with open(env_path) as f:
        current_array = None
        array_values = []

        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue

            # Handle array continuation
            if current_array and line.endswith(')'):
                value = line.strip().strip('"').strip("'").strip(')')
                if value:
                    array_values.append(value)
                os.environ[current_array] = str(array_values)
                current_array = None
                array_values = []
                continue

            if current_array:
                value = line.strip().strip('"').strip("'")
                if value:
                    array_values.append(value)
                continue

            # Check for array start
            if '=(' in line:
                key, _ = line.split('=(', 1)
                key = key.strip()
                current_array = key
                continue

            # Handle normal key=value pairs
            if '=' in line:
                key, value = line.split('=', 1)
                key = key.strip()

                # Remove inline comments
                if '#' in value:
                    value = value.split('#')[0]

                value = value.strip().strip("'").strip('"')

                # Try to detect and parse arrays on single line
                if value.startswith('[') and value.endswith(']'):
                    try:
                        parsed_value = ast.literal_eval(value)
                        os.environ[key] = str(parsed_value)
                    except:
                        os.environ[key] = value
                else:
                    os.environ[key] = value

def load_env():
    """
    Load environment variables from config.env file in parent directory.
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    config_path = os.path.join(script_dir, "..", "config.env")
    load_dotenv(config_path)
