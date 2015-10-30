require 'test_helper'


module Capistrano::Fiesta
  # Mocks
  class Editor
    def system(*args)
      true
    end
  end

  class SlackDummy
    def self.post(params = {})
      @test_log = params
    end

    def self.test_log
      @test_log
    end
  end

  class ReportTest < Minitest::Test
    def setup
      stub_request(:get, /github.com\/search/).to_return_json(items: [{ title: "New login", body: "", html_url: 'www.github.com' }])
      Report.chat_client = SlackDummy
    end

    def test_create
      query = "base:master repo:balvig/capistrano-fiesta merged:>2015-10-09T14:50:23Z"
      response = { items: [{ title: "New login [Delivers #123]", body: "" }] }
      github = stub_request(:get, "https://api.github.com:443/search/issues").with(query: { q: query }).to_return_json(response)

      announcement = <<-ANNOUNCEMENT
• New login
      ANNOUNCEMENT
      report = Report.create(repo, last_release: '20151009145023')
      assert_equal announcement, report.announcement
      assert_requested github
    end

    def test_create_with_comment
      draft = <<-DRAFT
# Only include new features

• New login
      DRAFT

      announcement = <<-ANNOUNCEMENT
• New login
      ANNOUNCEMENT

      report = Report.create(repo, comment: "Only include new features")
      assert_equal draft, report.send(:draft).render # find a way to set expectation on what Editor receives
      assert_equal announcement, report.announcement
    end

    def test_creating_release_on_github
      release_endpoint = stub_request(:post, "https://api.github.com/repos/balvig/capistrano-fiesta/releases").with(body: { name: "20151009145023", body: "- [New login](www.github.com)", tag_name: "release-20151009145023" })
      Report.create(repo).create_release('20151009145023')
      assert_requested release_endpoint
    end

    def test_creating_release_with_no_stories
      stub_request(:get, /github.com/).to_return_json(items: [])
      release_endpoint = stub_request(:post, "https://api.github.com/repos/balvig/capistrano-fiesta/releases")
      Report.create(repo).create_release('20151009145023')
      assert_not_requested release_endpoint
      assert_equal "[FIESTA] No new stories, skipping GitHub release", Logger.logs.last
    end

    def test_announce
      report = Report.create(repo)
      report.announce(team: 'bobcats', token: '1234', channel: 'releases')

      post = {
        team: 'bobcats',
        token: '1234',
        payload: {
          channel: 'releases',
          username: 'New Releases',
          icon_emoji: ':tada:',
          text: "• New login\n"
        }
      }

      assert_equal post, SlackDummy.test_log
    end

    def test_announce_without_chat_client
      Report.chat_client = nil
      report = Report.create(repo)
      report.announce
      assert_equal "[FIESTA] Install Slackistrano to announce releases on Slack", Logger.logs.last
    end

    def test_announce_with_no_stories
      stub_request(:get, /github.com/).to_return_json(items: [])
      Report.create(repo).announce
      assert_equal "[FIESTA] Announcement blank, nothing posted to Slack", Logger.logs.last
    end

    private

      def repo
        'git@github.com:balvig/capistrano-fiesta.git'
      end
  end
end
