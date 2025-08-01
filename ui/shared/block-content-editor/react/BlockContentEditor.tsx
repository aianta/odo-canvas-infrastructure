/*
 * Copyright (C) 2025 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import {Editor, Element, Frame, SerializedNodes} from '@craftjs/core'
import {AddBlock} from './AddBlock'
import {TextBlock} from './Blocks/TextBlock'
import {BlockContentEditorContext} from './BlockContentEditorContext'
import {AddBlockModalRenderer} from './AddBlock/AddBlockModalRenderer'
import {ImageBlock} from './Blocks/ImageBlock'
import {BlockContentEditorLayout} from './layout/BlockContentEditorLayout'
import {Toolbar} from './Toolbar'
import {
  PageEditorHandler,
  useBlockContentEditorIntegration,
} from './hooks/useBlockContentEditorIntegration'

export const BlockContentEditor = (props: {
  data: SerializedNodes | null
  onInit: ((handler: PageEditorHandler) => void) | null
}) => {
  const onNodesChange = useBlockContentEditorIntegration(props.onInit)
  return (
    <BlockContentEditorContext data={props.data}>
      <BlockContentEditorLayout
        toolbar={<Toolbar />}
        editor={
          <Editor resolver={{TextBlock, ImageBlock}} onNodesChange={onNodesChange}>
            <AddBlockModalRenderer />
            <AddBlock />
            <Frame data={props.data ?? undefined}>
              <Element is="div"></Element>
            </Frame>
          </Editor>
        }
      />
    </BlockContentEditorContext>
  )
}
