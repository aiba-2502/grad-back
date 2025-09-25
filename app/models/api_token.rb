# frozen_string_literal: true

require "securerandom"
require "digest"

class ApiToken < ApplicationRecord
  # Constants
  TOKEN_LENGTH = 32
  ACCESS_TOKEN_EXPIRY_HOURS = 2
  REFRESH_TOKEN_EXPIRY_DAYS = 7

  # Associations
  belongs_to :user

  # Validations
  validates :user, presence: true
  validate :at_least_one_token_present

  # Callbacks
  before_validation :generate_initial_tokens, on: :create

  # Scopes
  scope :active, -> {
    where(revoked_at: nil)
      .where("(access_expires_at IS NULL OR access_expires_at > ?) OR (refresh_expires_at IS NULL OR refresh_expires_at > ?)",
             Time.current, Time.current)
  }
  scope :expired, -> {
    where("(access_expires_at IS NOT NULL AND access_expires_at <= ?) AND (refresh_expires_at IS NOT NULL AND refresh_expires_at <= ?)",
          Time.current, Time.current)
  }

  # Class Methods
  def self.find_by_access_token(raw_token)
    return nil if raw_token.blank?

    encrypted = encrypt_token(raw_token)
    active.find_by(encrypted_access_token: encrypted)
  end

  def self.find_by_refresh_token(raw_token)
    return nil if raw_token.blank?

    encrypted = encrypt_token(raw_token)
    find_by(encrypted_refresh_token: encrypted)
  end

  # 後方互換性のためのメソッド（段階的に廃止予定）
  def self.find_by_token(raw_token)
    return nil if raw_token.blank?

    encrypted = encrypt_token(raw_token)

    # まず新しい方式で検索
    token = active.find_by(encrypted_access_token: encrypted)
    return token if token

    # 見つからなければリフレッシュトークンとして検索
    active.find_by(encrypted_refresh_token: encrypted)
  end

  def self.authenticate(raw_token)
    token_record = find_by_access_token(raw_token)
    return nil unless token_record

    token_record.user if token_record.access_valid?
  end

  def self.encrypt_token(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end

  # 新しいトークンペア生成（1レコードで管理）
  def self.generate_token_pair(user)
     token_family_id = SecureRandom.uuid

    # 両方のトークンを生成
    raw_access_token = SecureRandom.hex(TOKEN_LENGTH)
    raw_refresh_token = SecureRandom.hex(TOKEN_LENGTH)

    token_record = new(
      user: user,
      encrypted_access_token: encrypt_token(raw_access_token),
      encrypted_refresh_token: encrypt_token(raw_refresh_token),
      access_expires_at: ACCESS_TOKEN_EXPIRY_HOURS.hours.from_now,
      refresh_expires_at: REFRESH_TOKEN_EXPIRY_DAYS.days.from_now,
      token_family_id: token_family_id
    )

    token_record.save!

    # raw_tokenを仮想属性として設定
    token_record.raw_access_token = raw_access_token
    token_record.raw_refresh_token = raw_refresh_token

    # 後方互換性のため、既存のAPIレスポンス形式を維持
    {
      access_token: OpenStruct.new(raw_token: raw_access_token),
      refresh_token: OpenStruct.new(raw_token: raw_refresh_token)
    }
  end

  # リフレッシュトークンで新しいトークンペアを生成
  def rotate_tokens!
    # 新しいトークンを生成
    raw_access_token = SecureRandom.hex(TOKEN_LENGTH)
    raw_refresh_token = SecureRandom.hex(TOKEN_LENGTH)

    # 同じレコードを更新
    update!(
      encrypted_access_token: self.class.encrypt_token(raw_access_token),
      encrypted_refresh_token: self.class.encrypt_token(raw_refresh_token),
      access_expires_at: ACCESS_TOKEN_EXPIRY_HOURS.hours.from_now,
      refresh_expires_at: REFRESH_TOKEN_EXPIRY_DAYS.days.from_now
    )

    # raw_tokenを返す
    self.raw_access_token = raw_access_token
    self.raw_refresh_token = raw_refresh_token

    {
      access_token: OpenStruct.new(raw_token: raw_access_token),
      refresh_token: OpenStruct.new(raw_token: raw_refresh_token)
    }
  end

  # 古いトークンのクリーンアップ
  def self.cleanup_old_tokens(user_id, keep_count: 5)
    # ユーザーごとに最新のトークンのみ保持
    tokens = where(user_id: user_id)
             .active
             .order(created_at: :desc)
             .offset(keep_count)

    tokens.update_all(revoked_at: Time.current)
  end

  # Instance Methods
  attr_accessor :raw_access_token, :raw_refresh_token

  def active?
    revoked_at.nil? && (access_valid? || refresh_valid?)
  end

  def access_valid?
    revoked_at.nil? && encrypted_access_token.present? &&
      (access_expires_at.nil? || access_expires_at > Time.current)
  end

  def refresh_valid?
    revoked_at.nil? && encrypted_refresh_token.present? &&
      (refresh_expires_at.nil? || refresh_expires_at > Time.current)
  end

  def expired?
    !active?
  end

  # トークン有効性チェック（後方互換性）
  def token_valid?
    active?
  end

  # トークンチェーンの無効化
  def revoke_chain!
    if token_family_id.present?
      ApiToken.where(token_family_id: token_family_id)
              .update_all(revoked_at: Time.current)
    end
  end

  # トークンタイプ判定（後方互換性のため残す）
  def refresh?
    encrypted_refresh_token.present?
  end

  def access?
    encrypted_access_token.present?
  end

  def expire!
    update!(revoked_at: Time.current)
  end

  def refresh!(days = REFRESH_TOKEN_EXPIRY_DAYS)
    update!(refresh_expires_at: days.days.from_now)
  end

  def days_until_expiry
    return nil unless refresh_expires_at
    ((refresh_expires_at - Time.current) / 1.day).ceil
  end

  private

  def generate_initial_tokens
    # createコールバック用（通常は使用されない）
    if encrypted_access_token.blank? && encrypted_refresh_token.blank?
      self.raw_access_token = SecureRandom.hex(TOKEN_LENGTH)
      self.raw_refresh_token = SecureRandom.hex(TOKEN_LENGTH)
      self.encrypted_access_token = self.class.encrypt_token(raw_access_token)
      self.encrypted_refresh_token = self.class.encrypt_token(raw_refresh_token)
      self.access_expires_at ||= ACCESS_TOKEN_EXPIRY_HOURS.hours.from_now
      self.refresh_expires_at ||= REFRESH_TOKEN_EXPIRY_DAYS.days.from_now
    end
  end

  def at_least_one_token_present
    if encrypted_access_token.blank? && encrypted_refresh_token.blank?
      errors.add(:base, "少なくとも1つのトークンが必要です")
    end
  end
end
