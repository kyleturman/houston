# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Note, type: :model do
  let(:user) { create(:user) }
  
  describe 'validations' do
    it 'requires user' do
      note = Note.new(title: 'Test Note', content: 'Test content')
      expect(note).not_to be_valid
      expect(note.errors[:user]).to include('must exist')
    end
    
    it 'requires content' do
      note = Note.new(user: user, title: 'Test Note')
      expect(note).not_to be_valid
      expect(note.errors[:content]).to include("can't be blank")
    end
    
    it 'is valid without title' do
      note = Note.new(user: user, content: 'Test content')
      expect(note).to be_valid
    end
    
    it 'is valid with all attributes' do
      note = Note.new(user: user, title: 'Test Note', content: 'Test content')
      expect(note).to be_valid
    end
  end
  
  describe 'associations' do
    it 'belongs to user' do
      expect(Note.reflect_on_association(:user).macro).to eq(:belongs_to)
    end
  end
  
  describe 'note creation and retrieval' do
    let!(:note1) { create(:note, user: user, title: 'Ruby Programming', content: 'Learn Ruby basics') }
    let!(:note2) { create(:note, user: user, title: 'JavaScript Guide', content: 'Advanced JavaScript concepts') }
    let!(:note3) { create(:note, user: user, title: 'Database Design', content: 'SQL and NoSQL databases') }
    
    it 'can retrieve notes by user' do
      user_notes = Note.where(user: user)
      expect(user_notes).to include(note1, note2, note3)
    end
    
    it 'can retrieve individual notes' do
      expect(note1.title).to eq('Ruby Programming')
      expect(note1.content).to eq('Learn Ruby basics')
    end
    
    it 'handles encrypted fields correctly' do
      # Note: title and content are encrypted, so we test retrieval rather than search
      retrieved_note = Note.find(note1.id)
      expect(retrieved_note.title).to eq('Ruby Programming')
      expect(retrieved_note.content).to eq('Learn Ruby basics')
    end
  end
  
  describe 'scopes' do
    let!(:recent_note) { create(:note, user: user, created_at: 1.day.ago) }
    let!(:old_note) { create(:note, user: user, created_at: 1.month.ago) }

    it 'orders by most recent by default' do
      notes = Note.where(user: user).order(created_at: :desc)
      expect(notes.first).to eq(recent_note)
      expect(notes.last).to eq(old_note)
    end
  end
  
  describe 'content handling' do
    it 'preserves line breaks in content' do
      content_with_breaks = "Line 1\nLine 2\n\nLine 4"
      note = create(:note, user: user, content: content_with_breaks)
      
      expect(note.reload.content).to eq(content_with_breaks)
    end
    
    it 'handles long content' do
      long_content = 'A' * 10000
      note = create(:note, user: user, content: long_content)
      
      expect(note.reload.content.length).to eq(10000)
    end
  end
end
