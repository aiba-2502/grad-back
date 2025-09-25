# Seed emotion tags with metadata

emotions_data = [
  # Basic emotions
  { name: "joy", category: "emotion", metadata: { label_ja: "喜び", label_en: "Joy", color: "#FFD700", intensity_default: 0.5 } },
  { name: "sadness", category: "emotion", metadata: { label_ja: "悲しみ", label_en: "Sadness", color: "#4169E1", intensity_default: 0.5 } },
  { name: "anger", category: "emotion", metadata: { label_ja: "怒り", label_en: "Anger", color: "#DC143C", intensity_default: 0.5 } },
  { name: "fear", category: "emotion", metadata: { label_ja: "恐れ", label_en: "Fear", color: "#8B008B", intensity_default: 0.5 } },
  { name: "surprise", category: "emotion", metadata: { label_ja: "驚き", label_en: "Surprise", color: "#FF69B4", intensity_default: 0.5 } },
  { name: "disgust", category: "emotion", metadata: { label_ja: "嫌悪", label_en: "Disgust", color: "#8FBC8F", intensity_default: 0.5 } },

  # Complex emotions
  { name: "trust", category: "emotion", metadata: { label_ja: "信頼", label_en: "Trust", color: "#87CEEB", intensity_default: 0.5 } },
  { name: "anticipation", category: "emotion", metadata: { label_ja: "期待", label_en: "Anticipation", color: "#FFA500", intensity_default: 0.5 } },
  { name: "love", category: "emotion", metadata: { label_ja: "愛", label_en: "Love", color: "#FF1493", intensity_default: 0.5 } },
  { name: "anxiety", category: "emotion", metadata: { label_ja: "不安", label_en: "Anxiety", color: "#708090", intensity_default: 0.5 } },
  { name: "frustration", category: "emotion", metadata: { label_ja: "イライラ", label_en: "Frustration", color: "#CD5C5C", intensity_default: 0.5 } },
  { name: "relief", category: "emotion", metadata: { label_ja: "安心", label_en: "Relief", color: "#90EE90", intensity_default: 0.5 } },
  { name: "gratitude", category: "emotion", metadata: { label_ja: "感謝", label_en: "Gratitude", color: "#FFB6C1", intensity_default: 0.5 } },
  { name: "pride", category: "emotion", metadata: { label_ja: "誇り", label_en: "Pride", color: "#9370DB", intensity_default: 0.5 } },
  { name: "guilt", category: "emotion", metadata: { label_ja: "罪悪感", label_en: "Guilt", color: "#696969", intensity_default: 0.5 } },
  { name: "shame", category: "emotion", metadata: { label_ja: "恥", label_en: "Shame", color: "#8B4513", intensity_default: 0.5 } },
  { name: "hope", category: "emotion", metadata: { label_ja: "希望", label_en: "Hope", color: "#00CED1", intensity_default: 0.5 } },
  { name: "disappointment", category: "emotion", metadata: { label_ja: "失望", label_en: "Disappointment", color: "#778899", intensity_default: 0.5 } },
  { name: "contentment", category: "emotion", metadata: { label_ja: "満足", label_en: "Contentment", color: "#98FB98", intensity_default: 0.5 } },
  { name: "loneliness", category: "emotion", metadata: { label_ja: "孤独", label_en: "Loneliness", color: "#483D8B", intensity_default: 0.5 } },

  # Additional emotions for keywords
  { name: "discomfort", category: "emotion", metadata: { label_ja: "不快", label_en: "Discomfort", color: "#A52A2A", intensity_default: 0.5 } },
  { name: "confusion", category: "emotion", metadata: { label_ja: "困惑", label_en: "Confusion", color: "#B0C4DE", intensity_default: 0.5 } },
  { name: "excitement", category: "emotion", metadata: { label_ja: "興奮", label_en: "Excitement", color: "#FF4500", intensity_default: 0.5 } },
  { name: "calmness", category: "emotion", metadata: { label_ja: "落ち着き", label_en: "Calmness", color: "#5F9EA0", intensity_default: 0.5 } }
]

puts "Seeding emotion tags..."

emotions_data.each do |emotion_data|
  tag = Tag.find_or_initialize_by(
    name: emotion_data[:name],
    category: emotion_data[:category]
  )

  tag.metadata = emotion_data[:metadata]

  if tag.save
    puts "  ✓ Created/Updated emotion tag: #{emotion_data[:name]} (#{emotion_data[:metadata][:label_ja]})"
  else
    puts "  ✗ Failed to create emotion tag: #{emotion_data[:name]} - #{tag.errors.full_messages.join(', ')}"
  end
end

puts "Seeded #{Tag.where(category: 'emotion').count} emotion tags."
