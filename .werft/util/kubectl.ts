import { exec, ExecOptions, ExecResult } from "./shell";
import { sleep } from "./util";
import { getGlobalWerftInstance } from "./werft";

export const IS_PREVIEW_APP_LABEL: string = "isPreviewApp";

export function setKubectlContextNamespace(namespace: string, shellOpts: ExecOptions) {
    [`kubectl config current-context`, `kubectl config set-context --current --namespace=${namespace}`].forEach((cmd) =>
        exec(cmd, shellOpts),
    );
}

export async function wipePreviewEnvironmentAndNamespace(
    namespace: string,
    kubeconfig: string,
    shellOpts: ExecOptions,
) {
    const werft = getGlobalWerftInstance();

    // wipe preview envs built with installer
    await wipePreviewEnvironmentInstaller(namespace, kubeconfig, shellOpts);

    deleteAllWorkspaces(namespace, kubeconfig, shellOpts);

    await deleteAllUnnamespacedObjects(namespace, kubeconfig, shellOpts);

    deleteNamespace(true, namespace, kubeconfig, shellOpts);
    werft.done(shellOpts.slice);
}

export async function wipeAndRecreateNamespace(
    namespace: string,
    kubeconfig: string,
    shellOpts: ExecOptions,
) {
    await wipePreviewEnvironmentAndNamespace(namespace, kubeconfig, shellOpts);

    createNamespace(namespace, kubeconfig, shellOpts);
}

async function wipePreviewEnvironmentInstaller(namespace: string, kubeconfig: string, shellOpts: ExecOptions) {
    const slice = shellOpts.slice || "installer";
    const werft = getGlobalWerftInstance();

    const hasGitpodConfigmap =
        exec(`kubectl --kubeconfig ${kubeconfig} -n ${namespace} get configmap gitpod-app`, {
            slice,
            dontCheckRc: true,
        }).code === 0;
    if (hasGitpodConfigmap) {
        werft.log(slice, `${namespace} has Gitpod configmap, proceeding with removal`);
        exec(`./util/uninstall-gitpod.sh ${namespace} ${kubeconfig}`, { slice });
    } else {
        werft.log(slice, `There is no Gitpod configmap, moving on`);
    }
}

// Delete pods for running workspaces, even if they are stuck in terminating because of the finalizer decorator
function deleteAllWorkspaces(namespace: string, kubecofig: string, shellOpts: ExecOptions) {
    const objs = exec(
        `kubectl --kubeconfig ${kubecofig} get pod -l component=workspace --namespace ${namespace} --no-headers -o=custom-columns=:metadata.name`,
        { ...shellOpts, async: false },
    )
        .split("\n")
        .map((o) => o.trim())
        .filter((o) => o.length > 0);

    objs.forEach((o) => {
        try {
            // In most cases the calls below fails because the workspace is already gone. Ignore those cases, log others.
            exec(
                `kubectl --kubeconfig ${kubecofig} patch pod --namespace ${namespace} ${o} -p '{"metadata":{"finalizers":null}}'`,
                { ...shellOpts },
            );
            const result = exec(
                `kubectl --kubeconfig ${kubecofig} delete pod --namespace ${namespace} ${o} --ignore-not-found=true --timeout=10s`,
                { ...shellOpts, async: false, dontCheckRc: true },
            );
            if (result.code !== 0) {
                // We hit a timeout, and have no clue why. Manually re-trying has shown to consistenly being not helpful, either. Thus use THE FORCE.
                exec(
                    `kubectl --kubeconfig ${kubecofig} delete pod --namespace ${namespace} ${o} --ignore-not-found=true --force`,
                    { ...shellOpts },
                );
            }
        } catch (err) {
            const result = exec(`kubectl --kubeconfig ${kubecofig} get pod --namespace ${namespace} ${o}`, {
                ...shellOpts,
                dontCheckRc: true,
                async: false,
            });
            if (result.code === 0) {
                console.error(`unable to patch/delete ${o} but it's still on the dataplane`);
            }
        }
    });
}

