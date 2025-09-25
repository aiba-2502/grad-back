require 'rails_helper'

RSpec.describe ChatSessionService, type: :service do
  let(:user) { create(:user) }
  let(:session_id) { SecureRandom.uuid }
  let(:service) { described_class.new }

  describe '#find_or_create_chat' do
    context 'when chat does not exist' do
      it 'creates a new chat with session_id in title' do
        chat = service.find_or_create_chat(session_id, user)

        expect(chat).to be_persisted
        expect(chat.user).to eq(user)
        expect(chat.title).to eq("session:#{session_id}")
      end
    end

    context 'when chat already exists' do
      let!(:existing_chat) do
        Chat.create!(
          user: user,
          title: "session:#{session_id}"
        )
      end

      it 'returns the existing chat' do
        chat = service.find_or_create_chat(session_id, user)

        expect(chat).to eq(existing_chat)
        expect(Chat.where(title: "session:#{session_id}").count).to eq(1)
      end
    end

    context 'with existing messages' do
      let!(:chat_message) do
        create(:chat_message,
          user: user,
          session_id: session_id,
          created_at: 2.days.ago
        )
      end

      it 'sets chat created_at to earliest message time' do
        chat = service.find_or_create_chat(session_id, user)

        expect(chat.created_at).to be_within(1.second).of(chat_message.created_at)
      end
    end
  end

  describe '#session_id_from_chat' do
    let(:chat) { Chat.create!(user: user, title: "session:#{session_id}") }

    it 'extracts session_id from chat title' do
      extracted_id = service.session_id_from_chat(chat)

      expect(extracted_id).to eq(session_id)
    end

    context 'with non-session title' do
      let(:chat) { Chat.create!(user: user, title: "Regular Chat Title") }

      it 'returns nil' do
        extracted_id = service.session_id_from_chat(chat)

        expect(extracted_id).to be_nil
      end
    end
  end
end
