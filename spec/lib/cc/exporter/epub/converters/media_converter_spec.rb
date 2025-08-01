# frozen_string_literal: true

#
# Copyright (C) 2015 - present Instructure, Inc.
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

require_relative "../../../cc_spec_helper"

describe "MediaConverter" do
  let(:klass) do
    Class.new do
      include CC::Exporter::Epub::Converters::MediaConverter

      def initialize(course = {})
        @course = course
      end

      def unsupported_files
        [{
          file_name: File.basename("#{CGI.escape(self.class::WEB_CONTENT_TOKEN)}/path/to/movie.mov")
        }]
      end
    end
  end

  describe "#convert_media_paths!" do
    subject(:test_instance) { klass.new }

    let_once(:a_href) do
      "#{CGI.escape(klass::WEB_CONTENT_TOKEN)}/path/to/img.jpg"
    end
    let_once(:img_src) do
      "#{CGI.escape(klass::WEB_CONTENT_TOKEN)}/path/to/img.jpg"
    end
    let_once(:mov_path) do
      "#{CGI.escape(klass::WEB_CONTENT_TOKEN)}/path/to/movie.mov"
    end

    let(:doc) do
      Nokogiri::HTML5.fragment(<<~HTML)
        <div>
          <a href="#{a_href}">
            Image Link
          </a>
          <img src="#{img_src}" />
          <a href="#{mov_path}">
            This is no good.
          </a>
        </div>
      HTML
    end

    it "updates link hrefs containing WEB_CONTENT_TOKEN" do
      expect(doc.search("a").all? do |element|
        element["href"].match(CGI.escape(klass::WEB_CONTENT_TOKEN))
      end).to be_truthy, "precondition"

      test_instance.convert_media_paths!(doc)

      expect(doc.search("a").all? do |element|
        element["href"].match(CC::Exporter::Epub::FILE_PATH)
      end).to be_truthy

      expect(doc.search("a").all? do |element|
        element["href"].match(CGI.escape(klass::WEB_CONTENT_TOKEN))
      end).to be_falsey
    end

    it "updates img srcs containing WEB_CONTENT_TOKEN" do
      expect(doc.search("img").all? do |element|
        element["src"].match(CGI.escape(klass::WEB_CONTENT_TOKEN))
      end).to be_truthy, "precondition"

      test_instance.convert_media_paths!(doc)

      expect(doc.search("img").all? do |element|
        element["src"].match(CC::Exporter::Epub::FILE_PATH)
      end).to be_truthy

      expect(doc.search("img").all? do |element|
        element["src"].match(CGI.escape(klass::WEB_CONTENT_TOKEN))
      end).to be_falsey
    end

    it "replaces media that is not present with a span" do
      expect(doc.search("a[href*='#{mov_path}']").any?).to be_truthy, "precondition"
      expect(doc.search("span").empty?).to be_truthy, "precondition"

      test_instance.convert_media_paths!(doc)

      expect(doc.search("a[href*='#{mov_path}']").empty?).to be_truthy
      expect(doc.search("span").any?).to be_truthy
    end

    it "does not explode with non standard file names" do
      other_doc = Nokogiri::HTML5.fragment(
        "<div><a href=\"#{CGI.escape(klass::WEB_CONTENT_TOKEN)}/path/to/im%28g.jpg\"}>blah</a>"
      )

      test_instance.convert_media_paths!(other_doc)

      expect(other_doc.at_css("a")["href"]).to eq "#{CC::Exporter::Epub::FILE_PATH}/path/to/im%28g.jpg"
    end

    it "does not explode with extensions that aren't valid regexes" do
      other_doc = Nokogiri::HTML5.fragment(
        "<div><a href=\"#{CGI.escape(klass::WEB_CONTENT_TOKEN)}/path/to/(img.jpg)\"}>blah</a>"
      )

      test_instance.convert_media_paths!(other_doc)

      expect(other_doc.at_css("a")["href"]).to eq "#{CC::Exporter::Epub::FILE_PATH}/path/to/%28img.jpg%29"
    end
  end

  describe "#convert_flv_paths!" do
    subject(:test_instance) { klass.new }

    let(:doc) do
      Nokogiri::HTML5.fragment(<<~HTML)
        <div>
          <a href="media/media_objects/m-5G7G2CcbF2nd3nZ8pyT1z16ytNaQuQ1X.flv">
            Video Comment Link
          </a>
        </div>
      HTML
    end

    it "hrefses with flv to hrefs with mp4" do
      expect(doc.search("a").all? do |element|
        element["href"].match("flv")
      end).to be_truthy, "precondition"

      test_instance.convert_flv_paths!(doc)

      expect(doc.search("a").all? do |element|
        element["href"].match("mp4")
      end).to be_truthy

      expect(doc.search("a").all? do |element|
        element["href"].match("flv")
      end).to be_falsey
    end
  end

  describe "#convert_audio_tags!" do
    context "for links with class instructure_audio_link" do
      subject(:test_instance) { klass.new }

      let(:doc) do
        Nokogiri::HTML5.fragment(<<~HTML)
          <a href="#{CC::Exporter::Epub::FILE_PATH}/path/to/audio.mp3"
            class="instructure_audio_link">
            Audio Link
          </a>
        HTML
      end

      it "changes a tags to audio tags" do
        expect(doc.search("a").any?).to be_truthy, "precondition"
        expect(doc.search("audio").empty?).to be_truthy, "precondition"

        test_instance.convert_audio_tags!(doc)

        expect(doc.search("a").empty?).to be_truthy
        expect(doc.search("audio").any?).to be_truthy
      end
    end

    context "for links with class audio_comment" do
      subject(:test_instance) { klass.new }

      let(:doc) do
        Nokogiri::HTML5.fragment(<<~HTML)
          <a href="#{CC::Exporter::Epub::FILE_PATH}/path/to/audio.mp3"
            class="audio_comment">
            Audio Link
          </a>
        HTML
      end

      it "changes a tags to audio tags" do
        expect(doc.search("a").any?).to be_truthy, "precondition"
        expect(doc.search("audio").empty?).to be_truthy, "precondition"

        test_instance.convert_audio_tags!(doc)

        expect(doc.search("a").empty?).to be_truthy
        expect(doc.search("audio").any?).to be_truthy
      end
    end
  end

  describe "#convert_video_tags!" do
    context "for links with class instructure_video_link" do
      subject(:test_instance) { klass.new }

      let(:doc) do
        Nokogiri::HTML5.fragment(<<~HTML)
          <a href="#{CC::Exporter::Epub::FILE_PATH}/path/to/audio.mp3"
            class="instructure_video_link">
            Video Link
          </a>
        HTML
      end

      it "changes a tags to audio tags" do
        expect(doc.search("a").any?).to be_truthy, "precondition"
        expect(doc.search("video").empty?).to be_truthy, "precondition"

        test_instance.convert_video_tags!(doc)

        expect(doc.search("a").empty?).to be_truthy
        expect(doc.search("video").any?).to be_truthy
      end
    end

    context "for links with class video_comment" do
      subject(:test_instance) { klass.new }

      let(:doc) do
        Nokogiri::HTML5.fragment(<<~HTML)
          <a href="#{CC::Exporter::Epub::FILE_PATH}/path/to/audio.mp3"
            class="video_comment">
            Video Link
          </a>
        HTML
      end

      it "changes a tags to audio tags" do
        expect(doc.search("a").any?).to be_truthy, "precondition"
        expect(doc.search("video").empty?).to be_truthy, "precondition"

        test_instance.convert_video_tags!(doc)

        expect(doc.search("a").empty?).to be_truthy
        expect(doc.search("video").any?).to be_truthy
      end
    end
  end
end
