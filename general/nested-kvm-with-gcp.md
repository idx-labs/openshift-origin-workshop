# Create a Instance Capable of Nested KVM in Google Cloud Platform

Google Cloud Platform (GCP) allows nested hypervisors. Not all public clouds allow this, but, at this point in time, GCP does.

Below is an example of creating an instance that has nested virtualization available.

## Create an Instance to be Imaged

Create an instance. Note the `--no-boot-disk-auto-delete` option used here.

```
gcloud compute instances create centos7-nested-kvm-image \
--no-boot-disk-auto-delete \
--image-family=centos-7 \
--image-project=centos-cloud
```

The instance will be deleted but its disk will be left behind, and an image will be created from that disk.

Delete the instance.

```
gcloud compute instances delete centos7-nested-kvm-image
```

The disk is still available.

```
gcloud compute disks list
NAME                      ZONE        SIZE_GB  TYPE         STATUS
centos7-nested-kvm-image  us-east1-b  10       pd-standard  READY
```

An image can be created from that disk.

## Create an Image

Create an image from the root disk of the instance that was deleted. Note the license that is attached to this image.

```
gcloud compute images create centos7-nested-kvm \
--source-disk centos7-nested-kvm-image \
--source-disk-zone us-east1-b \
--licenses "https://www.googleapis.com/compute/v1/projects/vm-options/global/licenses/enable-vmx"
```

Example output of the above command:

```
gcloud compute images create centos7-nested-kvm \
> --source-disk centos7-nested-kvm-image \
> --source-disk-zone us-east1-b \
> --licenses "https://www.googleapis.com/compute/v1/projects/vm-options/global/licenses/enable-vmx"
Created [https://www.googleapis.com/compute/v1/projects/example-bar-foo-1/global/images/centos7-nested-kvm].
NAME                PROJECT            FAMILY  DEPRECATED  STATUS
centos7-nested-kvm  example-bar-foo-1                      READY
```

A custom image is now available.

```
gcloud compute images list --no-standard-images
NAME                PROJECT            FAMILY  DEPRECATED  STATUS
centos7-nested-kvm  example-bar-foo-1                      READY
```

## Create a New Nested Hypervisor Capable Instance

An instance can be created from the custom image that was just created.

```
gcloud compute instances create nested-kvm \
--image centos7-nested-kvm \
--machine-type n1-standard-4
```

By sshing into the instance the nested hypervisor capabilities can be viewed.

```
$ gcloud compute ssh nested-kvm
Warning: Permanently added 'compute.2975831285112279785' (ECDSA) to the list of known hosts.
[curtis@nested-kvm ~]$  grep -E '(vmx|svm)' /proc/cpuinfo
flags		: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ss ht syscall nx pdpe1gb rdtscp lm constant_tsc rep_good nopl xtopology nonstop_tsc eagerfpu pni pclmulqdq vmx ssse3 fma cx16 sse4_1 sse4_2 x2apic movbe popcnt aes xsave avx f16c rdrand hypervisor lahf_lm abm tpr_shadow flexpriority ept fsgsbase tsc_adjust bmi1 avx2 smep bmi2 erms xsaveopt
```

With these CPU capabilities available, KVM can be installed and used.

## Delete Resources

Delete the root disk that was used to create an image, it's no longer needed.

*NOTE: `-q` or quiet will select the default answer for all interactive actions.*

```
gcloud compute disks delete -q centos7-nested-kvm-image
```

If you no longer need the running instance, or custom image, delete those as well.
