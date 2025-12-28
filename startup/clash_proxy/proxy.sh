#!/bin/bash
# WSL Clash Proxy Setup - Simple Version
HOST_IP=$(grep nameserver /etc/resolv.conf | awk '{print $2}')
export HTTP_PROXY="http://$HOST_IP:7890"
export HTTPS_PROXY="http://$HOST_IP:7890"
export http_proxy="http://$HOST_IP:7890" 
export https_proxy="http://$HOST_IP:7890"
echo "Proxy set to: $HOST_IP:7890"
