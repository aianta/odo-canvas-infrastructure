# frozen_string_literal: true

#
# Copyright (C) 2019 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#
class SubmissionCommentReadLoader < GraphQL::Batch::Loader
  def initialize(current_user)
    super()
    @current_user = current_user
  end

  def perform(submission_comments)
    vsc = ViewedSubmissionComment
          .where(submission_comment_id: submission_comments, user: @current_user)
          .pluck("submission_comment_id")
          .to_set

    submission_comments.each do |sc|
      fulfill(sc, vsc.include?(sc.id))
    end
  end
end

module Types
  class SubmissionCommentType < ApplicationObjectType
    graphql_name "SubmissionComment"

    global_id_field :id

    implements Interfaces::TimestampInterface
    implements Interfaces::LegacyIDInterface

    field :created_at, Types::DateTimeType, null: false
    field :draft, Boolean, null: false
    field :submission_id, ID, null: false

    field :author, Types::UserType, null: true
    field :media_comment_id, String, null: true

    field :comment, String, null: true
    def comment
      Nokogiri::HTML(object.comment).text
    end

    # rubocop:disable GraphQL/FieldMethod
    # To keep the GraphQL endpoint consistent, we need to keep the comment field as plain text
    # and return the html comment separately
    field :html_comment, String, null: true
    def html_comment
      object.comment
    end
    # rubocop:enable GraphQL/FieldMethod

    def author
      # We are preloading submission and assignment here for the permission check.
      # Not ideal as that could be cached in redis, but in most cases the assignment
      # and submission will already be in the cache, as that's the graphql query
      # path to get to a submission comment, and thus costs us nothing to preload here.
      Promise.all([
                    load_association(:author),
                    load_association(:submission).then do |submission|
                      Loaders::AssociationLoader.for(Submission, :assignment).load(submission)
                    end
                  ]).then { object.author if object.grants_right?(current_user, :read_author) }
    end

    field :attachments, [Types::FileType], null: false
    def attachments
      attachment_ids = object.parse_attachment_ids
      return [] if attachment_ids.empty?

      load_association(:submission).then do |submission|
        Loaders::AssociationLoader.for(Submission, :assignment).load(submission).then do |assignment|
          scope = assignment.attachments
          Loaders::ForeignKeyLoader.for(scope, :id).load_many(attachment_ids).then do |attachments|
            # ForeignKeyLoaders returns results as an array and load_many also returns the values
            # as an array. Flatten them so we are not returning nested arrays here.
            attachments.flatten.compact
          end
        end
      end
    end

    field :assignment, Types::AssignmentType, null: true
    def assignment
      load_association(:submission).then do |submission|
        Loaders::AssociationLoader.for(Submission, :assignment).load(submission).then do |assignment|
          assignment
        end
      end
    end

    field :course, Types::CourseType, null: true
    def course
      load_association(:context).then do |course|
        course
      end
    end

    field :read, Boolean, null: false
    def read
      load_association(:submission).then do |submission|
        Promise.all([
                      Loaders::AssociationLoader.for(Submission, :content_participations).load(submission),
                      Loaders::AssociationLoader.for(Submission, :assignment).load(submission)
                    ]).then do
          next true if submission.read?(current_user)

          SubmissionCommentReadLoader.for(current_user).load(object)
        end
      end
    end

    field :media_object, Types::MediaObjectType, null: true
    def media_object
      Loaders::MediaObjectLoader.load(object.media_comment_id)
    end

    field :attempt, Integer, null: false
    def attempt
      # Attempt is nil in the database, but we are going to return it as 0 instead,
      # as it ends up being much easier to work with on an api level. Attempting
      # to fix this in the database is challenging because submission.attempt
      # should be changed as well in order to keep everything consistent.
      object.attempt.nil? ? 0 : object.attempt
    end

    field :can_reply, Boolean, null: true
    def can_reply
      object.submission.grants_right?(current_user, :comment)
    end

    field :provisional, Boolean, null: false
    delegate :provisional, to: :object
  end
end
