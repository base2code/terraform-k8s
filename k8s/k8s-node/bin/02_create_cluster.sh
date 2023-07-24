#!/bin/bash

hostname=$1

chown rke:rke /root/.ssh/id_rsa.pub
chown rke:rke /root/.ssh/id_rsa
chmod 600 /root/.ssh/id_rsa.pub
chmod 600 /root/.ssh/id_rsa

# Install kubeadm
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

kubectl version --client
if ! [ $? -eq 0 ]; then
  echo "kubectl installation failed"
  exit 1
fi

# Install rke

# Download latest release
filename=rke_linux-$(dpkg --print-architecture)
curl -s https://api.github.com/repos/rancher/rke/releases/latest \
| grep "$filename" \
| cut -d : -f 2,3 \
| tr -d \" \
| wget -qi -

mv "$filename" rke
chmod +x rke
mv rke /usr/local/bin/

rke --version
if ! [ $? -eq 0 ]; then
  echo "rke installation failed"
  exit 1
fi

rke up

export KUBECONFIG=$(pwd)/kube_config_cluster.yml
echo "export KUBECONFIG=$(pwd)/kube_config_cluster.yml" >> ~/.bashrc

# Install helm
apt-get install git -y
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install rancher (1)
KUBECONFIG=$(pwd)/kube_config_cluster.yml helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
KUBECONFIG=$(pwd)/kube_config_cluster.yml kubectl create namespace cattle-system

# Install Cert Manager
# If you have installed the CRDs manually instead of with the `--set installCRDs=true` option added to your Helm install command, you should upgrade your CRD resources before upgrading the Helm chart:
KUBECONFIG=$(pwd)/kube_config_cluster.yml kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.crds.yaml

# Add the Jetstack Helm repository
KUBECONFIG=$(pwd)/kube_config_cluster.yml helm repo add jetstack https://charts.jetstack.io

# Update your local Helm chart repository cache
KUBECONFIG=$(pwd)/kube_config_cluster.yml helm repo update

# Install the cert-manager Helm chart
KUBECONFIG=$(pwd)/kube_config_cluster.yml helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.11.0

# Install rancher (2)
# TODO: Set hostname and password
KUBECONFIG=$(pwd)/kube_config_cluster.yml helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set hostname="${hostname}" \
  --set bootstrapPassword=admin \
  --set ingress.tls.source=letsEncrypt \
  --set letsEncrypt.email=admin@base2code.dev \
  --set letsEncrypt.ingress.class=nginx
KUBECONFIG=$(pwd)/kube_config_cluster.yml kubectl -n cattle-system rollout status deploy/rancher
