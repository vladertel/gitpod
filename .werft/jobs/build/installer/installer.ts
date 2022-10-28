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
    domain: string;
    previewName: string;
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

    install(slice: string): void {
        const environment = {
            VERSION: this.options.version,
            INSTALLER_CONFIG_PATH: this.options.installerConfigPath,
            // TODO: Pass in the ???_KUBE_CONTEXT too
            DEV_KUBE_PATH: CORE_DEV_KUBECONFIG_PATH,
            HARVESTER_KUBE_PATH: HARVESTER_KUBECONFIG_PATH,
            PREVIEW_K3S_KUBE_PATH: PREVIEW_K3S_KUBECONFIG_PATH,
        };
        const variables = Object.entries(environment)
            .map(([key, value]) => `${key}="${value}"`)
            .join(" ");
        exec(`${variables} leeway run dev/preview:deploy-gitpod`, { slice: slice });
        this.options.werft.done(slice);
    }
}
