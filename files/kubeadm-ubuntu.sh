#!/bin/bash

set -eu

K8S_VERSION=${K8S_VERSION:-1.10}

#####
# Disable swap
#####
swapoff -a
sed -e 's-^\(.*swap.*\)-#\1-' -i /etc/fstab||true
swapon -s

#####
# Setup docker
#####
apt-get update
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common

cat > /etc/docker/daemon.json <<EOF
{
  "insecure-registries": ["registry.bee42:5000","registry.bee42:80"],
  "registry-mirrors": [ "http://registry.bee42:5001" ]
}
EOF

systemctl daemon-reload
systemctl restart docker

#apt-get install python-pip joe -y
#sudo -H pip install --upgrade pip

#####
#Setup Kubernetes
#####
tee /etc/apt/preferences.d/k8s <<EOF
Package: kubeadm
Pin: version $K8S_VERSION*
Pin-Priority: 1000

Package: kubelet
Pin: version $K8S_VERSION*
Pin-Priority: 1000

Package: kubectl
Pin: version $K8S_VERSION*
Pin-Priority: 1000
EOF

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update && apt-get install kubeadm kubelet kubectl kubernetes-cni -y 

systemctl enable docker kubelet

sed -i -e 's/AUTHZ_ARGS=.*/AUTHZ_ARGS="/' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

systemctl daemon-reload

case "${1}" in
        master)
            ADDRESS="$(ip -4 addr show eth0 | grep "inet" | head -1 |awk '{print $2}' | cut -d/ -f1)"

            echo Executing kubeadm init 
            kubeadm init --apiserver-advertise-address=${ADDRESS} --kubernetes-version "stable-$K8S_VERSION"

            echo copy token
            kubeadm token create --print-join-command > /tmp/kubeadm_join
            
            echo copy kube-config...
            mkdir -p ~/.kube/
            cp /etc/kubernetes/admin.conf ~/.kube/config

            echo Deploying Network Layer

            #  Network-Layer
            kubectl apply -f \
            "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
            ;;

        node)
            bash /tmp/kubeadm_join
            ;;
esac
