# Workspace Messaging System Walkthrough

This document provides a guide to the newly implemented Workspace Messaging System in FieldFleet.

## Overview

The messaging system allows workspace members to communicate with each other in real-time through direct (1-on-1) conversations.

## Features

- **Real-time Messaging**: Messages appear instantly without refreshing.
- **Direct Conversations**: Start 1-on-1 chats with any other member of the workspace.
- **Read Receipts**: See when your messages have been read (indicated by a double checkmark).
- **Unread Counts**: View the number of unread messages for each conversation.
- **Workspace Isolation**: Conversations are strictly scoped to the current workspace.

## How to Use

### Accessing Messages
1.  Open the **Messages** tab in the main navigation menu (left sidebar on desktop, bottom bar on mobile).
2.  You will see a list of your active conversations.

### Starting a New Conversation
1.  From the Messages screen, click the **+ (Plus)** button or **New Message**.
2.  You will see a list of all other members in the current workspace.
3.  Tap on a member to start a conversation.
    - If a conversation already exists, it will open.
    - If not, a new one will be created.

### Sending Messages
1.  Inside a conversation, type your message in the text field at the bottom.
2.  Press the **Send** button (paper airplane icon).
3.  Your message will appear in the chat bubble list.

### Read Receipts
- **Sent**: Message bubble appears.
- **Read**: A double checkmark icon appears next to the timestamp when the other person opens the conversation.

## Technical Details

### Data Models
- **Conversation**: Stores participants, last message details, and metadata.
- **Message**: Stores content, sender, timestamp, and read status.

### Security
- **Firestore Rules**: Ensure only participants can read/write to a conversation.
- **Workspace Scoping**: All queries are filtered by `workspaceId`.

### Navigation
- **Route**: `/messages` (List), `/messages/new` (Select Member), `/messages/conversation/:id` (Chat).
- **Integration**: Added to `AdaptiveNavigation` and `AppRouter`.

## Future Improvements (Not in MVP)
- Group chats / Channels.
- Rich text and file attachments.
- Push notifications.
- Typing indicators.
