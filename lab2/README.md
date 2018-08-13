# RabbitMQ Cluster on OpenShift WorkShop

In this workshop we will deploy a multi-node RabbitMQ cluster into OpenShift/Kubernetes. We will then deploy a publisher and a consumer and watch messages being passed.

## Acknowledgements

The RabbitMQ deployment was borrowed heavily from:

* https://github.com/rabbitmq/rabbitmq-peer-discovery-k8s/tree/master/examples/k8s_statefulsets

The Producer and Consumer environments were heavily borrow from:

* https://github.com/danellecline/rabbitmqpika

## Requirements

* A working OpenShift 3.9 cluster
* Administrative access to the OpenShift cluster
* A non-administrative user on the OpenShift cluster
* Ability to push an image to the remote OpenShift image registry
* The URL/Name of your remote image repository
* A local docker environment

## RabbitMQ Cluster

Login to a OpenShift controller.

Clone this repository.

### Create a Namespace

As `system:admin`:

```
# kubectl create namespace test-rabbitmq
```

### RBAC

As `system:admin` deploy RBAC requirements.

```
# kubectl create -f rabbitmq-rbac.yml
serviceaccount "rabbitmq" created
role "endpoint-reader" created
rolebinding "endpoint-reader" created
```

### Create Cluster

As `system:admin` create the cluster, which is using stateful sets.

*Note this is use the `test-rabbitmq` namespace that was previously created.*

```
# kubectl create -f rabbitmq-statefulsets.yml
service "rabbitmq" created
configmap "rabbitmq-config" created
statefulset "rabbitmq" created
```

### Observe Cluster

It should take 5 or 6 minutes for the cluster to completely create.

We can observe the pods creating.

```
# kubectl get pods --namespace=test-rabbitmq
NAME         READY     STATUS              RESTARTS   AGE
rabbitmq-0   1/1       Running             0          2m
rabbitmq-1   1/1       Running             0          1m
rabbitmq-2   0/1       ContainerCreating   0          5s
```

And review the service.

```
# kubectl get svc --namespace=test-rabbitmq
NAME       TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)                          AGE
rabbitmq   NodePort   172.30.207.156   <none>        15672:31672/TCP,5672:30672/TCP   3m
```

Finally check the `cluster_status`.

```
# FIRST_POD=$(kubectl get pods --namespace test-rabbitmq -l 'app=rabbitmq' -o jsonpath='{.items[0].metadata.name }')
# kubectl exec --namespace=test-rabbitmq $FIRST_POD rabbitmqctl cluster_status
/usr/lib/rabbitmq/bin/rabbitmqctl: 52: cd: can't cd to /var/log/rabbitmq
Cluster status of node rabbit@10.129.0.3 ...
[{nodes,[{disc,['rabbit@10.129.0.3','rabbit@10.129.0.4',
                'rabbit@10.130.0.3']}]},
 {running_nodes,['rabbit@10.129.0.4','rabbit@10.130.0.3','rabbit@10.129.0.3']},
 {cluster_name,<<"rabbit@rabbitmq-0.rabbitmq.test-rabbitmq.svc.cluster.local">>},
 {partitions,[]},
 {alarms,[{'rabbit@10.129.0.4',[]},
          {'rabbit@10.130.0.3',[]},
          {'rabbit@10.129.0.3',[]}]}]

```

## Deploy Message Producers and Consumers

Now that we have a RabbitMQ cluster to query, let's build a deployment that does just that.

*NOTE: Probably the more difficult part of this workshop is not building the Docker images or deploying and using Rabbit, rather pushing the Docker images to the OpenShift internal repository.*

### Checkout This Repository

TBD

### Build Docker Images

Build an image with the tag rabbitmq/consumer.

```
cd rabbitmq/consumer
$ docker build -t rabbitmq/consumer .
```

Example:

