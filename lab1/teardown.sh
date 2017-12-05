#!/bin/bash

# Teardown all the of the resources created by the lab

echo "Sourcing openshift-workshoprc"
. ./openshift-workshoprc

echo "Deleting servers..."
for s in $OPENSHIFT_NODES; do
  openstack server delete $s
done
openstack server delete openshift-1-util
echo "Done deleting servers"

echo "Sleeping for 30 seconds..."
# Wait until all nodes are deleted and volumes set to available
sleep 30;

echo "Deleting volumes..."
for s in $OPENSHIFT_NODES; do
  openstack volume delete $s-volume
done
echo "Done deleting volumes"

echo "Deleting network resources..."
openstack floating ip delete ${OPENSHIFT_FLOATING_IP_1}
openstack floating ip delete ${OPENSHIFT_FLOATING_IP_2}
openstack floating ip delete ${OPENSHIFT_FLOATING_IP_3}

openstack router remove subnet r-openshift-1 openshift-1-subnet
openstack router unset --external-gateway r-openshift-1
openstack router delete r-openshift-1

openstack subnet delete openshift-1-subnet
openstack network delete openshift-1
echo "Done deleteing network resources"
