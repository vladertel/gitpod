// Copyright (c) 2022 Gitpod GmbH. All rights reserved.
// Licensed under the GNU Affero General Public License (AGPL).
// See License-AGPL.txt in the project root for license information.

package cmd

import (
	"time"

	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"

	"github.com/gitpod-io/gitpod/previewctl/pkg/preview"
)

type installContextOpts struct {
	logger *logrus.Logger

	watch              bool
	kubeConfigSavePath string
	timeout            time.Duration
}

func newInstallContextCmd(logger *logrus.Logger) *cobra.Command {
	opts := installContextOpts{
		logger: logger,
	}

	// Used to ensure that we only install contexts
	var lastSuccessfulPreviewEnvironment *preview.Preview = nil

	install := func(timeout time.Duration) error {
		p, err := preview.New(branch, logger)

		if err != nil {
			return err
		}

		if lastSuccessfulPreviewEnvironment != nil && lastSuccessfulPreviewEnvironment.Same(p) {
			logger.Infof("The preview envrionment hasn't changed")
			return nil
		}

		err = p.InstallContext(opts.watch, opts.timeout, opts.kubeConfigSavePath)
		if err == nil {
			lastSuccessfulPreviewEnvironment = p
		}

		return err
	}

	cmd := &cobra.Command{
		Use:   "install-context",
		Short: "Installs the kubectl context of a preview environment.",
		PreRunE: func(cmd *cobra.Command, args []string) error {
			// TODO fix: this is a bit of a hack to call the get-credentials command before install-context
			// ideally we should get the (dev,harvester) contexts and merge with the k3s context at the end, and not call the command directly
			// we only run this if we specify a path to save the context to, as otherwise it would get output twice
			if opts.kubeConfigSavePath != "" {
				return newGetCredentialsCommand(logger).Execute()
			}

			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			if opts.watch {
				for range time.Tick(15 * time.Second) {
					// We're using a short timeout here to handle the scenario where someone switches
					// to a branch that doens't have a preview envrionment. In that case the default
					// timeout would mean that we would block for 10 minutes, potentially missing
					// if the user changes to a new branch that does that a preview.
					err := install(30 * time.Second)
					if err != nil {
						logger.WithFields(logrus.Fields{"err": err}).Info("Failed to install context. Trying again soon.")
					}
				}
			} else {
				return install(opts.timeout)
			}

			return nil
		},
	}

	cmd.Flags().BoolVar(&opts.watch, "watch", false, "If watch is enabled, previewctl will keep trying to install the kube-context every 15 seconds.")
	cmd.Flags().DurationVarP(&opts.timeout, "timeout", "t", 10*time.Minute, "Timeout before considering the installation failed")
	cmd.PersistentFlags().StringVar(&opts.kubeConfigSavePath, "kube-save-path", "", "path to save the generated kubeconfig to")

	return cmd
}
