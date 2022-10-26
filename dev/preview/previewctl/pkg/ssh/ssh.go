package ssh

import (
	"bytes"
	"context"
	"fmt"
	"golang.org/x/crypto/ssh"
	"os"
)

const (
	k3sConfigPath = "/etc/rancher/k3s/k3s.yaml"
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

	fmt.Println(config)

	return config, nil
}

func (k *K3SConfigGetter) connectToHost(ctx context.Context, host, port string) (sshClient, error) {
	return k.sshClientFactory.Dial(ctx, host, port)
}

func (k *K3SConfigGetter) Close() error {
	return k.client.Close()
}

func (k *K3SConfigGetter) GetK3SContext(ctx context.Context) (string, error) {
	stdout := new(bytes.Buffer)
	stderr := new(bytes.Buffer)

	err := k.client.Exec(ctx, "sudo cat /etc/rancher/k3s/k3s.yaml", stdout, stderr)
	if err != nil {
		return "", err
	}

	return stdout.String(), nil
}
