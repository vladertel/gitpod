package k8s

import (
	"fmt"

	"github.com/imdario/mergo"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/tools/clientcmd/api"
)

func RenameConfig(config *api.Config, oldName, newName string) (*api.Config, error) {
	// TODO add tests
	// TODO this is a bit long, should be possible to compress that function
	kubeCtx, exists := config.Contexts[oldName]
	if !exists {
		return nil, fmt.Errorf("cannot rename %q, it's not in the provided context", oldName)
	}

	if _, newExists := config.Contexts[newName]; newExists {
		return nil, fmt.Errorf("cannot rename %q, it already exists in the provided context", oldName)
	}

	kubeCtx.Cluster = newName
	kubeCtx.AuthInfo = newName
	config.Contexts[newName] = kubeCtx
	delete(config.Contexts, oldName)

	if config.CurrentContext == oldName {
		config.CurrentContext = newName
	}

	// we need to overwrite the cluster name and auth info
	// as otherwise another context might use the wrong cluster/auth (e.g. if they are called default)
	cluster, exists := config.Clusters[oldName]
	if !exists {
		return nil, fmt.Errorf("cannot rename %q, it's not in the provided context", oldName)
	}

	if _, newExists := config.Clusters[newName]; newExists {
		return nil, fmt.Errorf("cannot rename %q, it already exists in the provided context", oldName)
	}

	config.Clusters[newName] = cluster
	delete(config.Clusters, oldName)

	auth, exists := config.AuthInfos[oldName]
	if !exists {
		return nil, fmt.Errorf("cannot rename %q, it's not in the provided context", oldName)
	}

	if _, newExists := config.AuthInfos[newName]; newExists {
		return nil, fmt.Errorf("cannot rename %q, it already exists in the provided context", oldName)
	}

	config.AuthInfos[newName] = auth
	delete(config.AuthInfos, oldName)

	return config, nil
}

func MergeContextsWithDefault(configs ...*api.Config) (*api.Config, error) {
	// TODO add tests
	defaultConfig, err := clientcmd.NewDefaultClientConfigLoadingRules().Load()
	if err != nil {
		return nil, err
	}

	mapConfig := api.NewConfig()
	err = mergo.Merge(mapConfig, defaultConfig, mergo.WithOverride)
	if err != nil {
		return nil, err
	}

	// If the same contexts exist in the default config, we'll override them with the configs we merge
	for _, config := range configs {
		err = mergo.Merge(mapConfig, config, mergo.WithOverride)
		if err != nil {
			return nil, err
		}
	}

	return mapConfig, nil
}

func OutputContext(kubeConfigSavePath string, config *api.Config) error {
	if kubeConfigSavePath != "" {
		return clientcmd.WriteToFile(*config, kubeConfigSavePath)
	}

	bytes, err := clientcmd.Write(*config)
	if err != nil {
		return err
	}

	fmt.Println(string(bytes))

	return err
}