// deleteAllUnnamespacedObjects deletes all unnamespaced objects for the given namespace
async function deleteAllUnnamespacedObjects(
    namespace: string,
    kubeconfig: string,
    shellOpts: ExecOptions,
): Promise<void> {
    const werft = getGlobalWerftInstance();
    const slice = shellOpts.slice || "deleteobjs";

    const promisedDeletes: Promise<any>[] = [];
    for (const resType of ["clusterrole", "clusterrolebinding", "podsecuritypolicy"]) {
        werft.log(slice, `Searching and filtering ${resType}s...`);
        const objs = exec(
            `kubectl --kubeconfig ${kubeconfig} get ${resType} --no-headers -o=custom-columns=:metadata.name`,
            { ...shellOpts, slice, async: false },
        )
            .split("\n")
            .map((o) => o.trim())
            .filter((o) => o.length > 0)
            .filter((o) => o.startsWith(`${namespace}-ns-`)); // "{{ .Release.Namespace }}-ns-" is the prefix-pattern we use throughout our helm resources for un-namespaced resources

        werft.log(slice, `Deleting old ${resType}s...`);
        for (const obj of objs) {
            promisedDeletes.push(
                exec(`kubectl --kubeconfig ${kubeconfig} delete ${resType} ${obj}`, {
                    ...shellOpts,
                    slice,
                    async: true,
                }) as Promise<any>,
            );
        }
    }
    await Promise.all(promisedDeletes);
}

export function createNamespace(namespace: string, kubeconfig: string, shellOpts: ExecOptions) {
    const result = exec(`kubectl --kubeconfig ${kubeconfig} get namespace ${namespace}`, {
        ...shellOpts,
        dontCheckRc: true,
        async: false,
    });
    const exists = result.code === 0;
    if (exists) {
        return;
    }

    // (re-)create namespace
    [
        `kubectl --kubeconfig ${kubeconfig} create namespace ${namespace}`,
        `kubectl --kubeconfig ${kubeconfig} patch namespace ${namespace} --patch '{"metadata": {"labels": {"${IS_PREVIEW_APP_LABEL}": "true"}}}'`,
    ].forEach((cmd) => exec(cmd, shellOpts));
}

export function listAllPreviewNamespaces(kubeconfig: string, shellOpts: ExecOptions): string[] {
    return exec(
        `kubectl --kubeconfig ${kubeconfig} get namespaces -l ${IS_PREVIEW_APP_LABEL}=true -o=custom-columns=:metadata.name`,
        { ...shellOpts, silent: true, async: false },
    )
        .stdout.split("\n")
        .map((o) => o.trim())
        .filter((o) => o.length > 0);
}

export function deleteNamespace(wait: boolean, namespace: string, kubeconfig: string, shellOpts: ExecOptions) {
    // check if present
    const result = exec(`kubectl --kubeconfig ${kubeconfig} get namespace ${namespace}`, {
        ...shellOpts,
        dontCheckRc: true,
        async: false,
    });
    if (result.code !== 0) {
        return;
    }

    const cmd = `kubectl --kubeconfig ${kubeconfig} delete namespace ${namespace}`;
    exec(cmd, shellOpts);

    // wait until deletion was successful
    while (wait) {
        const result = exec(`kubectl --kubeconfig ${kubeconfig} get namespace ${namespace}`, {
            ...shellOpts,
            dontCheckRc: true,
            async: false,
        });
        wait = result.code === 0;
    }
}

export function waitForDeploymentToSucceed(
    name: string,
    namespace: string,
    type: string,
    kubeconfig: string,
    shellOpts: ExecOptions,
) {
    exec(`kubectl --kubeconfig ${kubeconfig} rollout status ${type} ${name} -n ${namespace}`, shellOpts);
}

export async function waitForApiserver(kubeconfig: string, shellOpts: ExecOptions) {
    const werft = getGlobalWerftInstance();
    for (let i = 0; i < 300; i++) {
        werft.log(shellOpts.slice, "Checking that k3s apiserver is ready...");
        const result = exec(`kubectl --kubeconfig ${kubeconfig} get --raw='/readyz?verbose'`, {
            ...shellOpts,
            dontCheckRc: true,
            async: false,
        });
        if (result.code == 0) {
            werft.log(shellOpts.slice, "k3s apiserver is ready");
            return;
        }
        await sleep(2 * 1000);
    }
    throw new Error(`The Apiserver did not become ready during the expected time.`);
}
