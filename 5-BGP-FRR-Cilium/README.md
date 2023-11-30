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
- jq

## Instructions

1. First clone the repo to the environment where you'll provision a KinD cluster.

1. Next, let's proceed to create 3 Docker networks.
    ```bash
    docker network create \
      --driver bridge \
      --subnet "172.24.0.0/16" \
      --gateway "172.24.0.1" \
      --ip-range "172.24.0.0/16" \
      -o "com.docker.network.bridge.enable_ip_masquerade=true" \
      --attachable \
      "bgp1"
    ```
    ```bash
    docker network create \
        --driver bridge \
        --subnet "172.25.0.0/16" \
        --gateway "172.25.0.1" \
        --ip-range "172.25.0.0/16" \
        -o "com.docker.network.bridge.enable_ip_masquerade=true" \
        --attachable \
        "bgp2"
    ```
    ```bash
    docker network create \
        --driver bridge \
        --subnet "172.26.0.0/16" \
        --gateway "172.26.0.1" \
        --ip-range "172.26.0.0/16" \
        -o "com.docker.network.bridge.enable_ip_masquerade=true" \
        --attachable \
        "bgp3"
    ```

1. Let's set the experimental Docker network to `bgp3` where we'll will deploy our KinD cluster along with associated FRR router
    ```bash
    export KIND_EXPERIMENTAL_DOCKER_NETWORK=bgp3
    ```

1. Once all prerequisites are met, you can proceed to install your kind cluster. You can do this from file
    ```bash
    kind create cluster --config=kindbgp.yaml
    ```

1. Next, let's install cilium using helm
    ```bash
    helm repo add cilium https://helm.cilium.io/

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
    ```

1. Wait two minutes after the previous step. Let's verify Cilium is installed
    ```bash
    cilium status
    ```
    If all looks good, proceed to step 7.

1. Let's deploy two FRR routers and attach them to a couple of docker networks
    ```bash
    docker run -d --privileged --name tor_frr2 --network bgp2 frrouting/frr:latest
    ```
    ```bash
    docker run -d --privileged --name tor_frr1 --network bgp2 frrouting/frr:latest
    ```
    ```bash
    docker network connect bgp3 tor_frr2
    docker network connect bgp1 tor_frr1
    ```

1. You'll need to get the address of `tor_frr2` on the `bgp3` network. This will be used for the `router-id` in [frrbgp1.conf](frrbgp1.conf) and the `peerAddress` field in [ciliumpeerpolicy-gr.yaml](ciliumpeerpolicy-gr.yaml).

    For example:

    ```bash
    docker inspect tor_frr2 | jq .[].NetworkSettings.Networks.bgp3.IPAddress
    ```
    may return `"172.26.0.5"`. Accordingly, [ciliumpeerpolicy-gr.yaml](ciliumpeerpolicy-gr.yaml) is edited to allow `tor_frr2` to peer with the Cilium nodes:
    ```yaml
    apiVersion: cilium.io/v2alpha1
    kind: CiliumBGPPeeringPolicy
    metadata:
      name: bgp-peer-frr
    spec:
      nodeSelector:
        matchLabels:
          kubernetes.io/os: linux
      virtualRouters:
        - exportPodCIDR: true
          localASN: 65013
          neighbors:
            - peerASN: 65012
              peerAddress: 172.26.0.5/32
              gracefulRestart:
                enabled: true
                restartTimeSeconds: 120
          serviceSelector:
            matchLabels:
              app: nginx    
    ```

1. You'll also need the address of `tor_frr1` on the bgp2 network. This IP will be used as the `bgp router-id` in [frrbgp1.conf](frrbgp1.conf) and the `peerAddress` field in [ciliumpeerpolicy-multihop.yaml](ciliumpeerpolicy-multihop.yaml).

    For example:

    ```bash
    docker inspect tor_frr1 | jq .[].NetworkSettings.Networks.bgp2.IPAddress
    ```
    may return `"172.25.0.2"`. Accordingly, [ciliumpeerpolicy-multihop.yaml](ciliumpeerpolicy-multihop.yaml) is edited to allow `tor_frr1` to peer with the Cilium nodes:
    ```yaml
    apiVersion: cilium.io/v2alpha1
    kind: CiliumBGPPeeringPolicy
    metadata:
      name: bgp-peer-frr
    spec:
      nodeSelector:
        matchLabels:
          kubernetes.io/os: linux
      virtualRouters:
        - exportPodCIDR: true
          localASN: 65013
          neighbors:
            - peerASN: 65011
              peerAddress: 172.25.0.2/32
              eBGPMultihopTTL: 2
              gracefulRestart:
                enabled: true
                restartTimeSeconds: 120
          serviceSelector:
            matchLabels:
              app: nginx
    ```

