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
        ${argc_cluster} "https://192.168.178.200"
}

eval "$(argc --argc-eval "$0" "$@")"
