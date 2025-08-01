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

import {gql} from 'graphql-tag'
import {executeQuery} from '@canvas/graphql'
import {showFlashError} from '@canvas/alerts/react/FlashAlert'
import {ModuleItemsResponse, ModuleItemsGraphQLResult, ModuleItem} from '../../utils/types.d'
import {useScope as createI18nScope} from '@canvas/i18n'
import {useQuery} from '@tanstack/react-query'

const I18n = createI18nScope('context_modules_v2')

const MODULE_ITEMS_QUERY = gql`
  query GetModuleItemsQuery($moduleId: ID!) {
    legacyNode(_id: $moduleId, type: Module) {
      ... on Module {
        moduleItems {
          _id
          id
          url
          title
          indent
          content {
            ... on Assignment {
              _id
              id
              type: __typename
              pointsPossible
              graded
              dueAt(applyOverrides: false)
              lockAt(applyOverrides: false)
              unlockAt(applyOverrides: false)
              published
              canUnpublish
              isLockedByMasterCourse
              canDuplicate
              assignmentOverrides(first: 100) {
                edges {
                  cursor
                  node {
                    _id
                    dueAt
                    lockAt
                    unlockAt
                    set {
                      ... on AdhocStudents {
                        students {
                          id
                        }
                      }
                      ... on Course {
                        courseId: id
                      }
                      ... on Group {
                        groupId: id
                      }
                      ... on Section {
                        sectionId: id
                      }
                    }
                  }
                }
              }
            }
            ... on Discussion {
              _id
              id
              type: __typename
              lockAt
              todoDate
              discussionType
              published
              canUnpublish
              isLockedByMasterCourse
              canDuplicate
              graded
              replyToEntryRequiredCount
              checkpoints {
                dueAt(applyOverrides: false)
                name
                tag
              }
            }
            ... on File {
              _id
              id
              type: __typename
              contentType
              size
              thumbnailUrl
              url
              published
              canUnpublish
              isLockedByMasterCourse
              canDuplicate
              fileState
              locked
              lockAt
              unlockAt
              graded
            }
            ... on Page {
              _id
              id
              published
              canUnpublish
              type: __typename
              isLockedByMasterCourse
              canDuplicate
              graded
            }
            ... on Quiz {
              _id
              id
              type: __typename
              pointsPossible
              published
              canUnpublish
              isLockedByMasterCourse
              canDuplicate
              graded
            }
            ... on ExternalUrl {
              type: __typename
              url
              published
              canUnpublish
              newTab
              graded
            }
            ... on ModuleExternalTool {
              type: __typename
              url
              published
              canUnpublish
              graded
            }
            ... on ExternalTool {
              type: __typename
              url
              published
              canUnpublish
              graded
            }
            ... on SubHeader {
              published
              type: __typename
            }
          }
        }
      }
    }
  }
`

const transformItems = (items: ModuleItem[], moduleId: string) => {
  return items.map((item, index) => ({
    ...item,
    moduleId,
    index,
  }))
}

async function getModuleItems({queryKey}: {queryKey: any}): Promise<ModuleItemsResponse> {
  const [_key, moduleId] = queryKey
  try {
    const result = await executeQuery<ModuleItemsGraphQLResult>(MODULE_ITEMS_QUERY, {
      moduleId,
    })

    if (result.errors) {
      throw new Error(result.errors.map(err => err.message).join(', '))
    }

    const moduleItems = result.legacyNode?.moduleItems || []

    return {
      moduleItems: transformItems(moduleItems, moduleId),
    }
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error)
    showFlashError(I18n.t('Failed to load module items: %{error}', {error: errorMessage}))
    throw error
  }
}

export function useModuleItems(moduleId: string, enabled: boolean = false) {
  return useQuery<ModuleItemsResponse, Error>({
    queryKey: ['moduleItems', moduleId],
    queryFn: getModuleItems,
    enabled,
    refetchOnWindowFocus: true,
    // 15 minutes, will reload on refresh because there is no persistence
    staleTime: 15 * 60 * 1000,
  })
}
