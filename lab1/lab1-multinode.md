# Deploy a Multinode OpenShift Origin System into an OpenStack Cloud

## Overview

For the purposes of this workshop, we will be deploying a multinode OpenShift Origin cluster, but it will not be setup to be highly available. We will only have one master node, one infra node, and one external router node. There will be two worker nodes.

It's quite possible to automate many of the commands that will be run here. For example, there are [several examples](https://github.com/redhat-openstack/openshift-on-openstack) of using OpenStack Heat to automate the deployment of OpenShift into an OpenStack cloud, but that is not the point of this workshop.

We will also be utilizing the RPM based OpenShift deployment instead of the containerized version.

## OpenShift Origin Version

At the time this workshop was created, OpenShift 3.7 had just been released and there were a few bugs in the deployment, so we stayed with 3.6 and will update in the near future.

## Requirements

You will need a bash shell available somewhere, as well as the OpenStack command line, and an environment properly configured to connect and use the OpenStack API.

### OpenStack Resources

* An OpenStack cloud and tenant with enough resources
* 3 floating IPs
* A CentOS 7 image available in OpenStack
* 1 openshift.util sized instance
* 4 openshift.node sized instances
* 1 openshift.master sized instance

### Flavors

You will need at least three flavors such as the below.

NOTE: Some flavors have ephemeral disks. They are required for Docker, as OpenShift will not deploy to a Docker instance that does not have a separate volume for Docker.

NOTE: The `openstack` command is abbreviated to `os`.

```
$ os flavor list -c Name -c RAM -c Disk -c Ephemeral -c VPUSs
+------------------+-------+------+-----------+
| Name             |   RAM | Disk | Ephemeral |
+------------------+-------+------+-----------+
| openshift.master | 16384 |   40 |        40 |
| openshift.node   |  8192 |   40 |        40 |
| openshift.util   |  1024 |   10 |         0 |
+------------------+-------+------+-----------+
```

Example of creating a flavor.

```
$ os flavor create --disk 10 --vcpus 1 --ram 2048 --public openshift.util
```

### DNS

DNS service is also quite important to deploying OpenShift Origin. In this workshop we will build our own simple DNS server to enable the deployment. In production a lot more thinking would need to go into the DNS infrastructure, as well as the overall architecture.

## Create an RC File

Sometimes it's easier to use a file that has all the variables needed defined, and we can just source that file on the command line to make the variables available.

File in each of these variables, then source the file into your shell environment.

```
alias os=openstack
export OPENSHIFT_SSH_KEY=
export OPENSHIFT_IMAGE_NAME=centos7
export OPENSHIFT_FLOATING_IP_NETWORK=
export OPENSHIFT_FLOATING_IP_1=
export OPENSHIFT_FLOATING_IP_2=
export OPENSHIFT_FLOATING_IP_3=
```

Source the file:

```
. ~/openshift-workshoprc
```

The rest of the workshop instructions require that the above variables are set in the bash session.

## Networking

Create a network in the OpenStack cloud.

NOTE: We are disabling port security on this network for convenience.

```
os network create \
--disable-port-security \
openshift-1
```

```
os subnet create \
--subnet-range 10.0.10.0/24 \
--dns-nameserver 8.8.8.8 \
--network openshift-1 \
openshift-1-subnet
```

Add a router.

```
os router create r-openshift-1
```

Add an external interface to the router.

```
os router set --external-gateway ${OPENSHIFT_FLOATING_IP_NETWORK} r-openshift-1
```

Add an interface to the router that is on the `openshift-1` network.

```
os router add subnet r-openshift-1 openshift-1
```

Create three floating IP addresses.

```
$ for i in 1 2 3; do
    os floating ip create ${OPENSHIFT_FLOATING_IP_NETWORK}
  done
```

We should now have three floating IPs availble.

NOTE: We are not showing the actual floating IPs as they are public.

```
$ os floating ip list -c "Floating IP Address" -c "Fixed IP Address"
+------------------------------+------------------+
| Floating IP Address          | Fixed IP Address |
+------------------------------+------------------+
| ${OPENSHIFT_FLOATING_IP_1}   | None             |
| ${OPENSHIFT_FLOATING_IP_2}   | None             |
| ${OPENSHIFT_FLOATING_IP_3}   | None             |
+------------------------------+------------------+
```

We are now done with the networking.

## Create and Configure the Utility Node

We need a "utility node" from which to run the Ansible deployment commands. Also we will use this node as a DNS server and as a "jump host" so as to be able to access the other nodes (if necessary)

NOTE: This util node needs at least 1GB of memory. With less than 1GB Ansible will actually run out of memory during the deployment.

Create the node:

