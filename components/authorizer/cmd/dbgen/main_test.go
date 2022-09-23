// Copyright (c) 2022 Gitpod GmbH. All rights reserved.
// Licensed under the GNU Affero General Public License (AGPL).
// See License-AGPL.txt in the project root for license information.

//go:generate sh -c "go run main.go > generated_test.go"

package main_test

import (
	"fmt"
	"testing"

	"github.com/gitpod-io/gitpod/authorizer/pkg/executor"
)

func TestCheck(t *testing.T) {
	db := executor.MapDB{
		"d_b_user": executor.MapDBTable{
			{executor.MapDBCol("id"): "foo"},
		},
		"d_b_workspace": executor.MapDBTable{
			{
				executor.MapDBCol("id"):      "foobar",
				executor.MapDBCol("ownerId"): "foo",
			},
		},
		"d_b_workspace_instance": executor.MapDBTable{
			{
				executor.MapDBCol("id"):          "bla",
				executor.MapDBCol("workspaceId"): "foobar",
			},
		},
	}

	sess := &Session{DB: db}

	// NOTE:
	//
	// The current approach of separate `checkXXX` calls is unlikely to work because it ignores the context of the relationship.
	// Instead, we should produce joined SQL statements which carry the context/selection of the actor and subject.

	// this should return false because there is no workspace instance fooi. It returns true because
	// currently we ignore the actor identity, as well was the subject type.
	check := must(sess.Check("user:chris", "writer", "workspace:workspacebla"))
	res := must(executor.Build(check, nil))
	res.NormalizeValues()
	res.DangerousInsertValues()
	sql, _ := res.SQL()
	fmt.Println(sql)

	// this should be true because there is a corresponding workspace instance, whose workspace owner is foo
	// assert.True(t, must(sess.Check(context.Background(), "workspace_instance:bla", "access", "user:foo")))
}

func must[T any](t T, err error) T {
	if err != nil {
		panic(err)
	}
	return t
}