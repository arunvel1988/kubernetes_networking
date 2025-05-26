#!/bin/bash

# Set environment for etcdctl
export ETCDCTL_API=3
export ETCDCTL_CACERT="/etc/kubernetes/pki/etcd/ca.crt"
export ETCDCTL_CERT="/etc/kubernetes/pki/etcd/server.crt"
export ETCDCTL_KEY="/etc/kubernetes/pki/etcd/server.key"

# Adjust if your etcd pod name or namespace differ
ETCD_POD="etcd-kind-control-plane"
ETCD_NS="kube-system"

function run_etcdctl() {
  # If etcd pod exists, run etcdctl inside pod, else locally
  if kubectl get pod "$ETCD_POD" -n "$ETCD_NS" &>/dev/null; then
    kubectl exec "$ETCD_POD" -n "$ETCD_NS" -- sh -c "ETCDCTL_API=3 etcdctl --cacert $ETCDCTL_CACERT --key $ETCDCTL_KEY --cert $ETCDCTL_CERT $*"
  else
    etcdctl "$@"
  fi
}

function show_menu() {
  clear
  cat <<EOF
========== etcdctl Kubernetes Advanced Helper ==========
 1. Check etcd health
 2. Endpoint status
 3. Member list
 4. Put a key
 5. Get a key
 6. Delete a key
 7. List Kubernetes etcd registry keys
 8. Get specific Kubernetes object (choose namespace + pod)
 9. Show etcd DB size metric
10. Compact etcd
11. Defragment etcd
12. Take snapshot
13. Restore snapshot
14. Dump etcd keys BEFORE pod creation
15. Create a pod (kubectl run)
16. Dump etcd keys AFTER pod creation & Compare
17. Show etcd disk usage (/var/lib/etcd)
18. Exit
========================================================
EOF
  read -rp "Enter your choice [1-18]: " choice
}

function wait_for_enter() {
  echo
  read -rp "Press Enter to return to menu..."
}

function dump_etcd_keys() {
  local file="$1"
  echo "Dumping all etcd keys with prefix / into $file ..."
  run_etcdctl get / --prefix --keys-only > "$file"
  echo "Dump complete."
}

function run_option() {
  case $choice in
    1)
      run_etcdctl endpoint health
      ;;
    2)
      run_etcdctl endpoint status --write-out=table
      ;;
    3)
      run_etcdctl member list
      ;;
    4)
      read -rp "Enter key: " key
      read -rp "Enter value: " value
      run_etcdctl put "$key" "$value"
      ;;
    5)
      read -rp "Enter key to get: " key
      run_etcdctl get "$key"
      ;;
    6)
      read -rp "Enter key to delete: " key
      run_etcdctl del "$key"
      ;;
    7)
      echo "Fetching Kubernetes object keys from /registry/ ..."
      run_etcdctl get /registry/ --prefix --keys-only
      ;;
    8)
      read -rp "Enter Kubernetes namespace: " ns
      echo "Fetching pods under /registry/pods/$ns ..."
      pod_keys=$(run_etcdctl get "/registry/pods/$ns/" --prefix --keys-only | grep "^/registry/pods/$ns/")

      if [[ -z "$pod_keys" ]]; then
        echo "No pods found in namespace '$ns'"
        wait_for_enter
        return
      fi

      echo "Select a pod:"
      IFS=$'\n' read -rd '' -a pods <<< "$pod_keys"
      for i in "${!pods[@]}"; do
        podname=$(basename "${pods[$i]}")
        echo "$((i+1)). $podname"
      done

      read -rp "Enter number: " podnum
      if ! [[ "$podnum" =~ ^[0-9]+$ ]] || (( podnum < 1 || podnum > ${#pods[@]} )); then
        echo "Invalid selection"
        wait_for_enter
        return
      fi

      selected_key="${pods[$((podnum-1))]}"
      echo "Fetching etcd object for: $selected_key"
      value=$(run_etcdctl get "$selected_key" --print-value-only)

      # Check if output is valid JSON
      if echo "$value" | jq empty >/dev/null 2>&1; then
        echo "$value" | jq .
      else
        echo "Output is not valid JSON, printing raw output:"
        echo "$value"
      fi
      ;;
    9)
      echo "Showing etcd DB size metric:"
      run_etcdctl endpoint status --write-out=table
      ;;
    10)
      rev=$(run_etcdctl endpoint status --write-out=json | jq -r '.[0].Status.header.revision')
      echo "Current revision: $rev"
      read -rp "Compact to revision [$rev]: " comprev
      comprev=${comprev:-$rev}
      run_etcdctl compact "$comprev"
      ;;
    11)
      run_etcdctl defrag
      ;;
    12)
      read -rp "Enter snapshot path (e.g., /tmp/etcd-snap.db): " snap
      run_etcdctl snapshot save "$snap"
      echo "Snapshot saved to $snap"
      ;;
    13)
      read -rp "Enter snapshot path to restore: " snap
      read -rp "Enter data dir to restore to (e.g., /var/lib/etcd-from-backup): " dir
      run_etcdctl snapshot restore "$snap" --data-dir "$dir"
      echo "Restored snapshot to $dir"
      ;;
    14)
      dump_etcd_keys "etcd-before-pod.txt"
      ;;
    15)
      read -rp "Enter pod name: " podname
      read -rp "Enter image name (default: nginx): " image
      image=${image:-nginx}
      echo "Creating pod '$podname' with image '$image'..."
      kubectl run "$podname" --image="$image" --restart=Never
      echo "Pod creation command issued."
      ;;
    16)
      dump_etcd_keys "etcd-after-pod.txt"
      echo
      echo "Comparing etcd keys before and after pod creation..."
      if [[ ! -f etcd-before-pod.txt ]]; then
        echo "Error: etcd-before-pod.txt not found. Please run option 14 before creating a pod."
      else
        echo "Keys added or changed:"
        comm -13 <(sort etcd-before-pod.txt) <(sort etcd-after-pod.txt)
        
      fi
      echo
      read -rp "Do you want to view event details for a pod? (y/N): " show_events
      if [[ "$show_events" =~ ^[Yy]$ ]]; then
      read -rp "Enter namespace of the pod: " event_ns
      read -rp "Enter event key suffix (e.g. my-pod.173bb0a9bbbda0b6): " event_suffix
      event_key="/registry/events/$event_ns/$event_suffix"

      echo "Fetching and decoding event for key: $event_key"
      etcdctl get "$event_key" -w json | jq -r '.kvs[0].value' | base64 --decode

      echo
      fi
      ;;
    17)
      echo "Checking etcd disk usage in /var/lib/etcd ..."
      if [[ $EUID -ne 0 ]]; then
        echo "You might need to run this script with sudo to check /var/lib/etcd disk usage."
      fi
      size=$(sudo du -sh /var/lib/etcd | awk '{print $1}')
      usage=$(df -h /var/lib/etcd | tail -1 | awk '{print $5}')
      echo "/var/lib/etcd size: $size"
      echo "Disk usage of partition containing /var/lib/etcd: $usage"
      echo
      echo "To free up space, consider:"
      echo "  - Compaction (Option 10)"
      echo "  - Defragmentation (Option 11)"
      echo "  - Taking and restoring from snapshot (Option 12 + 13)"
      ;;
    18)
      echo "Bye!"
      exit 0
      ;;
    *)
      echo "Invalid choice"
      ;;
  esac

  wait_for_enter
}

while true; do
  show_menu
  run_option
done