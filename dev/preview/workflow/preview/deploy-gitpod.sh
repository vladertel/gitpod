#!/usr/bin/env bash

set -euo pipefail

SCRIPT_PATH=$(realpath "$(dirname "$0")")

# shellcheck source=../lib/common.sh
source "$(realpath "${SCRIPT_PATH}/../lib/common.sh")"
# shellcheck source=../../util/preview-name-from-branch.sh
source "$(realpath "${SCRIPT_PATH}/../../util/preview-name-from-branch.sh")"

DEV_KUBE_PATH="/home/gitpod/.kube/config"
DEV_KUBE_CONTEXT="dev"
HARVESTER_KUBE_PATH="/home/gitpod/.kube/config"
HARVESTER_KUBE_CONTEXT="harvester"

INSTALLATION_NAMESPACE="default"

VERSION="${VERSION:-$(preview-name-from-branch)-dev}"
INSTALLER_HASH=$(
    leeway describe install/installer:app \
        -DSEGMENT_IO_TOKEN="$(kubectl --context=dev -n werft get secret self-hosted -o jsonpath='{.data.segmentIOToken}' | base64 -d)" \
        -DREPLICATED_API_TOKEN="$(kubectl --context=dev -n werft get secret replicated -o jsonpath='{.data.token}' | base64 -d)" \
        -DREPLICATED_APP="$(kubectl --context=dev -n werft get secret replicated -o jsonpath='{.data.app}' | base64 -d)" \
        -Dversion="${VERSION}" \
        --format=json \
    | jq -r '.metadata.version'
)

# TODO: Maybe use /tmp/installer so that it can be used in the rest of Werft too.
INSTALLER_CONFIG_PATH="${INSTALLER_CONFIG_PATH:-$(mktemp "/tmp/XXXXXX.gitpod.config.yaml")}"

# Using /tmp/installer as that's what Werft expects (for now)
cp "/tmp/build/install-installer--app.$INSTALLER_HASH/installer" /tmp/installer

function installer {
    /tmp/installer "$@"
}

# ========
# Init
# ========

installer config init --overwrite --config "$INSTALLER_CONFIG_PATH"

# =============
# Modify config
# =============

#
# getDevCustomValues
#
cat <<EOF > blockNewUsers.yaml
blockNewUsers:
  enabled: true
  passlist:
    - "gitpod.io"
EOF
yq m -i --overwrite "${INSTALLER_CONFIG_PATH}" "blockNewUsers.yaml"
rm blockNewUsers.yaml

#
# configureMetadata
#
cat <<EOF > shortname.yaml
metadata:
  shortname: "dev"
EOF
yq m -ix "${INSTALLER_CONFIG_PATH}" shortname.yaml
rm shortname.yaml

#
# configureContainerRegistry
#
CONTAINER_REGISTRY_URL="eu.gcr.io/gitpod-core-dev/build/";
IMAGE_PULL_SECRET_NAME="gcp-sa-registry-auth";
PROXY_SECRET_NAME="proxy-config-certificates";
yq w -i "${INSTALLER_CONFIG_PATH}" certificate.name "${PROXY_SECRET_NAME}"
yq w -i "${INSTALLER_CONFIG_PATH}" containerRegistry.inCluster "false"
yq w -i "${INSTALLER_CONFIG_PATH}" containerRegistry.external.url "${CONTAINER_REGISTRY_URL}"
yq w -i "${INSTALLER_CONFIG_PATH}" containerRegistry.external.certificate.kind secret
yq w -i "${INSTALLER_CONFIG_PATH}" containerRegistry.external.certificate.name "${IMAGE_PULL_SECRET_NAME}"

#
# configureDomain
#
DOMAIN="$(previewctl get-name).preview.gitpod-dev.com"
yq w -i "${INSTALLER_CONFIG_PATH}" domain "${DOMAIN}"

#
# configureWorkspaces
#
CONTAINERD_RUNTIME_DIR="/var/lib/containerd/io.containerd.runtime.v2.task/k8s.io"
yq w -i "${INSTALLER_CONFIG_PATH}" workspace.runtime.containerdRuntimeDir ${CONTAINERD_RUNTIME_DIR}
yq w -i "${INSTALLER_CONFIG_PATH}" workspace.resources.requests.cpu "100m"
yq w -i "${INSTALLER_CONFIG_PATH}" workspace.resources.requests.memory "256Mi"

# create two workspace classes (default and small) in server-config configmap
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.workspaceClasses[+].id "default"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.workspaceClasses[0].category "GENERAL PURPOSE"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.workspaceClasses[0].displayName "Default"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.workspaceClasses[0].description "Default workspace class (30GB disk)"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.workspaceClasses[0].powerups "1"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.workspaceClasses[0].isDefault "true"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.workspaceClasses[0].deprecated "false"

yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.workspaceClasses[+].id "small"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.workspaceClasses[1].category "GENERAL PURPOSE"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.workspaceClasses[1].displayName "Small"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.workspaceClasses[1].description "Small workspace class (20GB disk)"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.workspaceClasses[1].powerups "2"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.workspaceClasses[1].isDefault "false"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.workspaceClasses[1].deprecated "false"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.workspaceClasses[1].marker.moreResources "true"

# create two workspace classes (default and small) in ws-manager configmap
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.workspace.classes["default"].name "default"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.workspace.classes["default"].resources.requests.cpu "100m"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.workspace.classes["default"].resources.requests.memory "128Mi"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.workspace.classes["default"].pvc.size "30Gi"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.workspace.classes["default"].pvc.storageClass "rook-ceph-block"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.workspace.classes["default"].pvc.snapshotClass "csi-rbdplugin-snapclass"

yq w -i "${INSTALLER_CONFIG_PATH}" experimental.workspace.classes["small"].name "small"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.workspace.classes["small"].resources.requests.cpu "100m"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.workspace.classes["small"].resources.requests.memory "128Mi"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.workspace.classes["small"].pvc.size "20Gi"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.workspace.classes["small"].pvc.storageClass "rook-ceph-block"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.workspace.classes["small"].pvc.snapshotClass "csi-rbdplugin-snapclass"

#
# configureObjectStorage
#
yq w -i "${INSTALLER_CONFIG_PATH}" objectStorage.resources.requests.memory "256Mi"

#
# configureIDE
#
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.ide.resolveLatest "false"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.ide.ideMetrics.enabledErrorReporting "true"

#
# configureObservability
#
TRACING_ENDPOINT="http://otel-collector.monitoring-satellite.svc.cluster.local:14268/api/traces"
yq w -i "${INSTALLER_CONFIG_PATH}" observability.tracing.endpoint "${TRACING_ENDPOINT}"

log_success "Generated config at $INSTALLER_CONFIG_PATH"

#
# configureAuthProviders
#
for row in $(kubectl --kubeconfig "$DEV_KUBE_PATH" --context=${DEV_KUBE_CONTEXT} get secret preview-envs-authproviders-harvester --namespace=keys -o jsonpath="{.data.authProviders}" \
| base64 -d -w 0 \
| yq r - authProviders -j \
| jq -r 'to_entries | .[] | @base64'); do
    key=$(echo "$row "| base64 -d | jq -r '.key')
    providerId=$(echo "$row" | base64 -d | jq -r '.value.id | ascii_downcase')
    data=$(echo "$row" | base64 -d | yq r - value --prettyPrint)

    yq w -i "${INSTALLER_CONFIG_PATH}" authProviders["$key"].kind "secret"
    yq w -i "${INSTALLER_CONFIG_PATH}" authProviders["$key"].name "$providerId"

    kubectl create secret generic "$providerId" \
        --namespace "${INSTALLATION_NAMESPACE}" \
        --kubeconfig "${HARVESTER_KUBE_PATH}" \
        --context "${HARVESTER_KUBE_CONTEXT}" \
        --from-literal=provider="$data" \
        --dry-run=client -o yaml | \
        kubectl --kubeconfig "${HARVESTER_KUBE_PATH}" --context "${HARVESTER_KUBE_CONTEXT}" replace --force -f -
done

#
# configureStripeAPIKeys
#
kubectl --kubeconfig ${DEV_KUBE_PATH} -n werft get secret stripe-api-keys -o yaml > stripe-api-keys.secret.yaml
yq w -i stripe-api-keys.secret.yaml metadata.namespace "default"
yq d -i stripe-api-keys.secret.yaml metadata.creationTimestamp
yq d -i stripe-api-keys.secret.yaml metadata.uid
yq d -i stripe-api-keys.secret.yaml metadata.resourceVersion
kubectl --kubeconfig "${HARVESTER_KUBE_PATH}" --context "${HARVESTER_KUBE_CONTEXT}" apply -f stripe-api-keys.secret.yaml
rm -f stripe-api-keys.secret.yaml

#
# configureSSHGateway
#
kubectl --kubeconfig ${DEV_KUBE_PATH} --context "${DEV_KUBE_CONTEXT}" --namespace keys get secret host-key -o yaml \
| yq w - metadata.namespace ${INSTALLATION_NAMESPACE} \
| yq d - metadata.uid \
| yq d - metadata.resourceVersion \
| yq d - metadata.creationTimestamp \
| kubectl --kubeconfig ${HARVESTER_KUBE_PATH} --context "${HARVESTER_KUBE_CONTEXT}" apply -f -