1. You'll also need the address of `tor_frr2` on the bgp2 network. This IP will be used as the `neighbor` address in [frrbgp1.conf](frrbgp1.conf).

    For example:

    ```bash
    docker inspect tor_frr2 | jq .[].NetworkSettings.Networks.bgp2.IPAddress
    ```

    may return `"172.25.0.3"`. Accordingly, given the `router-id` of `172.25.0.2` discovered previously, [frrbgp1.conf](frrbgp1.conf) is modified as follows:

    ```
    hostname tor_frr1
    log stdout
    log syslog notifications
    frr defaults traditional
    !
    # Uncomment static route to forward traffic
    # to subnet bgp3 (unreachable from tor_frr1).
    # Allows cilium nodes to peer via second hop.
    #ip route 172.26.0.0/16 172.25.0.3 eth1
    #!
    router bgp 65011
    no bgp ebgp-requires-policy
    bgp router-id 172.25.0.2
    neighbor 172.25.0.3 remote-as 65012
    neighbor 172.25.0.3 update-source eth1
    neighbor 172.25.0.3 soft-reconfiguration inbound
    address-family ipv4 unicast
    exit-address-family
    !
    address-family ipv6 unicast
    exit-address-family
    !
    line vty
    ```

1. Run `kubectl get nodes -o wide` so we can establish the Node's IPs
    ```bash
    kubectl get nodes -o wide
    NAME                   STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE
    KERNEL-VERSION                        CONTAINER-RUNTIME
    bgpk8s-control-plane   Ready    control-plane   45h   v1.27.3   172.26.0.3    <none>        Debian GNU/Linux 11 (bullseye)   5.15.133.1-microsoft-standard-WSL2+   containerd://1.7.1
    bgpk8s-worker          Ready    <none>          45h   v1.27.3   172.26.0.2    <none>        Debian GNU/Linux 11 (bullseye)   5.15.133.1-microsoft-standard-WSL2+   containerd://1.7.1
    bgpk8s-worker2         Ready    <none>          45h   v1.27.3   172.26.0.4    <none>        Debian GNU/Linux 11 (bullseye)   5.15.133.1-microsoft-standard-WSL2+   containerd://1.7.1
    ```

1. Given the above pieces of information, update the `bgp router-id` and `neighbor` lines in [frrbgp1.conf](frrbgp1.conf) to configure peering with `tor_frr2`:

    ```
    hostname tor_frr1
    log stdout
    log syslog notifications
    frr defaults traditional
    !
    # Uncomment static route to forward traffic
    # to subnet bgp3 (unreachable from tor_frr1).
    # Allows cilium nodes to peer via second hop.
    ip route 172.26.0.0/16 172.25.0.3 eth1
    !
    router bgp 65011
    bgp router-id 172.25.0.2
    no bgp ebgp-requires-policy
    neighbor 172.25.0.3 remote-as 65012
    neighbor 172.25.0.3 update-source eth1
    neighbor 172.25.0.3 soft-reconfiguration inbound
    # Uncomment the lines below to multihop peer
    # to the cilium nodes.
    #neighbor 172.26.0.2 remote-as 65013
    #neighbor 172.26.0.2 ebgp-multihop
    #neighbor 172.26.0.2 graceful-restart
    #neighbor 172.26.0.3 remote-as 65013
    #neighbor 172.26.0.3 ebgp-multihop
    #neighbor 172.26.0.3 graceful-restart
    #neighbor 172.26.0.4 remote-as 65013
    #neighbor 172.26.0.4 ebgp-multihop
    #neighbor 172.26.0.4 graceful-restart
    !
    exit
    !
    line vty
    exit
    ```

