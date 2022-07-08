module github.com/gitpod-io/gitpod/content-service/api

go 1.18

require (
	github.com/gitpod-io/gitpod/common-go/baseserver v0.0.0-00010101000000-000000000000
	github.com/google/go-cmp v0.5.7
	github.com/opencontainers/go-digest v1.0.0
	github.com/opencontainers/image-spec v1.0.2
	golang.org/x/xerrors v0.0.0-20200804184101-5ec99f83aff1
	google.golang.org/grpc v1.45.0
	google.golang.org/protobuf v1.28.0
)

require (
	github.com/beorn7/perks v1.0.1 // indirect
	github.com/cespare/xxhash/v2 v2.1.2 // indirect
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/gitpod-io/gitpod/common-go/grpc v0.0.0-00010101000000-000000000000 // indirect
	github.com/gitpod-io/gitpod/common-go/log v0.0.0-00010101000000-000000000000 // indirect
	github.com/gitpod-io/gitpod/common-go/pprof v0.0.0-00010101000000-000000000000 // indirect
	github.com/gitpod-io/gitpod/common-go/util v0.0.0-00010101000000-000000000000 // indirect
	github.com/golang/protobuf v1.5.2 // indirect
	github.com/grpc-ecosystem/go-grpc-middleware v1.3.0 // indirect
	github.com/grpc-ecosystem/go-grpc-prometheus v1.2.0 // indirect
	github.com/hashicorp/golang-lru v0.5.1 // indirect
	github.com/heptiolabs/healthcheck v0.0.0-20211123025425-613501dd5deb // indirect
	github.com/matttproud/golang_protobuf_extensions v1.0.1 // indirect
	github.com/opentracing/opentracing-go v1.2.0 // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	github.com/prometheus/client_golang v1.12.1 // indirect
	github.com/prometheus/client_model v0.2.0 // indirect
	github.com/prometheus/common v0.32.1 // indirect
	github.com/prometheus/procfs v0.7.3 // indirect
	github.com/sirupsen/logrus v1.8.1 // indirect
	github.com/stretchr/testify v1.7.0 // indirect
	golang.org/x/net v0.0.0-20211209124913-491a49abca63 // indirect
	golang.org/x/sync v0.0.0-20210220032951-036812b2e83c // indirect
	golang.org/x/sys v0.0.0-20220114195835-da31bd327af9 // indirect
	golang.org/x/text v0.3.7 // indirect
	golang.org/x/time v0.0.0-20200630173020-3af7569d3a1e // indirect
	google.golang.org/genproto v0.0.0-20201019141844-1ed22bb0c154 // indirect
	gopkg.in/yaml.v3 v3.0.0-20210107192922-496545a6307b // indirect
)

replace github.com/gitpod-io/gitpod/common-go/baseserver => ../../common-go/baseserver // leeway

replace github.com/gitpod-io/gitpod/common-go/grpc => ../../common-go/grpc // leeway

replace github.com/gitpod-io/gitpod/common-go/log => ../../common-go/log // leeway

replace github.com/gitpod-io/gitpod/common-go/pprof => ../../common-go/pprof // leeway

replace github.com/gitpod-io/gitpod/common-go/util => ../../common-go/util // leeway
