package ssh

import (
	"context"
	"io"
	"k8s.io/apimachinery/pkg/runtime"
	"testing"

	"github.com/cockroachdb/errors"
	"github.com/stretchr/testify/assert"
	"k8s.io/client-go/tools/clientcmd/api"
)

func Test_GetK3SContext(t *testing.T) {
	type k3sExpStruct struct {
		config *api.Config
		err    error
	}
	type testCase struct {
		name     string
		cmd      mockCommand
		expected *k3sExpStruct
	}

	testCases := []testCase{
		{
			name: "k3s config not found",
			cmd: mockCommand{
				cmd:    catK3sConfigCmd,
				stdout: []byte(""),
				stderr: []byte("cat: /etc/rancher/k3s/k3s.yaml: No such file or directory"),
				err:    errors.New("some error that will be irrelevant"),
			},
			expected: &k3sExpStruct{
				config: nil,
				err:    ErrK3SConfigNotFound,
			},
		},
		{
			name: "returned config",
			cmd: mockCommand{
				cmd: catK3sConfigCmd,
				stdout: []byte(`
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: dGVzdF9kYXRh
    server: https://test.kube.gitpod-dev.com:6443
  name: test
contexts:
- context:
    cluster: test
    user: test
  name: test
current-context: test
kind: Config
preferences: {}
users:
- name: test
  user:
    client-certificate-data: dGVzdF9kYXRh
    client-key-data: dGVzdF9kYXRh
`),
				stderr: nil,
				err:    nil,
			},
			expected: &k3sExpStruct{
				config: &api.Config{
					Preferences: api.Preferences{
						Extensions: map[string]runtime.Object{},
					},
					Contexts: map[string]*api.Context{
						"test": {
							Cluster:    "test",
							AuthInfo:   "test",
							Extensions: map[string]runtime.Object{},
						},
					},
					Clusters: map[string]*api.Cluster{
						"test": {
							LocationOfOrigin:         "",
							Server:                   "https://test.kube.gitpod-dev.com:6443",
							CertificateAuthorityData: []byte("test_data"),
							Extensions:               map[string]runtime.Object{},
						},
					},
					CurrentContext: "test",
					AuthInfos: map[string]*api.AuthInfo{
						"test": {
							ClientCertificateData: []byte("test_data"),
							ClientKeyData:         []byte("test_data"),
							Extensions:            map[string]runtime.Object{},
						},
					},
					Extensions: map[string]runtime.Object{},
				},
				err: nil,
			},
		},
	}

	for _, test := range testCases {
		c := &mocksshClient{command: test.cmd}
		k := &K3SConfigGetter{client: c}

		config, err := k.GetK3SContext(context.TODO())

		assert.ErrorIs(t, err, test.expected.err)
		assert.Equal(t, config, test.expected.config)
	}
}

var _ sshClient = &mocksshClient{}

type mockCommand struct {
	cmd    string
	stdout []byte
	stderr []byte
	err    error
}

type mocksshClient struct {
	command mockCommand
}

func (m mocksshClient) Close() error {
	return nil
}

func (m mocksshClient) Run(ctx context.Context, cmd string, stdout io.Writer, stderr io.Writer) error {
	if m.command.cmd != cmd {
		return errors.New("command not found")
	}

	_, _ = stdout.Write(m.command.stdout)
	_, _ = stderr.Write(m.command.stderr)
	return m.command.err
}
