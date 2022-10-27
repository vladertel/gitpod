import { exec } from "../../../util/shell";
import { Werft } from "../../../util/werft";
import { CORE_DEV_KUBECONFIG_PATH, HARVESTER_KUBECONFIG_PATH, PREVIEW_K3S_KUBECONFIG_PATH } from "../const";

export type Analytics = {
    type: string;
    token: string;
};

export type GitpodDaemonsetPorts = {
    registryFacade: number;
    wsDaemon: number;
};

export type InstallerOptions = {
    werft: Werft;
    installerConfigPath: string;
    kubeconfigPath: string;
    version: string;
    proxySecretName: string;
    domain: string;
    previewName: string;
    imagePullSecretName: string;
    deploymentNamespace: string;
    analytics?: Analytics;
    withEELicense: boolean;
    workspaceFeatureFlags: string[];
};

export class Installer {
    options: InstallerOptions;

    constructor(options: InstallerOptions) {
        this.options = options;
    }

    generateAndValidateConfig(slice: string): void {
        const environment = {
            "VERSION": this.options.version,
            "INSTALLER_CONFIG_PATH": this.options.installerConfigPath,
            // TODO: Pass in the ???_KUBE_CONTEXT too
            "DEV_KUBE_PATH": CORE_DEV_KUBECONFIG_PATH,
            "HARVESTER_KUBE_PATH": HARVESTER_KUBECONFIG_PATH,
            "PREVIEW_K3S_KUBE_PATH": PREVIEW_K3S_KUBECONFIG_PATH
        }
        const variables = Object
            .entries(environment)
            .map(([key, value]) => `${key}="${value}"`)
            .join(" ")
        exec(`${variables} leeway run dev/preview:deploy-gitpod`, {slice: slice})
        this.options.werft.done(slice);
    }

    install(slice: string): void {
        this.options.werft.log(slice, "Installing Gitpod");
        exec(
            `kubectl --kubeconfig ${this.options.kubeconfigPath} delete -n ${this.options.deploymentNamespace} job migrations || true`,
            { silent: true },
        );
        // errors could result in outputing a secret to the werft log when kubernetes patches existing objects...
        exec(`kubectl --kubeconfig ${this.options.kubeconfigPath} apply -f k8s.yaml`, { silent: true });

        exec(
            `werft log result -d "dev installation" -c github-check-preview-env url https://${this.options.domain}/workspaces`,
        );
        this.options.werft.done(slice);
    }
}
