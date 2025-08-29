# ARENA 6.0 Infrastructure

[![ARENA Logo](https://raw.githubusercontent.com/nickypro/arena-infra/refs/heads/main/management/arena-infrastructure-image.png)](https://arena.education/)

This is the repository for running the the infrastructure for the [ARENA program](https://arena.education/). These scripts are used to set up cloud machines with GPUS with all necessary dependencies pre-installed for the participants to use and connect to.

We use Runpod for the ARENA 6.0 infrastructure, as they are relatively affordable and have a good API for setting up machines, but if you want to do things manually or only have a few machines, you can use another service like Vast.ai or whetever else.

The runpod template is available here: [https://link.nicky.pro/runpod-arena-env](https://link.nicky.pro/runpod-arena-env), but the actual images are available on docker hub as [nickypro/arena-env](https://hub.docker.com/r/nickypro/arena-env).

The template is set to automatically clone the latest version of the ARENA 3.0 repository and install the dependencies with conda and cuda.

![Diagram comparing manual ssh config VS automatic ssh config](https://raw.githubusercontent.com/nickypro/arena-infra/refs/heads/main/management/arena-infra-diagram.png)

## Steps for Setting up the infrastructure.

### 1. **Clone the repo on your local machine.**
- You will need git and python installed on your local machine.
- Clone this github repo on your local machine:
```git clone https://github.com/nickypro/arena-infra.git```
- install [runpod python api library](https://pypi.org/project/runpod/) on your local machine:
```pip install runpod```

### 2. **Get the keys**
- get api key from [runpod](https://link.nicky.pro/runpod)
- create a shared ssh key (optionally replace `shared_infra_key_name` with something meaningful for your program):
```ssh-keygen -t ed25519 -N "" -C "shared_infra_key_name" -f ~/.ssh/shared_infra_key_name```

<details>
<summary>What do these do?</summary>

- `RUNPOD_API_KEY`: The api key for runpod. This is optional, and you can use a different service if you prefer, but our scripts are set up to use runpod. Look below for "manual" setup if you don't want to use runpod.

- `SHARED_SSH_KEY_PATH`: This is a special key that allows anyone with it to access the machines. You should generate a new key for each program, and give it to all the participants. This has two components:
    - The private key, which you should save in `~/.ssh/shared_infra_key_name`. This is the key that is used to access the machines.
    - The public key, saved at `~/.ssh/shared_infra_key_name.pub`. This is put on the pods, so that if the users have the private key, they can ssh into the machines.

</details>
<details>
<summary>Why is a single key shared between all participants? Can I make a more secure setup?</summary>

As we don't keep sensitive data on the machines, and we mostly trust our participants, the flexibility and ease of being able to move machines if there are issues and not needing cusomised workflows for assigning people to pairs outweighs the slightly less secure setup and potential ability for participants to "abuse" the setup.

It would be possible and more secure to have a different key for each participant, but this would increase the complexity of the setup and make it more difficult to manage. If this is usecase that you need, feel free to contact [Nicky](https://nicky.pro/), I can see what I can do for you.

</details>


### 3. **Add details to Config**
- open `config.env` and add the details for:
- `RUNPOD_API_KEY`, the api key for runpod. (it would be better to add this specific one to your `~/.zshrc` or `~/.bashrc` file instead of the config.env file so that you can save this config file to github without exposing your api key, but if you don't feel comfortable with that, you can leave it in the config.env file.)
- `SHARED_SSH_KEY_PATH`, the path to the ssh key you created in step 2.
- (optional) `MACHINE_NAME_PREFIX`, the prefix for the machine names for your program (e.g: `arena`).
- (optional) modify any settings like `RUNPOD_GPU_TYPE` and `RUNPOD_CLOUD_TYPE` as desired for different GPUs, or `RUNPOD_NUM_GPUS` to change the number of GPUs per machine.
- (optional) modify `ARENA_REPO_OWNER` to the owner of the arena repo you want to use. You can use the default values for this, but if you want to be easily able to sync and save changes, you can change these to your own github fork of this repo.
- (optional) if you are planning to use many machines (>50), you will need to add more name options to the `MACHINE_NAME_LIST` variable in the config.

### 4. **Run the setup script to set up the machines**
**i. Creating the machines**

- To create however many runpod pods as you need, run `./management/create_new_pods.py`. It will ask for confirmation before creating the machines, and will only create the difference if you have already created some machines already.
```python3 ./management/create_new_pods.py -n <total_number_of_pods>```

- You can also create a specific number of new machines by running:
```python3 ./management/create_new_pods.py --add <additional_number_of_pods>```


<details>
<summary>I don't want to use runpod, or I don't want to run a script to set up the machines. Can I do it manually?</summary>

Yes, you can do it manually.

- a. Set them up manually (if only a few machines):
    - Go to [runpod](https://link.nicky.pro/runpod) and click on "Create Instance".
    - Use our template [https://link.nicky.pro/runpod-arena-env](https://link.nicky.pro/runpod-arena-env), or create your own template by going My Templates > New Template, and create one called something like `arena-env` that uses the docker image [`nickypro/arena-env:5.5`](https://hub.docker.com/r/nickypro/arena-env), and increase the volume size to 100GB.
    - Create a pod with the template for each pair of participants.

- b. VAST.ai
    - Go to [VAST.ai](https://link.nicky.pro/vast) and create an instance.
    - Use the `nickypro/arena-env:5.5` image.
    - Create an instance with desired GPU and reccomended ~100GB of storage.
    - You can then ssh into the machine using command given by VAST.

</details>

**ii. Connecting to the machines**

Now we can try connecting to the machines to make sure they are working correctly.
- (manual option) run `python3 ./management/ssh_config_manual.py` to print out the ssh config for the machines you have created. (this should give `~/.ssh/config` for the machines you have created). Save this file to your local machine. You can automatically append it to your existing config with:
```python3 ./management/ssh_config_manual.py >> ~/.ssh/config```
- You can see all the machines you have created and their current status with `python3 ./management/list_pods.py`.
- test one of the machines by trying to ssh into them with `ssh arena-<machine_name>`.
- Test all of the machines by running `test_em.sh`:
```bash ~/management/test_em.sh```
- try that you can connect to the machine using `Remote-SSH: Connect to Host...` in VSCode.

<details>
<summary>How do I get the `~/.ssh/config` if I am not using runpod?</summary>

You will need to manually add the following to your `~/.ssh/config` file, formatted like this. You will need to:
- replace `arena-` with `$MACHINE_NAME_PREFIX-` if you changed it
- replace `shared_infra_key_name` with the name of the key you created in step 2

and for each machine you created:
- replace `<machine_name>` with the name of the machine you created
- replace `<machine_ip>` with the ip address of the machine you created
- replace `<port>` with the port of the machine you created

```
Host arena-*
    User root
    IdentityFile ~/.ssh/shared_infra_key_name
    UserKnownHostsFile=/dev/null
    StrictHostKeyChecking=no

Host arena-<machine_name>
    HostName <machine_ip>
    Port <port>
Host arena-<machine_name>
    HostName <machine_ip>
    Port <port>
```

</details>

### 5. **Share the machines with the participants**
- give the participants the ssh private key `cat ~/.ssh/shared_infra_key_name`, get them to save it in `~/.ssh/shared_infra_key_name`. (If they are on MacOS/Linux, they will additionally need run `chmod 600 ~/.ssh/shared_infra_key_name` to make sure the key is not world readable.)
- give the participants the ssh config file `cat ~/.ssh/config` from step 4. They should add the lines to their own `~/.ssh/config` file.

### 6. **(optional) Streamlining the ssh config**
- One issue is that if you ever want to turn off a machine, or you want to change out one of the machines, you need to manually update the ssh config by giving this to each participant. This is a pain.
- set up an ubuntu proxy machine with many ports available. I use [hetzner](https://link.nicky.pro/hetzner), but you can use whatever you want.
- Note: you should should **use a different ssh key** than the one that is shared with the participants. (you can use an existing key you have for yourself, or create a new one with `ssh-keygen -t ed25519 -N "" -C "proxy_key_name" -f ~/.ssh/proxy_key_name`, and use the public key `cat ~/.ssh/proxy_key_name.pub` for the proxy machine.)
- add this proxy machine to your ~/.ssh/config
```
Host myproxy
    User root
    HostName <hetzner_machine_ip>
    IdentityFile ~/.ssh/proxy_key_name
    UserKnownHostsFile=/dev/null
    StrictHostKeyChecking=no
```
- Update the config.env, `SSH_PROXY_HOST` should be the ip address or domain name of the proxy machine. (optionally update `SSH_PROXY_NGINX_CONFIG_PATH` and `SSH_PROXY_STARTING_PORT` if you want to run multiple instances of the proxy on the same machine.)
- clone this repo on the proxy machine:
```git clone https://github.com/nickypro/arena-infra.git && cd arena-infra```
- copy the config.env file to the proxy machine:
```scp config.env myproxy:~/arena-infra/config.env```
- setup nginx on the proxy machine: `sudo bash ./proxy/setup_nginx.sh`.
- on the proxy machine, run `python3 ./proxy/nginx_pods.py -v` to print out the nginx proxy config for the machines you have created, as well as a more readable table showing the status.
- This should give `~/proxy.conf` for the machines you have created. Add this to `~/proxy.conf` on the proxy machine. You can do this automatically with:
```python3 ./proxy/nginx_pods.py > ~/proxy.conf && systemctl restart nginx```

- Note if you are manually editing `proxy.conf`, you will also need to then restart nginx: `sudo systemctl restart nginx`. Note that if there is an error in your config (eg: missing semicolon), nginx will not start. `nginx_pods.py` should directly give a working config, but if things fail, the best way to debug this is to run `journalctl -fu nginx` to see the error.
- On your local machine again now, you can generate the new ssh config file with `python3 ./management/ssh_config_proxy.py`. Now whenever you want to restart or change one of the machines, you only need to update the proxy config file and restart nginx on the proxy machine, no need to update the ssh config for all the participants.

<details>
<summary>How do I get the `~/proxy.conf` if I am not using runpod?</summary>

You will need to manually add the following to your `~/proxy.conf` file, formatted like this, for each machine you created. You will need to:
- replace `<machine_name>` with the name of the machine you created
- replace `<machine_ip>` with the ip address of the machine you created
- replace `<machine_port>` with the port of the machine you created (generated randomly by runpod/vastai/etc...)
- replace `<proxy_port>` with the port of the proxy machine you created (should be consistent, eg: 12000, 12001, etc...)

```
upstream <machine_name> { server <machine_ip>:<machine_port>; }
server { listen <proxy_port>; proxy_pass <machine_name>; }

```

for example, if you created a machine called `apple`, you would add the following to your `~/proxy.conf` file:

```
upstream apple { server 1.2.3.4:2222; }
server { listen 12000; proxy_pass apple; }
```

</details>

### 7. **(optional) setting up easy git push to branches on the machines**:
- you can make it so that the users can push to a branch of the arena repo, by automatically deploying the branch to the machine when it is pushed to.
- To do this, you will need to have your own fork of the arena repo on your account, and to add the public key (`~/.ssh/shared_infra_key_name.pub`) as a deploy key on the repo.
- You will then need to change the `ARENA_REPO_OWNER` in the config.env file to your github username. Make sure to set it so that the `main` branch has read-only access.
- You can then copy the ssh key to the machines, and automatically set the repo to be your account's repo with the script `python3 ./management/setup_em.py`.
- You can also automatically push all changes, by running `python3 ./management/sync_git.sh`

### 8. **(optional) copying API keys (for evals week3) to the machines**
- If you are doing evals week3, you will need to copy the API keys to the machines.
- You will need to manually make an api key on OpenAI and Anthropic, and make two CSV files of the format, saved to `./keys/openai_api_keys.csv` and `./keys/anthropic_api_keys.csv`:
```
arena-<machine_name>,sk-...
arena-apple,sk-...
arena-autumn,sk-...
arena-bloom,sk-...
```
- You can then copy the keys to the machines with `python3 ./management/copy_api_keys.py`.

### 9. **Stopping/Killing the machines**
- If you want to retain the data, make sure to use the script from step 7.
- You can stop the machines with `./management/stop_pods.py`. Note that be default this will **delete all the data on machines**, so make sure you have saved all the data you need.
(it is potentially possible to save the data by using volumes, but I have found that often one is left with the volume is connected to a machine with no gpus available when you want to start it again, so in practice this is not useful)
- To stop the machines, you can run:
```
python3 ./management/stop_pods.py
```
It will ask for confirmation, and then it will stop the machines. You can use the `--include <machine_name>` flag to stop a specific machine, or `--exclude <machine_name>` to stop all the machines except for a specific one.

- To finally delete the machines, you can run:
```
python3 ./management/delete_pods.py
```
It will ask for confirmation, and then it will delete the machines.



---

## Other notes


- If you want to know the current status of the machines, you can run `python3 ./management/list_pods.py`.
- If you want to update the machines, you will need to update either the `~/.ssh/config` for all users (4.ii) if you choose to use the manual ssh config, or the `~/proxy.conf` (6.) if you choose to use the proxy.

## Documentation of all of the scripts

- `create_new_pods.py`: Creates new runpod pods.
  - command options:
  - `python3 ./management/create_new_pods.py --help`: Shows the help message.
  - `python3 ./management/create_new_pods.py -n <total_number_of_pods>`: Creates up to a specified number of pods. If there are already sum number of pods, it will only make the difference.
  - `python3 ./management/create_new_pods.py -a <additional_number_of_pods>`: Creates additional in addition to the existing number of pods.
  - `python3 ./management/create_new_pods.py <machine_name_1> <machine_name_2> ...`: Creates a pod with the specified machine names.
  - `python3 ./management/create_new_pods.py -a 1 --gpu-type "NVIDIA A40" --num-gpus 4 --cloud-type SECURE --docker-image nickypro/arena-env:5.5 --disk-space-in-gb 500`: Creates 1 pod with the specified gpu type, number of gpus per machine, cloud type, docker image, and disk space.

- `ssh_config_manual.py`: Prints out the ssh config for the machines you have created.
- `ssh_config_proxy.py`: Prints out the ssh config for the machines you have created using the proxy.
- `list_pods.py`: Lists all of your runpod pods and their current status.
- `test_em.sh`: Tests the machines by sshing into them and running a few commands.
- `setup_em.py`: Sets up the machines to use your github fork of the arena repo.
- `sync_git.sh`: Automatically pushes all changes to the machines.
- `copy_api_keys.py`: Copies the API keys to the machines.
- `stop_pods.py`: Stops the machines (if you want to retain the data, make sure to use sync_git.sh first).
- `delete_pods.py`: Deletes all stopped pods.


### scripts to run on the proxy machine.
- `setup_nginx.sh`: Sets up nginx on the proxy machine.
- `nginx_pods.py`: Prints out the nginx proxy config for the machines you have created.
  - This should be added to the `~/proxy.conf` file on the proxy machine.
- `update.sh`: Restarts nginx on the proxy machine.
- `journalctl -fu nginx`: Shows the nginx logs, useful for debugging issues with nginx.
