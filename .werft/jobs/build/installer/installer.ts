import * as fs from "fs";
import { exec } from "../../../util/shell";
import { Werft } from "../../../util/werft";
import { renderPayment } from "../payment/render";

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
    gitpodDaemonsetPorts: GitpodDaemonsetPorts;
    smithToken: string;
};

export class Installer {
    options: InstallerOptions;

    constructor(options: InstallerOptions) {
        this.options = options;
    }

    generateAndValidateConfig(slice: string): void {
        const envirionment = {
            "VERSION": this.options.version,
            "INSTALLER_CONFIG_PATH": this.options.installerConfigPath
        }
        const variables = Object
            .entries(envirionment)
            .map(([key, value]) => `${key}="${value}`)
            .join(" ")
        exec(`${variables} leeway run dev/preview:deploy-gitpod`, {slice: slice})
    }

    render(slice: string): void {
        this.options.werft.log(slice, "Rendering YAML manifests");
        exec(
            `/tmp/installer render --use-experimental-config --namespace ${this.options.deploymentNamespace} --config ${this.options.installerConfigPath} > k8s.yaml`,
            { slice: slice },
        );
        this.options.werft.done(slice);
    }

    postProcessing(slice: string): void {
        this.options.werft.log(slice, "Post processing YAML manifests");

        this.configureLicense(slice);
        this.configureWorkspaceFeatureFlags(slice);
        this.configurePayment(slice);
        this.process(slice);

        this.options.werft.done(slice);
    }

    private configureLicense(slice: string): void {
        if (this.options.withEELicense) {
            // Previews in core-dev and harvester use different domain, which requires different licenses.
            exec(`cp /mnt/secrets/gpsh-harvester/license /tmp/license`, { slice: slice });
            // post-process.sh looks for /tmp/license, and if it exists, adds it to the configmap
        } else {
            exec(`touch /tmp/license`, { slice: slice });
        }
    }

    private configureWorkspaceFeatureFlags(slice: string): void {
        exec(`touch /tmp/defaultFeatureFlags`, { slice: slice });
        if (this.options.workspaceFeatureFlags && this.options.workspaceFeatureFlags.length > 0) {
            this.options.workspaceFeatureFlags.forEach((featureFlag) => {
                exec(`echo \'"${featureFlag}"\' >> /tmp/defaultFeatureFlags`, { slice: slice });
            });
            // post-process.sh looks for /tmp/defaultFeatureFlags
            // each "flag" string gets added to the configmap
            // also watches aout for /tmp/payment
        }
    }

    private configurePayment(slice: string): void {
        // 1. Read versions from docker image
        this.options.werft.log(slice, "configuring withPayment...");
        try {
            exec(
                `docker run --rm eu.gcr.io/gitpod-core-dev/build/versions:${this.options.version} cat /versions.yaml > versions.yaml`,
            );
        } catch (err) {
            this.options.werft.fail(slice, err);
        }
        const serviceWaiterVersion = exec("yq r ./versions.yaml 'components.serviceWaiter.version'")
            .stdout.toString()
            .trim();
        const paymentEndpointVersion = exec("yq r ./versions.yaml 'components.paymentEndpoint.version'")
            .stdout.toString()
            .trim();

        // 2. render chargebee-config and payment-endpoint
        const paymentYamls = renderPayment(
            this.options.deploymentNamespace,
            paymentEndpointVersion,
            serviceWaiterVersion,
        );
        fs.writeFileSync("/tmp/payment", paymentYamls);

        this.options.werft.log(slice, "done configuring withPayment.");
    }

    private process(slice: string): void {
        const flags = "WITH_VM=true ";

        exec(
            `${flags}./.werft/jobs/build/installer/post-process.sh ${this.options.gitpodDaemonsetPorts.registryFacade} ${this.options.gitpodDaemonsetPorts.wsDaemon} ${this.options.previewName} ${this.options.smithToken}`,
            { slice: slice },
        );
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
