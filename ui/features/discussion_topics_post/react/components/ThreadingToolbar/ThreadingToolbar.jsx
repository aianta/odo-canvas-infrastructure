/*
 * Copyright (C) 2021 - present Instructure, Inc.
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

import {useScope as createI18nScope} from '@canvas/i18n'
import PropTypes from 'prop-types'
import React from 'react'
import {InlineList} from '@instructure/ui-list'
import {Reply} from './Reply'
import {Like} from './Like'
import {Expansion} from './Expansion'
import {MarkAsRead} from './MarkAsRead'
import {SpeedGraderNavigator} from './SpeedGraderNavigator'
import {Link} from '@instructure/ui-link'
import {Text} from '@instructure/ui-text'
import {Responsive} from '@instructure/ui-responsive'
import {responsiveQuerySizes} from '../../utils'
import {isSpeedGraderInTopUrl} from '../../utils/constants'
import {View} from '@instructure/ui-view'
import {Pin} from './Pin'

const I18n = createI18nScope('discussion_posts')

export function ThreadingToolbar({...props}) {
  return (
    <Responsive
      match="media"
      query={responsiveQuerySizes({mobile: true, desktop: true})}
      render={(_responsiveProps, matches) => (
        <View>
          {(props.searchTerm || props.filter !== 'all') && !props.isSplitView ? (
            <Link
              as="button"
              isWithinText={false}
              data-testid="go-to-reply"
              onClick={() => {
                const parentId = props.discussionEntry.parentId
                  ? props.discussionEntry.parentId
                  : props.discussionEntry._id
                const relativeId = props.discussionEntry.rootEntryId
                  ? props.discussionEntry._id
                  : null

                props.onOpenSplitView(parentId, false, relativeId, props.discussionEntry._id)
              }}
            >
              <Text weight="bold">{I18n.t('Go to Reply')}</Text>
            </Link>
          ) : (
            <InlineList delimiter="pipe" display="inline-flex">
              {React.Children.map(props.children, (c, i) => (
                <InlineList.Item
                  delimiter="pipe"
                  key={c.props.delimiterKey}
                  data-testid={
                    matches.includes('mobile') ? 'mobile-thread-tool' : 'desktop-thread-tool'
                  }
                >
                  <View
                    margin={i === 0 ? '0 x-small 0 0' : '0 x-small'}
                    style={{display: 'inline-flex'}}
                  >
                    {c}
                  </View>
                </InlineList.Item>
              ))}
            </InlineList>
          )}
          {isSpeedGraderInTopUrl && (
            <View as="div" margin="small 0 0 0">
              <SpeedGraderNavigator />
            </View>
          )}
        </View>
      )}
    />
  )
}

ThreadingToolbar.propTypes = {
  children: PropTypes.arrayOf(PropTypes.node),
  searchTerm: PropTypes.string,
  filter: PropTypes.string,
  onOpenSplitView: PropTypes.func,
  discussionEntry: PropTypes.object,
  isSplitView: PropTypes.bool,
}

ThreadingToolbar.Reply = Reply
ThreadingToolbar.Like = Like
ThreadingToolbar.Pin = Pin
ThreadingToolbar.Expansion = Expansion
ThreadingToolbar.MarkAsRead = MarkAsRead

export default ThreadingToolbar
