Component | Purpose | What happens if it fails?
kube-apiserver
 | Frontend for the Kubernetes control plane (all communication goes through it) 
| Cluster stops responding to kubectl, controllers can’t act. Pods already running are fine, but you cannot create/update anything.
###########################################################
etcd 
| Stores all cluster data (state) | 
Cluster loses all memory if etcd is fully down. No recovery unless backups.
kube-scheduler | Decides which node a new Pod should run on | Running Pods are fine, but no new Pods will be scheduled.
###########################################################
kube-controller-manager
 | Runs controllers (Node controller, Replication controller, etc) | Cluster doesn't react to failures (e.g., dead nodes not detected, Pods not recreated)
########################################################
cloud-controller-manager (optional)
 | Manages cloud-specific stuff (load balancers, IPs, etc) | Cloud-specific automation stops working (e.g., new LoadBalancers won't be created)
 ###################################################