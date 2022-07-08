module github.com/gitpod-io/gitpod/ws-daemon/nsinsider

go 1.18

require (
	github.com/gitpod-io/gitpod/common-go/log v0.0.0-00010101000000-000000000000
	github.com/gitpod-io/gitpod/common-go/nsenter v0.0.0-00010101000000-000000000000
	github.com/google/nftables v0.0.0-20220329160011-5a9391c12fe3
	github.com/urfave/cli/v2 v2.3.0
	github.com/vishvananda/netlink v1.1.1-0.20210330154013-f5de75959ad5
	golang.org/x/sys v0.0.0-20220114195835-da31bd327af9
	golang.org/x/xerrors v0.0.0-20200804184101-5ec99f83aff1
)

require (
	github.com/BurntSushi/toml v0.4.1 // indirect
	github.com/cpuguy83/go-md2man/v2 v2.0.0 // indirect
	github.com/google/go-cmp v0.5.7 // indirect
	github.com/josharian/native v0.0.0-20200817173448-b6b71def0850 // indirect
	github.com/mdlayher/netlink v1.4.2 // indirect
	github.com/mdlayher/socket v0.0.0-20211102153432-57e3fa563ecb // indirect
	github.com/russross/blackfriday/v2 v2.0.1 // indirect
	github.com/shurcooL/sanitized_anchor_name v1.0.0 // indirect
	github.com/sirupsen/logrus v1.8.1 // indirect
	github.com/vishvananda/netns v0.0.0-20200728191858-db3c7e526aae // indirect
	golang.org/x/mod v0.5.1 // indirect
	golang.org/x/net v0.0.0-20211209124913-491a49abca63 // indirect
	golang.org/x/tools v0.1.8 // indirect
	honnef.co/go/tools v0.2.2 // indirect
)

replace github.com/gitpod-io/gitpod/common-go/baseserver => ../../common-go/baseserver // leeway

replace github.com/gitpod-io/gitpod/common-go/grpc => ../../common-go/grpc // leeway

replace github.com/gitpod-io/gitpod/common-go/log => ../../common-go/log // leeway

replace github.com/gitpod-io/gitpod/common-go/nsenter => ../../common-go/nsenter // leeway

replace github.com/gitpod-io/gitpod/common-go/pprof => ../../common-go/pprof // leeway

replace github.com/gitpod-io/gitpod/common-go/util => ../../common-go/util // leeway

replace github.com/gitpod-io/gitpod/content-service/api => ../../content-service-api/go // leeway

replace github.com/gitpod-io/gitpod/ws-daemon/api => ../../ws-daemon-api/go // leeway
