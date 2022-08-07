# Wordpress up and running with Civo Kubernetes and MySQL
## Prerequisites
- Git to clone the repo and downlod the MySQL and Wordpress YAMLs.
- Access to Civo.com Cloud to be able to provision K8s clusters and set DNS records
- Civo CLI to download and merge kubeconfig and scale clusters as needed (we will download this)
- Kubectl to access the K8s cluster
- The deployment manifests for Wordpress and MySQL
- A domain name like `example.xyz`. I used Google Domains to purchase marinowijay.info
- Your domain pointing to custom Name Servers and this is the selected option. I used Civo's nameservers.

## Let's get deploying!

While you could use any Kubernetes cluster, even with KinD and Minikube, we are aiming to publicly expose this app and make it accessible using a web-browser and a host name.

### Clone the repo
1. Make a new directory `mkdir wordpress`
2. Change into the directory `cd wordpress`
3. Clone the repo `git clone https://github.com/distributethe6ix/k8s_examples`
4. Change into the k8s_examples directory `cd k8s_examples/1-k8s-wordpress-mysql/
5. Check that the two deployment files are present `ls -la`

### Install Kubectl
If you haven't installed `kubectl` yet, here's your chance.
1. Head here because your CPU type may dictate the commands you run: https://kubernetes.io/docs/tasks/tools/

### Provision the Cluster

1. Log into Civo.com and you will see the main dashboard. Click on `Kubernetes` on the left-hand panel.
2. At the top right, click `Create new cluter`
3. Provide the following details but leave other fields untouched
- Name
- Select the size Small or Medium
4. Click `Create cluster`
5. It will take approximately 2-3 minutes to provision
6. In the left panel, go to Settings --> Profile and click `Generate` or `Regenerate` to get an API key
7. Copy this to your clipboard, we will need it for the Civo CLI.

### Download and consume the Civo CLI
1. You are likely on a MAC so you can go ahead and open a terminal and run:
```
brew tap civo/tools
brew install civo
```
or
```
$curl -sL https://civo.com/get | sh
```
or visit https://github.com/civo/cli for your OS
2. In your terminal, run the following `
```
civo apikey add [YOUR_KEY_NAME] [API_KEY_FROM_ABOVE]
```
3. At this point, you are authenticated into Civo cloud via the CLI
4. Go ahead and run `civo kubernetes ls` with a similar output
```
+--------------------------------------+-----------+--------+-------+-------+--------+
| ID                                   | Name      | Region | Nodes | Pools | Status |
+--------------------------------------+-----------+--------+-------+-------+--------+
| 13371337-1337-1337-1337-133713371337 | mywpapp01 | NYC1   |     3 |     1 | ACTIVE |
+--------------------------------------+-----------+--------+-------+-------+--------+
```

5. Now that you see the name and status of your cluster you can download the kubeconfig and merge it with an existing one, so run the following command `
```
civo kubernetes config [NAME_OF_YOUR_CLUSTER] --save --merge
```

6. Next, you want to run this to see your cluster's context
```
kubectl config get-contexts
```

7. Set your context with `kubectl config use-context [YOUR_CLUSTER_NAME_CONTEXT] 
```
kubectl config use-context [YOUR_CLUSTER_NAME_CONTEXT]
```

8. Check your cluster with `kubectl get nodes -o wide`
```
NAME                                             STATUS   ROLES    AGE    VERSION         INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
k3s-mywpapp01-ce62-658ed6-node-pool-2921-c4tr8   Ready    <none>   171m   v1.22.11+k3s1   192.168.1.3   <none>        Ubuntu 20.04.4 LTS   5.4.0-121-generic   containerd://1.5.13-k3s1
k3s-mywpapp01-ce62-658ed6-node-pool-2921-257rj   Ready    <none>   172m   v1.22.11+k3s1   192.168.1.5   <none>        Ubuntu 20.04.4 LTS   5.4.0-121-generic   containerd://1.5.13-k3s1
k3s-mywpapp01-ce62-658ed6-node-pool-2921-cviov   Ready    <none>   172m   v1.22.11+k3s1   192.168.1.4   <none>        Ubuntu 20.04.4 LTS   5.4.0-121-generic   containerd://1.5.13-k3s1
```
9. If you see `Ready` in the `STATUS` column, the infrastructure is ready and you should be able to deploy Wordpress.

### Let's deploy our Wordpress App
1. Let's first create our secret with Kustomize. Make sure to change the field `-password=YOUR_PASSWORD` to your own. 
```
cat <<EOF >./kustomization.yaml
secretGenerator:
- name: mysql-pass
  literals:
  - password=YOUR_PASSWORD
resources:
  - mysql-deployment.yaml
  - wordpress-deployment.yaml
EOF
```
2. Deploy all the components and wait roughly 5-10 minutes because all the infrascture pieces are deploying (compute, networking, and storage) for both the MySQL Database and Wordpress app.
```
kubectl apply -k ./
```
3. If you've waited about 5-10 minutes, run
```
$kubectl get all
NAME                                   READY   STATUS    RESTARTS   AGE
pod/wordpress-mysql-766577bbcf-bkff8   1/1     Running   0          3h9m
pod/wordpress-66866d9f6c-f29wn         1/1     Running   0          3h9m

NAME                      TYPE           CLUSTER-IP    EXTERNAL-IP     PORT(S)        AGE
service/kubernetes        ClusterIP      10.43.0.1     <none>          443/TCP        3h18m
service/wordpress-mysql   ClusterIP      None          <none>          3306/TCP       3h9m
service/wordpress         LoadBalancer   10.43.9.250   1.2.3.4   80:32610/TCP   3h9m

NAME                              READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/wordpress-mysql   1/1     1            1           3h9m
deployment.apps/wordpress         1/1     1            1           3h9m

NAME                                         DESIRED   CURRENT   READY   AGE
replicaset.apps/wordpress-mysql-766577bbcf   1         1         1       3h9m
replicaset.apps/wordpress-66866d9f6c         1         1         1       3h9m
```
Followed by a command that tells us about the storage and volume bindings.
```
$kubectl get pvc
NAME             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
wp-pv-claim      Bound    pvc-608e09c3-ad4c-4e30-9b41-3387e86928d4   20Gi       RWO            civo-volume    3h10m
mysql-pv-claim   Bound    pvc-60875bf5-a643-48e1-8099-94ee250539a7   20Gi       RWO            civo-volume    3h10m
```