1. Additionally, update the [frrbgp2.conf](frrbgp2.conf) file to configure peering with `tor_frr1`, `bgpk8s-control-plane`, `bgpk8s-worker` and `bgpk8s-worker2`:

    ```
    hostname tor_frr2
    log stdout
    log syslog notifications
    frr defaults traditional
    !
    router bgp 65012
    bgp router-id 172.26.0.5
    no bgp ebgp-requires-policy
    neighbor 172.25.0.2 remote-as 65011
    neighbor 172.25.0.2 update-source eth0
    neighbor 172.26.0.2 remote-as 65013
    neighbor 172.26.0.2 update-source eth1
    neighbor 172.26.0.2 graceful-restart
    neighbor 172.26.0.3 remote-as 65013
    neighbor 172.26.0.3 update-source eth1
    neighbor 172.26.0.3 graceful-restart
    neighbor 172.26.0.4 remote-as 65013
    neighbor 172.26.0.4 update-source eth1
    neighbor 172.26.0.4 graceful-restart
    !
    address-family ipv4 unicast
      network 172.26.0.0/24
      neighbor 172.25.0.2 soft-reconfiguration inbound
      neighbor 172.26.0.2 next-hop-self
      neighbor 172.26.0.2 soft-reconfiguration inbound
      neighbor 172.26.0.3 next-hop-self
      neighbor 172.26.0.3 soft-reconfiguration inbound
      neighbor 172.26.0.4 next-hop-self
      neighbor 172.26.0.4 soft-reconfiguration inbound
    exit-address-family
    exit
    !
    line vty
    exit
    ```

1. Copy the configuration to the routers.
    ```bash
    docker cp ./frrbgp1.conf tor_frr1:/etc/frr/frr.conf
    docker exec tor_frr1 chown frr:frr /etc/frr/frr.conf
    docker cp ./frrbgp2.conf tor_frr2:/etc/frr/frr.conf
    docker exec tor_frr2 chown frr:frr /etc/frr/frr.conf
    ```

1. Configure the `bgp daemon` to be enabled on each router.
    ```bash
    docker exec tor_frr1 sed -i -e 's:bgpd=no:bgpd=yes:' /etc/frr/daemons
    docker exec tor_frr2 sed -i -e 's:bgpd=no:bgpd=yes:' /etc/frr/daemons
    ```

1. Restart the routers:
    ```bash
    docker restart tor_frr1 tor_frr2
    ```

1. Next, let's annotate the nodes to tell them who they are with an `ASN` and `Router-ID` field. Ensure these match your node IPs.
    ```
    kubectl annotate node/bgpk8s-control-plane cilium.io/bgp-virtual-router.65013="local-port=179"
    kubectl annotate node/bgpk8s-worker2 cilium.io/bgp-virtual-router.65013="local-port=179"
    kubectl annotate node/bgpk8s-worker cilium.io/bgp-virtual-router.65013="local-port=179"
    ```

1. Let's now deploy a sample NGINX application with two replicas
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

1. Let's apply the CiliumLoadBalancerIPPool resource
    ``` 
    kubectl apply -f ciliumlbIPpool.yaml
    ``` 
1. Let's expose the application
    ```
    kubectl expose deployment/nginx --port=80 --type=LoadBalancer --labels app=nginx
    ```
1. Let's apply a `CiliumBGPPeeringPolicy` resource which defines neighbor peer relationships, to help us establish peering between the KinD Nodes and `tor_frr2`.
    ```
    kubectl apply -f ciliumpeerpolicy-gr.yaml
    ```
1. With the peering policy established, BGP should be functional. You can verify this from two ends.
    From Cilium:
    ```
    cilium bgp peers
    ```
    ```
    Node                   Local AS   Peer AS   Peer Address   Session State   Uptime     Family         Received   Advertised
    bgpk8s-control-plane   65013      65012     172.26.0.5     established     3h20m48s   ipv4/unicast   4          3
                                                                                          ipv6/unicast   0          1
    bgpk8s-worker          65013      65012     172.26.0.5     established     3h20m58s   ipv4/unicast   4          3
                                                                                          ipv6/unicast   0          1
    bgpk8s-worker2         65013      65012     172.26.0.5     established     3h20m58s   ipv4/unicast   4          3
                                                                                          ipv6/unicast   0          1 
    ```
