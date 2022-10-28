import * as fs from "fs";
import { exec, ExecOptions } from "../../util/shell";
import { MonitoringSatelliteInstaller } from "../../observability/monitoring-satellite";
import {
    createNamespace,
    waitForApiserver,
} from "../../util/kubectl";

import { env } from "../../util/util";
import { CORE_DEV_KUBECONFIG_PATH, PREVIEW_K3S_KUBECONFIG_PATH } from "./const";
import { Werft } from "../../util/werft";
import { JobConfig } from "./job-config";
import * as VM from "../../vm/vm";
import { Analytics, Installer } from "./installer/installer";
import { previewNameFromBranchName } from "../../util/preview";
import { SpanStatusCode } from "@opentelemetry/api";

// used by Installer
const STACKDRIVER_SERVICEACCOUNT = JSON.parse(
    fs.readFileSync(`/mnt/secrets/monitoring-satellite-stackdriver-credentials/credentials.json`, "utf8"),
);

const phases = {
    DEPLOY: "deploy",
    VM: "Ensure VM Readiness",
};

const installerSlices = {
    IMAGE_PULL_SECRET: "image pull secret",
    CLEAN_ENV_STATE: "clean envirionment",
    INSTALL: "Generate, validate, and install Gitpod",
    DEPLOYMENT_WAITING: "monitor server deployment",
};

const vmSlices = {
    VM_READINESS: "Waiting for VM readiness",
    START_KUBECTL_PORT_FORWARDS: "Start kubectl port forwards",
    COPY_CERT_MANAGER_RESOURCES: "Copy CertManager resources from core-dev",
    INSTALL_CERT_ISSUER: "Install Certificate Issuer",
    KUBECONFIG: "Getting kubeconfig",
    WAIT_K3S: "Waiting for k3s",
    WAIT_CERTMANAGER: "Waiting for Cert-Manager",
    EXTERNAL_LOGGING: "Install credentials to send logs from fluent-bit to GCP",
};

export async function deployToPreviewEnvironment(werft: Werft, jobConfig: JobConfig) {
    const {
        version,
        analytics,
        cleanSlateDeployment,
        withObservability,
        installEELicense,
        workspaceFeatureFlags,
    } = jobConfig;

    const { destname, namespace } = jobConfig.previewEnvironment;

    const domain = `${destname}.preview.gitpod-dev.com`;
    const monitoringDomain = `${destname}.preview.gitpod-dev.com`;
    const url = `https://${domain}`;

    const deploymentConfig: DeploymentConfig = {
        version,
        destname,
        namespace,
        domain,
        monitoringDomain,
        url,
        analytics,
        cleanSlateDeployment,
        installEELicense,
        withObservability,
    };

    // We set all attributes to false as default and only set it to true once the each process is complete.
    // We only set the attribute for jobs where a VM is expected.
    werft.rootSpan.setAttributes({ "preview.k3s_successfully_created": false });
    werft.rootSpan.setAttributes({ "preview.certmanager_installed_successfully": false });
    werft.rootSpan.setAttributes({ "preview.issuer_installed_successfully": false });
    werft.rootSpan.setAttributes({ "preview.rook_installed_successfully": false });
    werft.rootSpan.setAttributes({ "preview.fluentbit_installed_successfully": false });
    werft.rootSpan.setAttributes({ "preview.certificates_installed_successfully": false });
    werft.rootSpan.setAttributes({ "preview.monitoring_installed_successfully": false });

    werft.phase(phases.VM, "Ensuring VM is ready for deployment");

    werft.log(vmSlices.VM_READINESS, "Wait for VM readiness");
    VM.waitForVMReadiness({ name: destname, timeoutSeconds: 60 * 10, slice: vmSlices.VM_READINESS });
    werft.done(vmSlices.VM_READINESS);

    werft.log(vmSlices.KUBECONFIG, "Copying k3s kubeconfig");
    VM.copyk3sKubeconfigShell({ name: destname, timeoutMS: 1000 * 60 * 6, slice: vmSlices.KUBECONFIG });
    werft.done(vmSlices.KUBECONFIG);

    // TODO: Port over?
    // werft.log(vmSlices.WAIT_K3S, "Wait for k3s");
    // await waitForApiserver(PREVIEW_K3S_KUBECONFIG_PATH, { slice: vmSlices.WAIT_K3S });
    // await waitUntilAllPodsAreReady("kube-system", PREVIEW_K3S_KUBECONFIG_PATH, { slice: vmSlices.WAIT_K3S });
    // werft.rootSpan.setAttributes({ "preview.k3s_successfully_created": true });
    // werft.done(vmSlices.WAIT_K3S);

    // TODO: Port over?
    // werft.log(vmSlices.WAIT_CERTMANAGER, "Wait for Cert-Manager");
    // await waitUntilAllPodsAreReady("cert-manager", PREVIEW_K3S_KUBECONFIG_PATH, { slice: vmSlices.WAIT_CERTMANAGER });
    // werft.rootSpan.setAttributes({ "preview.certmanager_installed_successfully": true });
    // werft.done(vmSlices.WAIT_CERTMANAGER);

    exec(
        `kubectl --kubeconfig ${CORE_DEV_KUBECONFIG_PATH} get secret clouddns-dns01-solver-svc-acct -n certmanager -o yaml | sed 's/namespace: certmanager/namespace: cert-manager/g' > clouddns-dns01-solver-svc-acct.yaml`,
        { slice: vmSlices.INSTALL_CERT_ISSUER },
    );
    exec(
        `kubectl --kubeconfig ${CORE_DEV_KUBECONFIG_PATH} get clusterissuer letsencrypt-issuer-gitpod-core-dev -o yaml | sed 's/letsencrypt-issuer-gitpod-core-dev/letsencrypt-issuer/g' > letsencrypt-issuer.yaml`,
        { slice: vmSlices.INSTALL_CERT_ISSUER },
    );
    exec(
        `kubectl --kubeconfig ${PREVIEW_K3S_KUBECONFIG_PATH} apply -f clouddns-dns01-solver-svc-acct.yaml -f letsencrypt-issuer.yaml`,
        { slice: vmSlices.INSTALL_CERT_ISSUER, dontCheckRc: true },
    );
    werft.rootSpan.setAttributes({ "preview.issuer_installed_successfully": true });
    werft.done(vmSlices.INSTALL_CERT_ISSUER);

    VM.installRookCeph({ kubeconfig: PREVIEW_K3S_KUBECONFIG_PATH });
    werft.rootSpan.setAttributes({ "preview.rook_installed_successfully": true });
    VM.installFluentBit({
        namespace: "default",
        kubeconfig: PREVIEW_K3S_KUBECONFIG_PATH,
        slice: vmSlices.EXTERNAL_LOGGING,
    });
    werft.rootSpan.setAttributes({ "preview.fluentbit_installed_successfully": true });
    werft.done(vmSlices.EXTERNAL_LOGGING);

    // Deploying monitoring satellite to VM-based preview environments is currently best-effort.
    // That means we currently don't wait for the promise here, and should the installation fail
    // we'll simply log an error rather than failing the build.
    //
    // Note: Werft currently doesn't support slices spanning across multiple phases so running this
    // can result in many 'observability' slices. Currently we close all the spans in a phase
    // when we complete a phase. This means we can't currently measure the full duration or the
    // success rate or installing monitoring satellite, but we can at least count and debug errors.
    // In the future we can consider not closing spans when closing phases, or restructuring our phases
    // based on parallelism boundaries
    const monitoringSatelliteInstaller = new MonitoringSatelliteInstaller({
        kubeconfigPath: PREVIEW_K3S_KUBECONFIG_PATH,
        branch: jobConfig.observability.branch,
        satelliteNamespace: deploymentConfig.namespace,
        clusterName: deploymentConfig.namespace,
        nodeExporterPort: 9100,
        previewDomain: deploymentConfig.domain,
        previewName: previewNameFromBranchName(jobConfig.repository.branch),
        stackdriverServiceAccount: STACKDRIVER_SERVICEACCOUNT,
        werft: werft,
    });
    const sliceID = "observability";
    monitoringSatelliteInstaller
        .install()
        .then(() => {
            werft.rootSpan.setAttributes({ "preview.monitoring_installed_successfully": true });
            werft.log(sliceID, "Succeeded installing monitoring satellite");
        })
        .catch((err) => {
            werft.log(sliceID, `Failed to install monitoring: ${err}`);
            const span = werft.getSpanForSlice(sliceID);
            span.setStatus({
                code: SpanStatusCode.ERROR,
                message: err,
            });
        })
        .finally(() => werft.done(sliceID));

    werft.phase(phases.DEPLOY, "deploying to dev with Installer");
    await deployToDevWithInstaller(werft, deploymentConfig, workspaceFeatureFlags);
}

