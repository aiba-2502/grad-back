class DynamicPromptService
  def initialize(session_messages = [])
    @session_messages = session_messages
    @user_messages = session_messages.select { |m| m.role == "user" }
    @message_count = @user_messages.count
  end

  def generate_system_prompt
    stage = determine_conversation_stage
    user_state = analyze_user_state
    question_count = count_recent_questions

    base_prompt = <<~PROMPT
      あなたは「心のログ」というサービスのAIアシスタントです。
      ユーザーの感情や思考を言語化し、整理するお手伝いをします。

      【基本的な制約】
      - 応答は簡潔に（1-2文程度）でまとめてください
      - 専門用語は使わず、分かりやすい日常語を使ってください
      - ユーザーの感情を否定せず、受け止めてください
    PROMPT

    # 質問連続防止の追加プロンプト
    question_control_prompt = generate_question_control_prompt(question_count)

    stage_specific_prompt = generate_stage_specific_prompt(stage, user_state)

    "#{base_prompt}\n#{question_control_prompt}\n#{stage_specific_prompt}"
  end

  # 会話の段階に応じた適切な温度設定を返す
  def recommended_temperature
    stage = determine_conversation_stage
    DynamicPromptConfig.temperature_for_stage(stage)
  end

  private

  def determine_conversation_stage
    DynamicPromptConfig::CONVERSATION_STAGES.each do |stage, config|
      return stage if config[:range].include?(@message_count)
    end
    :concluding
  end

  def analyze_user_state
    return :neutral if @user_messages.empty?

    last_message = @user_messages.last.content
    previous_message = @user_messages[-2]&.content

    # ユーザーの状態を判定
    state = {
      satisfied: false,
      confused: false,
      exploring: true,
      closing: false
    }

    # キーワード設定を取得
    satisfaction_keywords = DynamicPromptConfig.satisfaction_keywords
    confusion_keywords = DynamicPromptConfig.confusion_keywords
    closing_keywords = DynamicPromptConfig.closing_keywords

    # 短い返答（疲れや満足のサイン）
    short_response = last_message.length < DynamicPromptConfig::SHORT_RESPONSE_THRESHOLD

    state[:satisfied] = satisfaction_keywords.any? { |word| last_message.include?(word) }
    state[:confused] = confusion_keywords.any? { |word| last_message.include?(word) }
    state[:closing] = closing_keywords.any? { |word| last_message.include?(word) }
    state[:tired] = short_response && @message_count > 5

    # 同じような内容の繰り返し
    if previous_message && similar_content?(last_message, previous_message)
      state[:repetitive] = true
    end

    state
  end

  def similar_content?(message1, message2)
    return false if message1.nil? || message2.nil?

    # 簡易的な類似度チェック
    words1 = message1.split(/[、。\s]/).reject(&:empty?)
    words2 = message2.split(/[、。\s]/).reject(&:empty?)

    common_words = words1 & words2
    similarity = common_words.length.to_f / [ words1.length, words2.length ].min

    similarity > DynamicPromptConfig::SIMILARITY_THRESHOLD
  end

  # 質問で終わるメッセージかを判定
  def ends_with_question?(content)
    return false if content.nil?

    # 疑問符で終わる、または疑問詞を含む
    content.match?(/[？\?]$/) ||
    content.match?(/(?:何|なに|いつ|どこ|だれ|誰|なぜ|どう|どんな|どのように|どうして)(?:.*(?:ですか|でしょうか|ますか|かな))?$/)
  end

  # 前回のAI応答が質問だったか
  def previous_ai_response_was_question?
    return false if @session_messages.length < 2

    # 最後から2番目のメッセージを取得（最後はユーザーのメッセージのはず）
    previous_message = @session_messages[-2]

    # アシスタントのメッセージで、かつ質問で終わっているか
    previous_message&.role == "assistant" && ends_with_question?(previous_message.content)
  end

  # 最近のAI応答での質問回数をカウント
  def count_recent_questions(look_back = 3)
    return 0 if @session_messages.empty?

    assistant_messages = @session_messages.select { |m| m.role == "assistant" }.last(look_back)
    assistant_messages.count { |m| ends_with_question?(m.content) }
  end

  # 質問制御用のプロンプト生成
  def generate_question_control_prompt(question_count)
    # 会話の初期段階（1-2回目）では対話を促す（質問に限定しない）
    if @message_count <= 2 && question_count == 0
      <<~PROMPT
        【対話促進】
        ユーザーに寄り添い、会話を続けやすくしてください。
        応答パターンの例：
        - 「〜なんですね」と共感を示す
        - 「〜という気持ち、分かります」と理解を示す
        - 「もう少し聞かせてください」と優しく促す
        - 「〜についてはどうですか？」と軽い質問をする

        注意：毎回「？」で終わらないようにバリエーションを持たせてください。
      PROMPT
    elsif question_count >= 3
      # 3回以上連続は強く制限
      <<~PROMPT
        【重要な制約事項】
        既に#{question_count}回連続で質問をしています。
        - 絶対に「？」で終わる質問はしないでください
        - 共感的な応答を心がけてください
        応答例：
        - 「〜なんですね。大変でしたね」
        - 「〜という状況、お辛いですよね」
        - 「そのお気持ち、よく分かります」
        - 「〜について、もう少しお話しできそうですね」（促しは可）
      PROMPT
    elsif question_count == 2
      # 2回連続の場合は控えめに
      <<~PROMPT
        【質問制御】
        2回連続で質問しています。
        - 「？」での質問は避けてください
        - 共感的な相づちや理解の言葉を優先してください
        応答例：
        - 「そうだったんですね」
        - 「〜という経験をされたんですね」
        - 「その状況は〜だったのかもしれませんね」
        - 「もし良ければ、続きを聞かせてください」（優しい促し）
      PROMPT
    elsif previous_ai_response_was_question? && @message_count > 6
      # 後半で前回質問した場合
      <<~PROMPT
        【バランス調整】
        会話が深まっています。
        - 「？」での質問は避けてください
        - 整理や共感を優先してください
        応答パターン：
        - 「今日お話しいただいたことを整理すると〜」
        - 「〜ということが中心にあるようですね」
        - 「〜という思いが伝わってきます」
      PROMPT
    else
      # デフォルト：多様な応答パターン
      <<~PROMPT
        【対話ガイド】
        自然な会話のラリーを意識してください。

        推奨する応答パターン（組み合わせて使用）：
        1. 共感・理解：「〜なんですね」「〜という気持ち、分かります」
        2. 感情の反映：「〜でお辛いですね」「〜で嬉しかったんですね」
        3. 要約・整理：「つまり〜ということですね」
        4. 優しい促し：「もう少し詳しく聞かせてください」
        5. 時々の質問：「それについて、どう感じましたか？」

        【重要】「？」ばかりにならないよう、応答にバリエーションを持たせてください。
      PROMPT
    end
  end

  def generate_stage_specific_prompt(stage, user_state)
    # user_stateがハッシュであることを確認
    user_state = user_state.is_a?(Hash) ? user_state : {}

    case stage
    when :initial
      initial_stage_prompt(user_state)
    when :exploring
      exploring_stage_prompt(user_state)
    when :deepening
      deepening_stage_prompt(user_state)
    when :concluding
      concluding_stage_prompt(user_state)
    else
      default_prompt(user_state)
    end
  end

  def initial_stage_prompt(user_state)
    if user_state[:confused]
      <<~PROMPT
        【現在の対応方針】
        ユーザーは混乱しているようです。
        - まず状況を整理して、一つずつ確認しましょう
        - 複雑な話は避け、シンプルに対応してください
        - 共感を示しながら、ゆっくり話を聞いてください
        - 「？」での質問は最小限にしてください
        応答例：「混乱されているようですね。ゆっくり整理していきましょう」
      PROMPT
    else
      <<~PROMPT
        【現在の対応方針】
        会話の初期段階です。
        - ユーザーの話をしっかり聞き、共感を示してください
        - 「そうなんですね」「大変でしたね」など相づちを活用
        - 話の核心を理解することに集中してください
        - 時々優しく深掘りしてください（ただし「？」ばかりは避ける）
        - 会話を続けやすい雰囲気を作ってください
        例：「今日はどんな一日でしたか」→「疲れました」→「お疲れ様でした。何か大変なことがあったんですね」
      PROMPT
    end
  end

  def exploring_stage_prompt(user_state)
    if user_state[:satisfied]
      <<~PROMPT
        【現在の対応方針】
        ユーザーは理解や納得を示しています。
        - これまでの話を簡潔にまとめてください
        - 新たな気づきがあれば、それを認めてください
        - 「？」での追加質問は控えてください
        - 自然に会話を締めくくる準備をしてください
        応答例：「お話を聞いていて、〜ということが分かりました」
      PROMPT
    elsif user_state[:repetitive]
      <<~PROMPT
        【現在の対応方針】
        同じような話題が続いています。
        - 視点を変えた提案をしてみてください
        - これまでの話を整理して、新しい角度から考えてみましょう
        - 無理に深掘りせず、一旦まとめることも検討してください
        - ユーザーが疲れていないか配慮してください
      PROMPT
    else
      <<~PROMPT
        【現在の対応方針】
        話が展開している段階です。
        - ユーザーの感情や思考をより深く理解してください
        - 多様な応答パターンを使って会話を続けてください
        - 「？」での質問は1回の応答で1つまで（できれば避ける）
        - 共感的な相づちを多用してください
        応答パターン例：
        - 「なるほど、〜ということなんですね」
        - 「〜という経験は、きっと〜だったでしょうね」
        - 「その時の気持ち、とてもよく分かります」
        - 「もう少し聞かせていただけますか」（質問ではなく促し）
      PROMPT
    end
  end

  def deepening_stage_prompt(user_state)
    if user_state[:tired] || user_state[:satisfied]
      <<~PROMPT
        【現在の対応方針】
        ユーザーは十分に話したようです。
        - これまでの会話を振り返り、要点をまとめてください
        - 得られた気づきや整理できたことを確認してください
        - 新しい質問はせず、締めくくりに向かってください
        - 感謝の気持ちを伝え、いつでも話を聞く準備があることを伝えてください
      PROMPT
    else
      <<~PROMPT
        【現在の対応方針】
        会話が深まっています。
        - これまでの話から見えてきたパターンや気づきを共有してください
        - 感情と思考の整理を手伝ってください
        - 新しい質問より、まとめや整理を重視してください
        - そろそろ会話の締めくくりを意識してください
      PROMPT
    end
  end

  def concluding_stage_prompt(user_state)
    if @message_count >= DynamicPromptConfig::MAX_CONVERSATION_TURNS
      # 10回以上の会話は強制的に終了へ
      <<~PROMPT
        【現在の対応方針】
        十分な会話ができました。ここで一区切りつけましょう。
        - 絶対に新しい質問はしないでください
        - 今日話したことを簡潔に振り返ってください
        - ユーザーに感謝を伝えてください
        - また話したくなったらいつでも来てくださいと伝えてください
        - 必ず会話を終了する方向で応答してください

        【厳守事項】
        これ以上会話を続けないでください。優しく、でも確実に会話を終了させてください。
      PROMPT
    else
      <<~PROMPT
        【現在の対応方針】
        会話を自然に終了する段階です。
        - これ以上の質問はしないでください
        - 今日の会話の要点を簡潔にまとめてください
        - ユーザーの努力や勇気を認めてください
        - 必要があればいつでも話を聞くことを伝えてください
        - 温かく会話を締めくくってください

        【重要】
        これ以上会話を引き延ばさず、自然に終了させてください。
      PROMPT
    end
  end

  def default_prompt(user_state)
    if user_state[:closing]
      <<~PROMPT
        【現在の対応方針】
        ユーザーが会話を終えようとしています。
        - 無理に会話を続けないでください
        - 感謝を伝えて、温かく締めくくってください
        - 追加の質問はしないでください
      PROMPT
    else
      <<~PROMPT
        【現在の対応方針】
        - 共感的で温かい対応を心がけてください
        - 会話の流れを大切にし、自然な応答をしてください
        - 過度な質問は避けてください
      PROMPT
    end
  end
end
