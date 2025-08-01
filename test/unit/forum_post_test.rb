require 'test_helper'

class ForumPostTest < ActiveSupport::TestCase
  context "A forum post" do
    setup do
      @user = FactoryBot.create(:user)
      @topic = FactoryBot.create(:forum_topic)
    end

    context "that mentions a user" do
      context "in a quote block" do
        setup do
          @user2 = FactoryBot.create(:user)
        end

        should "not create a dmail" do
          assert_difference("Dmail.count", 0) do
            FactoryBot.create(:forum_post, :topic_id => @topic.id, :body => "[quote]@#{@user2.name}[/quote]")
          end

          assert_difference("Dmail.count", 0) do
            FactoryBot.create(:forum_post, :topic_id => @topic.id, :body => "[quote]@#{@user2.name}[/quote] blah [quote]@#{@user2.name}[/quote]")
          end

          assert_difference("Dmail.count", 0) do
            FactoryBot.create(:forum_post, :topic_id => @topic.id, :body => "[quote][quote]@#{@user2.name}[/quote][/quote]")
          end

          assert_difference("Dmail.count", 1) do
            FactoryBot.create(:forum_post, :topic_id => @topic.id, :body => "[quote]@#{@user2.name}[/quote] @#{@user2.name}")
          end
        end
      end

      context "outside a quote block" do
        setup do
          @user2 = FactoryBot.create(:user)
          @post = build(:forum_post, creator: @user, topic: @topic, body: "Hey @#{@user2.name} check this out!")
        end

        should "create a dmail" do
          assert_difference("Dmail.count", 1) do
            @post.save
          end

          dmail = Dmail.last
          assert_equal(<<-EOS.strip_heredoc, dmail.body)
            @#{@user.name} mentioned you in topic ##{@topic.id} (\"#{@topic.title}\":[/forum_topics/#{@topic.id}?page=1]):

            [quote]
            Hey @#{@user2.name} check this out!
            [/quote]
          EOS
        end
      end

      should "not send a mention to yourself" do
        assert_no_difference("Dmail.count") do
          as(@user) { create(:forum_post, creator: @user, body: "hi from @#{@user.name}") }
        end
      end

      should "not fail when mentioning a nonexistent user" do
        assert_no_difference("Dmail.count") do
          as(@user) { create(:forum_post, creator: @user, body: "hi from @nonamethanks") }
        end
      end
    end

    context "that belongs to a topic with several pages of posts" do
      setup do
        Danbooru.config.stubs(:posts_per_page).returns(3)
        @posts = []
        9.times do
          @posts << FactoryBot.create(:forum_post, :topic_id => @topic.id, :body => rand(100_000))
        end
        travel(2.seconds) do
          @posts << FactoryBot.create(:forum_post, :topic_id => @topic.id, :body => rand(100_000))
        end
      end

      context "that is deleted" do
        should "update the topic's updated_at timestamp" do
          @mod = create(:moderator_user)

          assert_equal(@posts[-1].updated_at.to_i, @topic.reload.updated_at.to_i)
          @posts[-1].delete!(@mod)

          assert_equal(@posts[-2].updated_at.to_i, @topic.reload.updated_at.to_i)
        end
      end

      should "know which page it's on" do
        assert_equal(2, @posts[3].forum_topic_page)
        assert_equal(2, @posts[4].forum_topic_page)
        assert_equal(2, @posts[5].forum_topic_page)
        assert_equal(3, @posts[6].forum_topic_page)
      end

      should "update the topic's updated_at when deleted" do
        @posts.last.destroy
        @topic.reload
        assert_equal(@posts[8].updated_at.to_s, @topic.updated_at.to_s)
      end
    end

    should "update the topic when created" do
      @original_topic_updated_at = @topic.updated_at
      travel(1.second) do
        post = FactoryBot.create(:forum_post, :topic_id => @topic.id)
      end
      @topic.reload
      assert_not_equal(@original_topic_updated_at.to_s, @topic.updated_at.to_s)
    end

    should "update the topic when updated only for the original post" do
      posts = []
      3.times do
        posts << FactoryBot.create(:forum_post, :topic_id => @topic.id, :body => rand(100_000))
      end

      # updating the original post
      travel(1.second) do
        posts.first.update(body: "xxx")
      end
      @topic.reload
      assert_equal(posts.first.updated_at.to_s, @topic.updated_at.to_s)

      # updating a non-original post
      travel(2.seconds) do
        posts.last.update(body: "xxx")
      end
      assert_equal(posts.first.updated_at.to_s, @topic.updated_at.to_s)
    end

    should "be searchable by body content" do
      post = create(:forum_post, topic: @topic, body: "xxx")

      assert_search_equals(post, body_matches: "xxx")
      assert_search_equals([], body_matches: "aaa")
    end

    should "initialize its updater" do
      post = create(:forum_post, topic: @topic, creator: @user)
      assert_equal(@user, post.updater)
    end

    context "updated by a second user" do
      should "record its updater" do
        @post = create(:forum_post)
        @second_user = create(:user)

        @post.update(body: "abc", updater: @second_user)
        assert_equal(@second_user, @post.updater)
      end
    end

    context "during validation" do
      subject { build(:forum_post) }

      should_not allow_value("").for(:body)
      should_not allow_value(" ").for(:body)
      should_not allow_value("\u200B").for(:body)
      should_not allow_value((["!post #1"] * 10).join("\n")).for(:body)

      should "not allow NSFW media embeds" do
        post = create(:post, rating: "e")
        forum_post = build(:forum_post, body: "!post ##{post.id}").tap(&:validate)

        assert_includes(forum_post.errors[:body], "can't include NSFW images")
      end
    end
  end
end