```
$ docker build -t rabbitmq/consumer .
Sending build context to Docker daemon 5.632 kB
Step 1/2 : FROM python:2.7-onbuild
Trying to pull repository docker.io/library/python ...
2.7-onbuild: Pulling from docker.io/library/python
d660b1f15b9b: Pull complete
46dde23c37b3: Pull complete
6ebaeb074589: Pull complete
e7428f935583: Pull complete
0c3de61682aa: Pull complete
56f10ddf1173: Pull complete
4473537c621d: Pull complete
3106f7df3d1c: Pull complete
3de1c6ceef68: Pull complete
Digest: sha256:5af88e1d011bf7e845e83813712d9f91be1a39e2ede092008fc53e0a0ce1333b
Status: Downloaded newer image for docker.io/python:2.7-onbuild
# Executing 3 build triggers...
Step 1/1 : COPY requirements.txt /usr/src/app/
Step 1/1 : RUN pip install --no-cache-dir -r requirements.txt
 ---> Running in 6a88807b8d07

Collecting argparse==1.4.0 (from -r requirements.txt (line 1))
  Downloading https://files.pythonhosted.org/packages/f2/94/3af39d34be01a24a6e65433d19e107099374224905f1e0cc6bbe1fd22a2f/argparse-1.4.0-py2.py3-none-any.whl
Collecting pika==0.9.14 (from -r requirements.txt (line 2))
  Downloading https://files.pythonhosted.org/packages/2b/5b/4c5b6eafc63e0985b926267579a1e2534af70df0a45932f0c23fcc5f1b88/pika-0.9.14.tar.gz (72kB)
Requirement already satisfied: wsgiref==0.1.2 in /usr/local/lib/python2.7 (from -r requirements.txt (line 3)) (0.1.2)
Installing collected packages: argparse, pika
  Running setup.py install for pika: started
    Running setup.py install for pika: finished with status 'done'
Successfully installed argparse-1.4.0 pika-0.9.14
You are using pip version 10.0.1, however version 18.0 is available.
You should consider upgrading via the 'pip install --upgrade pip' command.
Step 1/1 : COPY . /usr/src/app
 ---> 6958753b2b65
Removing intermediate container f48cc71e4e2f
Removing intermediate container 6a88807b8d07
Removing intermediate container 8dd62e2ea28e
Step 2/2 : ENV PYTHONPATH /usr/src/app
 ---> Running in cdf61079a5cb
 ---> ddf9167e7c03
Removing intermediate container cdf61079a5cb
Successfully built ddf9167e7c03
```

Next we will build the producer image.

```
cd ../producer
$ docker build -t rabbitmq/producer .
```

Example.

```
$ docker build -t rabbitmq/producer .
Sending build context to Docker daemon 5.632 kB
Step 1/2 : FROM python:2.7-onbuild
# Executing 3 build triggers...
Step 1/1 : COPY requirements.txt /usr/src/app/
Step 1/1 : RUN pip install --no-cache-dir -r requirements.txt
 ---> Running in 15c8fcf7992d

Collecting pika==0.9.14 (from -r requirements.txt (line 1))
  Downloading https://files.pythonhosted.org/packages/2b/5b/4c5b6eafc63e0985b926267579a1e2534af70df0a45932f0c23fcc5f1b88/pika-0.9.14.tar.gz (72kB)
Requirement already satisfied: wsgiref==0.1.2 in /usr/local/lib/python2.7 (from -r requirements.txt (line 2)) (0.1.2)
Collecting argparse==1.4.0 (from -r requirements.txt (line 3))
  Downloading https://files.pythonhosted.org/packages/f2/94/3af39d34be01a24a6e65433d19e107099374224905f1e0cc6bbe1fd22a2f/argparse-1.4.0-py2.py3-none-any.whl
Installing collected packages: pika, argparse
  Running setup.py install for pika: started
    Running setup.py install for pika: finished with status 'done'
Successfully installed argparse-1.4.0 pika-0.9.14
You are using pip version 10.0.1, however version 18.0 is available.
You should consider upgrading via the 'pip install --upgrade pip' command.
Step 1/1 : COPY . /usr/src/app
 ---> bcbc49001086
Removing intermediate container fb61821bdd92
Removing intermediate container 15c8fcf7992d
Removing intermediate container dd3d38287ef8
Step 2/2 : ENV PYTHONPATH /usr/src/app
 ---> Running in 9b4caf6c0c64
 ---> ccc77c3f413b
Removing intermediate container 9b4caf6c0c64
Successfully built ccc77c3f413b
```

