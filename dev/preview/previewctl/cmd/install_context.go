// Copyright (c) 2022 Gitpod GmbH. All rights reserved.
// Licensed under the GNU Affero General Public License (AGPL).
// See License-AGPL.txt in the project root for license information.

package cmd

import (
	"context"
	"github.com/gitpod-io/gitpod/previewctl/pkg/preview"
	"time"

	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

var (
	watch   bool
	timeout time.Duration
)

type installContextOpts struct {
	logger *logrus.Logger

	watch              bool
	kubeConfigSavePath string
	timeout            time.Duration
}

func installContextCmd(logger *logrus.Logger) *cobra.Command {
	ctx := context.Background()
	opts := installContextOpts{
		logger: logger,
	}

	cmd := &cobra.Command{
		Use:   "install-context",
		Short: "Installs the kubectl context of a preview environment.",
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {

			return nil
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			p, err := preview.New(branch, logger)
			if err != nil {
				return err
			}

			return p.Install(ctx)
			//k, err := k8s.NewFromDefaultConfigWithContext(logger, "harvester")
			//if err != nil {
			//	return err
			//}
			//
			//previewName, err := preview.GetName("")
			//if err != nil {
			//	return err
			//}
			//
			//stopChan, readyChan := make(chan struct{}, 1), make(chan struct{}, 1)
			//
			//go func() {
			//	err := k.PortForward(context.Background(), previewName, fmt.Sprintf("preview-%s", previewName), []string{"2200"}, stopChan, readyChan)
			//	if err != nil {
			//		logrus.Fatal(err)
			//		return
			//	}
			//}()
			//
			//// block until port-forward is ready
			//<-readyChan
			//
			//cfgGet, err := ssh.NewK3SConfigGetter(ctx, "127.0.0.1", "2200")
			//if err != nil {
			//	return err
			//}
			//
			//kube, err := cfgGet.GetK3SContext(ctx)
			//if err != nil {
			//	return err
			//}
			//
			////c, _ := clientcmd.Write(*kube)
			////fmt.Println(string(c))
			//
			//k3sConfig, err := k8s.RenameConfig(kube, "default", previewName)
			//if err != nil {
			//	return err
			//}
			//
			//k3sConfig.Clusters[previewName].Server = fmt.Sprintf("https://%s.kube.gitpod-dev.com:6443", previewName)
			//
			//fmt.Println("========================================================================")
			//c, _ = clientcmd.Write(*k3sConfig)
			//fmt.Println(string(c))
			//
			return nil
			//return MergeContexts(opts.kubeConfigSavePath, k3sConfig)
		},
	}

	cmd.Flags().BoolVar(&opts.watch, "watch", false, "If watch is enabled, previewctl will keep trying to install the kube-context every 15 seconds.")
	cmd.Flags().DurationVarP(&opts.timeout, "timeout", "t", 10*time.Minute, "Timeout before considering the installation failed")
	cmd.PersistentFlags().StringVar(&opts.kubeConfigSavePath, "kube-save-path", "", "path to save the generated kubeconfig to")

	return cmd
}

//func installContextCmd(logger *logrus.Logger) *cobra.Command {
//
//	// Used to ensure that we only install contexts
//	var lastSuccessfulPreviewEnvironment *preview.Preview = nil
//
//	install := func(timeout time.Duration) error {
//		p, err := preview.New(branch, logger)
//
//		if err != nil {
//			return err
//		}
//
//		if lastSuccessfulPreviewEnvironment != nil && lastSuccessfulPreviewEnvironment.Same(p) {
//			logger.Infof("The preview envrionment hasn't changed")
//			return nil
//		}
//
//		err = p.InstallContext(true, timeout)
//		if err == nil {
//			lastSuccessfulPreviewEnvironment = p
//		}
//		return err
//	}
//
//	cmd := &cobra.Command{
//		Use:   "install-context",
//		Short: "Installs the kubectl context of a preview environment.",
//		RunE: func(cmd *cobra.Command, args []string) error {
//
//			if watch {
//				for range time.Tick(15 * time.Second) {
//					// We're using a short timeout here to handle the scenario where someone switches
//					// to a branch that doens't have a preview envrionment. In that case the default
//					// timeout would mean that we would block for 10 minutes, potentially missing
//					// if the user changes to a new branch that does that a preview.
//					err := install(30 * time.Second)
//					if err != nil {
//						logger.WithFields(logrus.Fields{"err": err}).Info("Failed to install context. Trying again soon.")
//					}
//				}
//			} else {
//				return install(timeout)
//			}
//
//			return nil
//		},
//	}
//
//	cmd.Flags().BoolVar(&watch, "watch", false, "If watch is enabled, previewctl will keep trying to install the kube-context every 15 seconds.")
//	cmd.Flags().DurationVarP(&timeout, "timeout", "t", 10*time.Minute, "Timeout before considering the installation failed")
//	return cmd
//}
