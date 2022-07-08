module github.com/gitpod-io/gitpod/loadgen

go 1.18

require (
	github.com/cheggaaa/pb/v3 v3.0.5
	github.com/gitpod-io/gitpod/content-service/api v0.0.0-00010101000000-000000000000
	github.com/gitpod-io/gitpod/ws-manager/api v0.0.0-00010101000000-000000000000
	github.com/google/uuid v1.1.2
	github.com/sirupsen/logrus v1.8.1
	github.com/spf13/cobra v1.1.3
	google.golang.org/grpc v1.45.0
	google.golang.org/protobuf v1.28.0
	sigs.k8s.io/yaml v1.3.0
)

require (
	github.com/gitpod-io/gitpod/common-go/log v0.0.0-00010101000000-000000000000
	github.com/gitpod-io/gitpod/common-go/namegen v0.0.0-00010101000000-000000000000
)

require (
	github.com/VividCortex/ewma v1.1.1 // indirect
	github.com/fatih/color v1.7.0 // indirect
	github.com/golang/protobuf v1.5.2 // indirect
	github.com/inconshreveable/mousetrap v1.0.0 // indirect
	github.com/mattn/go-colorable v0.1.2 // indirect
	github.com/mattn/go-isatty v0.0.12 // indirect
	github.com/mattn/go-runewidth v0.0.7 // indirect
	github.com/opencontainers/go-digest v1.0.0 // indirect
	github.com/opencontainers/image-spec v1.0.2 // indirect
	github.com/spf13/pflag v1.0.5 // indirect
	golang.org/x/net v0.0.0-20211209124913-491a49abca63 // indirect
	golang.org/x/sys v0.0.0-20220114195835-da31bd327af9 // indirect
	golang.org/x/text v0.3.7 // indirect
	golang.org/x/xerrors v0.0.0-20200804184101-5ec99f83aff1 // indirect
	google.golang.org/genproto v0.0.0-20201019141844-1ed22bb0c154 // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
)

replace github.com/gitpod-io/gitpod/common-go/baseserver => ../../components/common-go/baseserver // leeway

replace github.com/gitpod-io/gitpod/common-go/grpc => ../../components/common-go/grpc // leeway

replace github.com/gitpod-io/gitpod/common-go/log => ../../components/common-go/log // leeway

replace github.com/gitpod-io/gitpod/common-go/namegen => ../../components/common-go/namegen // leeway

replace github.com/gitpod-io/gitpod/common-go/pprof => ../../components/common-go/pprof // leeway

replace github.com/gitpod-io/gitpod/common-go/util => ../../components/common-go/util // leeway

replace github.com/gitpod-io/gitpod/content-service/api => ../../components/content-service-api/go // leeway

replace github.com/gitpod-io/gitpod/ws-manager/api => ../../components/ws-manager-api/go // leeway