We should now have those images in our local repository.

```
$ docker images
REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE
rabbitmq/producer   latest              ccc77c3f413b        38 seconds ago      687 MB
rabbitmq/consumer   latest              ddf9167e7c03        2 minutes ago       687 MB
docker.io/python    2.7-onbuild         3f246dd60a17        3 weeks ago         685 MB
```

### Push Images to Remote Repository

Ensure your local docker can use the remote registry.

*NOTE: If your remote registry uses an "insecure" SSL certificate, then Docker will need to know about it.*

```
{
  "insecure-registries" : ["docker-registry-default.apps.example.com:443"]
}
```

#### Tag the Images

Tag them with the remote repository location.

```
docker tag rabbitmq/consumer docker-registry-default.apps.example.com:443/rabbitmq/consumer
docker tag rabbitmq/producer docker-registry-default.apps.example.com:443/rabbitmq/producer
```

Example listing of images.

```
$ docker images
REPOSITORY                                                       TAG                 IMAGE ID            CREATED             SIZE
docker-registry-default.apps.example.com:443/rabbitmq/producer   latest              ccc77c3f413b        13 minutes ago      687 MB
rabbitmq/producer                                                latest              ccc77c3f413b        13 minutes ago      687 MB
docker-registry-default.apps.example.com:443/rabbitmq/consumer   latest              ddf9167e7c03        15 minutes ago      687 MB
rabbitmq/consumer                                                latest              ddf9167e7c03        15 minutes ago      687 MB
docker.io/python                                                 2.7-onbuild         3f246dd60a17        3 weeks ago         685 MB
```

#### Push the images.

First, login to OpenShift and create a new project called `rabbitmq`.

*NOTE: The project name is used in the image tag, so if you change it make sure to also change it in the image tag.*

```
oc login
oc new-project rabbitmq
```

Example:

```
$ oc login
Authentication required for https://shift.example.com:443 (openshift)
Username: curtis
Password:
Login successful.

You don't have any projects. You can try to create a new project, by running

    oc new-project <projectname>

$ oc new-project rabbitmq
Now using project "rabbitmq" on server "https://shift.example.com:443".

You can add applications to this project with the 'new-app' command. For example, try:

    oc new-app centos/ruby-22-centos7~https://github.com/openshift/ruby-ex.git

to build a new example application in Ruby.
```

Login to Docker.

```
docker login -u $(oc whoami) -p $(oc whoami -t) docker-registry-default.apps.example.com:443
```

At this point we should be able to push the images and make them accessible to OpenShift.

```
docker push docker-registry-default.apps.example.com:443/rabbitmq/consumer
docker push docker-registry-default.apps.example.com:443/rabbitmq/producer
```

Example:

