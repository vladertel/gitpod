// Copyright (c) 2022 Gitpod GmbH. All rights reserved.
// Licensed under the GNU Affero General Public License (AGPL).
// See License-AGPL.txt in the project root for license information.

package k8s

import (
	"context"
	"strings"

	"github.com/cockroachdb/errors"
	"github.com/sirupsen/logrus"
	authorizationv1 "k8s.io/api/authorization/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/tools/clientcmd/api"
)

var (
	ErrContextNotExists = errors.New("context doesn't exist")
)

type Config struct {
	harvester
	harvesterPreview

	coreClient    kubernetes.Interface
	dynamicClient dynamic.Interface
	config        *rest.Config

	logger *logrus.Logger
}

func NewWithConfig(logger *logrus.Logger, config *rest.Config) (*Config, error) {
	coreClient := kubernetes.NewForConfigOrDie(config)
	dynamicClient := dynamic.NewForConfigOrDie(config)

	return &Config{
		coreClient:    coreClient,
		dynamicClient: dynamicClient,
		logger:        logger,
		config:        config,
	}, nil
}

func NewFromDefaultConfigWithContext(logger *logrus.Logger, contextName string) (*Config, error) {
	kconf, err := GetKubernetesConfigFromContext(contextName)
	if err != nil {
		return nil, errors.Wrapf(err, "couldn't get [%s] kube context", contextName)
	}

	coreClient := kubernetes.NewForConfigOrDie(kconf)
	dynamicClient := dynamic.NewForConfigOrDie(kconf)

	return &Config{
		coreClient:    coreClient,
		dynamicClient: dynamicClient,
		logger:        logger,
		config:        kconf,
	}, nil
}

func GetClientConfigFromContext(context string) (*api.Config, error) {
	configLoadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
	configOverrides := &clientcmd.ConfigOverrides{CurrentContext: context}

	config, err := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(configLoadingRules, configOverrides).RawConfig()
	if err != nil {
		return nil, err
	}

	if _, ok := config.Contexts[context]; !ok {
		return nil, ErrContextNotExists
	}

	return &config, err
}

func GetKubernetesConfigFromContext(context string) (*rest.Config, error) {
	configLoadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
	configOverrides := &clientcmd.ConfigOverrides{CurrentContext: context}

	kconf, err := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(configLoadingRules, configOverrides).ClientConfig()
	if err != nil {
		if strings.Contains(err.Error(), "does not exist") {
			return nil, errors.Mark(err, ErrContextNotExists)
		}
		return nil, err
	}

	return kconf, err
}

func (c *Config) HasAccess() bool {
	sar := &authorizationv1.SelfSubjectAccessReview{
		Spec: authorizationv1.SelfSubjectAccessReviewSpec{
			ResourceAttributes: &authorizationv1.ResourceAttributes{
				Namespace: "default",
				Verb:      "get",
				Group:     "secrets",
			},
		},
	}

	_, err := c.coreClient.AuthorizationV1().SelfSubjectAccessReviews().Create(context.TODO(), sar, metav1.CreateOptions{})
	if err != nil {
		c.logger.Error(err)
		return false
	}

	return true
}
