docker network create \
      --driver bridge \
      --subnet "172.24.0.0/16" \
      --gateway "172.24.0.1" \
      --ip-range "172.24.0.0/16" \
      -o "com.docker.network.bridge.enable_ip_masquerade=true" \
      --attachable \
      "bgp1"
docker network create \
      --driver bridge \
      --subnet "172.25.0.0/16" \
      --gateway "172.25.0.1" \
      --ip-range "172.25.0.0/16" \
      -o "com.docker.network.bridge.enable_ip_masquerade=true" \
      --attachable \      
      "bgp2"
docker network create \
      --driver bridge \
      --subnet "172.26.0.0/16" \
      --gateway "172.26.0.1" \
      --ip-range "172.26.0.0/16" \
      -o "com.docker.network.bridge.enable_ip_masquerade=true" \
      --attachable \      
      "bgp3"

[ $(uname -m) = arm64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-darwin-arm64
chmod +x ./kind
mv ./kind /some-dir-in-your-PATH/kind

helm upgrade --install cilium cilium/cilium --namespace kube-system --version 1.14.4 --values - <<EOF
kubeProxyReplacement: strict
k8sServiceHost: bgpk8s-control-plane # use master node in kind network
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
ipv4NativeRoutingCIDR: 10.12.0.0/16
bgpControlPlane:
  enabled: true
autoDirectNodeRoutes: true
EOF

#Node annotation:
kubectl annotate node/bgpk8s-control-plane cilium.io/bgp-virtual-router.65010="local-port=179"
kubectl annotate node/bgpk8s-worker cilium.io/bgp-virtual-router.65010="local-port=179"
kubectl annotate node/bgpk8s-worker2 cilium.io/bgp-virtual-router.65010="local-port=179"