```
os server create \
--key-name ${OPENSHIFT_SSH_KEY} \
--flavor openshift.util \
--nic net-id=openshift-1,v4-fixed-ip=10.0.10.10\
--image ${OPENSHIFT_IMAGE_NAME} \
openshift-1-util
```

Once it has become available, add a floating IP to it.

```
os server add floating ip openshift-1-util ${OPENSHIFT_FLOATING_IP_1}
```

Test that you can access the utility node.

```
ssh centos@${OPENSHIFT_FLOATING_IP_1} hostname
openshift-1-util.novalocal
```

### Configure Utility Node to be a DNS Server

ssh into the utility node and install dnsmasq.

```
$ ssh centos@${OPENSHIFT_FLOATING_IP_1}
[centos@openshift-1-util ~]$ sudo yum install dnsmasq bind-utils -y
```

Edit the `/etc/hosts` file to look like the below. dnsmasq will use this file.

NOTE: Make sure to replace the `OPENSHIFT_FLOATING_IP_3` variable with the correct floating IP.

```
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

10.0.10.10 openshift-1-util openshift-1-util.example.com
10.0.10.11 openshift-1-master openshift-1-master.example.com
10.0.10.12 openshift-1-node-1 openshift-1-node-1.example.com
10.0.10.13 openshift-1-node-2 openshift-1-node-2.example.com
10.0.10.14 openshift-1-infra-1 openshift-1-infra-1.example.com
10.0.10.15 openshift-1-router-1 openshift-1-router-1.example.com
${OPENSHIFT_FLOATING_IP_3} openshift-1 openshift-1.example.com
```


Edit `/etc/dnsmasq.conf` to be the below. These three lines are all that is in the file.

```
server=8.8.8.8
local=/example.com/
conf-dir=/etc/dnsmasq.d,.rpmnew,.rpmsave,.rpmorig
```

Enable and restart dnsmasq.

```
[centos@openshift-1-util ~]$ sudo systemctl enable dnsmasq
[centos@openshift-1-util ~]$ sudo systemctl restart dnsmasq
```

Validate that DNS is working.

```
[centos@openshift-1-util ~]$ dig @localhost +short openshift-1-router-1
10.0.10.15
```

Set the openshift-1 network to use the util server as a DNS server.

```
$ os subnet set --no-dns-nameservers openshift-1-subnet
$ os subnet set --dns-nameserver 10.0.10.10 openshift-1-subnet
```

### Install Ansible and OpenShift Ansible

Install Ansible.

```
[centos@openshift-1-util ~]$ sudo yum install ansible  git -y
```

Checkout openshift-ansible.

NOTE: You MUST checkout release-3.6 for this workshop.

```
[centos@openshift-1-util ~]$ git clone https://github.com/openshift/openshift-ansible
[centos@openshift-1-util ~]$ cd openshift-ansible
[centos@openshift-1-util ~]$ git checkout release-3.6
[centos@openshift-1-util openshift-ansible]$ git branch
  master
* release-3.6
```

Copy the hosts file to `/etc/ansible/hosts`.

```
[centos@openshift-1-util ~]$ cd openshift-origin-workshop
[centos@openshift-1-util openshift-origin-workshop]$ sudo cp hosts /etc/ansible/hosts
```

## Create OpenShift Instances

Ensure you are in the `openshift-origin-worship` directory and run the below commands so that the `user-data.txt` file is avaiable.

```
os server create ${OPENSHIFT_SSH_KEY} --user-data user-data.txt --flavor openshift.master --nic net-id=openshift-1,v4-fixed-ip=10.0.10.11 --image ${OPENSHIFT_IMAGE_NAME} openshift-1-master
os server create ${OPENSHIFT_SSH_KEY} --user-data user-data.txt --flavor openshift.node --nic net-id=openshift-1,v4-fixed-ip=10.0.10.12 --image ${OPENSHIFT_IMAGE_NAME} openshift-1-node-1
os server create ${OPENSHIFT_SSH_KEY} --user-data user-data.txt --flavor openshift.node --nic net-id=openshift-1,v4-fixed-ip=10.0.10.13 --image ${OPENSHIFT_IMAGE_NAME} openshift-1-node-2
os server create ${OPENSHIFT_SSH_KEY} --user-data user-data.txt --flavor openshift.node --nic net-id=openshift-1,v4-fixed-ip=10.0.10.14 --image ${OPENSHIFT_IMAGE_NAME} openshift-1-infra-1
os server create ${OPENSHIFT_SSH_KEY} --user-data user-data.txt --flavor openshift.node --nic net-id=openshift-1,v4-fixed-ip=10.0.10.15 --image ${OPENSHIFT_IMAGE_NAME} openshift-1-router-1
```

