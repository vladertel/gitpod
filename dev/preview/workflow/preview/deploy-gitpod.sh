#!/usr/bin/env bash

set -euo pipefail

SCRIPT_PATH=$(realpath "$(dirname "$0")")
ROOT="${SCRIPT_PATH}/../../../../"

# shellcheck source=../lib/common.sh
source "$(realpath "${SCRIPT_PATH}/../lib/common.sh")"
# shellcheck source=../../util/preview-name-from-branch.sh
source "$(realpath "${SCRIPT_PATH}/../../util/preview-name-from-branch.sh")"

DEV_KUBE_PATH="/home/gitpod/.kube/config"
DEV_KUBE_CONTEXT="dev"
HARVESTER_KUBE_PATH="/home/gitpod/.kube/config"
HARVESTER_KUBE_CONTEXT="harvester"

PREVIEW_NAME="$(preview-name-from-branch)"
PREVIEW_K3S_KUBE_PATH="${PREVIEW_K3S_KUBECONFIG_PATH:-/home/gitpod/.kube/config}"
PREVIEW_K3S_KUBE_CONTEXT="${PREVIEW_K3S_KUBE_CONTEXT:-$PREVIEW_NAME}"

# TODO: Figure out why Leeway doesn't like this.
# AGENT_SMITH_TOKEN="$(tr -dc 'A-Fa-f0-9' < /dev/urandom | head -c61)"
AGENT_SMITH_TOKEN="57B8fdFD68442a37E18B22bFD83638D451E087A047Eb4e4BF8BCc3EdF5825"


INSTALLATION_NAMESPACE="default"

PATH_TO_RENDERED_YAML="k8s.yaml"

VERSION="${VERSION:-$(preview-name-from-branch)-dev}"
INSTALLER_CONFIG_PATH="${INSTALLER_CONFIG_PATH:-$(mktemp "/tmp/XXXXXX.gitpod.config.yaml")}"

# Using /tmp/installer as that's what Werft expects (for now)
docker run \
    --entrypoint sh \
    --rm \
    --pull=always \
    "eu.gcr.io/gitpod-core-dev/build/installer:${VERSION}" -c "cat /app/installer" \
> /tmp/installer
chmod +x /tmp/installer

function installer {
    /tmp/installer "$@"
}

