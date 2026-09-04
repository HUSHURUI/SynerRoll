import type { BoundaryItem } from '~~/types/boundary'
import type { CanvasWorkspace, FlowNode } from '~~/types/canvas'

import { findCanvasById } from './canvas'

const dedupeStrings = (values: string[]) => [...new Set(values.filter(Boolean))]

const getAllNodeIds = (workspace: CanvasWorkspace) =>
  new Set(
    workspace.canvases.flatMap(canvas => canvas.nodes.map(node => node.id))
  )

const getActiveCanvasNodeIds = (workspace: CanvasWorkspace) =>
  new Set(findCanvasById(workspace).nodes.map(node => node.id))

const getNodeBoundaryIds = (node: FlowNode) =>
  dedupeStrings(node.data?.business?.boundaryIds ?? [])

const setNodeBoundaryIds = (node: FlowNode, boundaryIds: string[]): FlowNode => {
  if (!node.data?.business) {
    return node
  }

  return {
    ...node,
    data: {
      ...node.data,
      business: {
        ...node.data.business,
        boundaryIds: dedupeStrings(boundaryIds)
      }
    }
  }
}

const sanitizeBoundaryNodeIds = (
  boundary: BoundaryItem,
  allNodeIds: Set<string>
) => ({
  ...boundary,
  relatedComponents: dedupeStrings(
    boundary.relatedComponents.filter(nodeId => allNodeIds.has(nodeId))
  )
})

const syncWorkspaceNodesFromBoundaries = (
  workspace: CanvasWorkspace,
  boundaries: BoundaryItem[]
) => {
  const activeCanvas = findCanvasById(workspace)
  const validBoundaryIds = new Set(boundaries.map(boundary => boundary.id))

  return {
    ...workspace,
    canvases: workspace.canvases.map(canvas => ({
      ...canvas,
      nodes: canvas.nodes.map(node => {
        const nextBoundaryIds = canvas.id === activeCanvas.id
          ? boundaries
            .filter(boundary => boundary.relatedComponents.includes(node.id))
            .map(boundary => boundary.id)
          : getNodeBoundaryIds(node).filter(boundaryId => validBoundaryIds.has(boundaryId))

        return setNodeBoundaryIds(node, nextBoundaryIds)
      })
    }))
  }
}

export const getBoundaryRelatedComponentsForActiveCanvas = (
  boundary: BoundaryItem,
  workspace: CanvasWorkspace
) => {
  const activeNodeIds = getActiveCanvasNodeIds(workspace)

  return dedupeStrings(boundary.relatedComponents)
    .filter(nodeId => activeNodeIds.has(nodeId))
}

export const setBoundaryRelatedComponentsForActiveCanvas = (
  boundary: BoundaryItem,
  workspace: CanvasWorkspace,
  relatedComponents: string[]
) => {
  const allNodeIds = getAllNodeIds(workspace)
  const activeNodeIds = getActiveCanvasNodeIds(workspace)
  const preservedOtherCanvasNodeIds = dedupeStrings(boundary.relatedComponents)
    .filter(nodeId => allNodeIds.has(nodeId) && !activeNodeIds.has(nodeId))
  const nextActiveCanvasNodeIds = dedupeStrings(relatedComponents)
    .filter(nodeId => activeNodeIds.has(nodeId))

  return dedupeStrings([
    ...preservedOtherCanvasNodeIds,
    ...nextActiveCanvasNodeIds
  ])
}

export const syncBoundaryStateFromBoundaries = (
  workspace: CanvasWorkspace,
  boundaries: BoundaryItem[]
) => {
  const allNodeIds = getAllNodeIds(workspace)
  const nextBoundaries = boundaries.map(boundary => sanitizeBoundaryNodeIds(boundary, allNodeIds))
  const nextWorkspace = syncWorkspaceNodesFromBoundaries(workspace, nextBoundaries)

  return {
    workspace: nextWorkspace,
    boundaries: nextBoundaries
  }
}

export const syncBoundaryStateFromNodes = (
  workspace: CanvasWorkspace,
  boundaries: BoundaryItem[]
) => {
  const activeCanvas = findCanvasById(workspace)
  const activeNodeIds = getActiveCanvasNodeIds(workspace)
  const allNodeIds = getAllNodeIds(workspace)

  const nextBoundaries = boundaries.map(boundary => {
    const sanitizedBoundary = sanitizeBoundaryNodeIds(boundary, allNodeIds)
    const preservedOtherCanvasNodeIds = sanitizedBoundary.relatedComponents
      .filter(nodeId => !activeNodeIds.has(nodeId))
    const nextActiveCanvasNodeIds = activeCanvas.nodes
      .filter(node => getNodeBoundaryIds(node).includes(boundary.id))
      .map(node => node.id)

    return {
      ...sanitizedBoundary,
      relatedComponents: dedupeStrings([
        ...preservedOtherCanvasNodeIds,
        ...nextActiveCanvasNodeIds
      ])
    }
  })

  const nextWorkspace = syncWorkspaceNodesFromBoundaries(workspace, nextBoundaries)

  return {
    workspace: nextWorkspace,
    boundaries: nextBoundaries
  }
}
