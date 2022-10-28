package ssh

import (
	"context"
	"fmt"
	"io"
	"net"

	"golang.org/x/crypto/ssh"
)

type sshClient interface {
	io.Closer

	Run(ctx context.Context, cmd string, stdout io.Writer, stderr io.Writer) error
}

type sshClientFactory interface {
	Dial(ctx context.Context, host, port string) (sshClient, error)
}

type clientImplementation struct {
	client *ssh.Client
}

var _ sshClient = &clientImplementation{}

func (s *clientImplementation) Run(ctx context.Context, cmd string, stdout io.Writer, stderr io.Writer) error {
	sess, err := s.client.NewSession()
	if err != nil {
		return err
	}

	defer func(sess *ssh.Session) {
		err := sess.Close()
		if err != nil && err != io.EOF {
			panic(err)
		}
	}(sess)

	sess.Stdout = stdout
	sess.Stderr = stderr

	return sess.Run(cmd)
}

func (s *clientImplementation) Close() error {
	return s.client.Close()
}

type factoryImplementation struct {
	sshConfig *ssh.ClientConfig
}

var _ sshClientFactory = &factoryImplementation{}

func (f *factoryImplementation) Dial(ctx context.Context, host, port string) (sshClient, error) {
	addr := fmt.Sprintf("%s:%s", host, port)
	d := net.Dialer{}
	conn, err := d.DialContext(ctx, "tcp", addr)
	if err != nil {
		return nil, err
	}

	var client *ssh.Client
	c, chans, reqs, err := ssh.NewClientConn(conn, addr, f.sshConfig)
	if err != nil {
		return nil, err
	}

	client = ssh.NewClient(c, chans, reqs)

	return &clientImplementation{
		client: client,
	}, nil
}
