#!/bin/bash

CONTROL_PLANE_IP=("192.168.178.201" "192.168.178.202" "192.168.178.203")  
YOUR_ENDPOINT="vadderung.niphrams-bu.de" # Should point to the VIP

# talosctl gen secrets -o secrets.yaml

CLUSTER_NAME="vadderung"

talosctl gen config --force -o ./generated/ \
    --with-secrets secrets.yaml \
    --config-patch @patches/01-vip.yaml \
    --config-patch @patches/02-controlplane.yaml \
    --config-patch @patches/03-raw-volume.yaml \
    $CLUSTER_NAME https://$YOUR_ENDPOINT:6443

for ip in "${CONTROL_PLANE_IP[@]}"; do
  echo "=== Applying configuration to node $ip ==="
  talosctl apply-config \
    --nodes $ip \
    --file ./generated/controlplane.yaml
  echo "Configuration applied to $ip"
  echo ""
done

# talosctl config remove -y "${CLUSTER_NAME}"
talosctl config merge ./generated/talosconfig

talosctl config endpoint "${CONTROL_PLANE_IP[@]}"

#talosctl bootstrap --nodes "${CONTROL_PLANE_IP[0]}"
talosctl kubeconfig -f -n "${CONTROL_PLANE_IP[0]}"
# TODO: replace ip in kubeconfig
kubectl get nodes
