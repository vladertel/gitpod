/**
 * Copyright (c) 2022 Gitpod GmbH. All rights reserved.
 * Licensed under the GNU Affero General Public License (AGPL).
 * See License-AGPL.txt in the project root for license information.
 */

// @generated by protoc-gen-connect-web v0.2.1 with parameter "target=ts"
// @generated from file gitpod/experimental/v1/workspaces.proto (package gitpod.experimental.v1, syntax proto3)
/* eslint-disable */
/* @ts-nocheck */

import {CreateAndStartWorkspaceRequest, CreateAndStartWorkspaceResponse, GetOwnerTokenRequest, GetOwnerTokenResponse, GetWorkspaceRequest, GetWorkspaceResponse, ListWorkspacesRequest, ListWorkspacesResponse, StopWorkspaceRequest, StopWorkspaceResponse} from "./workspaces_pb.js";
import {MethodKind} from "@bufbuild/protobuf";

/**
 * @generated from service gitpod.experimental.v1.WorkspacesService
 */
export const WorkspacesService = {
  typeName: "gitpod.experimental.v1.WorkspacesService",
  methods: {
    /**
     * ListWorkspaces enumerates all workspaces belonging to the authenticated user.
     *
     * @generated from rpc gitpod.experimental.v1.WorkspacesService.ListWorkspaces
     */
    listWorkspaces: {
      name: "ListWorkspaces",
      I: ListWorkspacesRequest,
      O: ListWorkspacesResponse,
      kind: MethodKind.Unary,
    },
    /**
     * GetWorkspace returns a single workspace.
     *
     * @generated from rpc gitpod.experimental.v1.WorkspacesService.GetWorkspace
     */
    getWorkspace: {
      name: "GetWorkspace",
      I: GetWorkspaceRequest,
      O: GetWorkspaceResponse,
      kind: MethodKind.Unary,
    },
    /**
     * GetOwnerToken returns an owner token.
     *
     * @generated from rpc gitpod.experimental.v1.WorkspacesService.GetOwnerToken
     */
    getOwnerToken: {
      name: "GetOwnerToken",
      I: GetOwnerTokenRequest,
      O: GetOwnerTokenResponse,
      kind: MethodKind.Unary,
    },
    /**
     * CreateAndStartWorkspace creates a new workspace and starts it.
     *
     * @generated from rpc gitpod.experimental.v1.WorkspacesService.CreateAndStartWorkspace
     */
    createAndStartWorkspace: {
      name: "CreateAndStartWorkspace",
      I: CreateAndStartWorkspaceRequest,
      O: CreateAndStartWorkspaceResponse,
      kind: MethodKind.Unary,
    },
    /**
     * StopWorkspace stops a running workspace (instance).
     * Errors:
     *   NOT_FOUND:           the workspace_id is unkown
     *   FAILED_PRECONDITION: if there's no running instance
     *
     * @generated from rpc gitpod.experimental.v1.WorkspacesService.StopWorkspace
     */
    stopWorkspace: {
      name: "StopWorkspace",
      I: StopWorkspaceRequest,
      O: StopWorkspaceResponse,
      kind: MethodKind.ServerStreaming,
    },
  }
} as const;