function findLastHostPort {
  name="$1"
  kubectl \
    --kubeconfig "${PREVIEW_K3S_KUBE_PATH}" \
    --context "${PREVIEW_K3S_KUBE_CONTEXT}" \
    get ds -n ${INSTALLATION_NAMESPACE} "${name}" -o yaml \
  | yq r - 'spec.template.spec.containers.*.ports.*.hostPort'

  #
  # TODO: If the port is empty, then select one.
  # [wsdaemonPortMeta, registryNodePortMeta] = await findFreeHostPorts(
  #           [
  #               { start: 10000, end: 11000 },
  #               { start: 30000, end: 31000 },
  #           ],
  #           deploymentKubeconfig,
  #           metaEnv({ slice: installerSlices.FIND_FREE_HOST_PORTS, silent: true }),
  #       );
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
    key=$(echo "${row}" | base64 -d | jq -r '.key')
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
kubectl --kubeconfig ${DEV_KUBE_PATH} --context "${DEV_KUBE_CONTEXT}" -n werft get secret stripe-api-keys -o yaml > stripe-api-keys.secret.yaml
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

# ========
# Render
# ========

installer render \
  --use-experimental-config \
  --namespace "${INSTALLATION_NAMESPACE}" \
  --config "${INSTALLER_CONFIG_PATH}" > "${PATH_TO_RENDERED_YAML}"

# ===============
# Post-processing
# ===============

#
# configureLicense
#
# TODO: Read "this.options.withEELicense"
WITH_EE_LICENSE="false"
if [[ "${WITH_EE_LICENSE}" == "true" ]]
then
  cp /mnt/secrets/gpsh-harvester/license /tmp/license
else
  touch /tmp/license
fi

#
# configureWorkspaceFeatureFlags
#

touch /tmp/defaultFeatureFlags
# TODO: Read "this.options.workspaceFeatureFlags"
WORKSPACE_FEATURE_FLAGS=""
for feature in ${WORKSPACE_FEATURE_FLAGS}; do
  # post-process.sh looks for /tmp/defaultFeatureFlags
  # each "flag" string gets added to the configmap
  # also watches aout for /tmp/payment
  echo "$feature" >> /tmp/defaultFeatureFlags
done

#
# configurePayment
#

# 1. Read versions from docker image
docker run --rm "eu.gcr.io/gitpod-core-dev/build/versions:$VERSION" cat /versions.yaml > /tmp/versions.yaml
SERVICE_WAITER_VERSION="$(yq r /tmp/versions.yaml 'components.serviceWaiter.version')"
PAYMENT_ENDPOINT_VERSION="$(yq r /tmp/versions.yaml 'components.paymentEndpoint.version')"

# 2. render chargebee-config and payment-endpoint
rm -f /tmp/payment
for manifest in "$ROOT"/.werft/jobs/build/payment/*.yaml; do
  sed "s/\${NAMESPACE}/${INSTALLATION_NAMESPACE}/g" "$manifest" \
  | sed "s/\${PAYMENT_ENDPOINT_VERSION}/${PAYMENT_ENDPOINT_VERSION}/g" \
  | sed "s/\${SERVICE_WAITER_VERSION}/${SERVICE_WAITER_VERSION}/g" \
  >> /tmp/payment
  echo "---" >> /tmp/payment
done

#
# Run post-process script
#

REGISTRY_FACADE_PORT="$(findLastHostPort 'registry-facade')"
WS_DAEMON_PORT="$(findLastHostPort 'ws-daemon')"
WITH_VM=true "$ROOT/.werft/jobs/build/installer/post-process.sh" \
  "${REGISTRY_FACADE_PORT}" \
  "${WS_DAEMON_PORT}" \
  "${PREVIEW_NAME}" \
  "${AGENT_SMITH_TOKEN}"

#
# Cleanup from post-processing
#
rm -f /tmp/payment
rm -f /tmp/defaultFeatureFlags
rm -f /tmp/license

# ===============
# Install
# ===============
kubectl --kubeconfig "${PREVIEW_K3S_KUBE_PATH}" --context "${PREVIEW_K3S_KUBE_CONTEXT}" delete -n "${INSTALLATION_NAMESPACE}" job migrations || true
kubectl --kubeconfig "${PREVIEW_K3S_KUBE_PATH}" --context "${PREVIEW_K3S_KUBE_CONTEXT}" apply -f "${PATH_TO_RENDERED_YAML}"
rm -f "${PATH_TO_RENDERED_YAML}"

# =========================
# Wait for pods to be ready
# =========================
echo "Waiting until all pods in namespace ${INSTALLATION_NAMESPACE} are Running/Succeeded/Completed."
ATTEMPTS=0
while [ ${ATTEMPTS} -lt 200 ]
do
  ATTEMPTS=$((ATTEMPTS+1))
  pods=$(
    kubectl \
      --kubeconfig "${PREVIEW_K3S_KUBE_PATH}" \
      --context "${PREVIEW_K3S_KUBE_CONTEXT}" \
      get pods -n ${INSTALLATION_NAMESPACE} \
        -l 'component!=workspace' \
        -o=jsonpath='{range .items[*]}{@.metadata.name}:{@.metadata.ownerReferences[0].kind}:{@.status.phase};{end}'
  )
  if [[ -z "${pods}" ]]; then
    echo "The namespace is empty or does not exist."
    echo "Sleeping"
    sleep 3
    continue
  fi
  break
done

echo "Installation is happy: https://${DOMAIN}/workspaces"
# =====================
# Add agent smith token
# =====================
# TODO: Invoke addAgentSmithToke
# process.env.KUBECONFIG = kubeconfigPath;
# process.env.TOKEN = token;
# setKubectlContextNamespace(namespace, {});
# exec("leeway run components:add-smith-token");
