// Copyright (c) 2022 Gitpod GmbH. All rights reserved.
// Licensed under the GNU Affero General Public License (AGPL).
// See License-AGPL.txt in the project root for license information.

package preview

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"math/rand"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/cockroachdb/errors"
	"github.com/sirupsen/logrus"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/tools/clientcmd/api"

	"github.com/gitpod-io/gitpod/previewctl/pkg/k8s"
	"github.com/gitpod-io/gitpod/previewctl/pkg/ssh"
)

var (
	ErrBranchNotExist = errors.New("branch doesn't exist")
)

const harvesterContextName = "harvester"

type Preview struct {
	branch       string
	name         string
	namespace    string
	kubeSavePath string

	harvesterClient *k8s.Config

	logger *logrus.Entry

	vmiCreationTime *metav1.Time
}

func New(branch string, logger *logrus.Logger) (*Preview, error) {
	branch, err := GetName(branch)
	if err != nil {
		return nil, err
	}

	logEntry := logger.WithFields(logrus.Fields{"branch": branch})

	harvesterConfig, err := k8s.NewFromDefaultConfigWithContext(logEntry.Logger, harvesterContextName)
	if err != nil {
		return nil, errors.Wrap(err, "couldn't instantiate a k8s config")
	}

	return &Preview{
		branch:          branch,
		namespace:       fmt.Sprintf("preview-%s", branch),
		name:            branch,
		harvesterClient: harvesterConfig,
		logger:          logEntry,
		vmiCreationTime: nil,
	}, nil
}

type InstallCtxOpts struct {
	Wait              bool
	Timeout           time.Duration
	KubeSavePath      string
	SSHPrivateKeyPath string
}

func (p *Preview) InstallContext(ctx context.Context, opts InstallCtxOpts) error {
	ctx, cancel := context.WithTimeout(ctx, opts.Timeout)
	defer cancel()

	p.logger.WithFields(logrus.Fields{"timeout": opts.Timeout}).Debug("Installing context")

	// we use this channel to signal when we've found an event in wait functions, so we know when we're done
	doneCh := make(chan struct{})
	defer close(doneCh)

	// TODO: fix this, as it's a bit ugly
	err := p.harvesterClient.GetVMStatus(ctx, p.name, p.namespace)
	if err != nil && !errors.Is(err, k8s.ErrVmNotReady) {
		return err
	} else if errors.Is(err, k8s.ErrVmNotReady) && !opts.Wait {
		return err
	} else if errors.Is(err, k8s.ErrVmNotReady) && opts.Wait {
		err = p.harvesterClient.WaitVMReady(ctx, p.name, p.namespace, doneCh)
		if err != nil {
			return err
		}
	}

	err = p.harvesterClient.GetProxyVMServiceStatus(ctx, p.namespace)
	if err != nil && !errors.Is(err, k8s.ErrSvcNotReady) {
		return err
	} else if errors.Is(err, k8s.ErrSvcNotReady) && !opts.Wait {
		return err
	} else if errors.Is(err, k8s.ErrSvcNotReady) && opts.Wait {
		err = p.harvesterClient.WaitProxySvcReady(ctx, p.namespace, doneCh)
		if err != nil {
			return err
		}
	}

	if opts.Wait {
		for {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.Tick(5 * time.Second):
				p.logger.Infof("waiting for context install to succeed")
				err = p.Install(ctx, opts)
				if err == nil {
					p.logger.Infof("Successfully installed context")
					return nil
				}
			}
		}
	}

	return p.Install(ctx, opts)
}

// Same compares two preview envrionments
//
// Preview environments are considered the same if they are based on the same underlying
// branch and the VM hasn't changed.
func (p *Preview) Same(newPreview *Preview) bool {
	sameBranch := p.branch == newPreview.branch
	if !sameBranch {
		return false
	}

	ensureVMICreationTime(p)
	ensureVMICreationTime(newPreview)

	return p.vmiCreationTime.Equal(newPreview.vmiCreationTime)
}

func ensureVMICreationTime(p *Preview) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if p.vmiCreationTime == nil {
		creationTime, err := p.harvesterClient.GetVMICreationTimestamp(ctx, p.name, p.namespace)
		p.vmiCreationTime = creationTime
		if err != nil {
			p.logger.WithFields(logrus.Fields{"err": err}).Infof("Failed to get creation time")
		}
	}
}

