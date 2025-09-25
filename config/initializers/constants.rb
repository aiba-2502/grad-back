# Application-wide constants

module AppConstants
  # Pagination
  DEFAULT_PAGE_SIZE = 20
  MAX_PAGE_SIZE = 100

  # Chat settings
  MAX_PAST_MESSAGES = 10
  MAX_MESSAGE_LENGTH = 10000
  DEFAULT_SESSION_TIMEOUT = 24.hours

  # User settings
  MIN_PASSWORD_LENGTH = 6
  MAX_NAME_LENGTH = 50
  MAX_EMAIL_LENGTH = 255

  # API limits
  MAX_TITLE_LENGTH = 120
  MAX_CONTENT_LENGTH = 65535

  # AI Service settings
  module AI
    DEFAULT_MODEL = "gpt-4o-mini"
    DEFAULT_MAX_TOKENS = 1000
    DEFAULT_TEMPERATURE = 0.7
    MAX_TEMPERATURE = 2.0
    MIN_TEMPERATURE = 0.0
  end

  # Response status
  module Status
    SUCCESS = "success"
    ERROR = "error"
    PENDING = "pending"
  end

  # User roles (for future use)
  module Role
    USER = "user"
    ADMIN = "admin"
    MODERATOR = "moderator"
  end

  # Message roles
  module MessageRole
    USER = "user"
    ASSISTANT = "assistant"
    SYSTEM = "system"
  end
end
