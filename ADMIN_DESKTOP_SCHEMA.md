# XapZap Admin Desktop Schema

This file documents the Appwrite tables and fields expected by the desktop admin app in:

- [lib/main_admin_desktop.dart](/c:/XapZap/xapzap/lib/main_admin_desktop.dart)
- [lib/admin/admin_desktop_app.dart](/c:/XapZap/xapzap/lib/admin/admin_desktop_app.dart)
- [lib/screens/help_support_screen.dart](/c:/XapZap/xapzap/lib/screens/help_support_screen.dart)

## Purpose

The desktop app is an admin-only control panel for:

- moderation
- support/help requests
- payout handling
- creator support lookup
- Appwrite data browsing
- backend operations

## Required Existing Tables

These are already used by the main app and are also read by the admin desktop:

- `profiles`
- `posts`
- `comments`
- `reports`
- `notifications`
- `messages`
- `chats`
- `ad_impressions`
- `creator_balances`
- `creator_payouts`
- `creator_earnings_daily`

## New Table

### `support_requests`

This table should be created in Appwrite.

Recommended fields:

| Field | Type | Required | Notes |
|---|---|---:|---|
| `userId` | string | no | empty string allowed for unauthenticated cases if needed |
| `email` | string | no | request sender email |
| `username` | string | no | sender username |
| `displayName` | string | no | sender display name |
| `subject` | string | yes | short support title |
| `message` | text | yes | support message body |
| `category` | string or enum | yes | e.g. `general`, `account`, `bug`, `moderation`, `payment` |
| `status` | string or enum | yes | e.g. `open`, `in_progress`, `answered`, `resolved` |
| `createdAt` | datetime | yes | ISO datetime string |
| `adminReply` | text | no | admin response text |
| `repliedAt` | datetime | no | when admin replied |

Recommended indexes:

- `userId`
- `status`
- `category`
- `createdAt`

## Extra Fields Used By Admin Workflows

These fields are optional in the mobile app but should exist if you want the richer admin workflows to persist data cleanly.

### `profiles`

Recommended extra fields:

| Field | Type | Required | Notes |
|---|---|---:|---|
| `dateOfBirth` | datetime | no | stored birth date used for age-gated experiences |
| `canSeeDatingButton` | boolean | no | stable 17+ eligibility flag for the dating entry point |

How to set `canSeeDatingButton`:

- the app already sets it automatically during signup and sign-in recovery logic
- if `dateOfBirth` resolves to age 17 or older, the client writes `canSeeDatingButton = true`
- if `dateOfBirth` is missing or under 17, the client writes `canSeeDatingButton = false`
- you can also set it manually in Appwrite on the user row in `profiles` if you need an admin override

### `reports`

Recommended extra fields:

| Field | Type | Required | Notes |
|---|---|---:|---|
| `status` | string or enum | no | `open`, `reviewing`, `resolved` |
| `resolvedAt` | datetime | no | when report was resolved |
| `moderationNotes` | text | no | internal admin note |
| `lastModeratedAt` | datetime | no | last admin moderation action |

### `posts`

Recommended extra fields: 

| Field | Type | Required | Notes |
|---|---|---:|---|
| `moderationNotes` | text | no | internal note |
| `lastModeratedAt` | datetime | no | moderation timestamp |

### `comments`

Recommended extra fields:

| Field | Type | Required | Notes |
|---|---|---:|---|
| `moderationNotes` | text | no | internal note |
| `lastModeratedAt` | datetime | no | moderation timestamp |

### `creator_payouts`

Recommended extra fields:

| Field | Type | Required | Notes |
|---|---|---:|---|
| `status` | string or enum | no | `requested`, `processing`, `paid` |
| `approvalNotes` | text | no | internal payout approval note |
| `approvedAt` | datetime | no | payout review timestamp |

## Permissions

Recommended Appwrite permissions approach:

- normal app users can create their own `support_requests`
- admins can read and update all `support_requests`
- admins can read and update `reports`
- admins can update moderation fields on `posts` and `comments`
- admins can read and update `creator_payouts`
- admins can read `creator_balances`, `creator_earnings_daily`, `ad_impressions`
- users should be able to read dating-enabled `profiles` rows that are meant for discovery
- users should be able to create their own `dating_likes` and `dating_passes`
- users should be able to read their own `dating_matches`

If you are using broad server-side/admin access in the current project, keep it consistent with the rest of your Appwrite setup.

## Dating Tables

If you want the new relationship screen to use real data instead of placeholders, keep using `profiles` and create only these three dating tables.

Minimal dating setup:

- `profiles.dateOfBirth`
- `profiles.canSeeDatingButton`
- `dating_likes`
- `dating_passes`
- `dating_matches`

### `dating_likes`

Recommended fields:

| Field | Type | Required | Notes |
|---|---|---:|---|
| `fromUserId` | string | yes | liker |
| `toUserId` | string | yes | liked user |
| `createdAt` | datetime | yes | like timestamp |

Recommended indexes:

- `fromUserId`
- `toUserId`
- composite on `fromUserId`, `toUserId`

### `dating_passes`

Recommended fields:

| Field | Type | Required | Notes |
|---|---|---:|---|
| `fromUserId` | string | yes | passer |
| `toUserId` | string | yes | skipped user |
| `createdAt` | datetime | yes | pass timestamp |

Recommended indexes:

- `fromUserId`
- `toUserId`

### `dating_matches`

Recommended fields:

| Field | Type | Required | Notes |
|---|---|---:|---|
| `userAId` | string | yes | sorted lower/first user id |
| `userBId` | string | yes | sorted higher/second user id |
| `matchedAt` | datetime | yes | time mutual like was formed |
| `chatId` | string | no | set after first match-only chat open |

Recommended indexes:

- `userAId`
- `userBId`
- `matchedAt`

## How To Run The Desktop App

### Windows

Run the admin desktop app:

```cmd
flutter run -d windows -t lib/main_admin_desktop.dart
```

Build Windows release:

```cmd
flutter build windows -t lib/main_admin_desktop.dart
```

### macOS

Run:

```bash
flutter run -d macos -t lib/main_admin_desktop.dart
```

Build:

```bash
flutter build macos -t lib/main_admin_desktop.dart
```

### Linux

Run:

```bash
flutter run -d linux -t lib/main_admin_desktop.dart
```

Build:

```bash
flutter build linux -t lib/main_admin_desktop.dart
```

## Desktop Login Rules

The desktop app:

- uses the existing Appwrite auth/session flow
- signs in with email and password
- checks `isCurrentUserAdmin()`
- blocks non-admin accounts

So the admin account must already exist in your normal user system and have admin access enabled in `profiles`.

## Current Admin Sections

The desktop app currently includes:

- `Overview`
- `Users`
- `Moderation`
- `Support`
- `Payouts`
- `Creators`
- `Data`
- `Operations`

## Notes

- This admin desktop app is separate from the mobile app entrypoint, so Android/mobile startup is not affected.
- The admin desktop currently reuses the same Appwrite services already present in the project.
