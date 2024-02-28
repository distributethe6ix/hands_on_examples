# How does networking work within the container space?
## We are now stepping into the land of Containers! 
Containers are isolated processes that run on a single operating system. Much like virtualization, containers will consume CPU, Memory, and Disk space, but require significantly less to run, as they are dedicated to a single function or process. Any time a container is created a full operating system isn't required. A container runtime such as containerd and interactive management layer such as Docker, make it possible to manage containers and resources, locally on a singular host.

Someone decides they want to create a small application to ensure it runs almost anywhere, so they decide to create a container image with the necessary binaries, libraries and language definition. There are instructions to compile the code which allows the software inside the container to be executable and return values (as required).

Interestingly enough, containers are isolated through a concept called Networking Namespaces.

## Networking Namespaces
Networking namespaces are used for container isolation. You can spin up a process and wrap it in networking namespace which is simply an isolated network.

Since we've developed a ton of networking knowledge it's worthwhile understanding how to build a networking namespace and have processes isolated to further understand containers and the associated networking.


## Building Networking Namespaces
We're going to build a couple of networking namespaces to be able to have each namespace interact or communicate with each other. We will also need to run a few additional commands requiring a quick installation.

One thing we need to do is clean up our IPtables rules from the previous section.

```
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
```
Let's now proceed to install some net-tools.

```
apt install net-tools
```
```
ip netns add sleep && ip netns add webapp
```
Let's now output those namespaces in the terminal
```
ip netns
```
Next lets find out what interfaces list the interfaces on the host
```
ip link
```
And let's do the same for each network namespace we created.
```
ip netns exec sleep ip link
ip netns exec webapp ip link
```
You can even use arp on the host to see what MAC address and IP addresses show up (remember each MAC is associated to an IP), but you will discover that these endpoints in each namespace don't know about each other. These are isolated "broadcast" domains if you will.

```
arp
```
```
ip netns exec sleep arp
```
```
ip netns exec webapp arp
```

Now, in order for these two network namespaces to communicate with each other, we need to either create a virtual wire or virtual bridge. If you recall in the physical world, we need a LAN/ethernet cable to connect two devices directly to each other. But we have way more than 2 devices at any given time, on a network. So we need a switch or a virtual bridge, which creates a more multi-access topology. The two network namespaces we created are representative of two different endpoints in their own isolated domain. Let's bridge them together.

We can verify this by checking the routing table of each host, and the two namespaces. By running the two below, you won't see entries for any networks. We haven't assigned any addresses to the two namespaces.

```
route
```
```
ip netns exec sleep route
```
```
ip netns exec webapp route
```
So the best way to fix this is to use the Linux bridge functionality. Let's create one called app-net-0 and then see it present on the host.

```
ip link add app-net-0 type bridge
```


```
ip link
```
If you notice, the state is currently down so we need to turn it up/online.

```
ip link set dev app-net-0 up
```

Next, we need to attach virtual wires from each namespace to a port, which we'll attach to the bridge shortly. We also need to assign each virtual wire's endpoint an IP on the 192.168.52.0/24 network, and as well, an IP for the bridge on the very same subnet. This is like assigning an IP address to a process in its own namespace, or even, assigning an IP to a container. This allows for all three to communicate with addressing in the same broadcast domain and subnet.
```
ip link add veth-sleep type veth peer name veth-sleep-br
```
```
ip link add veth-webapp type veth peer name veth-webapp-br
```
```
ip link set veth-sleep netns sleep
ip link set veth-webapp netns webapp
```
```
ip link set veth-sleep-br master app-net-0
ip link set veth-webapp-br master app-net-0
```

```
ip -n sleep addr add 192.168.52.1/24 dev veth-sleep
```
```
ip -n sleep link set veth-sleep up
```
```
ip -n webapp addr add 192.168.52.2/24 dev veth-webapp
```
```
ip -n webapp link set veth-webapp up
```

Let's add the ip to the bridge we created earlier and attach the virtual wires of the namespaces to it.
```
ip addr add 192.168.52.5/24 dev app-net-0
```
```
ip link set dev veth-sleep-br up
ip link set dev veth-webapp-br up
```

If you ping the sleep namespace endpoint, it will go through as the host's app-net-0 interface/bridge can communicate with this namespace
`ping 192.168.52.1`

But, if you attempt to ping something external to the network (like the IP of solo.io), it will report as unreachable because no default route exists or we aren't using network address translation.

```
ip netns exec webapp ping 23.185.0.4
ip netns exec webapp route
```

Let's fix this using an iptables rule that allows us to NAT the 192.168.52.0 with an IP on the host that can communicate outbound.
```
iptables -t nat -A POSTROUTING -s 192.168.52.0/24 -j MASQUERADE
ip netns exec webapp ping 23.185.0.4
```

So it seems like we are still missing something, let's check the routing table. Where is our default route? Let's add it. And let's also tell the kernel to forward this network traffic as well.
```
ip netns exec webapp route
ip netns exec webapp ip route add default via 192.168.52.5
```
```
sysctl -w net.ipv4.ip_forward=1
ip netns exec webapp ping 23.185.0.4
```
Now, as you can see, you can ping solo.io's website through the webapp namespace!!!


## As a recap, here is what we've built:


Obviously, there is much more to what was just demonstrated here from a network namespace point of view.

It's strongly recommended to dig further into NAT functionality, port-forwarding and inbound access as well. These become important because of the way Kubernetes handles ingressing networking requests. This will be covered in the next module.

But what was illustrated is all the networking that would need to be configured just for two processes, or containers in their own network namespace boundary, to communicate. Now imagine 1000 containers :).

Docker has a specific way of implementing networking for containers. This is out of scope at this time but, there are plenty of resources to understand Docker Networking.

You could automate and simplify this process, but imagine having to create each network namespace and associated settings every time a new container is created, and then reverting this when the container is deleted. Container Networking Interfaces and Kubernetes answers this particular problem with automation, and desired state.

You have successfully completed this module! Please move onto the final module to dig into Kubernetes Networking.

Skip
Next


Source


Destination
