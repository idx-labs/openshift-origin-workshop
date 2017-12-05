# Deploy a Multinode OpenShift Origin System into an OpenStack Cloud

## Overview

For the purposes of this workshop, we will be deploying a multinode OpenShift Origin cluster (though it will not be setup to be highly available) using the [OpenShift-Ansible](https://github.com/openshift/openshift-ansible) project. In terms of OpenShift infrastructure, we will deploy one master node, one infra node, and one external router node. There will be two worker nodes.

We will also be utilizing the RPM based OpenShift deployment instead of the containerized version.

### A Note About Automation

It's quite possible to automate many of the commands that will be run here. For example, there are [heat templates](https://github.com/redhat-openstack/openshift-on-openstack) to automate the deployment of OpenShift into an OpenStack cloud, but that is not the point of this workshop, and instead we will be manually provisioning virtual machines and OpenStack networking components using the OpenStack command line tool. A bit of "chop wood and carry water."

## OpenShift Origin Version

At the time this workshop was created, OpenShift 3.7 had just been released and there were a few bugs in the deployment, so we stayed with 3.6 and will update in the near future.

## Requirements

You will need a bash shell available somewhere, as well as the OpenStack command line, and an environment properly configured to connect and use the OpenStack API of some provider, whether it's a public OpenStack cloud, or a private cloud.

### OpenStack Resources

* An OpenStack cloud and tenant with enough resources
* 3 floating IPs
* A CentOS 7 image available in OpenStack
* 1 openshift.util sized instance
* 3 openshift.node sized instances
* 1 openshift.router sized instance
* 1 openshift.master sized instance

NOTE: [OpenShift-Ansible](https://github.com/openshift/openshift-ansible/blob/master/roles/openshift_health_checker/openshift_checks/memory_availability.py) expects Masters to have at least 16GB of memory, and nodes/router/infra to have at least 8GB.

### Flavors

OpenShift requires that Docker be backed by a separate volume. This can be done with ephemeral disks or Cinder volumes.  Persistent Cinder volumes are probably the best option if they are available.

#### Ephemeral

You will need at least three flavors such as the below. The flavors used don't have to be *exactly* the same, but should be similar. These are example flavors.

NOTE: In this lab the `openstack` command is abbreviated and aliased to `os`.

```
$ os flavor list -c Name -c RAM -c Disk -c Ephemeral -c VPUSs
+------------------+-------+------+-----------+
| Name             |   RAM | Disk | Ephemeral |
+------------------+-------+------+-----------+
| openshift.master | 16384 |   40 |        40 |
| openshift.node   |  8192 |   40 |        40 |
| openshift.util   |  2048 |   20 |         0 |
+------------------+-------+------+-----------+
```

Example of creating a flavor.

```
$ os flavor create --disk 10 --vcpus 1 --ram 2048 --public openshift.util
```

#### Cinder-based

Flavors can be the same, but not have any ephemeral disk.  

```
$ os flavor list -c Name -c RAM -c Disk -c Ephemeral -c VPUSs
+------------------+-------+------+-----------+
| Name             |   RAM | Disk | Ephemeral |
+------------------+-------+------+-----------+
| openshift.master | 16384 |   40 |         0 |
| openshift.node   |  8192 |   40 |         0 |
| openshift.util   |  2048 |   20 |         0 |
+------------------+-------+------+-----------+
```

### DNS

DNS service is also quite important to deploying OpenShift Origin. In this workshop we will build our own simple DNS server to enable the deployment. In production a more consideration would need to go into the DNS infrastructure, as well as the overall architecture.

## Setup Local Workstation

### Checkout Workshop Git Repository

```
$ git clone https://github.com/idx-labs/openshift-workshop
$ cd openshift-workshop/lab1
```

### Create an RC File

Sometimes it's easier to use a file that has all the variables needed defined, and we can just source that file on the command line to make the variables available.

Fill in the variables in the `openshift-workshoprc` file.

Source the file:

```
$ cd openshift-workshop/lab1
$ cp openshift-workshoprc.example openshift-workshoprc
# edit openshift-workshoprc then source it
$ . openshift-workshoprc
```

The rest of the workshop instructions require that the above variables are set in the bash session.

## Build OpenStack Resources

### Ensure an SSH Keypair Exists

Make sure to have an ssh keypair setup in your OpenStack provider. This keypair name should also be in the `openshift-workshoprc` file.

```
$ os keypair list -c Name
+---------+
| Name    |
+---------+
| default |
+---------+
```

To create:

```
$ os keypair create --public-key ~/.ssh/id_rsa.pub default
```

### Networking

Create a network in the OpenStack cloud.

NOTE: We are disabling port security on this network for convenience.

```
$ os network create \
--disable-port-security \
openshift-1
```

```
$ os subnet create \
--subnet-range 10.0.10.0/24 \
--dns-nameserver 8.8.8.8 \
--network openshift-1 \
openshift-1-subnet
```

Add a router.

NOTE: The router we create here is a Neutron router, and is not the same as the OpenShift node we are calling a "router".

```
os router create r-openshift-1
```

Add an external interface to the router.

```
os router set --external-gateway ${OPENSHIFT_FLOATING_IP_NETWORK} r-openshift-1
```

Add an interface to the router that is on the `openshift-1` network.

```
os router add subnet r-openshift-1 openshift-1-subnet
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

### Update the openshift-workshoprc File

Now would be a good time to update and doublecheck the `openshift-workshoprc` file.

### Create and Configure the Utility Node

We need a "utility node" from which to run the Ansible deployment commands. Also we will use this node as a DNS server and as a "jump host" so as to be able to access the other nodes (if necessary)

NOTE: This util node needs at least 2GB of memory. With less than 2GB Ansible can actually run out of memory during the deployment.

Create the node:

```
$ os server create \
--key-name ${OPENSHIFT_SSH_KEY} \
--flavor ${OPENSHIFT_UTIL_FLAVOR} \
--nic net-id=openshift-1,v4-fixed-ip=10.0.10.10 \
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

#### Configure Utility Node to Not Check SSH Known Hosts

Setup the centos users ssh configuration file as per the below.

```
$ ssh centos@${OPENSHIFT_FLOATING_IP_1}
[centos@openshift-1-util ~]$ echo "UserKnownHostsFile=/dev/null" > /home/centos/.ssh/config
[centos@openshift-1-util ~]$ echo "StrictHostKeyChecking=no" >> /home/centos/.ssh/config
[centos@openshift-1-util ~]$ chmod 600 /home/centos/.ssh/config
```

#### Configure Utility Node to be a DNS Server

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

Reboot the util node (or reset its DHCP) to get the new DNS server.

```
[centos@openshift-1-util ~]$ sudo reboot
```

#### Install Ansible and OpenShift Ansible

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

Also checkout this workshop's repository.

```
[centos@openshift-1-util openshift-ansible]$ cd
[centos@openshift-1-util ~]$ git clone https://github.com/idx-labs/openshift-workshop
```

Copy the hosts file to `/etc/ansible/hosts` on the `openshift-1-util` node.

```
[centos@openshift-1-util ~]$ cd openshift-workshop/lab1
[centos@openshift-1-util openshift-workshop]$ sudo cp hosts /etc/ansible/hosts
```

### Create OpenShift Instances

#### If Using Cinder Volumes

First, create the virtual machine instances.

```
os server create --key-name ${OPENSHIFT_SSH_KEY} --user-data user-data-cinder.txt --flavor ${OPENSHIFT_MASTER_FLAVOR} --nic net-id=openshift-1,v4-fixed-ip=10.0.10.11 --image ${OPENSHIFT_IMAGE_NAME} openshift-1-master
os server create --key-name ${OPENSHIFT_SSH_KEY} --user-data user-data-cinder.txt --flavor ${OPENSHIFT_NODE_FLAVOR} --nic net-id=openshift-1,v4-fixed-ip=10.0.10.12 --image ${OPENSHIFT_IMAGE_NAME} openshift-1-node-1
os server create --key-name ${OPENSHIFT_SSH_KEY} --user-data user-data-cinder.txt --flavor ${OPENSHIFT_NODE_FLAVOR} --nic net-id=openshift-1,v4-fixed-ip=10.0.10.13 --image ${OPENSHIFT_IMAGE_NAME} openshift-1-node-2
os server create --key-name ${OPENSHIFT_SSH_KEY} --user-data user-data-cinder.txt --flavor ${OPENSHIFT_NODE_FLAVOR} --nic net-id=openshift-1,v4-fixed-ip=10.0.10.14 --image ${OPENSHIFT_IMAGE_NAME} openshift-1-infra-1
os server create --key-name ${OPENSHIFT_SSH_KEY} --user-data user-data-cinder.txt --flavor ${OPENSHIFT_NODE_FLAVOR} --nic net-id=openshift-1,v4-fixed-ip=10.0.10.15 --image ${OPENSHIFT_IMAGE_NAME} openshift-1-router-1
```

NOTE: It will take a couple of minutes for the commands in the `user-data-cinder.txt` file to execute. While the servers will probably boot up quite quickly, installing the additional packages will take a couple of minutes.

Next, create cinder volumes.

```
os volume create --size 40 openshift-1-master-volume
os volume create --size 40 openshift-1-node-1-volume
os volume create --size 40 openshift-1-node-2-volume
os volume create --size 40 openshift-1-infra-1-volume
os volume create --size 40 openshift-1-router-1-volume
```

And attach them.

```
os server add volume openshift-1-master openshift-1-master-volume
os server add volume openshift-1-node-1 openshift-1-node-1-volume
os server add volume openshift-1-node-2 openshift-1-node-2-volume
os server add volume openshift-1-infra-1 openshift-1-infra-1-volume
os server add volume openshift-1-router-1 openshift-1-router-1-volume
```

To validate the attachment, you could do something like the below. `vdb` is the attached Cinder volume.

```
[centos@openshift-1-master ~]$ lsblk
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
vda    253:0    0  400G  0 disk
└─vda1 253:1    0  400G  0 part /
vdb    253:16   0   40G  0 disk
```

Setup the new volume as the Docker backing volume.

From the util node, run the below.

```
[centos@openshift-1-util ~]$ for s in master node-1 node-2 infra-1 router-1; do
ssh -t centos@openshift-1-$s "sudo docker-storage-setup"
ssh -t centos@openshift-1-$s "sudo systemctl start docker"
ssh -t centos@openshift-1-$s "sudo systemctl status docker"
done
```

Docker should now be ready on each of these nodes.

#### If Using Ephemeral Disks

NOTE: Skip if persistent disks were used and the nodes were already created.

Create the virtual machines.

```
os server create --key-name ${OPENSHIFT_SSH_KEY} --user-data user-data-ephemeral.txt --flavor ${OPENSHIFT_MASTER_FLAVOR}--nic net-id=openshift-1,v4-fixed-ip=10.0.10.11 --image ${OPENSHIFT_IMAGE_NAME} openshift-1-master
os server create --key-name ${OPENSHIFT_SSH_KEY} --user-data user-data-ephemeral.txt --flavor ${OPENSHIFT_NODE_FLAVOR} --nic net-id=openshift-1,v4-fixed-ip=10.0.10.12 --image ${OPENSHIFT_IMAGE_NAME} openshift-1-node-1
os server create --key-name ${OPENSHIFT_SSH_KEY} --user-data user-data-ephemeral.txt --flavor ${OPENSHIFT_NODE_FLAVOR} --nic net-id=openshift-1,v4-fixed-ip=10.0.10.13 --image ${OPENSHIFT_IMAGE_NAME} openshift-1-node-2
os server create --key-name ${OPENSHIFT_SSH_KEY} --user-data user-data-ephemeral.txt --flavor ${OPENSHIFT_NODE_FLAVOR} --nic net-id=openshift-1,v4-fixed-ip=10.0.10.14 --image ${OPENSHIFT_IMAGE_NAME} openshift-1-infra-1
os server create --key-name ${OPENSHIFT_SSH_KEY} --user-data user-data-ephemeral.txt --flavor ${OPENSHIFT_NODE_FLAVOR} --nic net-id=openshift-1,v4-fixed-ip=10.0.10.15 --image ${OPENSHIFT_IMAGE_NAME} openshift-1-router-1
```

The `user-data-ephemeral.txt` file has a script that will prepare the instances, for example installing and configuring Docker. This will take a few minutes, and please note they will be rebooted once.

#### Add Floating IP to Master and Router Nodes

Master:

```
$ os server add floating ip openshift-1-master ${OPENSHIFT_FLOATING_IP_3}
```

Router:

```
$ os server add floating ip openshift-1-router-1 ${OPENSHIFT_FLOATING_IP_2}
```

The `openshift-1-router-1` node will be the venue external clients use to access OpenShift provided resources.

## Reboot Nodes

If persistent disks were used, then reboot all the nodes. (When ephemeral disks are used in this workshop, the user-data file will reboot the nodes automatically, not so with the user-data for Cinder volumes as we have to add the volume after the node has been created.)

```
[centos@openshift-1-util ~]$ for s in master node-1 node-2 infra-1 router-1; do
ssh -t centos@openshift-1-$s "sudo shutdown -r now"
done
```

## Deploy OpenShift Origin

### Test Ansible Connectivity

We should test connectivity from the utility server to the other nodes using Ansible.

```
[centos@openshift-1-util ~]$ cd ~/openshift-workshop/
[centos@openshift-1-util openshift-workshop]$ ansible -m ping all
openshift-1-infra-1.example.com | SUCCESS => {
    "changed": false,
    "failed": false,
    "ping": "pong"
}
openshift-1-node-2.example.com | SUCCESS => {
    "changed": false,
    "failed": false,
    "ping": "pong"
}
openshift-1-node-1.example.com | SUCCESS => {
    "changed": false,
    "failed": false,
    "ping": "pong"
}
openshift-1-router-1.example.com | SUCCESS => {
    "changed": false,
    "failed": false,
    "ping": "pong"
}
openshift-1-master.example.com | SUCCESS => {
    "changed": false,
    "failed": false,
    "ping": "pong"
}
```

### Run OpenStack-Ansible

Now that we have built the instances and the infrastructure required, we can go ahead and actually deploy OpenShift.

First, establish a screen session. Screen is not necessary, but because the Ansible `config.yml` playbook will take a long time to run it's best to run it from a bash session that can be reattached, and won't die if the connection is lost.

```
[centos@openshift-1-util ~]$ sudo yum install screen -y
[centos@openshift-1-util ~]$ screen -R install
[centos@openshift-1-util ~]$ echo $STY
12352.install
```

And from that screen session, install OpenShift.

NOTE: This can take upwards of 30 minutes.

```
[centos@openshift-1-util ~]$ time ansible-playbook ~/openshift-ansible/playbooks/byo/config.yml
SNIP!
PLAY RECAP *****************************************************************************************************************************************************************
localhost                  : ok=12   changed=0    unreachable=0    failed=0   
openshift-1-infra-1.example.com : ok=243  changed=60   unreachable=0    failed=0   
openshift-1-master.example.com : ok=648  changed=177  unreachable=0    failed=0   
openshift-1-node-1.example.com : ok=243  changed=60   unreachable=0    failed=0   
openshift-1-node-2.example.com : ok=243  changed=60   unreachable=0    failed=0   
openshift-1-router-1.example.com : ok=243  changed=60   unreachable=0    failed=0   


real    24m19.094s
user    13m27.491s
sys     4m36.202s
```

OpenShift Origin has now been deployed.

### Validate Deployment

ssh into the master and validate the deployment.

```
[centos@openshift-1-util openshift-workshop]$ ssh openshift-1-master
[centos@openshift-1-master ~]$ oc get nodes
NAME         STATUS                     AGE       VERSION
10.0.10.11   Ready,SchedulingDisabled   41m       v1.6.1+5115d708d7
10.0.10.12   Ready                      41m       v1.6.1+5115d708d7
10.0.10.13   Ready                      10m       v1.6.1+5115d708d7
10.0.10.14   Ready                      41m       v1.6.1+5115d708d7
10.0.10.15   Ready                      41m       v1.6.1+5115d708d7
```

### Add a User

Login to the `openshift-1-master` node and edit the `/etc/origin/master/htpasswd` file using the `htpasswd` utility.

```
[centos@openshift-1-master ~]$ sudo su
[root@openshift-1-master centos]# cd /etc/origin/master/
[root@openshift-1-master master]# htpasswd -c htpasswd admin
New password:
Re-type new password:
```

### Setup Local Workstation /etc/hosts

If you would like to access the `example.com` URLs from your workstation, configure `/etc/hosts`.

```
$ grep example.com /etc/hosts
${OPENSHIFT_FLOATING_IP_3} openshift-1-master.example.com
${OPENSHIFT_FLOATING_IP_3} openshift-1.example.com
```

### Login to the OpenShift Web interface

Access the below URL. Note that it will be the same as what `openshift_master_cluster_public_hostname` is set to in the Ansible hosts file.

https://openshift-1.example.com:8443

Login with the user and password you added to the httpasswd file above.

## Conclusion

At this point, with any luck, you should have a multi-node OpenShift Origin cluster to test out.

## Teardown

Run the teardown script.

NOTE: This will delete all the resources created in this workshop.

```
$ ./teardown.sh
```

## Troubleshooting

* Check the `~/ansible.log` file on the utility node for Ansible errors
* Validate that Docker was properly configured in each of the non-util nodes
* Ensure that Ansible can access each of the virtual machines: run `ansible -m ping all` from the utility node

## OpenShift-Ansible Version

```
$ git show --oneline -s
3973489 Merge pull request #6265 from openshift-cherrypick-robot/cherry-pick-6188-to-release-3.6
```
