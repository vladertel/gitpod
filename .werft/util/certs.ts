import {exec, execStream} from "./shell";
import {
    CORE_DEV_KUBECONFIG_PATH,
    GCLOUD_SERVICE_ACCOUNT_PATH,
    GLOBAL_KUBECONFIG_PATH,
} from "../jobs/build/const";
import { Werft } from "./werft";
import { reportCertificateError } from "../util/slack";
import {JobConfig} from "../jobs/build/job-config";

export async function certReady(werft: Werft, config: JobConfig, slice: string): Promise<boolean> {
    const certName = `harvester-${config.previewEnvironment.destname}`;
    const cpu = config.withLargeVM ? 12 : 6;
    const memory = config.withLargeVM ? 24 : 12;

    // set some common vars for TF
    // We pass the GCP credentials explicitly, otherwise for some reason TF doesn't pick them up
    const commonVars = `GOOGLE_BACKEND_CREDENTIALS=${GCLOUD_SERVICE_ACCOUNT_PATH} \
                        GOOGLE_APPLICATION_CREDENTIALS=${GCLOUD_SERVICE_ACCOUNT_PATH} \
                        TF_VAR_cert_issuer=${config.certIssuer} \
                        TF_VAR_kubeconfig_path=${GLOBAL_KUBECONFIG_PATH} \
                        TF_VAR_preview_name=${config.previewEnvironment.destname} \
                        TF_VAR_vm_cpu=${cpu} \
                        TF_VAR_vm_memory=${memory}Gi \
                        TF_VAR_vm_storage_class="longhorn-gitpod-k3s-202209251218-onereplica"`

    if (isCertReady(certName)){
        werft.log(slice, `Certificate ready`);
        return true
    }

    const maxAttempts = 5
    var certReady = false
    for (var i = 1;i<=maxAttempts;i++) {
        werft.log(slice, `Checking for cert readiness: Attempt ${i}`);
        if (waitCertReady(certName)) {
            certReady = true;
            break;
        }

        werft.log(slice, `Creating cert: Attempt ${i}`);
        await execStream(`${commonVars} \
                        TF_CLI_ARGS_plan="-replace=kubernetes_manifest.cert" \
                        ./dev/preview/workflow/preview/deploy-harvester.sh`,
            {slice: slice})
    }

    if (!certReady) {
        retrieveFailedCertDebug(certName, slice)
        werft.fail(slice, `Certificate ${certName} never reached the Ready state`)
    }

    return certReady
}

function waitCertReady(certName: string): boolean {
    const timeout = "240s"
    const rc = exec(
        `kubectl --kubeconfig ${CORE_DEV_KUBECONFIG_PATH} wait --for=condition=Ready --timeout=${timeout} -n certs certificate ${certName}`,
        { dontCheckRc: true },
    ).code
    return rc == 0
}

function isCertReady(certName: string): boolean {
    const output = exec(
        `kubectl --kubeconfig ${CORE_DEV_KUBECONFIG_PATH} -n certs get certificate ${certName} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'`,
        { dontCheckRc: true }
    ).stdout.trim();

    return output == "True";
}

function retrieveFailedCertDebug(certName: string, slice: string) {
    const certificateYAML = exec(
        `kubectl --kubeconfig ${CORE_DEV_KUBECONFIG_PATH} -n certs get certificate ${certName} -o yaml`,
        { silent: true },
    ).stdout.trim();
    const certificateDebug = exec(`KUBECONFIG=${CORE_DEV_KUBECONFIG_PATH} cmctl status certificate ${certName} -n certs`);

    reportCertificateError({ certificateName: certName, certifiateYAML: certificateYAML, certificateDebug: certificateDebug }).catch((error: Error) =>
        console.error("Failed to send message to Slack", error),
    );
}
