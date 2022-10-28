// Copyright (c) 2022 Gitpod GmbH. All rights reserved.
// Licensed under the GNU Affero General Public License (AGPL).
// See License-AGPL.txt in the project root for license information.

package cmd

import (
	"context"
	"fmt"
	"github.com/cockroachdb/errors"
	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/tools/clientcmd/api"

	"github.com/gitpod-io/gitpod/previewctl/pkg/gcloud"
	kube "github.com/gitpod-io/gitpod/previewctl/pkg/k8s"
)

const (
	coreDevClusterName        = "core-dev"
	coreDevProjectID          = "gitpod-core-dev"
	coreDevClusterZone        = "europe-west1-b"
	coreDevDesiredContextName = "dev"
	harvesterContextName      = "harvester"
)

type getCredentialsOpts struct {
	gcpClient *gcloud.Config
	logger    *logrus.Logger

	serviceAccountPath string
	kubeConfigSavePath string

	getCredentialsMap map[string]func(ctx context.Context) (*api.Config, error)
	configMap         map[string]*api.Config
}

func newGetCredentialsCommand(logger *logrus.Logger) *cobra.Command {
	ctx := context.Background()
	opts := &getCredentialsOpts{
		logger:    logger,
		configMap: map[string]*api.Config{},
	}

	cmd := &cobra.Command{
		Use: "get-credentials",
		Long: `previewctl get-credentials retrieves the kubernetes configs for core-dev and harvester clusters,
merges them with the default config, and outputs them either to stdout or to a file.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			configs, err := opts.getCredentials(ctx)
			if err != nil {
				return err
			}

			return kube.OutputContext(opts.kubeConfigSavePath, configs)
		},
	}

	cmd.PersistentFlags().StringVar(&opts.serviceAccountPath, "gcp-service-account", "", "path to the GCP service account to use")
	cmd.PersistentFlags().StringVar(&opts.kubeConfigSavePath, "kube-save-path", "", "path to save the generated kubeconfig to")

	return cmd
}

func (o *getCredentialsOpts) getCredentials(ctx context.Context) (*api.Config, error) {
	// TODO: fix this as it's a bit ugly
	var shouldRun bool
	for _, kc := range []string{coreDevDesiredContextName, harvesterContextName} {
		if ok := hasAccess(o.logger, kc); !ok {
			shouldRun = true
			break
		}
	}

	if !shouldRun {
		return kube.MergeContextsWithDefault()
	}

	client, err := gcloud.New(ctx, o.serviceAccountPath)
	if err != nil {
		return nil, err
	}

	o.gcpClient = client
	o.getCredentialsMap = map[string]func(ctx context.Context) (*api.Config, error){
		"dev":       o.getCoreDevKubeConfig,
		"harvester": o.getHarvesterKubeConfig,
	}

	configs := make([]*api.Config, 0)
	for _, kc := range []string{coreDevDesiredContextName, harvesterContextName} {
		config, err := o.getCredentialsMap[kc](ctx)
		if err != nil {
			return nil, err
		}

		o.configMap[kc] = config
		configs = append(configs, config)
	}

	return kube.MergeContextsWithDefault(configs...)
}

func hasAccess(logger *logrus.Logger, contextName string) bool {
	config, err := kube.NewFromDefaultConfigWithContext(logger, contextName)
	if err != nil {
		if errors.Is(err, kube.ErrContextNotExists) {
			return false
		}

		logger.Fatal(err)
	}

	return config.HasAccess()
}

func (o *getCredentialsOpts) getCoreDevKubeConfig(ctx context.Context) (*api.Config, error) {
	config, err := kube.GetClientConfigFromContext(coreDevDesiredContextName)
	if err == nil {
		return config, nil
	}

	coreDevConfig, err := o.gcpClient.GenerateConfig(ctx, coreDevClusterName, coreDevProjectID, coreDevClusterZone, coreDevDesiredContextName)
	if err != nil {
		return nil, err
	}

	return coreDevConfig, nil
}

func (o *getCredentialsOpts) getHarvesterKubeConfig(ctx context.Context) (*api.Config, error) {
	if _, ok := o.configMap[coreDevDesiredContextName]; !ok {
		config, err := o.getCoreDevKubeConfig(ctx)
		if err != nil {
			return nil, err
		}

		o.configMap[coreDevDesiredContextName] = config
	}

	fmt.Println("harvest")
	config, err := kube.GetClientConfigFromContext(harvesterContextName)
	if err == nil {
		return config, nil
	}
	fmt.Println("harvestEER")

	coreDevClientConfig, err := clientcmd.NewNonInteractiveClientConfig(*o.configMap[coreDevDesiredContextName], coreDevDesiredContextName, nil, nil).ClientConfig()
	if err != nil {
		return nil, err
	}

	kubeConfig, err := kube.NewWithConfig(o.logger, coreDevClientConfig)
	if err != nil {
		return nil, err
	}

	harvesterConfig, err := kubeConfig.GetHarvesterKubeConfig(ctx)
	if err != nil {
		return nil, err
	}

	return harvesterConfig, nil
}
