package ssh

import (
	"bytes"
	"context"
	"os"
	"strings"

	"github.com/cockroachdb/errors"
	"golang.org/x/crypto/ssh"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/tools/clientcmd/api"
)

const (
	k3sConfigPath   = "/etc/rancher/k3s/k3s.yaml"
	catK3sConfigCmd = "sudo cat /etc/rancher/k3s/k3s.yaml"
)

var (
	ErrK3SConfigNotFound = errors.New("k3s config file not found")
)

type K3SConfigGetter struct {
	sshClientFactory sshClientFactory
	client           sshClient

	configPath string
}

func NewK3SConfigGetter(ctx context.Context, host, port string) (*K3SConfigGetter, error) {
	var err error

	key, err := os.ReadFile("/Users/vlk/temp/vm-keys/pkey")
	if err != nil {
		return nil, err
	}

	signer, err := ssh.ParsePrivateKey(key)
	if err != nil {
		return nil, err
	}

	config := &K3SConfigGetter{
		sshClientFactory: &factoryImplementation{
			sshConfig: &ssh.ClientConfig{
				User: "ubuntu",
				Auth: []ssh.AuthMethod{
					ssh.PublicKeys(signer),
				},
				HostKeyCallback: ssh.InsecureIgnoreHostKey(),
			},
		},
		configPath: k3sConfigPath,
	}

	client, err := config.connectToHost(ctx, host, port)
	if err != nil {
		return nil, err
	}

	config.client = client

	return config, nil
}

func (k *K3SConfigGetter) GetK3SContext(ctx context.Context) (*api.Config, error) {
	stdout := new(bytes.Buffer)
	stderr := new(bytes.Buffer)

	err := k.client.Run(ctx, catK3sConfigCmd, stdout, stderr)
	if err != nil {
		if strings.Contains(stderr.String(), "No such file or directory") {
			return nil, ErrK3SConfigNotFound
		}

		return nil, errors.Wrap(err, stderr.String())
	}

	c, err := clientcmd.NewClientConfigFromBytes(stdout.Bytes())
	if err != nil {
		return nil, err
	}

	rc, err := c.RawConfig()
	if err != nil {
		return nil, err
	}

	return &rc, nil
}

func (k *K3SConfigGetter) connectToHost(ctx context.Context, host, port string) (sshClient, error) {
	return k.sshClientFactory.Dial(ctx, host, port)
}

func (k *K3SConfigGetter) Close() error {
	return k.client.Close()
}
