#!/usr/bin/env bash
sudo apt update && sudo apt install nginx-full git vim -y

cp ./update.sh ~/
cp ./nginx.conf /etc/nginx/nginx.conf
mkdir /etc/nginx/streams-enabled
touch /etc/nginx/streams-enabled/proxy.conf
cd ~
ln -s /etc/nginx/streams-enabled/proxy.conf .

