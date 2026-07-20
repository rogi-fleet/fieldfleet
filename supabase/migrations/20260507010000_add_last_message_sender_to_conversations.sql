alter table conversations
  add column if not exists last_message_sender_id uuid references auth.users(id);
