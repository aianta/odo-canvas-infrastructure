# frozen_string_literal: true

#
# Copyright (C) 2012 - 2013 Instructure, Inc.
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
require_relative "../api_spec_helper"

describe "Account Notification API", type: :request do
  include Api
  include Api::V1::AccountNotifications

  before do
    @admin = account_admin_user
    user_with_pseudonym(user: @admin)
  end

  describe "user_index" do
    before do
      account_notification(message: "default")
      @path = "/api/v1/accounts/#{@admin.account.id}/account_notifications"
      @api_params = { controller: "account_notifications",
                      action: "user_index",
                      format: "json",
                      account_id: @admin.account.id.to_s }
    end

    let(:second_announcement) { account_notification(message: "second") }
    let(:third_announcement) { account_notification(message: "future", start_at: 1.day.from_now, end_at: 3.days.from_now) }

    it "lists notifications" do
      second_announcement
      third_announcement
      json = api_call(:get, @path, @api_params)
      expect(json.length).to eq 2
      expect(json.pluck("message")).to match_array(%w[default second])
    end

    it "still works on the old endpoint" do
      json = api_call(:get, "/api/v1/accounts/#{@admin.account.id}/users/#{@admin.id}/account_notifications", {
                        controller: "account_notifications",
                        action: "user_index_deprecated",
                        format: "json",
                        user_id: @admin.id.to_s,
                        account_id: @admin.account.id.to_s
                      })
      expect(json.pluck("message")).to eq %w[default]
    end

    it "catches a user_id mismatch on the old endpoint" do
      other_user = User.create!
      api_call(:get,
               "/api/v1/accounts/#{@admin.account.id}/users/#{other_user.id}/account_notifications",
               {
                 controller: "account_notifications",
                 action: "user_index_deprecated",
                 format: "json",
                 user_id: other_user.id.to_s,
                 account_id: @admin.account.id.to_s
               },
               {},
               { expected_status: 404 })
    end

    it "includes dismissed past announcements" do
      @user.close_announcement(second_announcement)
      json = api_call(:get, @path, @api_params.merge(include_past: true))
      expect(json.length).to eq 2
    end

    describe "include_all param" do
      it "includes all announcements for an admin" do
        third_announcement
        student_role = @account.get_role_by_name("StudentEnrollment")
        @user.close_announcement(second_announcement)
        account_notification(message: "student_only", role_ids: [student_role.id])
        json = api_call(:get, @path, @api_params.merge(include_all: true))

        expect(json.length).to eq 4
        messages = json.pluck("message")
        expect(messages).to match_array(%w[default second student_only future])
      end

      it "returns bad request if non admin user tries to call with include_all" do
        non_admin = user_with_managed_pseudonym(account: @admin.account)
        api_call_as_user(non_admin, :get, @path, @api_params.merge(include_all: true))

        expect(response).to have_http_status :forbidden
      end
    end

    it "does not include dismissed past announcements by default" do
      @user.close_announcement(second_announcement)
      json = api_call(:get, @path, @api_params)
      expect(json.length).to eq 1
    end

    describe "show_is_closed param" do
      before do
        @api_params = { controller: "account_notifications",
                        action: "user_index",
                        format: "json",
                        account_id: @user.account.id.to_s,
                        include_all: true,
                        show_is_closed: true }
        @notification = account_notification(message: "show_is_closed")
      end

      it "includes closed flag for notifications when show_is_closed is true" do
        @user.close_announcement(@notification)
        json = api_call(:get, @path, @api_params)

        expect(json.length).to eq 2
        expect(json.first["closed"]).to be true
        expect(json.second["closed"]).to be false
      end

      it "does not include closed flag for notifications when show_is_closed is false" do
        @user.close_announcement(@notification)
        json = api_call(:get, @path, @api_params.merge(show_is_closed: false))

        expect(json.length).to eq 2
        expect(json.first["closed"]).to be_nil
        expect(json.second["closed"]).to be_nil
      end
    end
  end

  describe "show" do
    before do
      @an = account_notification(message: "default")
      @path = "/api/v1/accounts/#{@admin.account.id}/account_notifications/#{@an.id}"
      @api_params = { controller: "account_notifications",
                      action: "show",
                      format: "json",
                      id: @an.id,
                      account_id: @admin.account.id.to_s }
    end

    it "shows a notification" do
      json = api_call(:get, @path, @api_params)
      expect(json["id"]).to eq @an.id
    end

    it "shows the notification as a non admin" do
      user = user_with_managed_pseudonym(account: @admin.account)

      @path = "/api/v1/accounts/#{user.account.id}/account_notifications/#{@an.id}"

      @api_params = { controller: "account_notifications",
                      action: "show",
                      format: "json",
                      id: @an.id,
                      account_id: @user.account.id.to_s }

      json = api_call(:get, @path, @api_params)
      expect(json["id"]).to eq @an.id
    end
  end

  describe "user_close_notification" do
    before do
      @a = account_notification(message: "default")
      @account = @admin.account
      @path = "/api/v1/accounts/#{@account.id}/account_notifications/#{@a.id}"
      @api_params = { controller: "account_notifications",
                      action: "user_close_notification",
                      format: "json",
                      id: @a.id.to_param,
                      account_id: @admin.account.id.to_s }
    end

    context "as an admin" do
      it "closes notification" do
        api_call(:delete, @path, @api_params)
        expect(response).to have_http_status :ok

        @admin.reload
        expect(@admin.get_preference(:closed_notifications)).to eq [@a.id]

        json = api_call(:get, "/api/v1/accounts/#{@account.id}/account_notifications", @api_params.merge(action: "user_index"))
        expect(json.length).to eq 0
      end

      it "does not soft-delete the notification unless the remove parameter has the value true" do
        expect(AccountNotification.find_by(id: @a.id)).not_to be_nil

        api_call(:delete, @path, @api_params.merge(remove: ""))
        expect(response).to have_http_status :ok
        expect(AccountNotification.find_by(id: @a.id).active?).to be true
      end

      it "soft-deletes the notification if a remove=true parameter is passed" do
        expect(AccountNotification.find_by(id: @a.id)).not_to be_nil

        api_call(:delete, @path, @api_params.merge(remove: "true"))
        expect(response).to have_http_status :ok
        expect(AccountNotification.find_by(id: @a.id).deleted?).to be true
      end
    end

    context "as a non-admin" do
      before do
        @non_admin = user_with_managed_pseudonym(account: @account)
      end

      it "closes notification" do
        expect(@non_admin.get_preference(:closed_notifications)).to be_nil

        api_call_as_user(@non_admin, :delete, @path, @api_params)
        expect(response).to have_http_status :ok

        @non_admin.reload
        expect(@non_admin.get_preference(:closed_notifications)).to eq [@a.id]

        json = api_call(:get, "/api/v1/accounts/#{@account.id}/account_notifications", @api_params.merge(action: "user_index"))
        expect(json.length).to eq 0
      end

      it "does not delete notification" do
        api_call_as_user(@non_admin, :delete, @path, @api_params.merge(remove: "true"))

        expect(response).to have_http_status :forbidden
      end
    end
  end

  describe "create" do
    before do
      @path = "/api/v1/accounts/#{@admin.account.id}/account_notifications"
      @api_params = { controller: "account_notifications",
                      action: "create",
                      format: "json",
                      account_id: @admin.account.id.to_s }
      @start_at = Time.zone.now.utc
      @end_at = 1.day.from_now.utc
    end

    it "creates an account notification" do
      json = api_call(:post,
                      @path,
                      @api_params,
                      { account_notification: {
                        subject: "New global notification",
                        start_at: @start_at.iso8601,
                        end_at: @end_at.iso8601,
                        message: "This is a notification",
                        icon: "information"
                      } })
      expect(json.keys).to include "start_at"
      expect(json.keys).to include "end_at"
      expect(json["subject"]).to eq "New global notification"
      expect(json["message"]).to eq "This is a notification"
      expect(json["icon"]).to eq "information"
      expect(json["roles"]).to eq []
    end

    it "creates an account notification with attachment associations" do
      aa_test_data = AttachmentAssociationsSpecHelper.new(@admin.account, @admin)
      json = api_call(:post,
                      @path,
                      @api_params,
                      { account_notification: {
                        subject: "New global notification",
                        start_at: @start_at.iso8601,
                        end_at: @end_at.iso8601,
                        message: aa_test_data.base_html,
                        icon: "information"
                      } })

      aas = AttachmentAssociation.where(context_type: "AccountNotification", context_id: json["id"])
      expect(aas.count).to eq 1
      expect(aas.first.attachment_id).to eq aa_test_data.attachment1.id
    end

    it "creates an account notification with attachment associations in a subaccount" do
      aa_test_data = AttachmentAssociationsSpecHelper.new(@admin.account, @admin)
      @subaccount = account_model(name: "subaccutcha", parent_account: @admin.account, root_account: @admin.account)
      json = api_call(:post,
                      "/api/v1/accounts/#{@subaccount.id}/account_notifications",
                      @api_params.merge(account_id: @subaccount.id.to_s),
                      { account_notification: {
                        subject: "New global notification",
                        start_at: @start_at.iso8601,
                        end_at: @end_at.iso8601,
                        message: aa_test_data.base_html,
                        icon: "information"
                      } })

      aas = AttachmentAssociation.where(context_type: "AccountNotification", context_id: json["id"])
      expect(aas.count).to eq 1
      expect(aas.first.attachment_id).to eq aa_test_data.attachment1.id
    end

    it "defaults icon to warning" do
      json = api_call(:post,
                      @path,
                      @api_params,
                      { account_notification: {
                        subject: "New global notification",
                        start_at: @start_at.iso8601,
                        end_at: @end_at.iso8601,
                        message: "This is a notification"
                      } })

      expect(json["icon"]).to eq "warning"
    end

    it "creates an account notification for specific roles using the old role names" do
      json = api_call(:post,
                      @path,
                      @api_params,
                      { account_notification_roles: ["AccountAdmin"],
                        account_notification: {
                          subject: "New global notification",
                          start_at: @start_at.iso8601,
                          end_at: @end_at.iso8601,
                          message: "This is a notification"
                        } })

      notification = AccountNotification.last
      roles = notification.account_notification_roles
      expect(roles.count).to eq 1
      expect(roles.first.role_id).to eq admin_role.id
      expect(json["roles"]).to eq ["AccountAdmin"]
      expect(json["role_ids"]).to eq [admin_role.id]
    end

    it "creates an account notification for specific roles using role ids" do
      json = api_call(:post,
                      @path,
                      @api_params,
                      { account_notification_roles: [admin_role.id],
                        account_notification: {
                          subject: "New global notification",
                          start_at: @start_at.iso8601,
                          end_at: @end_at.iso8601,
                          message: "This is a notification"
                        } })

      notification = AccountNotification.last
      roles = notification.account_notification_roles
      expect(roles.count).to eq 1
      expect(roles.first.role_id).to eq admin_role.id
      expect(json["roles"]).to eq ["AccountAdmin"]
      expect(json["role_ids"]).to eq [admin_role.id]
    end

    it "creates an account notification for specific course-level roles using role ids" do
      json = api_call(:post,
                      @path,
                      @api_params,
                      { account_notification_roles: [student_role.id],
                        account_notification: {
                          subject: "New global notification",
                          start_at: @start_at.iso8601,
                          end_at: @end_at.iso8601,
                          message: "This is a notification"
                        } })

      notification = AccountNotification.last
      roles = notification.account_notification_roles
      expect(roles.count).to eq 1
      expect(roles.first.role_id).to eq student_role.id
      expect(json["roles"]).to eq ["StudentEnrollment"]
      expect(json["role_ids"]).to eq [student_role.id]
    end

    it 'creates an account notification for the "nil enrollment"' do
      json = api_call(:post,
                      @path,
                      @api_params,
                      { account_notification_roles: ["NilEnrollment"],
                        account_notification: {
                          subject: "New global notification",
                          start_at: @start_at.iso8601,
                          end_at: @end_at.iso8601,
                          message: "This is a notification"
                        } })

      notification = AccountNotification.last
      roles = notification.account_notification_roles
      expect(roles.count).to eq 1
      expect(roles.first.role_id).to be_nil
      expect(json["roles"]).to eq ["NilEnrollment"]
      expect(json["role_ids"]).to eq [nil]
    end

    it "returns not authorized for non admin user" do
      user = user_with_managed_pseudonym
      api_call_as_user(user,
                       :post,
                       @path,
                       @api_params,
                       { account_notification_roles: ["StudentEnrollment"],
                         account_notification: {
                           subject: "New global notification",
                           start_at: @start_at.iso8601,
                           end_at: @end_at.iso8601,
                           message: "This is a notification"
                         } },
                       {},
                       expected_status: 403)
    end

    it "returns an error for missing required params" do
      missing = %w[subject message start_at end_at]
      raw_api_call(:post, @path, @api_params, { account_notification: { icon: "warning" } })
      expect(response).to have_http_status :bad_request
      json = JSON.parse(response.body)
      errors = json["errors"].keys
      expect(missing - errors).to be_blank
    end

    it "returns an error for malformed dates" do
      raw_api_call(:post,
                   @path,
                   @api_params,
                   { account_notification: {
                     subject: "New global notification",
                     start_at: "asdrsldkfj",
                     end_at: "invalid_date",
                     message: "This is a notification",
                     icon: "information"
                   } })
      expect(response).to have_http_status :bad_request
    end

    it "does not allow an end date to be before a start date" do
      raw_api_call(:post,
                   @path,
                   @api_params,
                   { account_notification: {
                     subject: "New global notification",
                     start_at: @end_at.iso8601,
                     end_at: @start_at.iso8601,
                     message: "This is a notification",
                     icon: "information"
                   } })
      expect(response).to have_http_status :bad_request
      errors = JSON.parse(response.body)
      expect(errors["errors"].keys).to include "end_at"
    end
  end

  describe "update" do
    before do
      @notification = account_notification(message: "default")
      @path = "/api/v1/accounts/#{@admin.account.id}/account_notifications/#{@notification.id}"
      @api_params = { controller: "account_notifications",
                      action: "update",
                      format: "json",
                      account_id: @admin.account.id.to_s,
                      id: @notification.id.to_s }
      @start_at = Time.zone.now
      @end_at = 1.day.from_now
    end

    context "for attachment associations" do
      before do
        @aa_test_data = AttachmentAssociationsSpecHelper.new(@admin.account, @admin)
      end

      it "updates with multiple attachments" do
        raw_api_call(:put,
                     @path,
                     @api_params,
                     { account_notification: {
                       start_at: @start_at.iso8601,
                       end_at: @end_at.iso8601,
                       message: @aa_test_data.added_html
                     } })

        aas = AttachmentAssociation.where(context_type: "AccountNotification", context_id: @notification.id)
        expect(aas.count).to eq 2
        attachment_ids = aas.pluck(:attachment_id)
        expect(attachment_ids).to match_array [@aa_test_data.attachment1.id, @aa_test_data.attachment2.id]
      end

      it "updates with no attachment" do
        raw_api_call(:put,
                     @path,
                     @api_params,
                     { account_notification: {
                       start_at: @start_at.iso8601,
                       end_at: @end_at.iso8601,
                       message: @aa_test_data.removed_html
                     } })

        aas = AttachmentAssociation.where(context_type: "AccountNotification", context_id: @notification.id)
        expect(aas.count).to eq 0
      end
    end

    it "returns forbidden for non admin user" do
      user = user_with_managed_pseudonym
      api_call_as_user(user,
                       :put,
                       @path,
                       @api_params,
                       { account_notification_roles: ["StudentEnrollment"],
                         account_notification: {
                           subject: "update a global notification",
                           start_at: @start_at.iso8601,
                           end_at: @end_at.iso8601,
                           message: "This is a notification"
                         } },
                       {},
                       expected_status: 403)
    end

    it "updates an existing account notification" do
      raw_api_call(:put,
                   @path,
                   @api_params,
                   { account_notification: {
                     subject: "updated global notification",
                     start_at: @start_at.iso8601,
                     end_at: @end_at.iso8601,
                     message: "This is an updated notification",
                     icon: "warning"
                   } })
      @notification.reload
      expect(@notification.subject).to eq("updated global notification")
      expect(@notification.start_at).to eq(@start_at.iso8601)
      expect(@notification.end_at).to eq(@end_at.iso8601)
      expect(@notification.message).to eq("This is an updated notification")
      expect(@notification.icon).to eq("warning")
    end

    it "updates an account notification for specific roles using role names" do
      student_role = @account.get_role_by_name("StudentEnrollment")
      existing_roles = [student_role]
      @notification.account_notification_roles.build(existing_roles.map { |r| { role: r } })
      @notification.save
      raw_api_call(:put,
                   @path,
                   @api_params,
                   { account_notification_roles: ["TeacherEnrollment"],
                     account_notification: {
                       subject: "added role to global notification",
                       start_at: @start_at.iso8601,
                       end_at: @end_at.iso8601,
                       message: "This is a notification"
                     } })
      @notification.reload
      notification_roles = @notification.account_notification_roles
      expect(@notification.subject).to eq("added role to global notification")
      role_names = notification_roles.map { |r| r.role.name }
      expect(role_names).not_to include("StudentEnrollment")
      expect(role_names).to include("TeacherEnrollment")
    end
  end
end