1. Graceful restart is enabled through this configuration, and timers are set to 120 seconds. In the case of BGP graceful restart, if you restart the cilium agent, while the neighbors will go offline, the datapath is present and routes remain on the `tor_frr2` routing table.

    You can test this by running `kubectl -n kube-system rollout restart daemonset/cilium` and then hop over to `tor_frr2` (via the command `docker exec -it tor_frr2 vtysh`) and run a `show ip route` to see that all the routes are still present and not flushed.

    ```
    b269741f3ab0# show ip route
    Codes: K - kernel route, C - connected, S - static, R - RIP,
          O - OSPF, I - IS-IS, B - BGP, E - EIGRP, N - NHRP,
          T - Table, v - VNC, V - VNC-Direct, A - Babel, F - PBR,
          f - OpenFabric,
          > - selected route, * - FIB route, q - queued, r - rejected, b - backup
          t - trapped, o - offload failure

    K>* 0.0.0.0/0 [0/0] via 172.25.0.1, eth0, 03:27:12
    B>* 10.12.143.239/32 [20/0] via 172.26.0.2, eth1, weight 1, 03:27:01
      *                         via 172.26.0.3, eth1, weight 1, 03:27:01
      *                         via 172.26.0.4, eth1, weight 1, 03:27:01
    B>* 10.242.0.0/24 [20/0] via 172.26.0.3, eth1, weight 1, 03:27:01
    B>* 10.242.1.0/24 [20/0] via 172.26.0.2, eth1, weight 1, 03:27:11
    B>* 10.242.2.0/24 [20/0] via 172.26.0.4, eth1, weight 1, 03:27:11
    C>* 172.25.0.0/16 is directly connected, eth0, 03:27:12
    C>* 172.26.0.0/16 is directly connected, eth1, 03:27:12
    b269741f3ab0#
    ```

1. Let's remove the current cilium BGP peer policy and use another one which allows for multi-hop.

    ```
    kubectl delete -f ciliumpeerpolicy-gr.yaml
    ```
    ```
    kubectl apply -f ciliumpeerpolicy-multihop.yaml
    ```

1. Run `cilium bgp peers` and you will see neighbor status update but it will say `ACTIVE`. 
    This is because there is no direct path between the KinD nodes, and `tor_frr1`. 
    
    We need to add a static route on `tor_frr1` for traffic destined for the network `bgp3`, and configure peering with the cilium nodes.
     
    Typically, docker networks use a /16 subnet. Continuing the above example, modify [frrbgp1.conf](frrbgp1.conf) by uncommenting these lines, and ensuring that the addresses are correct:

    ```
    ...

    # Uncomment static route to forward traffic
    # to subnet bgp3 (unreachable from tor_frr1).
    # Allows cilium nodes to peer via second hop.
    #ip route 172.26.0.0/16 172.25.0.3 eth1
    #!

    ...

    # Uncomment the lines below to multihop peer
    # to the cilium nodes.
    #neighbor 172.26.0.2 remote-as 65013
    #neighbor 172.26.0.2 ebgp-multihop
    #neighbor 172.26.0.2 graceful-restart
    #neighbor 172.26.0.3 remote-as 65013
    #neighbor 172.26.0.3 ebgp-multihop
    #neighbor 172.26.0.3 graceful-restart
    #neighbor 172.26.0.4 remote-as 65013
    #neighbor 172.26.0.4 ebgp-multihop
    #neighbor 172.26.0.4 graceful-restart

    ...
    ```

    Finally, we need to add a static route to on each of the cilium nodes to route traffic destined for the `tor_frr2` `IPAddress` on network `bgp2` via the `tor_frr2` `IPAddress` on network `bgp3`.

    To fix this, let's apply some static routes on the KinD Nodes to get reach `tor_frr1` (via `tor_frr2`).

    Continuing the above example, we would execute the following commands:

    ```
    docker exec -it bgpk8s-control-plane ip route add 172.25.0.2/32 via 172.26.0.5
    docker exec -it bgpk8s-worker ip route add 172.25.0.2/32 via 172.26.0.5
    docker exec -it bgpk8s-worker2 ip route add 172.25.0.2/32 via 172.26.0.5
    ```

    If you hop over to the `vtysh` of `tor_frr1` and run `show ip route`, you will now see routes being learned from Cilium, but is two hops away.

1. While this is not a production setup, you can replicate these pieces elsewhere. You are now complete!


