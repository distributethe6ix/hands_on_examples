docker network create bgp1
docker network create bgp2
docker network create bgp3

[ $(uname -m) = arm64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-darwin-arm64
chmod +x ./kind
mv ./kind /some-dir-in-your-PATH/kind

helm upgrade --kube-context kind-cilium2 --install cilium cilium/cilium --namespace kube-system --version 1.14.0 --values - <<EOF
kubeProxyReplacement: strict
k8sServiceHost: cilium2-control-plane # use master node in kind network
k8sServicePort: 6443               # use api server port
hostServices:
  enabled: false
externalIPs:
  enabled: true
nodePort:
  enabled: true
hostPort:
  enabled: true
image:
  pullPolicy: IfNotPresent
ipam:
  mode: kubernetes
tunnel: disabled
ipv4NativeRoutingCIDR: 10.11.0.0/16
bgpControlPlane:
  enabled: true
autoDirectNodeRoutes: true
EOF
