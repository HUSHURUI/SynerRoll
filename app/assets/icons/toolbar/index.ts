import type { Component } from 'vue'

import AlignBottomIcon from './AlignBottomIcon.vue'
import AlignCenterIcon from './AlignCenterIcon.vue'
import AlignLeftIcon from './AlignLeftIcon.vue'
import AlignMiddleIcon from './AlignMiddleIcon.vue'
import AlignRightIcon from './AlignRightIcon.vue'
import AlignTopIcon from './AlignTopIcon.vue'
import AxisXIcon from './AxisXIcon.vue'
import AxisYIcon from './AxisYIcon.vue'
import BackgroundIcon from './BackgroundIcon.vue'
import CanvasSizeIcon from './CanvasSizeIcon.vue'
import ChartIcon from './ChartIcon.vue'
import CopyIcon from './CopyIcon.vue'
import DeleteIcon from './DeleteIcon.vue'
import DisplayIcon from './DisplayIcon.vue'
import DistributeHorizontalIcon from './DistributeHorizontalIcon.vue'
import DistributeVerticalIcon from './DistributeVerticalIcon.vue'
import DownloadIcon from './DownloadIcon.vue'
import FitIcon from './FitIcon.vue'
import FlipHorizontalIcon from './FlipHorizontalIcon.vue'
import FlipVerticalIcon from './FlipVerticalIcon.vue'
import GridIcon from './GridIcon.vue'
import GridPatternIcon from './GridPatternIcon.vue'
import GridTypeIcon from './GridTypeIcon.vue'
import HeightIcon from './HeightIcon.vue'
import LayerDownIcon from './LayerDownIcon.vue'
import LayerUpIcon from './LayerUpIcon.vue'
import PackageIcon from './PackageIcon.vue'
import PasteIcon from './PasteIcon.vue'
import PatternIcon from './PatternIcon.vue'
import PlayIcon from './PlayIcon.vue'
import PortIcon from './PortIcon.vue'
import PortraitIcon from './PortraitIcon.vue'
import RedoIcon from './RedoIcon.vue'
import RotateIcon from './RotateIcon.vue'
import RotateLeftIcon from './RotateLeftIcon.vue'
import RotateRightIcon from './RotateRightIcon.vue'
import ShowLabelIcon from './ShowLabelIcon.vue'
import SizeIcon from './SizeIcon.vue'
import ToBackIcon from './ToBackIcon.vue'
import ToFrontIcon from './ToFrontIcon.vue'
import UndoIcon from './UndoIcon.vue'
import WidthIcon from './WidthIcon.vue'
import ZoomInIcon from './ZoomInIcon.vue'
import ZoomOutIcon from './ZoomOutIcon.vue'

export const toolbarIconMap: Record<string, Component> = {
  'layer-up': LayerUpIcon,
  'layer-down': LayerDownIcon,
  'to-front': ToFrontIcon,
  'to-back': ToBackIcon,
  'align-left': AlignLeftIcon,
  'align-center': AlignCenterIcon,
  'align-right': AlignRightIcon,
  'align-top': AlignTopIcon,
  'align-middle': AlignMiddleIcon,
  'align-bottom': AlignBottomIcon,
  'distribute-h': DistributeHorizontalIcon,
  'distribute-v': DistributeVerticalIcon,
  width: WidthIcon,
  height: HeightIcon,
  size: SizeIcon,
  undo: UndoIcon,
  redo: RedoIcon,
  rotate: RotateIcon,
  'rotate-left': RotateLeftIcon,
  'rotate-right': RotateRightIcon,
  'flip-horizontal': FlipHorizontalIcon,
  'flip-vertical': FlipVerticalIcon,
  'axis-x': AxisXIcon,
  'axis-y': AxisYIcon,
  copy: CopyIcon,
  paste: PasteIcon,
  delete: DeleteIcon,
  fit: FitIcon,
  'zoom-in': ZoomInIcon,
  'zoom-out': ZoomOutIcon,
  'grid-pattern': GridPatternIcon,
  pattern: PatternIcon,
  download: DownloadIcon,
  package: PackageIcon,
  play: PlayIcon,
  chart: ChartIcon,
  background: BackgroundIcon,
  'canvas-size': CanvasSizeIcon,
  grid: GridIcon,
  display: DisplayIcon,
  'show-label': ShowLabelIcon,
  portrait: PortraitIcon,
  'grid-type': GridTypeIcon,
  'show-ports': PortIcon
}
