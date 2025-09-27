# Backend リファレンス - 心のログ

## 目次
- [概要](#概要)
- [技術スタック](#技術スタック)
- [プロジェクト構造](#プロジェクト構造)
- [モデル設計](#モデル設計)
- [コントローラー](#コントローラー)
- [サービス層](#サービス層)
- [API仕様](#api仕様)
- [データベース](#データベース)
- [認証・認可](#認証認可)
- [AI統合](#ai統合)
- [開発ガイド](#開発ガイド)
- [テスト](#テスト)
- [デプロイ](#デプロイ)

## 概要

心のログのバックエンドは、Rails 8.0.2のAPIモードで構築された堅牢なRESTful APIサーバーです。
OpenAI、Anthropic、Google Geminiなどの複数のAIプロバイダーと統合し、感情分析、会話の永続化、レポート生成などの高度な機能を提供します。

## 技術スタック

### コア技術
- **Ruby**: 3.3.5
- **Rails**: 8.0.2 (API mode)
- **PostgreSQL**: 16
- **MongoDB**: 9.0 (Mongoid ORM)

### 主要Gem
```ruby
# データベース
gem 'pg', '~> 1.1'              # PostgreSQLアダプタ
gem 'mongoid', '~> 9.0'         # MongoDB ODM

# 認証・セキュリティ
gem 'bcrypt', '~> 3.1.7'        # パスワード暗号化
gem 'jwt'                       # JSON Web Token

# AI統合
gem 'ruby-openai', '~> 8.3'     # OpenAI API
gem 'anthropic', '~> 0.3'       # Anthropic Claude API
gem 'gemini-ai', '~> 4.2'       # Google Gemini API
gem 'httparty', '~> 0.23.1'     # HTTP通信

# サーバー・パフォーマンス
gem 'puma', '>= 5.0'            # Webサーバー
gem 'bootsnap', require: false  # 起動高速化
gem 'rack-cors'                 # Cross-Origin対応

# 開発・品質
gem 'debug'                     # デバッグ
gem 'rubocop-rails-omakase'     # コード品質
gem 'brakeman'                  # セキュリティ監査
```

## プロジェクト構造

```
backend/
├── app/
│   ├── controllers/
│   │   ├── application_controller.rb    # ベースコントローラー
│   │   ├── home_controller.rb          # ルートAPI
│   │   └── api/
│   │       └── v1/
│   │           ├── auth_controller.rb   # 認証
│   │           ├── chats_controller.rb  # チャット
│   │           ├── reports_controller.rb # レポート
│   │           ├── users_controller.rb   # ユーザー
│   │           ├── voices_controller.rb  # 音声
│   │           └── auth/
│   │               └── registrations_controller.rb
│   ├── models/
│   │   ├── api_token.rb                # APIトークン管理
│   │   ├── application_record.rb       # ベースモデル
│   │   ├── chat.rb                     # チャットセッション
│   │   ├── message.rb                  # メッセージ
│   │   ├── summary.rb                  # サマリー
│   │   ├── tag.rb                      # タグ
│   │   ├── user.rb                     # ユーザー
│   │   └── concerns/                   # 共通モジュール
│   ├── services/                       # ビジネスロジック
│   │   ├── ai_service_v2.rb           # AI統合サービス
│   │   ├── api_token_validator.rb      # トークン検証
│   │   ├── chat_message_service.rb     # チャット処理
│   │   ├── dynamic_prompt_service.rb   # 動的プロンプト生成
│   │   ├── emotion_extraction_service.rb # 感情分析
│   │   ├── openai_service.rb          # OpenAI通信
│   │   ├── report_service.rb          # レポート生成
│   │   ├── extractors/                 # データ抽出
│   │   │   └── emotion_extractor.rb
│   │   └── reports/                    # レポート関連
│   │       ├── base_report.rb
│   │       ├── daily_report.rb
│   │       ├── monthly_report.rb
│   │       ├── report_generator.rb
│   │       ├── session_report.rb
│   │       └── weekly_report.rb
│   ├── jobs/                          # バックグラウンドジョブ
│   └── lib/
│       └── app_constants.rb           # アプリ定数
├── config/
│   ├── routes.rb                      # ルーティング
│   ├── database.yml                   # DB設定
│   ├── mongoid.yml                    # MongoDB設定
│   ├── application.rb                 # アプリ設定
│   └── initializers/
│       ├── cors.rb                    # CORS設定
│       └── dynamic_prompt_config.rb   # プロンプト設定
├── db/
│   ├── migrate/                       # マイグレーション
│   │   └── 20250124150000_rdb_init_schema.rb
│   ├── schema.rb                      # スキーマ
│   └── seeds.rb                       # シードデータ
├── test/                              # テスト
└── lib/
    └── tasks/                        # Rakeタスク
```

## モデル設計

### User
```ruby
class User < ApplicationRecord
  # 認証
  has_secure_password

  # 関連
  has_many :api_tokens, dependent: :destroy
  has_many :chats, dependent: :destroy
  has_many :messages, through: :chats
  has_many :summaries, dependent: :destroy

  # バリデーション
  validates :name, presence: true, length: { maximum: 50 }
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 6 }, if: :password_required?

  # スコープ
  scope :active, -> { where(is_active: true) }

  # メソッド
  def generate_jwt
    ApiToken.generate_jwt(user: self)
  end
end
```

### Chat
```ruby
class Chat < ApplicationRecord
  # 関連
  belongs_to :user
  belongs_to :tag, optional: true
  has_many :messages, dependent: :destroy
  has_many :summaries, dependent: :destroy

  # バリデーション
  validates :session_id, presence: true, uniqueness: true
  validates :title, length: { maximum: 120 }

  # スコープ
  scope :recent, -> { order(created_at: :desc) }
  scope :with_messages, -> { includes(:messages) }
  scope :for_session, ->(session_id) { where(session_id: session_id) }
end
```

### Message
```ruby
class Message < ApplicationRecord
  # Enum
  enum :role, { user: "user", assistant: "assistant", system: "system" }

  # 関連
  belongs_to :chat

  # バリデーション
  validates :content, presence: true
  validates :role, presence: true
  validates :sent_at, presence: true

  # JSONフィールド
  # emotions: { "joy" => 0.8, "sadness" => 0.2, ... }
  # metadata: { "model" => "gpt-4", "tokens" => 150, ... }

  # スコープ
  scope :by_role, ->(role) { where(role: role) }
  scope :recent, -> { order(sent_at: :desc) }
  scope :with_emotions, -> { where.not(emotions: nil) }

  # メソッド
  def user?
    role == "user"
  end

  def assistant?
    role == "assistant"
  end
end
```

### ApiToken
```ruby
class ApiToken < ApplicationRecord
  # 関連
  belongs_to :user

  # バリデーション
  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true

  # スコープ
  scope :active, -> { where("expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }

  # クラスメソッド
  def self.generate_jwt(user:, expires_in: 24.hours)
    payload = {
      user_id: user.id,
      exp: expires_in.from_now.to_i
    }
    token = JWT.encode(payload, Rails.application.secret_key_base)
    create!(
      user: user,
      token: token,
      expires_at: expires_in.from_now
    )
  end

  def self.decode_jwt(token)
    JWT.decode(token, Rails.application.secret_key_base)[0]
  rescue JWT::DecodeError
    nil
  end

  # インスタンスメソッド
  def active?
    expires_at > Time.current
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
```

### Summary
```ruby
class Summary < ApplicationRecord
  # Enum
  enum :period, {
    session: "session",
    daily: "daily",
    weekly: "weekly",
    monthly: "monthly"
  }

  # 関連
  belongs_to :chat, optional: true
  belongs_to :user, optional: true

  # バリデーション
  validates :period, presence: true
  validates :tally_start_at, presence: true
  validates :tally_end_at, presence: true
  validates :analysis_data, presence: true

  # JSONフィールド
  # analysis_data: {
  #   "emotion_summary" => {...},
  #   "topics" => [...],
  #   "insights" => [...],
  #   "advice" => "..."
  # }

  # スコープ
  scope :for_period, ->(period) { where(period: period) }
  scope :in_range, ->(start_date, end_date) {
    where(tally_start_at: start_date..end_date)
  }
  scope :recent, -> { order(created_at: :desc) }
end
```

## コントローラー

### ApplicationController
```ruby
class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :set_default_format

  private

  def authenticate_user!
    authenticate_with_http_token do |token, _options|
      decoded = ApiToken.decode_jwt(token)
      return unless decoded

      @current_user = User.find_by(id: decoded["user_id"])
      @current_token = ApiToken.active.find_by(token: token, user: @current_user)
    end

    render_unauthorized unless @current_user && @current_token
  end

  def current_user
    @current_user
  end

  def render_unauthorized
    render json: { error: "Unauthorized" }, status: :unauthorized
  end

  def set_default_format
    request.format = :json
  end
end
```

### Api::V1::ChatsController
```ruby
class Api::V1::ChatsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_chat_service, only: [:create, :index]

  # POST /api/v1/chats
  def create
    result = @chat_service.create_message(
      content: chat_params[:content],
      provider: chat_params[:provider],
      api_key: chat_params[:api_key],
      system_prompt: chat_params[:system_prompt],
      model: chat_params[:model],
      temperature: chat_params[:temperature],
      max_tokens: chat_params[:max_tokens]
    )

    render json: result, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # GET /api/v1/chats
  def index
    result = @chat_service.list_messages(
      page: params[:page],
      per_page: params[:per_page]
    )

    render json: result
  end

  # GET /api/v1/chats/sessions
  def sessions
    chats = current_user.chats
                        .joins(:messages)
                        .select("chats.*, MAX(messages.sent_at) as last_message_at, COUNT(messages.id) as message_count")
                        .group("chats.id")
                        .order("last_message_at DESC")

    render json: { sessions: format_sessions(chats) }
  end

  # DELETE /api/v1/chats/:id
  def destroy
    message = Message.joins(:chat)
                    .where(chats: { user_id: current_user.id })
                    .find(params[:id])
    message.destroy!

    render json: { message: "Message deleted successfully" }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Message not found" }, status: :not_found
  end

  # DELETE /api/v1/chats/sessions/:id
  def destroy_session
    chat = current_user.chats.find_by(session_id: params[:id])
    return render json: { error: "Session not found" }, status: :not_found unless chat

    chat.destroy!
    render json: { message: "Session deleted successfully" }, status: :ok
  end

  private

  def set_chat_service
    @chat_service = ChatMessageService.new(
      user: current_user,
      session_id: params[:session_id]
    )
  end

  def chat_params
    params.permit(:content, :session_id, :provider, :api_key, :system_prompt, :model, :temperature, :max_tokens)
  end
end
```

## サービス層

### ChatMessageService
```ruby
class ChatMessageService
  attr_reader :user, :chat

  def initialize(user:, session_id: nil)
    @user = user
    @session_id = session_id || generate_session_id
    @chat = find_or_create_chat
  end

  def create_message(content:, provider: nil, api_key: nil, system_prompt: nil, model: nil, temperature: nil, max_tokens: nil)
    ActiveRecord::Base.transaction do
      # 感情抽出
      emotions = extract_emotions(content, provider, api_key)

      # ユーザーメッセージを保存
      user_message = save_user_message(content, emotions)

      # AI応答を生成
      ai_response = generate_ai_response(
        content: content,
        provider: provider,
        api_key: api_key,
        system_prompt: system_prompt,
        model: model,
        temperature: temperature,
        max_tokens: max_tokens
      )

      # アシスタントメッセージを保存
      assistant_message = save_assistant_message(ai_response)

      {
        session_id: @session_id,
        chat_id: @chat.id,
        user_message: serialize_message(user_message),
        assistant_message: serialize_message(assistant_message)
      }
    end
  end

  def list_messages(page: 1, per_page: nil)
    per_page ||= AppConstants::DEFAULT_PAGE_SIZE

    messages = Message.where(chat: @chat)
                     .order(sent_at: :asc)
                     .page(page)
                     .per(per_page)

    {
      messages: messages.map { |msg| serialize_message(msg) },
      total_count: messages.total_count,
      current_page: messages.current_page,
      total_pages: messages.total_pages
    }
  end
end
```

### AiServiceV2
```ruby
class AiServiceV2
  PROVIDERS = {
    openai: "OpenAI",
    anthropic: "Anthropic",
    google: "Google"
  }.freeze

  def initialize(provider: nil, api_key: nil)
    @provider = provider || default_provider
    @api_key = api_key || fetch_api_key(@provider)
    validate_configuration!
  end

  def chat(messages, model: nil, temperature: nil, max_tokens: nil)
    case @provider.to_sym
    when :openai
      openai_chat(messages, model, temperature, max_tokens)
    when :anthropic
      anthropic_chat(messages, model, temperature, max_tokens)
    when :google
      google_chat(messages, model, temperature, max_tokens)
    else
      raise "Unsupported provider: #{@provider}"
    end
  end

  private

  def openai_chat(messages, model, temperature, max_tokens)
    client = OpenAI::Client.new(access_token: @api_key)
    response = client.chat(
      parameters: {
        model: model || "gpt-4o-mini",
        messages: messages,
        temperature: temperature || 0.7,
        max_tokens: max_tokens || 1000
      }
    )
    response.dig("choices", 0, "message", "content")
  end

  def anthropic_chat(messages, model, temperature, max_tokens)
    client = Anthropic::Client.new(api_key: @api_key)
    # Anthropic特有の実装
  end

  def google_chat(messages, model, temperature, max_tokens)
    client = Gemini::Client.new(api_key: @api_key)
    # Google Gemini特有の実装
  end
end
```

### DynamicPromptService
```ruby
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

    base_prompt = generate_base_prompt
    question_control = generate_question_control_prompt(question_count)
    stage_specific = generate_stage_specific_prompt(stage, user_state)

    "#{base_prompt}\n#{question_control}\n#{stage_specific}"
  end

  def recommended_temperature
    stage = determine_conversation_stage
    DynamicPromptConfig.temperature_for_stage(stage)
  end

  private

  def determine_conversation_stage
    case @message_count
    when 0..2 then :opening
    when 3..5 then :exploration
    when 6..8 then :deepening
    when 9..11 then :insight
    else :concluding
    end
  end

  def analyze_user_state
    # ユーザーの感情状態を分析
    emotions = extract_emotions_from_messages
    determine_dominant_emotion(emotions)
  end
end
```

### EmotionExtractionService
```ruby
class EmotionExtractionService
  EMOTION_CATEGORIES = {
    joy: ["嬉しい", "楽しい", "幸せ", "最高", "良かった"],
    sadness: ["悲しい", "辛い", "寂しい", "切ない", "泣きそう"],
    anger: ["怒り", "イライラ", "腹立つ", "むかつく", "憤り"],
    fear: ["怖い", "不安", "心配", "恐怖", "緊張"],
    surprise: ["驚き", "びっくり", "意外", "予想外", "まさか"],
    disgust: ["嫌悪", "気持ち悪い", "不快", "嫌い", "苦手"]
  }.freeze

  def initialize(provider: nil, api_key: nil)
    @ai_service = AiServiceV2.new(provider: provider, api_key: api_key)
  end

  def extract(text)
    return {} if text.blank?

    # AI分析と辞書ベース分析を組み合わせ
    ai_emotions = extract_with_ai(text)
    dict_emotions = extract_with_dictionary(text)

    merge_emotion_scores(ai_emotions, dict_emotions)
  end

  private

  def extract_with_ai(text)
    prompt = build_emotion_extraction_prompt(text)
    response = @ai_service.chat([
      { role: "system", content: "You are an emotion analysis expert." },
      { role: "user", content: prompt }
    ])
    parse_ai_emotion_response(response)
  end

  def extract_with_dictionary(text)
    emotions = {}
    EMOTION_CATEGORIES.each do |emotion, keywords|
      score = calculate_keyword_score(text, keywords)
      emotions[emotion] = score if score > 0
    end
    emotions
  end
end
```

### ReportService
```ruby
class ReportService
  def initialize(user)
    @user = user
  end

  def generate_report(period: :weekly, start_date: nil, end_date: nil)
    start_date, end_date = calculate_date_range(period, start_date, end_date)

    messages = fetch_messages_in_range(start_date, end_date)
    return empty_report if messages.empty?

    report_data = {
      period: period,
      start_date: start_date,
      end_date: end_date,
      message_count: messages.count,
      emotion_summary: analyze_emotions(messages),
      topics: extract_topics(messages),
      insights: generate_insights(messages),
      advice: generate_personalized_advice(messages)
    }

    save_summary(report_data)
    format_report(report_data)
  end

  def get_latest_report(period: :weekly)
    summary = @user.summaries
                   .for_period(period)
                   .recent
                   .first

    return { error: "No report found" } unless summary

    format_report(summary.analysis_data.merge(
      period: summary.period,
      start_date: summary.tally_start_at,
      end_date: summary.tally_end_at
    ))
  end

  private

  def analyze_emotions(messages)
    emotions = messages.flat_map { |m| m.emotions&.to_a || [] }
    emotion_counts = emotions.group_by(&:first)
                             .transform_values { |v| v.map(&:last).sum / v.size }

    {
      dominant_emotion: emotion_counts.max_by(&:last)&.first,
      emotion_distribution: emotion_counts,
      emotional_trend: calculate_emotional_trend(messages)
    }
  end

  def generate_insights(messages)
    # AI分析による洞察生成
    ai_service = AiServiceV2.new
    prompt = build_insight_prompt(messages)
    response = ai_service.chat([
      { role: "system", content: "You are a psychological counselor analyzing chat logs." },
      { role: "user", content: prompt }
    ])
    parse_insights(response)
  end
end
```

## API仕様

### 認証エンドポイント

| メソッド | パス | 説明 | リクエスト | レスポンス |
|---------|------|------|-----------|-----------|
| POST | `/api/v1/auth/signup` | ユーザー登録 | `{ email, password, name }` | `{ user, token }` |
| POST | `/api/v1/auth/login` | ログイン | `{ email, password }` | `{ user, token }` |
| POST | `/api/v1/auth/refresh` | トークン更新 | Authorization header | `{ token }` |
| POST | `/api/v1/auth/logout` | ログアウト | Authorization header | `{ message }` |
| GET | `/api/v1/auth/me` | 現在のユーザー | Authorization header | `{ user }` |

### チャットエンドポイント

| メソッド | パス | 説明 | リクエスト | レスポンス |
|---------|------|------|-----------|-----------|
| POST | `/api/v1/chats` | メッセージ送信 | `{ content, session_id, provider, ... }` | `{ user_message, assistant_message }` |
| GET | `/api/v1/chats` | メッセージ取得 | `?session_id=&page=&per_page=` | `{ messages, total_count, ... }` |
| GET | `/api/v1/chats/sessions` | セッション一覧 | - | `{ sessions }` |
| DELETE | `/api/v1/chats/:id` | メッセージ削除 | - | `{ message }` |
| DELETE | `/api/v1/chats/sessions/:id` | セッション削除 | - | `{ message }` |

### レポートエンドポイント

| メソッド | パス | 説明 | リクエスト | レスポンス |
|---------|------|------|-----------|-----------|
| GET | `/api/v1/report` | 最新レポート | - | `{ report_data }` |
| POST | `/api/v1/report/analyze` | 分析実行 | `{ period, start_date, end_date }` | `{ analysis_result }` |
| GET | `/api/v1/report/weekly` | 週次レポート | - | `{ weekly_report }` |
| GET | `/api/v1/report/monthly` | 月次レポート | - | `{ monthly_report }` |

### 音声エンドポイント

| メソッド | パス | 説明 | リクエスト | レスポンス |
|---------|------|------|-----------|-----------|
| POST | `/api/v1/voices/generate` | 音声生成 | `{ text, voice, speed }` | Audio stream |

### ユーザーエンドポイント

| メソッド | パス | 説明 | リクエスト | レスポンス |
|---------|------|------|-----------|-----------|
| GET | `/api/v1/users/me` | プロフィール取得 | - | `{ user }` |
| PATCH | `/api/v1/users/me` | プロフィール更新 | `{ name, email, ... }` | `{ user }` |

## データベース

### PostgreSQL スキーマ

```sql
-- Enum types
CREATE TYPE period_type AS ENUM ('session', 'daily', 'weekly', 'monthly');

-- Users table
CREATE TABLE users (
  id BIGSERIAL PRIMARY KEY,
  name VARCHAR(50) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  password_digest VARCHAR(255) NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Tags table
CREATE TABLE tags (
  id BIGSERIAL PRIMARY KEY,
  name VARCHAR(50) NOT NULL UNIQUE,
  description TEXT,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Chats table
CREATE TABLE chats (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  tag_id BIGINT REFERENCES tags(id) ON DELETE SET NULL,
  session_id VARCHAR(100) NOT NULL UNIQUE,
  title VARCHAR(120),
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Messages table
CREATE TABLE messages (
  id BIGSERIAL PRIMARY KEY,
  chat_id BIGINT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  role VARCHAR(20) NOT NULL,
  emotions JSONB,
  metadata JSONB,
  sent_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Summaries table
CREATE TABLE summaries (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
  chat_id BIGINT REFERENCES chats(id) ON DELETE CASCADE,
  period period_type NOT NULL,
  tally_start_at TIMESTAMP NOT NULL,
  tally_end_at TIMESTAMP NOT NULL,
  analysis_data JSONB NOT NULL,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- API Tokens table
CREATE TABLE api_tokens (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMP NOT NULL,
  revoked_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_chats_user_id ON chats(user_id);
CREATE INDEX idx_chats_session_id ON chats(session_id);
CREATE INDEX idx_messages_chat_id ON messages(chat_id);
CREATE INDEX idx_messages_sent_at ON messages(sent_at);
CREATE INDEX idx_summaries_user_id ON summaries(user_id);
CREATE INDEX idx_summaries_period ON summaries(period);
CREATE INDEX idx_api_tokens_user_id ON api_tokens(user_id);
CREATE INDEX idx_api_tokens_token ON api_tokens(token);
```

### MongoDB コレクション (将来実装)

```javascript
// Sessions collection
{
  _id: ObjectId,
  user_id: String,
  session_id: String,
  messages: [
    {
      role: String,
      content: String,
      timestamp: Date,
      emotions: Object,
      metadata: Object
    }
  ],
  created_at: Date,
  updated_at: Date
}

// Analytics collection
{
  _id: ObjectId,
  user_id: String,
  date: Date,
  metrics: {
    message_count: Number,
    emotion_scores: Object,
    topics: Array,
    engagement_time: Number
  },
  created_at: Date
}
```

## 認証・認可

### JWT認証フロー

1. ユーザーがログイン情報を送信
2. サーバーが認証情報を検証
3. 有効な場合、JWTトークンを生成
4. トークンをApiTokensテーブルに保存
5. クライアントにトークンを返却
6. 以降のリクエストでAuthorizationヘッダーにトークンを含める
7. サーバーはトークンを検証して認証

### トークン管理
```ruby
# トークン生成
token = ApiToken.generate_jwt(user: user, expires_in: 24.hours)

# トークン検証
decoded = ApiToken.decode_jwt(token_string)
user = User.find(decoded["user_id"]) if decoded

# トークン無効化
token.revoke!
```

## AI統合

### 対応AIプロバイダー

#### OpenAI
- GPT-4o, GPT-4o-mini
- Text generation, Embeddings
- 感情分析、要約生成

#### Anthropic Claude
- Claude 3 Opus, Sonnet, Haiku
- 高度な推論と分析
- 長文コンテキスト処理

#### Google Gemini
- Gemini Pro, Gemini Pro Vision
- マルチモーダル対応
- 日本語最適化

### プロンプトエンジニアリング

動的プロンプト生成により、会話の段階に応じて最適化：
- **開始段階** (0-2メッセージ): 雰囲気作り、信頼構築
- **探索段階** (3-5メッセージ): 話題の深掘り
- **深化段階** (6-8メッセージ): 感情の探索
- **洞察段階** (9-11メッセージ): 気づきの促進
- **締結段階** (12+メッセージ): まとめと次のステップ

## 開発ガイド

### 環境変数

```bash
# .env
DATABASE_HOST=db
DATABASE_USER=postgres
DATABASE_PASSWORD=password
DATABASE_NAME=kokoro_log_development
RAILS_ENV=development

# JWT
JWT_SECRET_KEY=your-secret-key-here

# AI APIs
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_GEMINI_API_KEY=AI...

# MongoDB (オプション)
MONGODB_URI=mongodb://localhost:27017/kokoro_log
```

### 開発コマンド

```bash
# サーバー起動
rails server

# コンソール起動
rails console

# マイグレーション
rails db:migrate

# データベースリセット
rails db:reset

# シード実行
rails db:seed

# テスト実行
rails test

# Rubocop実行
rubocop -A

# ルート確認
rails routes | grep api
```

### Makeコマンド

```bash
# Rails console
make rails-console

# DB console
make db-console

# マイグレーション
make db-migrate

# DB初期化
make db-init

# ログ確認
make logs-web
```

## テスト

### テスト構造
```
test/
├── models/
│   ├── user_test.rb
│   ├── chat_test.rb
│   ├── message_test.rb
│   └── api_token_test.rb
├── controllers/
│   └── api/v1/
│       ├── auth_controller_test.rb
│       ├── chats_controller_test.rb
│       └── reports_controller_test.rb
├── services/
│   ├── ai_service_v2_test.rb
│   ├── chat_message_service_test.rb
│   └── emotion_extraction_service_test.rb
└── integration/
    ├── authentication_flow_test.rb
    └── chat_flow_test.rb
```

### テスト実行
```bash
# 全テスト実行
rails test

# 特定ファイルのテスト
rails test test/models/user_test.rb

# 特定のテストメソッド
rails test test/models/user_test.rb -n test_valid_user

# カバレッジ付き
COVERAGE=true rails test
```

## デプロイ

### Docker設定

```dockerfile
FROM ruby:3.3.5-slim

# 必要なパッケージをインストール
RUN apt-get update -qq && \
    apt-get install -y postgresql-client build-essential libpq-dev nodejs && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Gemfile をコピーして bundle install
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'development test' && \
    bundle install --jobs=4

# アプリケーションコードをコピー
COPY . .

# アセットプリコンパイル（必要な場合）
# RUN rails assets:precompile

# ポート公開
EXPOSE 3000

# サーバー起動
CMD ["rails", "server", "-b", "0.0.0.0"]
```

### 本番環境の最適化

#### パフォーマンス設定
```ruby
# config/environments/production.rb
config.cache_classes = true
config.eager_load = true
config.force_ssl = true
config.log_level = :info
config.active_record.dump_schema_after_migration = false
```

#### データベース接続プール
```yaml
# config/database.yml
production:
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000
```

#### メモリ最適化（t3.micro向け）
```bash
# docker-compose.prod.yml
services:
  web:
    mem_limit: 400m
    environment:
      - RAILS_MAX_THREADS=3
      - WEB_CONCURRENCY=1
```

## セキュリティ

### 実装済みセキュリティ対策

- **認証**: JWT + BCrypt
- **CORS**: 設定済み
- **SQLインジェクション対策**: ActiveRecord使用
- **XSS対策**: API mode + JSON response
- **強力なパラメータ**: Strong Parameters
- **セキュアヘッダー**: ActionDispatch::SSL

### セキュリティベストプラクティス

```ruby
# CORS設定
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("FRONTEND_URL", "http://localhost:3001")
    resource "/api/*",
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: true
  end
end

# Rate limiting (今後実装)
# Rack::Attack設定
```

## トラブルシューティング

### よくある問題

#### 1. データベース接続エラー
```bash
# PostgreSQLの状態確認
docker compose ps db
docker compose logs db

# 接続テスト
rails db:migrate:status
```

#### 2. JWTトークンエラー
```bash
# トークンの検証
rails console
> token = "your-token-here"
> ApiToken.decode_jwt(token)
```

#### 3. AI API エラー
```bash
# APIキーの確認
rails console
> ENV["OPENAI_API_KEY"]
> AiServiceV2.new.test_connection
```

#### 4. メモリ不足（t3.micro）
```bash
# メモリ使用状況確認
docker stats

# プロセス調整
RAILS_MAX_THREADS=2 WEB_CONCURRENCY=1 rails server
```

## 関連資料
- [Rails Guides](https://guides.rubyonrails.org/)
- [Rails API Documentation](https://api.rubyonrails.org/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [OpenAI API Reference](https://platform.openai.com/docs/)
- [Anthropic API Documentation](https://docs.anthropic.com/)
- [Google AI Documentation](https://ai.google.dev/)