yq w -i "${INSTALLER_CONFIG_PATH}" sshGatewayHostKey.kind "secret"
yq w -i "${INSTALLER_CONFIG_PATH}" sshGatewayHostKey.name "host-key"

#
# configurePublicAPIServer
#
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.publicApi.enabled true

#
# configureUsage
#
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.usage.enabled "true"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.usage.schedule "1m"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.usage.billInstancesAfter "2022-08-11T08:05:32.499Z"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.usage.defaultSpendingLimit.forUsers "500"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.usage.defaultSpendingLimit.forTeams "0"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.usage.defaultSpendingLimit.minForUsersOnStripe "1000"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.usage.creditsPerMinuteByWorkspaceClass['default'] "0.1666666667"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.usage.creditsPerMinuteByWorkspaceClass['gitpodio-internal-xl'] "0.3333333333"

# Configure Price IDs
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.stripe.individualUsagePriceIds['EUR'] "price_1LmYVxGadRXm50o3AiLq0Qmo"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.stripe.individualUsagePriceIds['USD'] "price_1LmYWRGadRXm50o3Ym8PLqnG"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.stripe.teamUsagePriceIds['EUR'] "price_1LiId7GadRXm50o3OayAS2y4"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.stripe.teamUsagePriceIds['USD'] "price_1LiIdbGadRXm50o3ylg5S44r"

#
# configureConfigCat
#
# This key is not a secret, it is a unique identifier of our ConfigCat application
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.configcatKey "WBLaCPtkjkqKHlHedziE9g/LEAOCNkbuUKiqUZAcVg7dw"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.proxy.configcat.baseUrl "https://cdn-global.configcat.com"
yq w -i "${INSTALLER_CONFIG_PATH}" experimental.webapp.proxy.configcat.pollInterval "1m"

#
# configureDefaultTemplate
#
yq w -i "${INSTALLER_CONFIG_PATH}" 'workspace.templates.default.spec.containers[+].name' "workspace"
yq w -i "${INSTALLER_CONFIG_PATH}" 'workspace.templates.default.spec.containers.(name==workspace).env[+].name' "GITPOD_PREVENT_METADATA_ACCESS"
yq w -i "${INSTALLER_CONFIG_PATH}" 'workspace.templates.default.spec.containers.(name==workspace).env.(name==GITPOD_PREVENT_METADATA_ACCESS).value' "true"

# TODO: Pass the token (or find a way to read it) and conditionally decide (include or dontIncludeAnalytics)
#
# includeAnalytics
#
# yq w -i "${INSTALLER_CONFIG_PATH}" analytics.writer segment
# yq w -i "${INSTALLER_CONFIG_PATH}" analytics.segmentKey ${this.options.analytics.token}
# yq w -i "${INSTALLER_CONFIG_PATH}" 'workspace.templates.default.spec.containers.(name==workspace).env[+].name' "GITPOD_ANALYTICS_WRITER"
# yq w -i "${INSTALLER_CONFIG_PATH}" 'workspace.templates.default.spec.containers.(name==workspace).env.(name==GITPOD_ANALYTICS_WRITER).value' "segment"
# yq w -i "${INSTALLER_CONFIG_PATH}" 'workspace.templates.default.spec.containers.(name==workspace).env[+].name' "GITPOD_ANALYTICS_SEGMENT_KEY"
# yq w -i "${INSTALLER_CONFIG_PATH}" 'workspace.templates.default.spec.containers.(name==workspace).env.(name==GITPOD_ANALYTICS_SEGMENT_KEY).value' "${this.options.analytics.token}"

# dontIncludeAnalytics
yq w -i "${INSTALLER_CONFIG_PATH}" analytics.writer ""

#
# chargebee
#
yq w -i "${INSTALLER_CONFIG_PATH}" "experimental.webapp.server.chargebeeSecret" "chargebee-config"

#
# Stripe
#
yq w -i "${INSTALLER_CONFIG_PATH}" "experimental.webapp.server.stripeSecret" "stripe-api-keys"
yq w -i "${INSTALLER_CONFIG_PATH}" "experimental.webapp.server.stripeConfig" "stripe-config"

# ========
# Validate
# ========

installer validate config --config "$INSTALLER_CONFIG_PATH"

# TODO: This doesn't support separate kubeconfig and kubectx yet so we need to find a way around that
# installer validate cluster --kubeconfig "${HARVESTER_KUBE_PATH}" --config "${INSTALLER_CONFIG_PATH}"
