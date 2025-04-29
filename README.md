# kubernetes_networking
kubernetes_networking


/etc/kubernetes/pki/apiserver.crt

/etc/kubernetes/pki/apiserver.key



/etc/kubernetes/pki/apiserver-kubelet-client.crt

/etc/kubernetes/pki/etcd/server.crt

/etc/kubernetes/pki/etcd/server.key


/etc/kubernetes/pki/apiserver-etcd-client.crt

/etc/kubernetes/pki/apiserver-etcd-client.key


/etc/kubernetes/pki/controller-manager.crt

/etc/kubernetes/pki/scheduler.crt

/etc/kubernetes/admin.conf

openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep -A 2 Validity


# On kubeadm clusters
kubeadm certs renew apiserver

# Alternative manual renewal (requires CA key)
openssl x509 -req -in apiserver.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out apiserver.crt

# Typically managed by static pod
cp newcert.crt /etc/kubernetes/pki/apiserver.crt
crictl rm $(crictl ps -a | grep kube-apiserver | awk '{print $1}')

openssl x509 -in /etc/kubernetes/pki/etcd/server.crt -text -noout | grep -A 2 Validity

openssl x509 -in /etc/kubernetes/pki/apiserver-etcd-client.crt -text -noout | grep -A 2 Validity


# On kubeadm clusters
kubeadm certs renew etcd-server
kubeadm certs renew etcd-peer
kubeadm certs renew apiserver-etcd-client

# Restart etcd
crictl rm $(crictl ps -a | grep etcd | awk '{print $1}')

ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
  snapshot restore backup.db

  openssl x509 -in /etc/kubernetes/pki/controller-manager.crt -text -noout | grep -A 2 Validity

  # On kubeadm clusters
kubeadm certs renew controller-manager

# Restart controller manager
crictl rm $(crictl ps -a | grep controller-manager | awk '{print $1}')

kubectl logs -n kube-system kube-controller-manager-<master-node-name>
# or
crictl logs $(crictl ps -a | grep controller-manager | awk '{print $1}')

openssl x509 -in /etc/kubernetes/pki/scheduler.crt -text -noout | grep -A 2 Validity

# On kubeadm clusters
kubeadm certs renew scheduler

# Restart scheduler
crictl rm $(crictl ps -a | grep scheduler | awk '{print $1}')

# Example script to check expiration dates
for cert in $(find /etc/kubernetes/pki -name "*.crt"); do
  echo "$cert: $(openssl x509 -in $cert -noout -enddate)"
done

ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /backup/etcd-snapshot-$(date +%Y%m%d).db

  tar -czf k8s-certs-backup-$(date +%Y%m%d).tar.gz /etc/kubernetes/pki