```
$ docker push docker-registry-default.apps.example.com:443/rabbitmq/consumer
The push refers to a repository [docker-registry-default.apps.example.com:443/rabbitmq/consumer]
13f09b5012ce: Pushed
7b918d3e6883: Pushed
1f10192172b7: Pushed
3e397f5b8357: Mounted from rabbitmq/rabbitmq-producer
e257add70b4b: Mounted from rabbitmq/rabbitmq-producer
ce7e990ce056: Mounted from rabbitmq/rabbitmq-producer
633d23790c1d: Mounted from rabbitmq/rabbitmq-producer
d071a18d9802: Mounted from rabbitmq/rabbitmq-producer
8451f9fe0016: Mounted from rabbitmq/rabbitmq-producer
858cd8541f7e: Mounted from rabbitmq/rabbitmq-producer
a42d312a03bb: Mounted from rabbitmq/rabbitmq-producer
dd1eb1fd7e08: Mounted from rabbitmq/rabbitmq-producer
latest: digest: sha256:58dde906e2552098202a00f17c1c4e224137caba64d36deb9f5e79d5b1b72e2f size: 2843
$ docker push docker-registry-default.apps.example.com:443/rabbitmq/producer
The push refers to a repository [docker-registry-default.apps.example.com:443/rabbitmq/producer]
1ea1b087529e: Pushed
175116dcc57a: Pushed
4f1c92ada2d8: Pushed
3e397f5b8357: Mounted from rabbitmq/consumer
e257add70b4b: Mounted from rabbitmq/consumer
ce7e990ce056: Mounted from rabbitmq/consumer
633d23790c1d: Mounted from rabbitmq/consumer
d071a18d9802: Mounted from rabbitmq/consumer
8451f9fe0016: Mounted from rabbitmq/consumer
858cd8541f7e: Mounted from rabbitmq/consumer
a42d312a03bb: Mounted from rabbitmq/consumer
dd1eb1fd7e08: Mounted from rabbitmq/consumer
latest: digest: sha256:84e5e8c1b3a584606e5ef6cc0234040529e70f18d0630936729271b0905e9d19 size: 2843
```

Validate the images have been pushed by using `oc` to list image streams.

```
$ oc get is
NAME       DOCKER REPO                                          TAGS      UPDATED
consumer   docker-registry.default.svc:5000/rabbitmq/consumer   latest    9 minutes ago
producer   docker-registry.default.svc:5000/rabbitmq/producer   latest    9 minutes ago
```

### Create the Deployments

First, create the consumer deployment.

```
$ kubectl create -f consumer.yaml
deployment.extensions/consumer created
```

Next, the producer deployment.

```
$ kubectl create -f producer.yaml
deployment.extensions/producer created
```


```
$ kubectl get pods
NAME                        READY     STATUS              RESTARTS   AGE
consumer-656cd8bff8-zd75g   1/1       Running             0          29s
producer-5fcc796887-nvbmn   0/1       ContainerCreating   0          2s
```

Once the producer is running it will send messages to the rabbitmq cluster and the consumer will pull the messages off of the queue and log them.

```
$ kubectl logs consumer-656cd8bff8-zd75g
INFO:pika.adapters.base_connection:Connecting to 172.30.207.156:5672
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
INFO:__main__:Message has been received Hello
```

The consumer will continue to run, however the producer will stop after 30 messages, and Kubernetes/OpenShift will restart the pod, and it will send another 30 messages.

```
$ kubectl get pods
NAME                        READY     STATUS    RESTARTS   AGE
consumer-656cd8bff8-zd75g   1/1       Running   0          2m
producer-5fcc796887-nvbmn   1/1       Running   1          1m
```

Above we can see the number of restarts.

We can also scale the producer.

```
$ kubectl scale --replicas=5 -f producer.yaml
deployment.extensions/producer scaled
$ kubectl get pods
NAME                        READY     STATUS              RESTARTS   AGE
consumer-656cd8bff8-zd75g   1/1       Running             0          3m
producer-5fcc796887-5bxtx   0/1       ContainerCreating   0          3s
producer-5fcc796887-b8d94   0/1       ContainerCreating   0          3s
producer-5fcc796887-g74zp   0/1       ContainerCreating   0          3s
producer-5fcc796887-nvbmn   1/1       Running             2          3m
producer-5fcc796887-v9xfz   0/1       ContainerCreating   0          3s
```

### Destroy the Deployments

```
kubectl destroy -f consumer.yaml
kubectl destroy -f producer.yaml
```
