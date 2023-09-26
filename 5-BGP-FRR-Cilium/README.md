# Deploying BGP on Cilium with FRR
This folder provides configurations required to get FRR up and running with BGP along with Cilium. 
Our topology will look like this:

`nettools-container <--bgp1--> tor_frr1 <--bgp2--> tor_frr2 <--bgp3--> KinD w/ Cilium`

## Prerequsites
- kubectl
- helm
- cilium cli
- Docker
- kind
- FRR running in docker

## Instructions

1. First clone the repo to the environment where you'll provision a KinD cluster. You may need to update the `ciliumpeerpolicy-gr.yaml` to ensure it matches your Neighbors.
2. Next, let's proceed to create 3 Docker networks.
```
docker network create --driver bridge -o "com.docker.network.bridge.enable_ip_masquerade=true" --attachable "bgp1"
```
```
docker network create --driver bridge -o "com.docker.network.bridge.enable_ip_masquerade=true" --attachable "bgp2"
```
```
docker network create --driver bridge -o "com.docker.network.bridge.enable_ip_masquerade=true" --attachable "bgp3"
```

3. Let's set the experimental Docker network to `bgp3` where we'll will deploy our KinD cluster along with associated FRR router
```
export KIND_EXPERIMENTAL_DOCKER_NETWORK=bgp3
```
4. Once all prerequisites are met, you can proceed to install your kind cluster. You can do this from file
```
kind create cluster --config=kindbgp.yaml
```
5. Next, let's install cilium using helm
```
helm upgrade --install cilium cilium/cilium --namespace kube-system --version 1.14.2 --values - <<EOF
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
```
6. Wait two minutes after the previous step. Let's verify Cilium is installed
```
cilium status
```
If all looks good, proceed to step 7.

7. Let's deploy two FRR routers and attach them to a couple of docker networks
```
docker run -d --privileged --name tor_frr2 --network bgp2 frrouting/frr:latest
```
```
docker run -d --privileged --name tor_frr1 --network bgp2 frrouting/frr:latest
```
```
docker network connect bgp3 tor_frr2
docker network connect bgp1 tor_frr1
```
8. Next, run `kubectl get nodes -o wide` so we can establish the Node's IPs
```
root@hootbpg-3a50-83b010:~# kubectl get nodes -o wide
NAME                   STATUS   ROLES           AGE     VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION      CONTAINER-RUNTIME
bgpk8s-control-plane   Ready    control-plane   3h38m   v1.27.3   172.21.0.2    <none>        Debian GNU/Linux 11 (bullseye)   5.15.0-40-generic   containerd://1.7.1
bgpk8s-worker          Ready    <none>          3h38m   v1.27.3   172.21.0.3    <none>        Debian GNU/Linux 11 (bullseye)   5.15.0-40-generic   containerd://1.7.1
bgpk8s-worker2         Ready    <none>          3h38m   v1.27.3   172.21.0.4    <none>        Debian GNU/Linux 11 (bullseye)   5.15.0-40-generic   containerd://1.7.1
root@hootbpg-3a50-83b010:~# 
```


9. Update the neighbor fields of the `tor_frr2.conf` file to ensure your neighbor IPs match the IPs in the output above.

10. We now need to turn on the `bgp daemon` in each router. You can access bash by running the following:
```
sudo docker exec -it tor_frr1 bash
```
Once in, you will need to edit the file located at `/etc/frr/daemons` and change `bgpd=no` to `bgpd=yes`. Run a reboot from the container, and startup the container again with `docker start torfrr_1`

Repeat the same for `tor_frr2`.

9. You can also load the configurations of FRR in two ways. Either by staying in bash and copying the contents of `frrbgp1.conf` to /etc/frr/frr.conf, and doing another reload, or you can use the Network Engineer approach by accessing the terminal through `sudo docker exec -it tor_frr1 vtysh`. 

In this state, you are now logged into the router application itself and can directly configure it using the `config` global command and pasting the context of `frrbgp1.conf`. Please ensure you run `copy run start` in `exec` mode after pasting these commands.

Ensure you repeat the process for `tor_frr2`.

10. Next, let's annotate the nodes to tell them who they are with an `ASN` and `Router-ID` field. Ensure these match your node IPs.
```
kubectl annotate node/bgpk8s-control-plane cilium.io/bgp-virtual-router.65013="local-port=179"
kubectl annotate node/bgpk8s-worker2 cilium.io/bgp-virtual-router.65013="local-port=179"
kubectl annotate node/bgpk8s-worker cilium.io/bgp-virtual-router.65013="local-port=179"
```

11. Let's now deploy a sample NGINX application with two replicas
```
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 2
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
EOF
```

12. Let's apply the CiliumLoadBalancerIPPool resource
``` 
kubectl apply -f ciliumlbIPpool.yaml
``` 
13. Let's expose the application
```
kubectl expose deployment/nginx --port=80 --type=LoadBalancer --labels app=nginx
```
14. Let's apply a `CiliumBGPPeeringPolicy` resource which defines neighbor peer relationships, to help us establish peering between the KinD Nodes and `tor_frr2`.
```
kubectl apply -f ciliumpeerpolicy-gr.yaml
```
15. With the peering policy established, BGP should be functional. You can verify this from two ends.
From Cilium:
```
cilium bgp peers
```
```
Node                   Local AS   Peer AS   Peer Address   Session State   Uptime   Family         Received   Advertised
bgpk8s-control-plane   65013      65012     172.21.0.5     established     5s       ipv4/unicast   4          3    
                                                                                    ipv6/unicast   0          1    
bgpk8s-worker          65013      65012     172.21.0.5     established     6s       ipv4/unicast   4          3    
                                                                                    ipv6/unicast   0          1    
bgpk8s-worker2         65013      65012     172.21.0.5     established     2s       ipv4/unicast   4          3    
                                                                                    ipv6/unicast   0          1    
```
16. Graceful restart is enabled through this configuration, and timers are set to 120 seconds. In the case of BGP graceful restart, if you restart the cilium agent, while the neighbors will go offline, the datapath is present and routes remain on the `tor_frr2` routing table.

You can test this by running `kubectl -n kube-system rollout restart daemonset/cilium` and then hop over to `tor_frr2` and run a `show ip route` to see that all the routes are still present and not flushed.

17. Let's remove the current cilium BGP peer policy and use another one which allows for multi-hop.
```
```
kubectl delete -f ciliumpeerpolicy-gr.yaml
```
```
kubectl apply -f ciliumpeerpolicy-multihop.yaml
```

18. Run `cilium bgp peers` and you will see neighbor status update but it will say `ACTIVE`. 
This is because there is no direct path between the KinD nodes, and `tor_frr1`. 

To fix this, let's apply some static routes on the KinD Nodes:
```
docker exec -it bgpk8s-control-plane bash
ip route add 172.20.0.3/32 172.21.0.5
exit
```
```
docker exec -it bgpk8s-worker bash
ip route add 172.20.0.3/32 172.21.0.5
exit
```
docker exec -it bgpk8s-worker2 bash
ip route add 172.20.0.3/32 172.21.0.5
exit
```



If you hop over to the `vtysh` of `tor_frr1`, run the following

```
ip route add 172.21.0.0/24 via 172.20.0.3
```

And then run `show ip route`, you will now see routes being learned from Cilium, but is two hops away.

19. While this is not a production setup, you can replicate these pieces elsewhere. You are now complete!