func (p *Preview) Install(ctx context.Context, opts InstallCtxOpts) error {
	cfg, err := p.GetPreviewContext(ctx, opts)
	if err != nil {
		return err
	}

	merged, err := k8s.MergeContextsWithDefault(cfg)
	if err != nil {
		return err
	}

	return k8s.OutputContext(opts.KubeSavePath, merged)
}

func (p *Preview) GetPreviewContext(ctx context.Context, opts InstallCtxOpts) (*api.Config, error) {
	stopChan, readyChan, errChan := make(chan struct{}, 1), make(chan struct{}, 1), make(chan error, 1)

	// pick a random port, so we avoid clashes if something else port-forwards to 2200
	randPort := strconv.Itoa(rand.Intn(2299-2201) + 2201)
	go func() {
		err := p.harvesterClient.PortForward(ctx, k8s.PortForwardOpts{
			Name:      p.name,
			Namespace: p.namespace,
			Ports: []string{
				fmt.Sprintf("%s:2200", randPort),
			},
			ReadyChan: readyChan,
			StopChan:  stopChan,
			ErrChan:   errChan,
		})
		if err != nil {
			errChan <- err
			return
		}
	}()

	select {
	case <-readyChan:
		cfgGet, err := ssh.NewK3SConfigGetter(ctx, ssh.K3SConfigGetterOpts{
			Host:              "127.0.0.1",
			Port:              randPort,
			SSHPrivateKeyPath: opts.SSHPrivateKeyPath,
		})
		if err != nil {
			return nil, err
		}

		kube, err := cfgGet.GetK3SContext(ctx)
		if err != nil {
			return nil, err
		}

		k3sConfig, err := k8s.RenameConfig(kube, "default", p.name)
		if err != nil {
			return nil, err
		}

		k3sConfig.Clusters[p.name].Server = fmt.Sprintf("https://%s.kube.gitpod-dev.com:6443", p.name)

		c, _ := clientcmd.Write(*k3sConfig)
		p.logger.Debugln(string(c))

		return k3sConfig, nil
	case err := <-errChan:
		return nil, err
	case <-time.After(time.Second * 2):
		return nil, errors.New("timed out waiting for port forward")
	case <-ctx.Done():
		p.logger.Debug("context cancelled")
		return nil, ctx.Err()
	}
}

func installContext(branch string) error {
	return exec.Command("bash", "/workspace/gitpod/dev/preview/install-k3s-kubeconfig.sh", "-b", branch).Run()
}

func SSHPreview(branch string) error {
	sshCommand := exec.Command("bash", "/workspace/gitpod/dev/preview/ssh-vm.sh", "-b", branch)

	// We need to bind standard output files to the command
	// otherwise 'previewctl' will exit as soon as the script is run.
	sshCommand.Stderr = os.Stderr
	sshCommand.Stdin = os.Stdin
	sshCommand.Stdout = os.Stdout

	return sshCommand.Run()
}

func branchFromGit(branch string) (string, error) {
	if branch == "" {
		out, err := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD").Output()
		if err != nil {
			return "", errors.Wrap(err, "Could not retrieve branch name.")
		}

		branch = string(out)
	} else {
		_, err := exec.Command("git", "rev-parse", "--verify", branch).Output()
		if err != nil {
			return "", errors.CombineErrors(err, ErrBranchNotExist)
		}
	}

	return branch, nil
}

func GetName(branch string) (string, error) {
	var err error
	if branch == "" {
		branch, err = branchFromGit(branch)
		if err != nil {
			return "", err
		}
	}

	branch = strings.TrimSpace(branch)
	withoutRefsHead := strings.Replace(branch, "/refs/heads/", "", 1)
	lowerCased := strings.ToLower(withoutRefsHead)

	var re = regexp.MustCompile(`[^-a-z0-9]`)
	sanitizedBranch := re.ReplaceAllString(lowerCased, `$1-$2`)

	if len(sanitizedBranch) > 20 {
		h := sha256.New()
		h.Write([]byte(sanitizedBranch))
		hashedBranch := hex.EncodeToString(h.Sum(nil))

		sanitizedBranch = sanitizedBranch[0:10] + hashedBranch[0:10]
	}

	return sanitizedBranch, nil
}

func (p *Preview) ListAllPreviews(ctx context.Context) error {
	previews, err := p.harvesterClient.GetVMs(ctx)
	if err != nil {
		return err
	}

	for _, preview := range previews {
		fmt.Printf("%v\n", preview)
	}

	return nil
}
