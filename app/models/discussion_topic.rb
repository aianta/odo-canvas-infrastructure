# frozen_string_literal: true

# Copyright (C) 2011 - present Instructure, Inc.
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

class DiscussionTopic < ActiveRecord::Base
  include Workflow
  include SendToStream
  include HasContentTags
  include CopyAuthorizedLinks
  include TextHelper
  include HtmlTextHelper
  include ContextModuleItem
  include SearchTermHelper
  include Submittable
  include Plannable
  include MasterCourses::Restrictor
  include DuplicatingObjects
  include LockedFor
  include DatesOverridable
  include LinkedAttachmentHandler

  def self.html_fields
    %w[message]
  end

  def actual_saving_user
    user
  end

  REQUIRED_CHECKPOINT_COUNT = 2

  restrict_columns :content, [:title, :message]
  restrict_columns :settings, %i[require_initial_post
                                 discussion_type
                                 assignment_id
                                 pinned
                                 locked
                                 allow_rating
                                 only_graders_can_rate
                                 sort_by_rating
                                 sort_order
                                 expanded
                                 sort_order_locked
                                 expanded_locked
                                 group_category_id]
  restrict_columns :state, [:workflow_state]
  restrict_columns :availability_dates, %i[unlock_at delayed_post_at lock_at]
  restrict_assignment_columns

  attr_writer :can_unpublish, :preloaded_subentry_count, :sections_changed, :overrides_changed
  attr_accessor :user_has_posted, :saved_by, :total_root_discussion_entries, :notify_users

  module DiscussionTypes
    SIDE_COMMENT = "side_comment"
    NOT_THREADED = "not_threaded"
    THREADED     = "threaded"
    FLAT         = "flat"
    TYPES        = DiscussionTypes.constants.map { |c| DiscussionTypes.const_get(c) }
  end

  module SortOrder
    DESC = "desc"
    ASC = "asc"
    DEFAULT = DESC
    # Inherit is not a real sort order but a placeholder meaning participant's should follow discussion's
    INHERIT = "inherit"
    TYPES = SortOrder.constants.map { |c| SortOrder.const_get(c) }
  end

  DEFAULT_EXPANDED_STATE = false

  module Errors
    class LockBeforeDueDate < StandardError; end
  end

  attr_readonly :context_id, :context_type, :user_id, :is_anonymous_author

  has_many :discussion_entries, -> { order(:created_at) }, dependent: :destroy, inverse_of: :discussion_topic
  has_many :discussion_entry_drafts, dependent: :destroy, inverse_of: :discussion_topic
  has_many :rated_discussion_entries,
           lambda {
             order(
               Arel.sql("COALESCE(parent_id, 0)"), Arel.sql("COALESCE(rating_sum, 0) DESC"), :created_at
             )
           },
           class_name: "DiscussionEntry"
  has_many :root_discussion_entries, -> { preload(:user).where("discussion_entries.parent_id IS NULL AND discussion_entries.workflow_state<>'deleted'") }, class_name: "DiscussionEntry"
  has_one :external_feed_entry, as: :asset
  belongs_to :root_account, class_name: "Account"
  belongs_to :external_feed
  belongs_to :context, polymorphic: [:course, :group]
  belongs_to :attachment
  belongs_to :editor, class_name: "User"
  belongs_to :root_topic, class_name: "DiscussionTopic"
  belongs_to :group_category
  has_many :sub_assignments, through: :assignment
  has_many :child_topics, class_name: "DiscussionTopic", foreign_key: :root_topic_id, dependent: :destroy, inverse_of: :root_topic
  has_many :discussion_topic_participants, dependent: :destroy
  has_many :discussion_entry_participants, through: :discussion_entries
  has_many :discussion_topic_section_visibilities,
           lambda {
             where("discussion_topic_section_visibilities.workflow_state<>'deleted'")
           },
           inverse_of: :discussion_topic,
           dependent: :destroy
  has_many :course_sections, through: :discussion_topic_section_visibilities, dependent: :destroy
  belongs_to :user
  has_one :master_content_tag, class_name: "MasterCourses::MasterContentTag", inverse_of: :discussion_topic
  has_many :summaries, class_name: "DiscussionTopicSummary"
  has_many :insights, class_name: "DiscussionTopicInsight"
  has_many :insight_entries, class_name: "DiscussionTopicInsight::Entry"
  has_one :estimated_duration, dependent: :destroy, inverse_of: :discussion_topic
  has_many :attachment_associations, as: :context, inverse_of: :context

  validates_with HorizonValidators::DiscussionsValidator, if: -> { context.is_a?(Course) && context.horizon_course? }
  validates_associated :discussion_topic_section_visibilities
  validates :context_id, :context_type, presence: true
  validates :discussion_type, inclusion: { in: DiscussionTypes::TYPES }
  validates :message, length: { maximum: maximum_long_text_length, allow_blank: true }
  validates :title, length: { maximum: maximum_string_length, allow_nil: true }
  # For our users, when setting checkpoints, the value must be between 1 and 10.
  # But we also allow 0 when there are no checkpoints.
  validates :reply_to_entry_required_count, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }
  validates :reply_to_entry_required_count, numericality: { greater_than: 0 }, if: -> { reply_to_entry_checkpoint.present? }
  validate :validate_draft_state_change, if: :workflow_state_changed?
  validate :section_specific_topics_must_have_sections
  validate :only_course_topics_can_be_section_specific
  validate :assignments_cannot_be_section_specific
  validate :course_group_discussion_cannot_be_section_specific
  validate :collapsed_not_enforced

  sanitize_field :message, CanvasSanitize::SANITIZE
  copy_authorized_links(:message) { [context, nil] }
  acts_as_list scope: { context: self, pinned: true }

  before_create :initialize_last_reply_at
  before_create :set_root_account_id
  before_save :default_values
  before_save :set_schedule_delayed_transitions
  before_save :set_edited_at
  after_save :update_assignment
  after_save :update_subtopics
  after_save :touch_context
  after_save :schedule_delayed_transitions
  after_save :update_materialized_view_if_changed
  after_save :recalculate_progressions_if_sections_changed
  after_save :sync_attachment_with_publish_state
  after_update :clear_non_applicable_stream_items
  after_create :create_participant
  after_create :create_materialized_view

  include SmartSearchable
  use_smart_search title_column: :title,
                   body_column: :message,
                   index_scope: ->(course) { course.discussion_topics.active },
                   search_scope: ->(course, user) { DiscussionTopic::ScopedToUser.new(course, user, course.discussion_topics.active).scope }

  def section_specific_topics_must_have_sections
    if !deleted? && is_section_specific && discussion_topic_section_visibilities.none?(&:active?)
      errors.add(:is_section_specific, t("Section specific topics must have sections"))
    else
      true
    end
  end

  def only_course_topics_can_be_section_specific
    if is_section_specific && !(context.is_a? Course)
      errors.add(:is_section_specific, t("Only course announcements and discussions can be section-specific"))
    else
      true
    end
  end

  def assignments_cannot_be_section_specific
    if is_section_specific && assignment
      errors.add(:is_section_specific, t("Discussion assignments cannot be section-specific"))
    else
      true
    end
  end

  def course_group_discussion_cannot_be_section_specific
    if is_section_specific && has_group_category?
      errors.add(:is_section_specific, t("Discussions with groups cannot be section-specific"))
    else
      true
    end
  end

  def sections_for(user)
    return unless is_section_specific?

    unlocked_teacher = context.enrollments.active.instructor
                              .where(limit_privileges_to_course_section: false, user:)

    if unlocked_teacher.count > 0
      CourseSection.where(id: DiscussionTopicSectionVisibility.active
                                                              .where(discussion_topic_id: id)
                                                              .select("discussion_topic_section_visibilities.course_section_id"))
    else
      CourseSection.where(id: DiscussionTopicSectionVisibility.active.where(discussion_topic_id: id)
                                                              .where(Enrollment.active_or_pending
                                                                                             .where(user_id: user)
                                                                                             .where("enrollments.course_section_id = discussion_topic_section_visibilities.course_section_id")
                                                                                             .arel.exists)
                                                              .select("discussion_topic_section_visibilities.course_section_id"))
    end
  end

  # This Method is used to help the messageable user calculator narrow down the scope of users to filter.
  # After the scope is narrowed down , the calculator uses the visible_for? method to reject users without visibility permissions
  def address_book_context_for(user)
    # If section overrides are present
    if only_visible_to_overrides && !all_assignment_overrides.active.where.not(set_type: "CourseSection").exists?
      # Get all section overrides for the topic
      section_overrides = all_assignment_overrides.active.where(set_type: "CourseSection").pluck(:set_id)

      # get the sectiosn the user can see
      visible_sections_for_user = context.course_section_visibility(user)
      return [] if visible_sections_for_user == :none

      # If a user can see alls ections, then just return section_overrides for the topic
      section_overrides_and_visibility = (visible_sections_for_user == :all) ? section_overrides : (visible_sections_for_user & section_overrides) # return a list of sections that the user can see
      CourseSection.where(id: section_overrides_and_visibility)
    elsif is_section_specific?
      sections_for(user)
    else
      context
    end
  end

  def threaded=(v)
    self.discussion_type = Canvas::Plugin.value_to_boolean(v) ? DiscussionTypes::THREADED : DiscussionTypes::NOT_THREADED
  end

  def threaded?
    discussion_type == DiscussionTypes::THREADED ||
      (context.discussion_checkpoints_enabled? && checkpoints?) ||
      (DiscussionTypes::SIDE_COMMENT && has_threaded_replies?)
  end
  alias_method :threaded, :threaded?

  def has_threaded_replies?
    DiscussionEntry.where.not(parent_id: nil)
                   .where.not(workflow_state: "deleted")
                   .where(discussion_topic: [id] + child_topics.select(:id))
                   .exists?
  end

  def discussion_type
    super || DiscussionTypes::NOT_THREADED
  end

  def validate_draft_state_change
    old_draft_state, new_draft_state = changes["workflow_state"]
    return if old_draft_state == new_draft_state

    if new_draft_state == "unpublished" && !can_unpublish?
      errors.add :workflow_state, I18n.t("#discussion_topics.error_draft_state_with_posts",
                                         "This topic cannot be set to draft state because it contains posts.")
    end
  end

  def default_values
    self.context_code = "#{context_type.underscore}_#{context_id}"

    if title.blank?
      self.title = t("#discussion_topic.default_title", "No Title")
    end

    d_type = self["discussion_type"]
    d_type ||= context.feature_enabled?("react_discussions_post") ? DiscussionTypes::THREADED : DiscussionTypes::NOT_THREADED
    self.discussion_type = d_type

    d_sort = self["sort_order"]
    if d_sort.nil? || !SortOrder::TYPES.include?(d_sort)
      self.sort_order = SortOrder::DEFAULT
    end

    @content_changed = message_changed? || title_changed?

    default_submission_values

    if has_group_category?
      self.subtopics_refreshed_at ||= Time.zone.parse("Jan 1 2000")
    end
    self.lock_at = CanvasTime.fancy_midnight(lock_at&.in_time_zone(context.time_zone))

    %i[
      could_be_locked
      podcast_enabled
      podcast_has_student_posts
      require_initial_post
      pinned
      locked
      allow_rating
      only_graders_can_rate
      sort_by_rating
      sort_order_locked
      expanded
      expanded_locked
    ].each { |attr| self[attr] = false if self[attr].nil? }
  end
  protected :default_values

  def has_group_category?
    !!group_category_id
  end

  def effective_group_category_id
    has_group_category? ? group_category_id : nil
  end

  def set_schedule_delayed_transitions
    @delayed_post_at_changed = delayed_post_at_changed? || unlock_at_changed?
    if delayed_post_at? && @delayed_post_at_changed
      @should_schedule_delayed_post = true
      self.workflow_state = "post_delayed" if [:migration, :after_migration].include?(saved_by) && delayed_post_at > Time.zone.now
    end
    if lock_at && lock_at_changed?
      self.locked = false if [:migration, :after_migration].include?(saved_by) && lock_at > Time.zone.now
    end

    true
  end

  def update_materialized_view_if_changed
    if saved_change_to_sort_by_rating?
      update_materialized_view
    end
  end

  def recalculate_progressions_if_sections_changed
    # either changed sections or undid section specificness
    return unless is_section_specific? ? @sections_changed : is_section_specific_before_last_save

    self.class.connection.after_transaction_commit do
      if context_module_tags.preload(:context_module).exists?
        context_module_tags.map(&:context_module).uniq.each do |cm|
          cm.invalidate_progressions
          cm.touch
        end
      end
    end
  end

  def schedule_delayed_transitions
    return if saved_by == :migration

    bp = true if @importing_migration&.migration_type == "master_course_import"
    delay(run_at: delayed_post_at).update_based_on_date(for_blueprint: bp) if @should_schedule_delayed_post
    # need to clear these in case we do a save whilst saving (e.g.
    # Announcement#respect_context_lock_rules), so as to avoid the dreaded
    # double delayed job ಠ_ಠ
    @should_schedule_delayed_post = nil
  end

  def sync_attachment_with_publish_state
    if (saved_change_to_workflow_state? || saved_change_to_locked? || saved_change_to_attachment_id?) &&
       attachment && !attachment.hidden? # if it's already hidden leave alone
      locked = !!(unpublished? || not_available_yet? || not_available_anymore?)
      attachment.update_attribute(:locked, locked)
    end
  end

  def update_subtopics
    if !deleted? && (has_group_category? || !!group_category_id_before_last_save)
      delay_if_production(singleton: "refresh_subtopics_#{global_id}").refresh_subtopics
    end
  end

  def refresh_subtopics
    sub_topics = []
    category = group_category

    if category && root_topic_id.blank? && !deleted?
      category.groups.active.order(:id).each do |group|
        sub_topics << ensure_child_topic_for(group)
      end
    end

    shard.activate do
      # delete any lingering child topics
      DiscussionTopic.where(root_topic_id: self).where.not(id: sub_topics).update_all(workflow_state: "deleted")
    end
  end

  def ensure_child_topic_for(group)
    group.shard.activate do
      DiscussionTopic.unique_constraint_retry do
        topic = DiscussionTopic.where(context_id: group, context_type: "Group", root_topic_id: self).first
        topic ||= group.discussion_topics.build { |dt| dt.root_topic = self }
        topic.message = message
        topic.reply_to_entry_required_count = reply_to_entry_required_count if reply_to_entry_required_count
        topic.title = CanvasTextHelper.truncate_text("#{title} - #{group.name}", { max_length: 250 }) # because of course people do this
        topic.assignment_id = assignment_id
        topic.attachment_id = attachment_id
        topic.group_category_id = group_category_id
        topic.user_id = user_id
        topic.discussion_type = discussion_type
        topic.workflow_state = workflow_state
        topic.allow_rating = allow_rating
        topic.only_graders_can_rate = only_graders_can_rate
        topic.sort_by_rating = sort_by_rating
        topic.sort_order = sort_order
        topic.sort_order_locked = sort_order_locked
        topic.expanded = expanded
        topic.expanded_locked = expanded_locked
        topic.save if topic.changed?
        topic
      end
    end
  end

  def update_assignment
    return if deleted?

    if !assignment_id && @old_assignment_id
      context_module_tags.find_each do |cmt|
        cmt.confirm_valid_module_requirements
        cmt.update_course_pace_module_items
      end
    end
    if @old_assignment_id
      Assignment.where(id: @old_assignment_id, context_id:, context_type:, submission_types: "discussion_topic").update_all(workflow_state: "deleted", updated_at: Time.now.utc)
      old_assignment = Assignment.find(@old_assignment_id)
      ContentTag.delete_for(old_assignment)
      # prevent future syncs from recreating the deleted assignment
      if is_child_content?
        old_assignment.submission_types = "none"
        own_tag = MasterCourses::ChildContentTag.find_by(content: self)
        own_tag&.child_subscription&.create_content_tag_for!(old_assignment, downstream_changes: ["workflow_state"])
      end
    elsif assignment && @saved_by != :assignment && !root_topic_id
      deleted_assignment = assignment.deleted?
      sync_assignment
      assignment.workflow_state = "published" if is_announcement && deleted_assignment
      assignment.description = message
      if saved_change_to_group_category_id?
        assignment.validate_assignment_overrides(force_override_destroy: true)
      end
      assignment.save
    end

    # make sure that if the topic has a new assignment (either by going from
    # ungraded to graded, or from one assignment to another; we ignore the
    # transition from graded to ungraded) we acknowledge that the users that
    # have posted have contributed to the topic and that course paces are up
    # to date
    if assignment_id && saved_change_to_assignment_id?
      recalculate_context_module_actions!
      context_module_tags.find_each(&:update_course_pace_module_items)
    end
  end
  protected :update_assignment

  def recalculate_context_module_actions!
    posters.each { |user| context_module_action(user, :contributed) }
  end

  def is_announcement
    false
  end

  def homeroom_announcement?(_context)
    false
  end

  def root_topic?
    !root_topic_id && has_group_category?
  end

  # only the root level entries
  def discussion_subentries
    root_discussion_entries
  end

  # count of all active discussion_entries
  def discussion_subentry_count
    @preloaded_subentry_count || discussion_entries.active.count
  end

  def for_group_discussion?
    has_group_category? && root_topic?
  end

  def plaintext_message=(val)
    self.message = format_message(strip_tags(val)).first
  end

  def plaintext_message
    truncate_html(message, max_length: 250)
  end

  def create_participant
    if user
      discussion_topic_participants.create(user:,
                                           workflow_state: "read",
                                           unread_entry_count: 0,
                                           subscribed: !subscription_hold(user, nil))
    end
  end

  def update_materialized_view
    # kick off building of the view
    self.class.connection.after_transaction_commit do
      DiscussionTopic::MaterializedView.for(self).update_materialized_view(xlog_location: self.class.current_xlog_location)
    end
  end

  def group_category_deleted_with_entries?
    group_category.try(:deleted_at?) && !can_group?
  end

  def get_potentially_conflicting_titles(title_base)
    DiscussionTopic.active.where(context_type:, context_id:)
                   .starting_with_title(title_base).pluck("title").to_set
  end

  # This is a guess of what to copy over.
  def duplicate_base_model(title, opts)
    DiscussionTopic.new({
                          title:,
                          message:,
                          context_id:,
                          context_type:,
                          user_id: opts[:user] ? opts[:user].id : user_id,
                          type:,
                          workflow_state: "unpublished",
                          could_be_locked:,
                          context_code:,
                          podcast_enabled:,
                          require_initial_post:,
                          podcast_has_student_posts:,
                          discussion_type:,
                          delayed_post_at:,
                          lock_at:,
                          pinned:,
                          locked:,
                          group_category_id:,
                          allow_rating:,
                          only_graders_can_rate:,
                          sort_by_rating:,
                          sort_order:,
                          sort_order_locked:,
                          expanded:,
                          expanded_locked:,
                          todo_date:,
                          is_section_specific:,
                          anonymous_state:,
                          reply_to_entry_required_count:
                        })
  end

  # Presumes that self has no parents
  # Does not duplicate the child topics; the hooks take care of that for us.
  def duplicate(opts = {})
    # Don't clone a new record
    return self if new_record?

    default_opts = {
      duplicate_assignment: true,
      copy_title: nil,
      user: nil
    }
    opts_with_default = default_opts.merge(opts)
    copy_title =
      opts_with_default[:copy_title] || get_copy_title(self, t("Copy"), title)
    result = duplicate_base_model(copy_title, opts_with_default)

    # Start with a position guaranteed to not conflict with existing ones.
    # Clients are encouraged to set the correct position later on and do
    # an insert_at upon save.

    if pinned
      result.position = context.discussion_topics.active.where(pinned: true).maximum(:position) + 1
    end

    if assignment && opts_with_default[:duplicate_assignment]
      result.assignment = assignment.duplicate({
                                                 duplicate_discussion_topic: false,
                                                 copy_title: result.title,
                                                 discussion_topic_for_checkpoints: result
                                               })
    end

    result.discussion_topic_section_visibilities = []
    if is_section_specific
      original_visibilities = discussion_topic_section_visibilities.active
      original_visibilities.each do |visibility|
        new_visibility = DiscussionTopicSectionVisibility.new(
          discussion_topic: result,
          course_section: visibility.course_section
        )
        result.discussion_topic_section_visibilities << new_visibility
      end
    end

    # For some reason, the relation doesn't take care of this for us. Don't understand why.
    # Without this line, *two* discussion topic duplicates appear when a save is performed.
    result.assignment&.discussion_topic = result

    result
  end

  # If no join record exists, assume all discussion enrties are unread, and
  # that a join record will be created the first time one is marked as read.
  attr_accessor :current_user

  def read_state(current_user = nil)
    current_user ||= self.current_user
    return "read" unless current_user # default for logged out user

    uid = current_user.is_a?(User) ? current_user.id : current_user
    ws = if discussion_topic_participants.loaded?
           discussion_topic_participants.detect { |dtp| dtp.user_id == uid }&.workflow_state
         else
           discussion_topic_participants.where(user_id: uid).pick(:workflow_state)
         end
    ws || "unread"
  end

  def read?(current_user = nil)
    read_state(current_user) == "read"
  end

  def unread?(current_user = nil)
    !read?(current_user)
  end

  def change_read_state(new_state, current_user = nil)
    current_user ||= self.current_user
    return nil unless current_user

    context_module_action(current_user, :read) if new_state == "read"

    return true if new_state == read_state(current_user)

    StreamItem.update_read_state_for_asset(self, new_state, current_user.id)
    update_or_create_participant(current_user:, new_state:)
  end

  def change_all_read_state(new_state, current_user = nil, opts = {})
    current_user ||= self.current_user
    return unless current_user

    update_fields = { workflow_state: new_state }
    update_fields[:forced_read_state] = opts[:forced] if opts.key?(:forced)

    transaction do
      update_stream_item_state(current_user, new_state)
      update_participants_read_state(current_user, new_state, update_fields)
    end
  end

  def update_stream_item_state(current_user, new_state)
    context_module_action(current_user, :read) if new_state == "read"
    StreamItem.update_read_state_for_asset(self, new_state, current_user.id)
  end
  protected :update_stream_item_state

  def update_participants_read_state(current_user, new_state, update_fields)
    # if workflow_state is unread, and force_read_state is not provided then
    # mark everything as unread but use the defaults, or allow other entries to
    # be implicitly unread, but still update any existing records.
    if new_state == "unread" && !update_fields.key?(:forced_read_state)
      DiscussionEntryParticipant.where(discussion_entry_id: discussion_entries.select(:id), user: current_user)
                                .where.not(workflow_state: new_state)
                                .in_batches.update_all(update_fields)
    else
      DiscussionEntryParticipant.upsert_for_topic(self,
                                                  current_user,
                                                  new_state:,
                                                  forced: update_fields[:forced_read_state])
    end

    update_or_create_participant(current_user:,
                                 new_state:,
                                 new_count: (new_state == "unread") ? default_unread_count : 0)
  end
  protected :update_participants_read_state

  def default_unread_count
    discussion_entries.active.count
  end

  # Do not use the lock options unless you truly need
  # the lock, for instance to update the count.
  # Careless use has caused database transaction deadlocks
  def unread_count(current_user = nil, lock: false, opts: {})
    current_user ||= self.current_user
    return 0 unless current_user # default for logged out users

    environment = lock ? :primary : :secondary
    GuardRail.activate(environment) do
      topic_participant = if opts[:use_preload] && association(:discussion_topic_participants).loaded?
                            discussion_topic_participants.find { |dtp| dtp.user_id == current_user.id }
                          else
                            discussion_topic_participants.where(user_id: current_user).select(:unread_entry_count).lock(lock).take
                          end
      topic_participant&.unread_entry_count || default_unread_count
    end
  end

  # Cases where you CAN'T subscribe:
  #  - initial post is required and you haven't made one
  #  - it's an announcement
  #  - this is a root level graded group discussion and you aren't in any of the groups
  #  - this is group level discussion and you aren't in the group
  def subscription_hold(user, session)
    return nil unless user

    if initial_post_required?(user, session)
      :initial_post_required
    elsif root_topic? && !child_topic_for(user)
      :not_in_group_set
    elsif context.is_a?(Group) && !context.has_member?(user)
      :not_in_group
    end
  end

  def subscribed?(current_user = nil, opts: {})
    current_user ||= self.current_user
    return false unless current_user # default for logged out user

    if root_topic?
      participant = DiscussionTopicParticipant.find_by(user_id: current_user.id,
                                                       discussion_topic_id: child_topics.pluck(:id))
    end
    participant ||= if opts[:use_preload] && association(:discussion_topic_participants).loaded?
                      discussion_topic_participants.find { |dtp| dtp.user_id == current_user.id }
                    else
                      discussion_topic_participants.find_by(user_id: current_user)
                    end
    if participant
      if participant.subscribed.nil?
        # if there is no explicit subscription, assume the author and posters
        # are subscribed, everyone else is not subscribed
        (current_user == user || participant.discussion_topic.posters.include?(current_user)) && !participant.discussion_topic.subscription_hold(current_user, nil)
      else
        participant.subscribed
      end
    else
      current_user == user && !subscription_hold(current_user, nil)
    end
  end

  def subscribe(current_user = nil)
    change_subscribed_state(true, current_user)
  end

  def unsubscribe(current_user = nil)
    change_subscribed_state(false, current_user)
  end

  def change_subscribed_state(new_state, current_user = nil)
    current_user ||= self.current_user
    return unless current_user
    return true if subscribed?(current_user) == new_state

    if root_topic?
      return if change_child_topic_subscribed_state(new_state, current_user)

      ctss = DiscussionTopicParticipant.new
      ctss.errors.add(:discussion_topic_id, I18n.t("no child topic found"))
      ctss
    else
      update_or_create_participant(current_user:, subscribed: new_state)
    end
  end

  def child_topic_for(user)
    return unless context.is_a?(Course)

    group_ids = user.group_memberships.active.pluck(:group_id) &
                context.groups.active.pluck(:id)
    child_topics.active.where(context_id: group_ids, context_type: "Group").first
  end

  def change_child_topic_subscribed_state(new_state, current_user)
    topic = child_topic_for(current_user)
    topic&.update_or_create_participant(current_user:, subscribed: new_state)
  end
  protected :change_child_topic_subscribed_state

  def participant(current_user = nil)
    current_user ||= self.current_user
    return nil unless current_user

    discussion_topic_participants.find_by(user_id: current_user)
  end

  def update_or_create_participant(opts = {})
    current_user = opts[:current_user] || self.current_user
    return nil unless current_user

    topic_participant = nil
    GuardRail.activate(:primary) do
      DiscussionTopic.uncached do
        DiscussionTopic.unique_constraint_retry do
          topic_participant = discussion_topic_participants.where(user_id: current_user).lock.first
          topic_participant ||= discussion_topic_participants.build(user: current_user,
                                                                    unread_entry_count: unread_count(current_user, lock: true),
                                                                    workflow_state: "unread",
                                                                    subscribed: current_user == user && !subscription_hold(current_user, nil),
                                                                    sort_order: DiscussionTopic::SortOrder::INHERIT,
                                                                    summary_enabled:)
          topic_participant.workflow_state = opts[:new_state] if opts[:new_state]
          topic_participant.unread_entry_count += opts[:offset] if opts[:offset] && opts[:offset] != 0
          topic_participant.unread_entry_count = opts[:new_count] if opts[:new_count]
          topic_participant.subscribed = opts[:subscribed] if opts.key?(:subscribed)
          topic_participant.expanded = opts[:expanded] if opts.key?(:expanded)
          topic_participant.sort_order = opts[:sort_order] if opts.key?(:sort_order)
          topic_participant.summary_enabled = opts[:summary_enabled] if opts.key?(:summary_enabled)
          topic_participant.save
        end
      end
    end
    topic_participant
  end

  scope :joins_ungraded_discussion_student_visibilities, lambda { |user_ids, course_ids|
    visible_discussion_topics = UngradedDiscussionVisibility::UngradedDiscussionVisibilityService.discussion_topics_visible(user_ids:, course_ids:).map(&:discussion_topic_id)
    if visible_discussion_topics.any?
      where(id: visible_discussion_topics)
        .where(assignment_id: nil)
    else
      none
    end
  }

  scope :visible_to_students_in_course_with_da, lambda { |user_ids, course_ids|
    where.not(assignment_id: nil)
         .joins_assignment_student_visibilities(user_ids, course_ids)
         .union(
           joins_ungraded_discussion_student_visibilities(user_ids, course_ids)
         )
  }

  scope :not_ignored_by, lambda { |user, purpose|
    where.not(Ignore.where(asset_type: "DiscussionTopic", user_id: user, purpose:)
      .where("asset_id=discussion_topics.id").arel.exists)
  }

  scope :not_fully_anonymous, -> { where(anonymous_state: [nil, "partial_anonymity"]) }

  scope :todo_date_between, lambda { |starting, ending|
    where("(discussion_topics.type = 'Announcement' AND posted_at BETWEEN :start_at and :end_at)
           OR todo_date BETWEEN :start_at and :end_at",
          { start_at: starting, end_at: ending })
  }
  scope :for_courses_and_groups, lambda { |course_ids, group_ids|
    where("(discussion_topics.context_type = 'Course'
          AND discussion_topics.context_id IN (?))
          OR (discussion_topics.context_type = 'Group'
          AND discussion_topics.context_id IN (?))",
          course_ids,
          group_ids)
  }

  class QueryError < StandardError
    attr_accessor :status_code

    def initialize(message = nil, status_code = nil)
      super(message)
      self.status_code = status_code
    end
  end

  # Retrieves all the *course* (as oppposed to group) discussion topics that apply
  # to the given sections.  Group topics will not be returned.  TODO: figure out
  # a good way to deal with group topics here.
  #
  # Takes in an array of section objects, and it is required that they all belong
  # to the same course.  At least one section must be provided.
  scope :in_sections, lambda { |course_sections|
    course_ids = course_sections.pluck(:course_id).uniq
    if course_ids.length != 1
      raise QueryError, I18n.t("Searching for announcements in sections must span exactly one course")
    end

    course_id = course_ids.first
    joins("LEFT OUTER JOIN #{DiscussionTopicSectionVisibility.quoted_table_name}
           AS discussion_section_visibilities ON discussion_topics.is_section_specific = true AND
           discussion_section_visibilities.discussion_topic_id = discussion_topics.id")
      .where("discussion_topics.context_type = 'Course' AND
             discussion_topics.context_id = :course_id",
             { course_id: })
      .where("discussion_section_visibilities.id IS null OR
             (discussion_section_visibilities.workflow_state = 'active' AND
              discussion_section_visibilities.course_section_id IN (:course_sections))",
             { course_sections: course_sections.pluck(:id) }).distinct
  }

  scope :discussion_topic_section_visibility_scope, lambda { |student|
    DiscussionTopicSectionVisibility
      .select(1)
      .active
      .where("discussion_topic_section_visibilities.discussion_topic_id = discussion_topics.id")
      .where(
        Enrollment.active_or_pending.where(user_id: student)
          .select(1)
          .where("enrollments.course_section_id = discussion_topic_section_visibilities.course_section_id")
          .limit(1)
          .arel.exists
      )
  }

  scope :visible_to_student_sections, lambda { |student|
    merge(
      DiscussionTopic.where.not(discussion_topics: { context_type: "Course" })
      .or(DiscussionTopic.where(discussion_topics: { is_section_specific: false }))
      .or(DiscussionTopic.where(discussion_topic_section_visibility_scope(student).arel.exists))
    )
  }

  scope :visible_to_ungraded_discussion_student_visibilities, lambda { |users, courses = nil|
    observed_student_ids = []
    visible_topic_ids = []

    Array(courses).each do |course|
      course = Course.find(course) unless course.is_a?(Course)

      if course&.user_has_been_observer?(users)
        observed_student_ids.concat(ObserverEnrollment.observed_student_ids(course, users))
      end

      if User.observing_full_course(course).where(id: users).exists?
        visible_topic_ids.concat(DiscussionTopic.where(context_type: "Course", context_id: course.id).active.pluck(:id))
      end
    end

    user_ids = Array(users) | observed_student_ids
    visible_differentiated_topic_ids = UngradedDiscussionVisibility::UngradedDiscussionVisibilityService.discussion_topics_visible(user_ids:).map(&:discussion_topic_id)
    merge(DiscussionTopic.where.not(context_type: "Course")
    .or(DiscussionTopic.where(id: visible_topic_ids))
    .or(DiscussionTopic.where(id: visible_differentiated_topic_ids, is_section_specific: false))
    .or(DiscussionTopic.where(is_section_specific: true).where(discussion_topic_section_visibility_scope(user_ids).arel.exists)))
  }

  scope :recent, -> { where("discussion_topics.last_reply_at>?", 2.weeks.ago).order("discussion_topics.last_reply_at DESC") }
  scope :only_discussion_topics, -> { where(type: nil) }
  scope :for_subtopic_refreshing, -> { where("discussion_topics.subtopics_refreshed_at IS NOT NULL AND discussion_topics.subtopics_refreshed_at<discussion_topics.updated_at").order("discussion_topics.subtopics_refreshed_at") }
  scope :active, -> { where("discussion_topics.workflow_state<>'deleted'") }
  scope :for_context_codes, ->(codes) { where(context_code: codes) }

  scope :before, ->(date) { where("discussion_topics.created_at<?", date) }

  scope :by_position, -> { order("discussion_topics.position ASC, discussion_topics.created_at DESC, discussion_topics.id DESC") }
  scope :by_position_legacy, -> { order("discussion_topics.position DESC, discussion_topics.created_at DESC, discussion_topics.id DESC") }
  scope :by_last_reply_at, -> { order("discussion_topics.last_reply_at DESC, discussion_topics.created_at DESC, discussion_topics.id DESC") }

  scope :by_posted_at, lambda {
    order(Arel.sql(<<~SQL.squish))
      COALESCE(discussion_topics.unlock_at, discussion_topics.delayed_post_at, discussion_topics.posted_at, discussion_topics.created_at) DESC,
      discussion_topics.created_at DESC,
      discussion_topics.id DESC
    SQL
  }

  scope :read_for, lambda { |user|
    eager_load(:discussion_topic_participants)
      .where("discussion_topic_participants.id IS NOT NULL
          AND (discussion_topic_participants.user_id = :user
            AND discussion_topic_participants.workflow_state = 'read')",
             user:)
  }
  scope :unread_for, lambda { |user|
    joins(sanitize_sql(["LEFT OUTER JOIN #{DiscussionTopicParticipant.quoted_table_name} ON
            discussion_topic_participants.discussion_topic_id=discussion_topics.id AND
            discussion_topic_participants.user_id=?",
                        user.id]))
      .where("discussion_topic_participants IS NULL
          OR discussion_topic_participants.workflow_state <> 'read'
          OR discussion_topic_participants.unread_entry_count > 0")
  }
  scope :published, -> { where("discussion_topics.workflow_state = 'active'") }
  scope :published_or_post_delayed, -> { where("discussion_topics.workflow_state = 'active' OR discussion_topics.workflow_state = 'post_delayed'") }

  # TODO: this scope is appearing in a few models now with identical code.
  # Can this be extracted somewhere?
  scope :starting_with_title, lambda { |title|
    where("title ILIKE ?", "#{title}%")
  }

  alias_attribute :available_until, :lock_at

  def available_from
    self[:delayed_post_at]
  end

  def available_from=(value)
    self[:delayed_post_at] = value
  end

  def unlock_at
    self[:unlock_at].nil? ? self[:delayed_post_at] : self[:unlock_at]
  end

  def delayed_post_at
    self[:unlock_at].nil? ? self[:delayed_post_at] : self[:unlock_at]
  end

  def unlock_at=(value)
    self[:delayed_post_at] = value
    super
  end

  def delayed_post_at=(value)
    self[:unlock_at] = value
    super
  end

  def should_lock_yet
    # not assignment or vdd aware! only use this to check the topic's own field!
    # you should be checking other lock statuses in addition to this one
    lock_at && lock_at < Time.now.utc
  end
  alias_method :not_available_anymore?, :should_lock_yet

  def should_not_post_yet
    # not assignment or vdd aware! only use this to check the topic's own field!
    # you should be checking other lock statuses in addition to this one
    delayed_post_at && delayed_post_at > Time.now.utc
  end
  alias_method :not_available_yet?, :should_not_post_yet

  # There may be delayed jobs that expect to call this to update the topic, so be sure to alias
  # the old method name if you change it
  # Also: if this method is scheduled by a blueprint sync, ensure it isn't counted as a manual downstream change
  def update_based_on_date(for_blueprint: false)
    skip_downstream_changes! if for_blueprint
    delayed_post unless should_not_post_yet
  end
  alias_method :try_posting_delayed, :update_based_on_date
  alias_method :auto_update_workflow, :update_based_on_date

  workflow do
    state :active
    state :unpublished
    state :post_delayed do
      event :delayed_post, transitions_to: :active do
        self.notify_users = true
        self.last_reply_at = Time.zone.now
        self.posted_at = Time.zone.now
      end
      # with draft state, this means published. without, unpublished. so we really do support both events
    end
    state :deleted
  end

  def active?
    # using state instead of workflow_state so this works with new records
    state == :active || (!is_announcement && state == :post_delayed)
  end

  def publish
    # follows the logic of setting post_delayed in other places of this file
    self.workflow_state = (delayed_post_at && delayed_post_at > Time.zone.now) ? "post_delayed" : "active"
    self.last_reply_at = Time.zone.now
    self.posted_at = Time.zone.now
  end

  def publish!
    publish
    save!
  end

  def edit!
    self.last_reply_at = Time.zone.now
    save!
  end

  def unpublish
    self.workflow_state = "unpublished"
  end

  def unpublish!
    unpublish
    save!
  end

  def can_lock?
    !(assignment.try(:due_at) && assignment.due_at > Time.zone.now)
  end

  def comments_disabled?
    return false unless is_announcement

    if context.is_a?(Course)
      context.lock_all_announcements
    elsif context.context.is_a?(Course)
      context.context.lock_all_announcements
    elsif context.context.is_a?(Account)
      context.context.lock_all_announcements[:value]
    else
      false
    end
  end

  def lock(opts = {})
    raise Errors::LockBeforeDueDate unless can_lock?

    self.locked = true
    save! unless opts[:without_save]
  end
  alias_method :lock!, :lock

  def unlock(opts = {})
    self.locked = false
    self.workflow_state = "active" if workflow_state == "locked"
    save! unless opts[:without_save]
  end
  alias_method :unlock!, :unlock

  def published?
    return false if workflow_state == "unpublished"
    return false if workflow_state == "post_delayed" && is_announcement

    true
  end

  def can_unpublish?(opts = {})
    return @can_unpublish unless @can_unpublish.nil?

    @can_unpublish = if assignment
                       !assignment.has_student_submissions? && !assignment.has_student_submissions_for_sub_assignments?
                     elsif !opts[:has_student_entries].nil?
                       # Use preloaded data if available to avoid N+1 queries
                       !opts[:has_student_entries]
                     else
                       student_ids = opts[:student_ids] || context.all_real_student_enrollments.select(:user_id)
                       if for_group_discussion?
                         !DiscussionEntry.active.joins(:discussion_topic).merge(child_topics).where(user_id: student_ids).exists?
                       else
                         !discussion_entries.active.where(user_id: student_ids).exists?
                       end
                     end
  end

  def self.create_graded_topic!(course:, title:, user: nil)
    raise ActiveRecord::RecordInvalid if course.nil?

    assignment = course.assignments.create!(submission_types: "discussion_topic", updating_user: user, title:)
    assignment.discussion_topic
  end

  def self.preload_can_unpublish(context, topics, assmnt_ids_with_subs = nil)
    return unless topics.any?

    assignment_ids = topics.filter_map(&:assignment_id)
    assmnt_ids_with_subs ||= (Assignment.assignment_ids_with_submissions(assignment_ids) + Assignment.assignment_ids_with_sub_assignment_submissions(assignment_ids)).uniq

    student_ids = context.all_real_student_enrollments.select(:user_id)
    topic_ids_with_entries = DiscussionEntry.active.where(discussion_topic_id: topics)
                                            .where(user_id: student_ids).distinct.pluck(:discussion_topic_id)
    topic_ids_with_entries += DiscussionTopic.where.not(root_topic_id: nil)
                                             .where(id: topic_ids_with_entries).distinct.pluck(:root_topic_id)

    topics.each do |topic|
      topic.can_unpublish = if topic.assignment_id
                              !assmnt_ids_with_subs.include?(topic.assignment_id)
                            else
                              !topic_ids_with_entries.include?(topic.id)
                            end
    end
  end

  def self.preload_subentry_counts(topics)
    counts_by_topic_id = DiscussionEntry
                         .active
                         .where(discussion_topic_id: topics.pluck(:id))
                         .group(:discussion_topic_id)
                         .count

    topics.each { |topic| topic.preloaded_subentry_count = counts_by_topic_id.fetch(topic.id, 0) }
  end

  def can_group?(opts = {})
    can_unpublish?(opts)
  end

  def should_send_to_stream
    published? &&
      !not_available_yet? &&
      !cloned_item_id &&
      !(root_topic_id && has_group_category?) &&
      !in_unpublished_module? &&
      !locked_by_module?
  end

  on_create_send_to_streams do
    if should_send_to_stream
      active_participants_with_visibility
    end
  end

  on_update_send_to_streams do
    check_state = is_announcement ? "post_delayed" : "unpublished"
    became_active = workflow_state_before_last_save == check_state && workflow_state == "active"
    if should_send_to_stream && (@content_changed || became_active)
      active_participants_with_visibility
    end
  end

  # This is manually called for module publishing
  def send_items_to_stream
    if should_send_to_stream
      queue_create_stream_items
    end
  end

  def in_unpublished_module?
    return true if ContentTag.where(content_type: "DiscussionTopic", content_id: self, workflow_state: "unpublished").exists?

    ContextModule.joins(:content_tags).where(content_tags: { content_type: "DiscussionTopic", content_id: self }, workflow_state: "unpublished").exists?
  end

  def locked_by_module?
    return false unless context_module_tags.any?

    ContentTag.where(content_type: "DiscussionTopic", content_id: self, workflow_state: "active").all? { |tag| tag.context_module.unlock_at&.future? }
  end

  def should_clear_all_stream_items?
    (!published? && saved_change_to_attribute?(:workflow_state)) ||
      (is_announcement && not_available_yet? && (saved_change_to_attribute?(:delayed_post_at) || saved_change_to_attribute?(:unlock_at)))
  end

  def clear_non_applicable_stream_items
    return clear_stream_items if should_clear_all_stream_items?

    section = is_section_specific? ? @sections_changed : is_section_specific_before_last_save
    lock = locked_by_module?

    if lock || section
      delay_if_production.partially_clear_stream_items(locked_by_module: lock, section_specific: section)
    end
    if @overrides_changed
      delay_if_production.clear_invalid_stream_items
    end
  end

  def clear_invalid_stream_items
    user_ids = []

    stream_item&.stream_item_instances&.where(workflow_state: "unread")&.find_each do |item|
      destroy_item_and_track(item, user_ids) unless visible_for?(item.user)
    end
    clear_stream_item_cache_for(user_ids)
  end

  def partially_clear_stream_items(locked_by_module: false, section_specific: false)
    remaining_participants = participants if section_specific
    user_ids = []
    stream_item&.stream_item_instances&.shard(stream_item)&.find_each do |item|
      if (locked_by_module && locked_by_module_item?(item.user)) ||
         (section_specific && remaining_participants.none? { |p| p.id == item.user_id })
        destroy_item_and_track(item, user_ids)
      end
    end
    clear_stream_item_cache_for(user_ids)
  end

  def destroy_item_and_track(item, user_ids)
    user_ids.push(item.user_id)
    item.destroy
  end

  def clear_stream_item_cache_for(user_ids)
    if stream_item && user_ids.any?
      StreamItemCache.delay_if_production(priority: Delayed::LOW_PRIORITY)
                     .invalidate_all_recent_stream_items(
                       user_ids,
                       stream_item.context_type,
                       stream_item.context_id
                     )
    end
  end

  def require_initial_post?
    require_initial_post || root_topic&.require_initial_post
  end

  def user_ids_who_have_posted_and_admins
    ids = discussion_entries.active.select(:user_id).pluck(:user_id)
    ids = ids.uniq
    ids += course.admin_enrollments.active.pluck(:user_id) if course.is_a?(Course)
    ids
  end

  def user_can_see_posts?(user, session = nil, associated_user_ids = [])
    return false unless user

    !require_initial_post? || grants_right?(user, session, :read_as_admin) ||
      ([user.id] + associated_user_ids).intersect?(user_ids_who_have_posted_and_admins)
  end

  def locked_announcement?
    is_a?(Announcement) && locked?
  end

  def reply_from(opts)
    raise IncomingMail::Errors::ReplyToDeletedDiscussion if deleted?
    raise IncomingMail::Errors::UnknownAddress if context.root_account.deleted?

    user = opts[:user]
    if opts[:html]
      message = opts[:html].strip
    else
      message = opts[:text].strip
      message = format_message(message).first
    end
    user = nil unless user && context.users.include?(user)
    if !user
      raise IncomingMail::Errors::InvalidParticipant
    elsif !grants_right?(user, :read)
      nil
    else
      shard.activate do
        entry = discussion_entries.new(message:, user:)
        if entry.grants_right?(user, :create) && !comments_disabled? && !locked_announcement?
          entry.save!
          entry
        else
          raise IncomingMail::Errors::ReplyToLockedTopic
        end
      end
    end
  end

  alias_method :destroy_permanently!, :destroy
  def destroy
    ContentTag.delete_for(self)
    self.workflow_state = "deleted"
    self.deleted_at = Time.now.utc
    discussion_topic_section_visibilities&.update_all(workflow_state: "deleted")
    save

    if for_assignment? && root_topic_id.blank? && !assignment.deleted?
      assignment.skip_downstream_changes! if @skip_downstream_changes
      assignment.destroy
    end

    child_topics.each(&:destroy)
  end

  def restore(from = nil)
    unless restorable?
      errors.add(:deleted_at, I18n.t("Cannot undelete a child topic when the root course topic is also deleted. Please undelete the root course topic instead."))
      return false
    end
    if is_section_specific?
      DiscussionTopicSectionVisibility.where(discussion_topic_id: id).to_a.uniq(&:course_section_id).each do |dtsv|
        dtsv.workflow_state = "active"
        dtsv.save
      end
    end
    discussion_topic_section_visibilities.reload
    self.workflow_state = can_unpublish? ? "unpublished" : "active"
    save

    if from != :assignment && for_assignment? && root_topic_id.blank?
      assignment.restore(:discussion_topic)
    end

    child_topics.each(&:restore)
  end

  def restorable?
    # Not restorable if the root topic context is a course and
    # root topic is deleted.
    !(root_topic&.context_type == "Course" && root_topic&.deleted?)
  end

  def unlink!(type)
    @saved_by = type
    self.assignment = nil
    if discussion_entries.empty?
      destroy
    else
      save
    end
    child_topics.each { |t| t.unlink!(:assignment) }
  end

  def self.per_page
    10
  end

  def initialize_last_reply_at
    unless [:migration, :after_migration].include?(saved_by)
      self.posted_at ||= Time.now.utc
      self.last_reply_at ||= Time.now.utc
    end
  end

  set_policy do
    # Users may have can :read, but should not have access to all the data
    # because the topic is locked_for?(user)
    given { |user| visible_for?(user) }
    can :read

    given { |user| grants_right?(user, :read) }
    can :read_replies

    given { |user| self.user && self.user == user && visible_for?(user) && !locked_for?(user, check_policies: true) && can_participate_in_course?(user) && !comments_disabled? }
    can :reply

    given { |user| self.user && self.user == user && available_for?(user) && context.user_can_manage_own_discussion_posts?(user) && context.grants_right?(user, :participate_as_student) }
    can :update

    given { |user| self.user && self.user == user and discussion_entries.active.empty? && available_for?(user) && !root_topic_id && context.user_can_manage_own_discussion_posts?(user) && context.grants_right?(user, :participate_as_student) }
    can :delete

    given do |user, session|
      !locked_for?(user, check_policies: true) &&
        context.grants_right?(user, session, :post_to_forum) && visible_for?(user) && can_participate_in_course?(user) && !comments_disabled?
    end
    can :reply

    given { |user, session| user_can_create(user, session) }
    can :create

    given { |user, session| user_can_create(user, session) && user_can_duplicate(user, session) }
    can :duplicate

    given { |user, session| context.respond_to?(:allow_student_forum_attachments) && context.allow_student_forum_attachments && context.grants_any_right?(user, session, :create_forum, :post_to_forum) }
    can :attach

    given { course.student_reporting? }
    can :student_reporting

    given { |user, session| !root_topic_id && context.grants_all_rights?(user, session, :read_forum, :moderate_forum) && available_for?(user) }
    can :update and can :read_as_admin and can :delete and can :create and can :read and can :attach

    # Moderators can still modify content even in unavailable topics (*especially* unlocking them)
    given { |user, session| !root_topic_id && context.grants_all_rights?(user, session, :read_forum, :moderate_forum) }
    can :update and can :read_as_admin and can :delete and can :read and can :attach

    given { |user, session| root_topic&.grants_right?(user, session, :read_as_admin) }
    can :read_as_admin

    given { |user, session| root_topic&.grants_right?(user, session, :delete) }
    can :delete

    given { |user, session| root_topic&.grants_right?(user, session, :read) }
    can :read

    given { |user, session| context.grants_all_rights?(user, session, :moderate_forum, :read_forum) }
    can :moderate_forum

    given do |user, session|
      allow_rating && (!only_graders_can_rate ||
                            course.grants_right?(user, session, :manage_grades))
    end
    can :rate

    given do |user, session|
      next false unless user && context.is_a?(Course) && context.grants_right?(user, session, :moderate_forum)

      if assignment_id
        context.grants_right?(user, session, :manage_assignments_edit)
      else
        context.user_is_admin?(user) || context.account_membership_allows(user) || !context.visibility_limited_to_course_sections?(user)
      end
    end
    can :manage_assign_to

    given do |user, session|
      next false unless user && context.is_a?(Course) && context.grants_right?(user, session, :create_forum)

      if assignment_id
        context.grants_right?(user, session, :manage_assignments_add)
      else
        context.user_is_admin?(user) || context.account_membership_allows(user) || !context.visibility_limited_to_course_sections?(user)
      end
    end
    can :create_assign_to
  end

  def self.context_allows_user_to_create?(context, user, session)
    new(context:).grants_right?(user, session, :create)
  end

  def context_allows_user_to_create?(user)
    return true unless context.respond_to?(:allow_student_discussion_topics)
    return true if context.grants_right?(user, :read_as_admin)

    context.allow_student_discussion_topics
  end

  def user_can_create(user, session)
    !is_announcement &&
      context.grants_any_right?(user, session, :create_forum, :moderate_forum) &&
      context_allows_user_to_create?(user)
  end

  def user_can_duplicate(user, session)
    context.is_a?(Group) ||
      course.user_is_instructor?(user) ||
      context.grants_right?(user, session, :read_as_admin)
  end

  def user_can_summarize?(user)
    if is_announcement
      return false
    end

    # course can be an account in case the topic context is group
    # and the group context is account
    unless course.is_a?(Course)
      return false
    end

    course.feature_enabled?(:discussion_summary) && (
      course.user_is_instructor?(user) || course.grants_right?(user, :read_as_admin)
    )
  end

  def user_can_access_insights?(user)
    if is_announcement
      return false
    end

    # course can be an account in case the topic context is group
    # and the group context is account
    unless course.is_a?(Course)
      return false
    end

    course.feature_enabled?(:discussion_insights) && (
      course.user_is_instructor?(user) || course.grants_right?(user, :read_as_admin)
    )
  end

  def discussion_topic_id
    id
  end

  def discussion_topic
    self
  end

  def to_atom(opts = {})
    author_name = user.present? ? user.name : t("#discussion_topic.atom_no_author", "No Author")
    prefix = [is_announcement ? t("#titles.announcement", "Announcement") : t("#titles.discussion", "Discussion")]
    prefix << context.name if opts[:include_context]

    {
      title: [before_label(prefix.to_sentence), title].join(" "),
      author: author_name,
      updated: updated_at,
      published: created_at,
      id: "tag:#{HostUrl.default_host},#{created_at.strftime("%Y-%m-%d")}:/discussion_topics/#{feed_code}",
      link: "http://#{HostUrl.context_host(context)}/#{context_url_prefix}/discussion_topics/#{id}",
      content: message || ""
    }
  end

  def context_prefix
    context_url_prefix
  end

  def context_module_action(user, action, points = nil)
    return root_topic.context_module_action(user, action, points) if root_topic

    tags_to_update = context_module_tags.to_a
    if for_assignment?
      tags_to_update += assignment.context_module_tags
      if context.grants_right?(user, :participate_as_student) && assignment.visible_to_user?(user) && [:contributed, :deleted].include?(action)
        only_update = (action == :deleted) # if we're deleting an entry, don't make a submission if it wasn't there already
        ensure_submission(user, only_update)
      end
    end
    unless action == :deleted
      tags_to_update.each { |tag| tag.context_module_action(user, action, points) }
    end
  end

  def ensure_submission(user, only_update = false)
    topic = (root_topic? && child_topic_for(user)) || self

    submissions = []
    all_entries_for_user = topic.discussion_entries.all_for_user(user)

    if topic.context.discussion_checkpoints_enabled? && checkpoints?
      reply_to_topic_submitted_at = topic.discussion_entries.top_level_for_user(user).minimum(:created_at)

      if reply_to_topic_submitted_at.present?
        reply_to_topic_submission = ensure_particular_submission(reply_to_topic_checkpoint, user, reply_to_topic_submitted_at, only_update:)
        submissions << reply_to_topic_submission if reply_to_topic_submission.present?
      end

      reply_to_entries = topic.discussion_entries.non_top_level_for_user(user)

      if reply_to_entries.any? && enough_replies_for_checkpoint?(reply_to_entries)
        reply_to_entry_submitted_at = reply_to_entries.minimum(:created_at)
        reply_to_entry_submission = ensure_particular_submission(reply_to_entry_checkpoint, user, reply_to_entry_submitted_at, only_update:)
        submissions << reply_to_entry_submission if reply_to_entry_submission.present?
      end
    else
      submitted_at = all_entries_for_user.minimum(:created_at)

      submission = ensure_particular_submission(assignment, user, submitted_at, only_update:)
      submissions << submission if submission.present?
    end

    return unless submissions.any?

    attachment_ids = all_entries_for_user.where.not(attachment_id: nil).pluck(:attachment_id).sort.map(&:to_s).join(",")

    submissions.each do |s|
      s.attachment_ids = attachment_ids
      s.save! if s.changed?
    end
  end

  def ensure_particular_submission(assignment, user, submitted_at, only_update: false)
    submission = Submission.active.where(assignment_id: assignment.id, user_id: user).first
    unless only_update || (submission && submission.submission_type == "discussion_topic" && submission.workflow_state != "unsubmitted")
      submission = assignment.submit_homework(user,
                                              submission_type: "discussion_topic",
                                              submitted_at:)
    end

    submission
  end

  def send_notification_for_context?
    notification_context =
      if context.is_a?(Group) && context.context.is_a?(Course)
        context.context # we need to go deeper
      else
        context
      end
    notification_context.available?
  end

  def course_broadcast_data
    context&.broadcast_data
  end

  has_a_broadcast_policy

  set_broadcast_policy do |p|
    p.dispatch :new_discussion_topic
    p.to { users_with_permissions(active_participants_with_visibility) }
    p.whenever do |record|
      record.send_notification_for_context? and
        ((record.previously_new_record? && record.active?) || record.changed_state(:active, record.is_announcement ? :post_delayed : :unpublished))
    end
    p.data { course_broadcast_data }
  end

  def delay_posting=(val); end

  def set_assignment=(val); end

  # From the given list of users, return those that are permitted to see the section
  # of the topic.  If the topic is not section specific this just returns the
  # original list.
  def users_with_section_visibility(users)
    return users unless is_section_specific? && context.is_a?(Course)

    non_nil_users = users.compact
    section_ids = DiscussionTopicSectionVisibility.active.where(discussion_topic_id: id)
                                                  .pluck(:course_section_id)
    user_ids = non_nil_users.pluck(:id)
    # Context is known to be a course here
    users_in_sections = context.enrollments.active_or_pending
                               .where(user_id: user_ids, course_section_id: section_ids).pluck(:user_id).to_set
    unlocked_teachers = context.enrollments.active_or_pending.instructor
                               .where(limit_privileges_to_course_section: false, user_id: user_ids)
                               .pluck(:user_id).to_set
    permitted_user_ids = users_in_sections.union(unlocked_teachers)
    non_nil_users.select { |u| permitted_user_ids.include?(u.id) }
  end

  def participants(include_observers = false)
    participants = context.participants(include_observers:, by_date: true)
    participants_in_section = users_with_section_visibility(participants.compact)
    if user && !participants_in_section.to_set(&:id).include?(user.id)
      participants_in_section += [user]
    end
    participants_in_section
  end

  def visible_to_admins_only?
    (context.respond_to?(:available?) && !context.available?) ||
      unpublished? || not_available_yet? || not_available_anymore?
  end

  def active_participants(include_observers = false)
    if visible_to_admins_only? && context.respond_to?(:participating_admins)
      context.participating_admins
    else
      participants(include_observers)
    end
  end

  def active_participants_include_tas_and_teachers(include_observers = false)
    participants = active_participants(include_observers)
    if context.is_a?(Group) && !context.course.nil?
      participants += context.course.participating_instructors_by_date
      participants = participants.compact.uniq
    end
    participants
  end

  def users_with_permissions(users)
    permission = is_announcement ? :read_announcements : :read_forum
    course = self.course
    unless course.is_a?(Course)
      return users.select do |u|
        is_announcement ? context.grants_right?(u, :read_announcements) : context.grants_right?(u, :read_forum)
      end
    end

    readers = self.course.filter_users_by_permission(users, permission)
    users_with_section_visibility(readers)
  end

  def course
    @course ||= context.is_a?(Group) ? context.context : context
  end

  def group
    @group ||= context.is_a?(Group) ? context : nil
  end

  def active_participants_with_visibility
    return active_participants_include_tas_and_teachers unless for_assignment? || assignment_overrides.active.any?

    users_with_visibility = for_assignment? ? assignment.students_with_visibility.pluck(:id) : []

    assignment_overrides.select(&:active?).each do |override|
      # specific user
      if override.adhoc?
        adhoc_users = users_with_visibility.concat(override.assignment_override_students.pluck(:user_id))
        users_with_visibility.concat(adhoc_users)
      elsif override.course_section?
        users_in_section = User.joins(:enrollments).where(enrollments: { course_section_id: override.set_id }).pluck(:id)
        users_with_visibility.concat(users_in_section)
      end
    end

    admin_ids = course.participating_admins.pluck(:id)
    users_with_visibility.concat(admin_ids)
    users_with_visibility.uniq!

    # observers will not be returned, which is okay for the functions current use cases (but potentially not others)
    active_participants_include_tas_and_teachers.select { |p| users_with_visibility.include?(p.id) }
  end

  def participating_users(user_ids)
    context.respond_to?(:participating_users) ? context.participating_users(user_ids) : User.find(user_ids)
  end

  def subscribers
    # this duplicates some logic from #subscribed? so we don't have to call
    # #posters for each legacy subscriber.
    sub_ids = discussion_topic_participants.where(subscribed: true).pluck(:user_id)
    legacy_sub_ids = discussion_topic_participants.where(subscribed: nil).pluck(:user_id)
    poster_ids = posters.map(&:id)
    legacy_sub_ids &= poster_ids
    sub_ids += legacy_sub_ids

    subscribed_users = participating_users(sub_ids).to_a

    filter_message_users(subscribed_users)
  end

  def filter_message_users(users)
    if for_assignment?
      students_with_visibility = assignment.students_with_visibility.pluck(:id)

      admin_ids = course.participating_admins.pluck(:id)
      observer_ids = course.participating_observers.pluck(:id)
      observed_students = ObserverEnrollment.observed_student_ids_by_observer_id(course, observer_ids)

      users.select! do |user|
        students_with_visibility.include?(user.id) || admin_ids.include?(user.id) ||
          # an observer with no students or one with students who have visibility
          (observed_students[user.id] && (observed_students[user.id] == [] || observed_students[user.id].intersect?(students_with_visibility)))
      end
    end
    users
  end

  def posters
    user_ids = discussion_entries.map(&:user_id).push(user_id).uniq
    participating_users(user_ids)
  end

  def user_name
    user&.name
  end

  def available_from_for(user)
    if assignment
      assignment.overridden_for(user).unlock_at
    else
      available_from
    end
  end

  def available_for?(user, opts = {})
    return false unless published?
    return false if is_announcement && locked?

    !locked_for?(user, opts)
  end

  # Public: Determine if the given user can view this discussion topic.
  #
  # user - The user attempting to view the topic (default: nil).
  #
  # Returns a boolean.
  def visible_for?(user = nil)
    RequestCache.cache("discussion_visible_for", self, is_announcement, user) do
      # user is the topic's author
      next true if user && user.id == user_id

      next false unless context
      next false unless is_announcement ? context.grants_right?(user, :read_announcements) : context.grants_right?(user, :read_forum)

      # Don't have visibilites for any of the specific sections in a section specific topic
      if context.is_a?(Course) && try(:is_section_specific)
        section_visibilities = context.course_section_visibility(user)
        next false if section_visibilities == :none

        if section_visibilities != :all
          course_section_ids = shard.activate { course_sections.ids }

          next false unless section_visibilities.intersect?(course_section_ids)
        end
      end
      # Verify that section limited teachers/ta's are properly restricted
      if context.is_a?(Course) && !visible_to_everyone && context.user_is_instructor?(user)

        section_overrides = assignment_overrides.active.where(set_type: "CourseSection").pluck(:set_id)
        visible_sections_for_user = context.course_section_visibility(user)
        next false if visible_sections_for_user == :none

        # If there are no section_overrides, then no check for section_specific instructor roles is needed
        if visible_sections_for_user != :all && section_overrides.any?
          next false unless visible_sections_for_user.intersect?(section_overrides)
        end
      end
      # user is an admin in the context (teacher/ta/designer) OR
      # user is an account admin with appropriate permission
      next true if context.grants_any_right?(user, :manage, :read_as_admin)

      # assignment exists and isn't assigned to user (differentiated assignments)
      if for_assignment?
        next false unless assignment.visible_to_user?(user)
      # Announcements can be section specific, but that is already handled above.
      # Eventually is_section_specific will be replaced with assignment overrides, and then announcements will need to be handled
      elsif !is_announcement
        next false unless visible_to_user?(user)
      end

      # topic is not published
      next false unless published?

      # unlock_at and lock_at determine visibility for announcements
      if is_announcement
        next false if lock_at && Time.now.utc > lock_at
        next false if unlock_at && unlock_at > Time.now.utc
      end

      next true
    end
  end

  def can_participate_in_course?(user)
    if group&.deleted?
      false
    elsif course.is_a?(Course)
      # this probably isn't a perfect way to determine this but I can't think of a better one
      course.enrollments.for_user(user).active_by_date.exists? || course.grants_right?(user, :read_as_admin)
    else
      true
    end
  end

  # Determine if the discussion topic is locked for a user. The topic is locked
  # if the delayed_post_at is in the future or the assignment is locked.
  # This does not determine the visibility of the topic to the user,
  # only that they are unable to reply and unable to see the message.
  # Generally you want to call :locked_for?(user, check_policies: true), which
  # will call this method.
  def low_level_locked_for?(user, opts = {})
    return false if opts[:check_policies] && grants_right?(user, :read_as_admin)

    RequestCache.cache(locked_request_cache_key(user)) do
      locked = false
      # get the topic's overridden availability dates for the user. If graded, the dates will be on the assignment.
      topic_for_user = assignment.present? ? assignment.overridden_for(user) : overridden_for(user)
      # prefer unlock_at, but fall back to delayed_post_at for DiscussionTopics until the latter is removed
      overridden_unlock_at = topic_for_user.unlock_at
      overridden_unlock_at ||= topic_for_user.delayed_post_at if topic_for_user.respond_to?(:delayed_post_at)
      overridden_lock_at = topic_for_user.lock_at
      if overridden_unlock_at && overridden_unlock_at > Time.zone.now
        locked = { object: self, unlock_at: overridden_unlock_at }
      elsif overridden_lock_at && overridden_lock_at < Time.zone.now
        locked = { object: self, lock_at: overridden_lock_at, can_view: true }
      elsif could_be_locked && (item = locked_by_module_item?(user, opts))
        locked = { object: self, module: item.context_module }
      elsif locked? # nothing more specific, it's just locked
        locked = { object: self, can_view: true }
      elsif (l = root_topic&.low_level_locked_for?(user, opts)) # rubocop:disable Lint/DuplicateBranch
        locked = l
      end
      locked
    end
  end

  def show_in_search_for_user?(user)
    return false unless user && !deleted?
    return false if anonymous? && !context.feature_enabled?(:react_discussions_post)
    return true if context.grants_right?(user, :read_as_admin)
    return false if locked_by_module_item?(user)

    locked = locked_for?(user, check_policies: true, deep_check_if_needed: true)
    locked.is_a?(Hash) ? !!locked[:can_view] : visible_for?(user)
  end

  def self.reject_context_module_locked_topics(topics, user)
    progressions = ContextModuleProgression
                   .joins(context_module: :content_tags)
                   .where({
                            :user => user,
                            "content_tags.content_type" => "DiscussionTopic",
                            "content_tags.content_id" => topics,
                          })
                   .select("context_module_progressions.*")
                   .distinct_on("context_module_progressions.id")
                   .preload(:user)
    progressions = progressions.index_by(&:context_module_id)

    topics.reject do |topic|
      topic.locked_by_module_item?(user, {
                                     deep_check_if_needed: true,
                                     user_context_module_progressions: progressions,
                                   })
    end
  end

  def entries_for_feed(user, podcast_feed = false)
    return [] unless user_can_see_posts?(user)
    return [] if locked_for?(user, check_policies: true)

    entries = discussion_entries.active
    if podcast_feed && !podcast_has_student_posts && context.is_a?(Course)
      entries = entries.where(user_id: context.admins)
    end
    entries
  end

  def all_child_entries_from_user(user)
    return [] unless for_group_discussion?

    child_topics.map do |t|
      t.discussion_entries.active.for_user(user)
    end.flatten.sort_by(&:created_at)
  end

  def self.podcast_elements(messages, context)
    attachment_ids = []
    media_object_ids = []
    messages_hash = {}
    messages.each do |message|
      txt = message.message || ""
      attachment_matches = txt.scan(%r{/#{context.class.to_s.pluralize.underscore}/#{context.id}/files/(\d+)/download})
      attachment_ids += (attachment_matches || []).pluck(0)
      media_object_matches = txt.scan(/media_comment_([\w-]+)/) + txt.scan(/data-media-id="([\w-]+)"/)
      media_object_ids += (media_object_matches || []).pluck(0).uniq
      (attachment_ids + media_object_ids).each do |id|
        messages_hash[id] ||= message
      end
    end

    media_object_ids = media_object_ids.uniq.compact
    attachment_ids = attachment_ids.uniq.compact
    attachments = attachment_ids.empty? ? [] : context.attachments.active.find_all_by_id(attachment_ids)
    attachments = attachments.select { |a| a.content_type&.match(/(video|audio)/) }
    attachments.each do |attachment|
      attachment.podcast_associated_asset = messages_hash[attachment.id.to_s]
    end
    media_object_ids -= attachments.filter_map(&:media_entry_id) # don't include media objects if the file is already included

    media_objects = media_object_ids.empty? ? [] : MediaObject.where(media_id: media_object_ids).to_a
    media_objects = media_objects.uniq(&:media_id)
    media_objects = media_objects.map do |media_object|
      if media_object.media_id == "maybe" || media_object.deleted? || (media_object.context_type != "User" && media_object.context != context)
        media_object = nil
      end
      if media_object&.podcast_format_details
        media_object.podcast_associated_asset = messages_hash[media_object.media_id]
      end
      media_object
    end

    to_podcast(attachments + media_objects.compact)
  end

  def self.to_podcast(elements)
    require "rss/2.0"
    elements.filter_map do |elem|
      asset = elem.podcast_associated_asset
      next unless asset

      item = RSS::Rss::Channel::Item.new
      item.title = before_label(asset.title) + elem.name
      link = nil
      case asset
      when DiscussionTopic
        link = "http://#{HostUrl.context_host(asset.context)}/#{asset.context_url_prefix}/discussion_topics/#{asset.id}"
      when DiscussionEntry
        link = "http://#{HostUrl.context_host(asset.context)}/#{asset.context_url_prefix}/discussion_topics/#{asset.discussion_topic_id}#entry-#{asset.id}"
      end

      item.link = link
      item.guid = RSS::Rss::Channel::Item::Guid.new
      item.pubDate = elem.updated_at.utc
      item.description = asset ? asset.message : elem.name
      item.enclosure
      case elem
      when Attachment
        item.guid.content = link + "/#{elem.uuid}"
        url = "http://#{HostUrl.context_host(elem.context)}/#{elem.context_url_prefix}" \
              "/files/#{elem.id}/download#{elem.extension}?verifier=#{elem.uuid}"
        item.enclosure = RSS::Rss::Channel::Item::Enclosure.new(url, elem.size, elem.content_type)
      when MediaObject
        item.guid.content = link + "/#{elem.media_id}"
        details = elem.podcast_format_details
        content_type = "video/mpeg"
        content_type = "audio/mpeg" if elem.media_type == "audio"
        size = details[:size].to_i.kilobytes
        ext = details[:extension] || details[:fileExt]
        url = "http://#{HostUrl.context_host(elem.context)}/#{elem.context_url_prefix}" \
              "/media_download.#{ext}?type=#{ext}&entryId=#{elem.media_id}&redirect=1"
        item.enclosure = RSS::Rss::Channel::Item::Enclosure.new(url, size, content_type)
      end
      item
    end
  end

  def initial_post_required?(user, session = nil)
    if require_initial_post?
      associated_user_ids = user.observer_enrollments.active.where(course_id: course).pluck(:associated_user_id).compact
      return !user_can_see_posts?(user, session, associated_user_ids)
    end
    false
  end

  # returns the materialized view of the discussion as structure, participant_ids, and entry_ids
  # the view is already converted to a json string, the other two arrays of ids are ruby arrays
  # see the description of the format in the discussion topics api documentation.
  #
  # returns nil if the view is not currently available, and kicks off a
  # background job to build the view. this typically only takes a couple seconds.
  #
  # if a new message is posted, it won't appear in this view until the job to
  # update it completes. so this view is eventually consistent.
  #
  # if the topic itself is not yet created, it will return blank data. this is for situations
  # where we're creating topics on the first write - until that first write, we need to return
  # blank data on reads.
  def materialized_view(opts = {})
    if new_record?
      ["[]", [], [], []]
    else
      DiscussionTopic::MaterializedView.materialized_view_for(self, opts)
    end
  end

  # synchronously create/update the materialized view
  def create_materialized_view
    DiscussionTopic::MaterializedView.for(self).update_materialized_view(synchronous: true, use_master: true)
  end

  def grading_standard_or_default
    grading_standard_context = assignment || context

    if grading_standard_context.present?
      grading_standard_context.grading_standard_or_default
    else
      GradingStandard.default_instance
    end
  end

  def set_root_account_id
    self.root_account_id ||= context&.root_account_id
  end

  def anonymous?
    !anonymous_state.nil?
  end

  def checkpoints?
    sub_assignments.any?
  end

  def reply_to_topic_checkpoint
    sub_assignments.find_by(sub_assignment_tag: CheckpointLabels::REPLY_TO_TOPIC)
  end

  def reply_to_entry_checkpoint
    sub_assignments.find_by(sub_assignment_tag: CheckpointLabels::REPLY_TO_ENTRY)
  end

  def create_checkpoints(reply_to_topic_points:, reply_to_entry_points:, reply_to_entry_required_count: 1)
    return false if checkpoints?
    return false unless context.is_a?(Course)
    return false unless assignment.present?

    Checkpoints::DiscussionCheckpointCreatorService.call(
      discussion_topic: self,
      checkpoint_label: CheckpointLabels::REPLY_TO_TOPIC,
      dates: [],
      points_possible: reply_to_topic_points
    )

    Checkpoints::DiscussionCheckpointCreatorService.call(
      discussion_topic: self,
      checkpoint_label: CheckpointLabels::REPLY_TO_ENTRY,
      dates: [],
      points_possible: reply_to_entry_points,
      replies_required: reply_to_entry_required_count
    )
  end

  def self.visible_ids_by_user(opts)
    # Discussions with an assignment: pluck id, assignment_id, and user_id from items joined with the SQL view
    visible_assignments = AssignmentVisibility::AssignmentVisibilityService.assignments_visible_to_students(user_ids: opts[:user_id], course_ids: opts[:course_id])
    # map the visibilities to a hash of assignment_id => [user_ids]
    assignment_user_map = visible_assignments.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |visibility, hash|
      hash[visibility.assignment_id] << visibility.user_id
    end
    # this mimicks the format of the non-flagged group_by to pair each user_id to the correct visible discussion/discussion's assignment
    plucked_visibilities = where(assignment_id: assignment_user_map.keys)
                           .pluck(:id, :assignment_id)
                           .flat_map { |discussion_id, assignment_id| assignment_user_map[assignment_id].map { |user_id| [discussion_id, assignment_id, user_id] } }
                           .group_by { |_, _, user_id| user_id }

    # Initialize dictionaries for different visibility scopes
    ids_visible_to_all = []

    # Get Section specific discussions:
    sections_per_user = {}
    Enrollment.active.where(course_id: opts[:course_id], user_id: opts[:user_id])
              .pluck(:user_id, :course_section_id)
              .each { |user_id, section_id| (sections_per_user[user_id] ||= Set.new) << section_id }

    # build hash of section_ids to array of visible topic ids
    all_section_ids = sections_per_user.values.reduce([]) { |all_ids, section_ids| all_ids.concat(section_ids.to_a) }
    topic_ids_per_section = {}
    DiscussionTopicSectionVisibility.active.where(course_section_id: all_section_ids)
                                    .pluck(:course_section_id, :discussion_topic_id)
                                    .each { |section_id, topic_id| (topic_ids_per_section[section_id] ||= Set.new) << topic_id }
    topic_ids_per_section.each { |section_id, topic_ids| topic_ids_per_section[section_id] = topic_ids.to_a }

    # finally, build hash of user_ids to array of visible topic ids
    topic_ids_per_user = {}
    opts[:user_id].each { |user_id| topic_ids_per_user[user_id] = sections_per_user[user_id]&.map { |section_id| topic_ids_per_section[section_id] }&.flatten&.uniq&.compact }
    ids_visible_to_sections = topic_ids_per_user

    visible_topic_user_id_pairs = UngradedDiscussionVisibility::UngradedDiscussionVisibilityService.discussion_topics_visible(user_ids: opts[:user_id], course_ids: opts[:course_id]).map { |visibility| [visibility.discussion_topic_id, visibility.user_id] }
    eligible_topic_ids = DiscussionTopic.where(id: visible_topic_user_id_pairs.map(&:first)).where(assignment_id: nil).where.not(is_section_specific: true).pluck(:id)
    eligible_visible_topic_user_id_pairs = visible_topic_user_id_pairs.select { |discussion_topic_id, _user_id| eligible_topic_ids.include?(discussion_topic_id) } # rubocop:disable Style/HashSlice
    ungraded_differentiated_topic_ids_per_user = eligible_visible_topic_user_id_pairs.group_by(&:last).transform_values { |pairs| pairs.map(&:first) }

    # build map of user_ids to array of item ids {1 => [2,3,4], 2 => [2,4]}
    opts[:user_id].index_with do |student_id|
      assignment_item_ids = (plucked_visibilities[student_id] || []).map { |id, _, _| id }
      section_specific_ids = ids_visible_to_sections[student_id] || []
      ungraded_differentiated_specific_ids = ungraded_differentiated_topic_ids_per_user[student_id] || []
      assignment_item_ids.concat(ids_visible_to_all).concat(section_specific_ids).concat(ungraded_differentiated_specific_ids)
    end
  end

  def set_edited_at
    if (will_save_change_to_message? || will_save_change_to_title?) && !new_record?
      self.edited_at = Time.now.utc
    end
  end

  def ungraded_discussion_overrides(current_user = nil)
    current_user ||= self.current_user
    return unless current_user
    return nil if assignment.present? || context_type == "Group" || is_announcement

    overrides = AssignmentOverrideApplicator.overrides_for_assignment_and_user(self, current_user)

    # this is a temporary check for any discussion_topic_section_visibilities until we eventually backfill that table
    if is_section_specific
      section_overrides = assignment_overrides.active.where(set_type: "CourseSection").select(:set_id)
      section_visibilities = discussion_topic_section_visibilities.active.where.not(course_section_id: section_overrides)
    end

    if section_visibilities
      section_overrides = section_visibilities.map do |section_visibility|
        assignment_override = AssignmentOverride.new(
          discussion_topic: section_visibility.discussion_topic,
          course_section: section_visibility.course_section
        )
        assignment_override.unlock_at = unlock_at if unlock_at
        assignment_override.lock_at = lock_at if lock_at
        assignment_override
      end
    end

    all_overrides = overrides.to_a
    all_overrides += section_overrides if section_visibilities
    all_overrides
  end

  def sanitized_sort_order
    if DiscussionTopic::SortOrder::TYPES.include?(sort_order)
      sort_order
    else
      DiscussionTopic::SortOrder::DEFAULT
    end
  end

  def sort_order_for_user(current_user = nil)
    return sanitized_sort_order if sort_order_locked

    current_user ||= self.current_user
    participant_sort_order = participant(current_user)&.sort_order
    participant_sort_order = sanitized_sort_order if participant_sort_order == DiscussionTopic::SortOrder::INHERIT
    participant_sort_order || DiscussionTopic::SortOrder::DEFAULT
  end

  def expanded_for_user(current_user = nil)
    return expanded if expanded_locked

    current_user ||= self.current_user
    participant_expanded = participant(current_user)&.expanded
    if participant_expanded.nil?
      return expanded
    end

    participant_expanded
  end

  private

  def enough_replies_for_checkpoint?(reply_to_entries)
    reply_to_entries.count >= reply_to_entry_required_count
  end

  # For the current business logic we don't allow collapsed discussion locking in any scenarios
  def collapsed_not_enforced
    if !expanded && expanded_locked
      errors.add(:expanded_locked, t("Cannot lock a collapsed discussion"))
    end
  end
end
