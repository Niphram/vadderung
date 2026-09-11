#!/usr/bin/env bash

set -e

# @meta dotenv .env

# @cmd
# @describe Opens the talosctl dashboard for all nodes.
# @option --controlnodes+, $CONTROL_NODES <nodes> bind-env
# @option --workernodes*, $WORKER_NODES <nodes> bind-env
dashboard() {
    nodes+=( "${argc_controlnodes[@]}" "${argc_workernodes[@]}" )
    nodes=$(IFS=, ; echo "${nodes[*]}")
    talosctl dashboard -n"${nodes}"
}

# @cmd
# @describe Reboots all nodes at the same time (need to rework this to be sequential)
# @option --nodes+, $CONTROL_NODES <nodes> bind-env
reboot-all() {
    nodes=$(IFS=, ; echo "${argc_nodes[*]}")
    talosctl reboot -n"${nodes}"
}

# @cmd
# @describe Generate the talos config.
# @option --talosversion! $TALOS_VERSION <version> bind-env
# @option --k8sversion! $KUBERNETES_VERSION <version> bind-env
# @option --cluster! $CLUSTER_NAME <name> bind-env
# @option --controlpane! $CONTROL_PANE <ip> bind-env
# @option --controlport! $CONTROL_PORT <port> bind-env
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
        ${argc_cluster} "https://${argc_controlpane}:${argc_controlport}"
}

# @cmd
# @describe Applies the talos config to all nodes.
# @option --controlnodes+, $CONTROL_NODES <nodes> bind-env
# @option --workernodes*, $WORKER_NODES <nodes> bind-env
apply-config() {
    for cn in "${argc_controlnodes[@]}"
    do
        echo "Applying config to control node: $cn"
        talosctl apply-config \
            -n $cn \
            --file ./generated/controlplane.yaml
    done
    
    for wn in "${argc_workernodes[@]}"
    do
        echo "Applying config to worker node: $wn"
        talosctl apply-config \
            -n $wn \
            --file ./generated/worker.yaml
    done
    
    echo "Done."
}

# @cmd
# @describe Upgrade k8s on all control nodes.
# @option --controlnodes+, $CONTROL_NODES <nodes> bind-env
upgrade-k8s() {
    for cn in "${argc_controlnodes[@]}"
    do
        echo "Upgrading k8s on control node: $cn"
        talosctl upgrade-k8s -n $cn
    done
    
    echo "Done."
}

# @cmd
# @describe Runs the cilium pre-flight-checks for the given version.
# @meta require-tools helm,kubectl
# @arg ciliumversion! <cilium_version>
# @option --controlpane! $CONTROL_PANE <ip> bind-env
# @option --controlport! $CONTROL_PORT <port> bind-env
cilium-preflightcheck() {
    PREFLIGHT_YAML=$(
        helm template cilium/cilium --version "${argc_ciliumversion}" \
        --namespace kube-system \
        --set preflight.enabled=true \
        --set agent=false \
        --set operator.enabled=false \
        --set k8sServiceHost="${argc_controlpane}" \
        --set k8sServicePort="${argc_controlport}"
    )

    trap "echo \"Deleting pre-flight-check resources.\"; kubectl delete -f - <<< ${PREFLIGHT_YAML@Q} > /dev/null" EXIT

    echo "Creating pre-flight-check resources."

    kubectl create -f - <<< "${PREFLIGHT_YAML}"

    echo "Waiting for resources to be ready."

    kubectl rollout status daemonset \
        cilium-pre-flight-check \
        -n kube-system \
        --timeout 60s

    kubectl rollout status deployment \
        cilium-pre-flight-check \
        -n kube-system \
        --timeout 60s

    echo "Pre-flight-check done."
}

# @cmd
# @describe Upgrades the cilium installation to the specified version and adds the generated files to the patches.
# Make sure to first read the upgrade-notes and run the pre-flight-check first.
# @meta require-tools helm,kubectl,yq
# @arg ciliumversion! <cilium_version>
# @option --controlpane! $CONTROL_PANE <ip> bind-env
# @option --controlport! $CONTROL_PORT <port> bind-env
upgrade-cilium() {
    CILIUM_YAML=$(
        helm template cilium/cilium \
        --version "${argc_ciliumversion}" \
        --namespace kube-system \
        --set k8sServiceHost="${argc_controlpane}" \
        --set k8sServicePort="${argc_controlport}" \
        -f cilium-values.yaml
    )

    kubectl apply -f - <<< "${CILIUM_YAML}"

    inline_manifest=$CILIUM_YAML yq eval -i '(.cluster.inlineManifests.[] | select(.name = "cilium") | .contents) = strenv(inline_manifest)' patches/control-plane/03-cni.yaml
}

eval "$(argc --argc-eval "$0" "$@")"
