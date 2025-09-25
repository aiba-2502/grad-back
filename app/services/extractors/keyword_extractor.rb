# frozen_string_literal: true

module Extractors
  # キーワード抽出サービス
  class KeywordExtractor
    # ストップワード（除外する一般的な単語）
    STOP_WORDS = %w[
      これ それ あれ この その あの ここ そこ あそこ
      こちら どこ だれ なに なん 何 私 僕 俺
      あなた みんな それで そして しかし でも
      ある いる する なる できる わかる
      です ます ません でした ました
      から まで より ため ので けど ても
      という こと もの ところ
      の を に へ と から で や が は も
    ].freeze

    def extract(text, options = {})
      return [] if text.blank?

      # オプション
      min_length = options[:min_length] || 2
      max_keywords = options[:max_keywords] || 10

      # テキストを単語に分割
      words = tokenize(text)

      # フィルタリング
      filtered_words = words.select { |word| valid_keyword?(word, min_length) }

      # 頻度カウント
      word_counts = count_frequencies(filtered_words)

      # 上位キーワードを返す
      format_keywords(word_counts, max_keywords)
    end

    def extract_from_messages(messages, options = {})
      all_text = messages.map(&:content).join(" ")
      extract(all_text, options)
    end

    private

    def tokenize(text)
      # 基本的なトークン化（改善の余地あり）
      text.gsub(/[。、！？\n]/, " ")
          .split(/\s+/)
          .map(&:strip)
          .reject(&:empty?)
    end

    def valid_keyword?(word, min_length)
      return false if word.length < min_length
      return false if STOP_WORDS.include?(word)
      return false if word =~ /^\d+$/ # 数字のみは除外

      true
    end

    def count_frequencies(words)
      words.group_by(&:itself)
           .transform_values(&:count)
           .sort_by { |_, count| -count }
    end

    def format_keywords(word_counts, max_keywords)
      total = word_counts.sum { |_, count| count }

      word_counts.take(max_keywords).map do |word, count|
        {
          word: word,
          count: count,
          percentage: (count.to_f / total * 100).round(1)
        }
      end
    end
  end
end