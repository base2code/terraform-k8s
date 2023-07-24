#!/bin/bash

# input IP addresses
input=$1

# convert comma-separated input to array
IFS=',' read -ra ADDR <<< "$input"

# create the yaml file
echo 'nodes:' > cluster.yml

# iterate over addresses and append to the file
for i in "${ADDR[@]}"; do
    yq e -i '.nodes += [{"address": "'"$i"'", "user": "rke", "role": ["controlplane", "etcd", "worker"]}]' cluster.yml
done

#cat >> cluster.yml <<EOF
#
#ingress:
#    provider: nginx
#    extra_args:
#      http-port: 8081
#      https-port: 8444
#EOF
