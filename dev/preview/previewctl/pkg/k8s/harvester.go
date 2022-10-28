// Copyright (c) 2022 Gitpod GmbH. All rights reserved.
// Licensed under the GNU Affero General Public License (AGPL).
// See License-AGPL.txt in the project root for license information.

package k8s

import (
	"bytes"
	"context"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"github.com/cockroachdb/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/tools/clientcmd/api"
	"k8s.io/client-go/tools/portforward"
	"k8s.io/client-go/transport/spdy"
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

	return RenameConfig(config, "default", "harvester")
}

func (c *Config) getVMPodName(ctx context.Context, name, namespace string) (string, error) {
	// TODO replace this with a call to SVC.Proxy and get the pod name from there
	labelSelector := metav1.LabelSelector{
		MatchLabels: map[string]string{
			"harvesterhci.io/vmName": name,
		},
	}

	pods, err := c.coreClient.CoreV1().Pods(namespace).List(ctx, metav1.ListOptions{
		LabelSelector: labels.Set(labelSelector.MatchLabels).String(),
	})

	if err != nil {
		return "", err
	}

	if len(pods.Items) != 1 {
		return "", errors.Newf("expected a single pod, got [%d]", len(pods.Items))
	}

	return pods.Items[0].Name, nil
}

type PortForwardOpts struct {
	Name                string
	Namespace           string
	Ports               []string
	ReadyChan, StopChan chan struct{}
	ErrChan             chan error
}

func (c *Config) PortForward(ctx context.Context, opts PortForwardOpts) error {
	roundTripper, upgrader, err := spdy.RoundTripperFor(c.config)
	if err != nil {
		panic(err)
	}

	podName, err := c.getVMPodName(ctx, opts.Name, opts.Namespace)
	if err != nil {
		return err
	}

	path := fmt.Sprintf("/api/v1/namespaces/%s/pods/%s/portforward", opts.Namespace, podName)
	hostIP := strings.TrimLeft(c.config.Host, "https://")
	serverURL := url.URL{Scheme: "https", Path: path, Host: hostIP}

	dialer := spdy.NewDialer(upgrader, &http.Client{Transport: roundTripper}, http.MethodPost, &serverURL)

	out, errOut := new(bytes.Buffer), new(bytes.Buffer)
	forwarder, err := portforward.New(dialer, opts.Ports, opts.StopChan, opts.ReadyChan, out, errOut)
	if err != nil {
		return err
	}

	go func() {
		for range opts.StopChan { // Kubernetes will close this channel when it has something to tell us.
		}
		if len(errOut.String()) != 0 {
			opts.ErrChan <- errors.New(errOut.String())
		} else if len(out.String()) != 0 {
			c.logger.Debug(out.String())
		}
	}()

	if err = forwarder.ForwardPorts(); err != nil { // Locks until stopChan is closed.
		return err
	}

	return nil
}