/*
 * Deploy a preview environment using the Installer
 */
async function deployToDevWithInstaller(
    werft: Werft,
    deploymentConfig: DeploymentConfig,
    workspaceFeatureFlags: string[]
) {
    const { version, namespace } = deploymentConfig;
    const deploymentKubeconfig = PREVIEW_K3S_KUBECONFIG_PATH;

    // clean environment state
    // TODO: I think we can rid of this - we're using the default namespace now
    try {
        werft.log(installerSlices.CLEAN_ENV_STATE, "Clean the preview environment slate...");
        createNamespace(namespace, deploymentKubeconfig, metaEnv({ slice: installerSlices.CLEAN_ENV_STATE }));
        werft.done(installerSlices.CLEAN_ENV_STATE);
    } catch (err) {
        werft.fail(installerSlices.CLEAN_ENV_STATE, err);
    }

    let analytics: Analytics | undefined;
    if ((deploymentConfig.analytics || "").startsWith("segment|")) {
        analytics = {
            type: "segment",
            token: deploymentConfig.analytics!.substring("segment|".length),
        };
    }

    const installer = new Installer({
        werft: werft,
        installerConfigPath: "/tmp/config.yaml",
        kubeconfigPath: deploymentKubeconfig,
        version: version,
        domain: deploymentConfig.domain,
        previewName: deploymentConfig.destname,
        deploymentNamespace: namespace,
        analytics: analytics,
        withEELicense: deploymentConfig.installEELicense,
        workspaceFeatureFlags: workspaceFeatureFlags
    });
    try {
        werft.log(phases.DEPLOY, "deploying using installer");
        installer.install(installerSlices.INSTALL);
        exec(`werft log result -d "dev installation" -c github-check-preview-env url https://${domain}/workspaces`)
    } catch (err) {
        werft.fail(phases.DEPLOY, err);
    }

    werft.log(installerSlices.DEPLOYMENT_WAITING, "Waiting until all pods are ready.");
    await waitUntilAllPodsAreReady(deploymentConfig.namespace, installer.options.kubeconfigPath, {
        slice: installerSlices.DEPLOYMENT_WAITING,
    });
    werft.done(installerSlices.DEPLOYMENT_WAITING);

    werft.done(phases.DEPLOY);
}

interface DeploymentConfig {
    version: string;
    destname: string;
    namespace: string;
    domain: string;
    monitoringDomain: string;
    url: string;
    analytics?: string;
    cleanSlateDeployment: boolean;
    installEELicense: boolean;
    withObservability: boolean;
}

function metaEnv(_parent?: ExecOptions): ExecOptions {
    return env("", _parent);
}