The `user-data.txt` file has a script that will prepare the instances, for example installing and configuring Docker. This will take a few minutes, and please note they will be rebooted once.

### Add Floating IP to Master and Router Nodes

Master:

```
$ os server add floating ip openshift-1-master ${OPENSHIFT_FLOATING_IP_3}
```

Router:

```
$ os server add floating ip openshift-1-router-1 ${OPENSHIFT_FLOATING_IP_2}
```

## Test Ansible Connectivity

While we are waiting for the instances to be completely ready, we can test connectivity from the utility server to the other nodes using Ansible.

```
[centos@openshift-1-util ~]$ cd openshift-origin-workshop/
[centos@openshift-1-util openshift-origin-workshop]$ ansible -m shell -a "hostname -f" all
openshift-1-infra-1.example.com | SUCCESS | rc=0 >>
openshift-1-infra-1.example.com

openshift-1-router-1.example.com | SUCCESS | rc=0 >>
openshift-1-router-1.example.com

openshift-1-master.example.com | SUCCESS | rc=0 >>
openshift-1-master.example.com

openshift-1-node-1.example.com | SUCCESS | rc=0 >>
openshift-1-node-1.example.com

openshift-1-node-2.example.com | SUCCESS | rc=0 >>
openshift-1-node-2.example.com
```

Above we can see that all the nodes have had their hostname properly set.

## Deploy OpenShift Origin

Now that we have built the instances and the infrastructure required, we can go ahead and actually deploy OpenShift.

First, establish a screen session.

```
[centos@openshift-1-util ~]$ sudo yum install screen -y
[centos@openshift-1-util ~]$ screen -R install
[centos@openshift-1-util ~]$ echo $STY
12352.install
```

And from that screen session, install OpenShift.

NOTE: This can take upwards of 30 minutes.

```
[centos@openshift-1-util ~]$ ansible-playbook ~/openshift-ansible/playbooks/byo/config.yml
SNIP!
PLAY RECAP *****************************************************************************************************************************************************************
localhost                  : ok=12   changed=0    unreachable=0    failed=0
openshift-1-infra-1.example.com : ok=231  changed=12   unreachable=0    failed=0
openshift-1-master.example.com : ok=617  changed=52   unreachable=0    failed=0
openshift-1-node-1.example.com : ok=231  changed=12   unreachable=0    failed=0
openshift-1-node-2.example.com : ok=243  changed=56   unreachable=0    failed=0
openshift-1-router-1.example.com : ok=231  changed=12   unreachable=0    failed=0
```

OpenShift Origin has now been deployed.

ssh into the master and validate the deployment.

```
[centos@openshift-1-util openshift-origin-workshop]$ ssh openshift-1-master
[centos@openshift-1-master ~]$ oc get nodes
NAME         STATUS                     AGE       VERSION
10.0.10.11   Ready,SchedulingDisabled   41m       v1.6.1+5115d708d7
10.0.10.12   Ready                      41m       v1.6.1+5115d708d7
10.0.10.13   Ready                      10m       v1.6.1+5115d708d7
10.0.10.14   Ready                      41m       v1.6.1+5115d708d7
10.0.10.15   Ready                      41m       v1.6.1+5115d708d7
```

## Add a User

Login to the `openshift-1-master` node and edit the `/etc/origin/master/htpasswd` file using the `htpasswd` utility.

```
[centos@openshift-1-master ~]$ sudo su
[root@openshift-1-master centos]# cd /etc/origin/master/
[root@openshift-1-master master]# htpasswd -c htpasswd admin
New password:
Re-type new password:
```

## Setup /etc/hosts

If you would like to access the `example.com` URLs from your workstation, configure `/etc/hosts`.

```
$ grep example.com /etc/hosts
${OPENSHIFT_FLOATING_IP_3} openshift-1-master.example.com
${OPENSHIFT_FLOATING_IP_3} openshift-1.example.com
```

## Login to the OpenShift Web interface

Access the below URL. Note that it will be the same as what `openshift_master_cluster_public_hostname` is set to in the Ansible hosts file.

https://openshift-1.example.com:8443

Login with the user and password you added to the httpasswd file above.

## Troubleshooting

* Check the `~/ansible.log` file on the utility node for Ansible errors
* Validate that Docker was properly configured in each of the non-util nodes
* Ensure that Ansible can access each of the virtual machines: run `ansible -m ping all` from the utility node

## OpenShift-Ansible Version

```
$ git show --oneline -s
3973489 Merge pull request #6265 from openshift-cherrypick-robot/cherry-pick-6188-to-release-3.6

```
