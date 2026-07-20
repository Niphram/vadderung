#!/usr/bin/env bash

set -e

# @meta dotenv .env

# @cmd
# @option --nodes+, $CONTROL_NODES <nodes> bind-env
dashboard() {
    nodes=$(IFS=, ; echo "${argc_nodes[*]}")

    talosctl dashboard -n"${nodes}"
}

# @cmd
# @option --nodes+, $CONTROL_NODES <nodes> bind-env
reboot-all() {
    nodes=$(IFS=, ; echo "${argc_nodes[*]}")
    talosctl reboot -n"${nodes}"
}

# @cmd
# @option --talosversion! $TALOS_VERSION <version> bind-env
# @option --k8sversion! $KUBERNETES_VERSION <version> bind-env
# @option --cluster! $CLUSTER_NAME <name> bind-env
gen-config() {
    echo "Generating talos config for cluster $argc_cluster..."

    PATCHES=""
    for file in ./patches/common/*.yaml
    do
        echo "Applying common patch $file"
        PATCHES="${PATCHES} --config-patch @$file"
    done

    for file in ./patches/control-plane/*.yaml
    do
        echo "Applying control-plane patch $file"
        PATCHES="${PATCHES} --config-patch-control-plane @$file"
    done

    for file in ./patches/worker/*.yaml
    do
        echo "Applying worker patch $file"
        PATCHES="${PATCHES} --config-patch-worker @$file"
    done

    talosctl gen config --force -o ./generated/ \
        --kubernetes-version ${argc_k8sversion} \
        --talos-version ${argc_talosversion} \
        --with-secrets secrets.yaml \
        ${PATCHES} \
        ${argc_cluster} "https://192.168.178.200:6443"
}

# @cmd
# @option --controlnodes+, $CONTROL_NODES <nodes> bind-env
apply-config() {
    for cn in "${argc_controlnodes[@]}" 
    do
        echo "Applying config to control node: $cn"
        talosctl apply-config \
            -n $cn \
            --file ./generated/controlplane.yaml
    done

    echo "Done."
}

# @cmd
# @option --controlnodes+, $CONTROL_NODES <nodes> bind-env
upgrade-k8s() {
    for cn in "${argc_controlnodes[@]}" 
    do
        echo "Upgrading k8s on control node: $cn"
        talosctl upgrade-k8s -n $cn
    done

    echo "Done."
}

# Cilium config
# helm template \
#     cilium \
#     cilium/cilium \
#     --version 1.19.6 \
#     --namespace kube-system \
#     --set ipam.mode=kubernetes \
#     --set kubeProxyReplacement=true \
#     --set l2announcements.enabled=true \
#     --set k8sClientRateLimit.qps=10 \
#     --set k8sClientRateLimit.burst=25 \
#     --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
#     --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
#     --set cgroup.autoMount.enabled=false \
#     --set cgroup.hostRoot=/sys/fs/cgroup \
#     --set k8sServiceHost=localhost \
#     --set k8sServicePort=7445 > cilium.yaml


eval "$(argc --argc-eval "$0" "$@")"
