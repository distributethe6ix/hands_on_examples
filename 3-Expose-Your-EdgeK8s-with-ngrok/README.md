# Expose your Kubernetes Edge with ngrok tunnelling!
In this brief tutorial, we'll use KinD and ngrok to expose the Yelb app.

## Prerequisites
- Linux, I chose Ubuntu 22.04 (as it's already deployed on my Edge NUC node)
- Docker which you can get at this URL https://docs.docker.com/get-docker/
- KinD, which runs K8s in Docker, and you can get that here https://kind.sigs.k8s.io/docs/user/quick-start/#installation
- kubectl, download and install it here https://kubernetes.io/docs/tasks/tools/install-kubectl/
- ngrok, which you can download from here https://ngrok.com/download

**Note** 
- You can also run ngrok on Windows and MacOS, more details here: https://ngrok.com/docs/getting-started/.
- You will also need your authtoken, after you've created your account.

## Deploying ngrok
1. Make sure you sign up for an account here: https://dashboard.ngrok.com/signup
2. You'll have instructions to download ngrok for your host OS
3. Deploy your authtoken 
```
ngrok config add-authtoken TOKEN
```
Which results in the following message:
```
Authtoken saved to configuration file: /home/....
```

## Deploying a KinD cluster
With KinD install, all you need to run is:
```
kind create cluster --name edgengrok01
```

And your cluster should now be online:
```
marino@mwlinux02:~$ kind create cluster -n edgengrok01
Creating cluster "edgengrok01" ...
 ✓ Ensuring node image (kindest/node:v1.25.3) 🖼 
 ✓ Preparing nodes 📦  
 ✓ Writing configuration 📜 
 ✓ Starting control-plane 🕹️ 
 ✓ Installing CNI 🔌 
 ✓ Installing StorageClass 💾 
Set kubectl context to "kind-edgengrok01"
You can now use your cluster with:

kubectl cluster-info --context kind-edgengrok01

Have a nice day! 👋
```

## Deploy a sample app
We're going to deploy the Yelb app, a simple voting app to test our functionality.

**Note** We are using the NodePort service which uses the nodes physical IP, and mapping that to an ngrok tunnel
Let's deploy the app:
```
kubectl create ns yelb
kubectl apply -f https://raw.githubusercontent.com/lamw/vmware-k8s-app-demo/master/yelb.yaml
```
We can verify successful deployment:
```
marino@mwlinux02:~$ kubectl get pods -n yelb
NAME                              READY   STATUS    RESTARTS   AGE
redis-server-6bd7885d5d-qsfhw     1/1     Running   0          20s
yelb-appserver-5d89946ffd-97ckk   1/1     Running   0          20s
yelb-db-697bd9f9d9-w42dw          1/1     Running   0          20s
yelb-ui-7d889cdcf4-dgsp4          1/1     Running   0          20s
```
Let's also capture the `NodePort` port
```
marino@mwlinux02:~$ kubectl get svc -n yelb
NAME             TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
redis-server     ClusterIP   10.96.44.157   <none>        6379/TCP       48s
yelb-appserver   ClusterIP   10.96.79.24    <none>        4567/TCP       48s
yelb-db          ClusterIP   10.96.71.47    <none>        5432/TCP       48s
yelb-ui          NodePort    10.96.51.141   <none>        80:30001/TCP   48s
```

Let's also get the node's IP:
```
kubectl get nodes -o wide
```

```
marino@mwlinux02:~$ kubectl get nodes -o wide
NAME                        STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
edgengrok01-control-plane   Ready    control-plane   4h    v1.25.3   172.18.0.2    <none>        Ubuntu 22.04.1 LTS   5.15.0-56-generic   containerd://1.6.9
```
Our IP is found! Let's expose!

## Expose sample app with ngrok
We need to take port 30001 (which might be different in your system) and pair that with 172.18.0.2 and then run the following command on that Linux machine:
```
ngrok http 172.18.0.2:30001
```
Which results in the following output. **Note** Removed my example for security

```
ngrok                                                                             (Ctrl+C to quit)
                                                                                                  
Add OAuth and webhook security to your ngrok (its free!): https://ngrok.com/free                  
                                                                                                  
Session Status                online                                                              
Account                       marino.wijay@gmail.com (Plan: Enterprise)                           
Version                       3.2.1                                                               
Region                        United States (us)                                                  
Latency                       -                                                                   
Web Interface                 http://127.0.0.1:4040                                               
Forwarding                    https://YOURINSTANCE.ngrok.app -> http://172.18.0.2:30001           
                                                                                                  
Connections                   ttl     opn     rt1     rt5     p50     p90                         
                              0       0       0.00    0.00    0.00    0.00
```

Now, if you go to the URL provided that forwards to your address, your app will be available publicly!!!

You can also use curl to see the result:
```
curl https://YOURINSTANCE.ngrok.app/
<!doctype html>
<html>
<head>
    <script src="env.js"></script>
    <meta charset="utf-8">
    <title>Yelb</title>
    <base href="/">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="icon" type="image/x-icon" href="favicon.ico?v=2">
</head>
<body>
<yelb>Loading...</yelb>
<script type="text/javascript" src="inline.bundle.js"></script><script type="text/javascript" src="styles.bundle.js"></script><script type="text/javascript" src="scripts.bundle.js"></script><script type="text/javascript" src="vendor.bundle.js"></script><script type="text/javascript" src="main.bundle.js"></script></body>
</html>
```

## Conclusion
ngrok is a powerful tunneling utility to expose local services, or even services that exist at the edge. Try it out!
