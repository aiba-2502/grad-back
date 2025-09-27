require "test_helper"

class TagTest < ActiveSupport::TestCase
  def setup
    # Create test tags
    @emotion_tag_active = Tag.create!(
      name: "test_joy",
      category: "emotion",
      is_active: true,
      metadata: { label_ja: "テスト喜び", label_en: "Test Joy" }
    )

    @emotion_tag_inactive = Tag.create!(
      name: "test_sadness",
      category: "emotion",
      is_active: false,
      metadata: { label_ja: "テスト悲しみ", label_en: "Test Sadness" }
    )

    @topic_tag = Tag.create!(
      name: "test_topic",
      category: "topic",
      is_active: true
    )
  end

  test "emotion_tags scope returns only emotion category tags" do
    emotion_tags = Tag.emotion_tags

    assert_includes emotion_tags, @emotion_tag_active
    assert_includes emotion_tags, @emotion_tag_inactive
    refute_includes emotion_tags, @topic_tag
  end

  test "active scope returns only active tags" do
    active_tags = Tag.active

    assert_includes active_tags, @emotion_tag_active
    refute_includes active_tags, @emotion_tag_inactive
    assert_includes active_tags, @topic_tag
  end

  test "emotion_tags.active chain returns only active emotion tags" do
    active_emotion_tags = Tag.emotion_tags.active

    assert_includes active_emotion_tags, @emotion_tag_active
    refute_includes active_emotion_tags, @emotion_tag_inactive
    refute_includes active_emotion_tags, @topic_tag
  end

  test "metadata is accessible as JSON" do
    tag = @emotion_tag_active

    assert_equal "テスト喜び", tag.metadata["label_ja"]
    assert_equal "Test Joy", tag.metadata["label_en"]
  end
end
