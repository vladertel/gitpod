// Copyright (c) 2022 Gitpod GmbH. All rights reserved.
// Licensed under the GNU Affero General Public License (AGPL).
// See License-AGPL.txt in the project root for license information.

package k8s

import (
	"bytes"
	"context"
	"fmt"
	"k8s.io/client-go/tools/portforward"
	"k8s.io/client-go/transport/spdy"
	"net/http"
	"net/url"
	"strings"

	"github.com/cockroachdb/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/tools/clientcmd/api"
)

type harvester interface {
	GetHarvesterKubeConfig(ctx context.Context) (*api.Config, error)
}

type harvesterPreview interface {
	PortForward(ctx context.Context) error
}

var (
	ErrSecretDataNotFound = errors.New("secret data not found")
)

const (
	harvesterConfigSecretName = "harvester-kubeconfig"
	werftNamespace            = "werft"
)

func (c *Config) GetHarvesterKubeConfig(ctx context.Context) (*api.Config, error) {
	secret, err := c.coreClient.CoreV1().Secrets(werftNamespace).Get(ctx, harvesterConfigSecretName, metav1.GetOptions{})
	if err != nil {
		return nil, err
	}

	if _, ok := secret.Data["harvester-kubeconfig.yml"]; !ok {
		return nil, ErrSecretDataNotFound
	}

	config, err := clientcmd.Load(secret.Data["harvester-kubeconfig.yml"])
	if err != nil {
		return nil, err
	}

	return RenameContext(config, "default", "harvester")
}

func (c *Config) PortForward(ctx context.Context, name, port string) error {
	roundTripper, upgrader, err := spdy.RoundTripperFor(c.config)
	if err != nil {
		panic(err)
	}

	path := fmt.Sprintf("/api/v1/namespaces/%s/services/%s/portforward", "default", name)
	hostIP := strings.TrimLeft(c.config.Host, "https:/")
	serverURL := url.URL{Scheme: "https", Path: path, Host: hostIP}

	dialer := spdy.NewDialer(upgrader, &http.Client{Transport: roundTripper}, http.MethodPost, &serverURL)

	stopChan, readyChan := make(chan struct{}, 1), make(chan struct{}, 1)
	out, errOut := new(bytes.Buffer), new(bytes.Buffer)

	forwarder, err := portforward.New(dialer, []string{port}, stopChan, readyChan, out, errOut)
	if err != nil {
		panic(err)
	}

	go func() {
		for range readyChan { // Kubernetes will close this channel when it has something to tell us.
		}
		if len(errOut.String()) != 0 {
			panic(errOut.String())
		} else if len(out.String()) != 0 {
			fmt.Println(out.String())
		}
	}()

	if err = forwarder.ForwardPorts(); err != nil { // Locks until stopChan is closed.
		panic(err)
	}

	return nil
}
