#!/bin/bash
# Parameter:
# 1 - Master/node
# 2 - IP Master
# 3 - Kubernetes-version

set -eu

K8S_VERSION=$3
K8S_VERSION=${K8S_VERSION:-1.9.6}

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
            kubeadm init --apiserver-advertise-address=${ADDRESS} --kubernetes-version "$K8S_VERSION"

            echo copy token
            kubeadm token create --print-join-command > /tmp/kubeadm_join
            
            echo copy kube-config...
            mkdir -p ~/.kube/
            cp /etc/kubernetes/admin.conf ~/.kube/config

            echo Deploying Network Layer

            sleep 30
            #  Network-Layer
            kubectl apply -f \
            "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
            #curl https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml| sed "s/amd64/arm/g" | kubectl create -f -
            
            cat > helm-rbac.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tiller
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: tiller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: tiller
    namespace: kube-system
EOF
            kubectl apply -f helm-rbac.yaml
            #helm init --service-account tiller

            ;;

        node)
            bash /tmp/kubeadm_join
            ;;
esac
