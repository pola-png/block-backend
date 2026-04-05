Block Filter + Push Notification Deploy Notes

This function package now handles:

- existing block-filter/feed routes
- account deletion route
- AdMob sync routes
- FCM push dispatch for notification rows
- Appwrite Messaging push target registration
- Appwrite Messaging topic subscription
- Appwrite Messaging push sending for topic/user/target delivery

Required Appwrite function event

- Add a table-row create event for the notifications table to this same function.
- Use the notifications row create event for your project/database/table.

Required queue table

- Create a dedicated `notification_queue` table for batched notification fan-out.
- The queue processor reads pending rows from that table.
- Suggested columns:
  - `eventType` string
  - `status` string
  - `postId` string
  - `creatorId` string
  - `title` string
  - `body` string
  - `actorName` string
  - `actorAvatar` string
  - `actionUrl` string
  - `recipientIdsJson` string
  - `recipientCount` integer
  - `attempts` integer
  - `createdAt` text
  - `updatedAt` text

Required messaging target table

- Create a dedicated `messaging_targets` table to map your app device IDs to Appwrite Messaging target IDs.
- Suggested columns:
  - `userId` string
  - `deviceId` string
  - `targetId` string
  - `platform` string
  - `targetName` string
  - `enabled` boolean
  - `tokenHash` string
  - `createdAt` text
  - `updatedAt` text

Expected function environment variables

- `APPWRITE_FUNCTION_API_KEY` or `APPWRITE_API_KEY`
- `APPWRITE_FUNCTION_API_ENDPOINT` or `APPWRITE_ENDPOINT`
- `APPWRITE_FUNCTION_PROJECT_ID` or `APPWRITE_PROJECT_ID`
- `XAPZAP_DATABASE_ID`
- `XAPZAP_NOTIFICATION_QUEUE_TABLE_ID`
- `XAPZAP_NOTIFICATIONS_TABLE_ID`
- `XAPZAP_MESSAGING_TARGETS_TABLE_ID`
- `XAPZAP_BROADCAST_TOPIC_ID`
- `XAPZAP_PUSH_PROVIDER_ID` (optional when only one push provider is configured)
- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`

Firebase notes

- `FIREBASE_PRIVATE_KEY` must preserve line breaks. If entered as a single line in Appwrite env vars, `\n` is supported and converted back at runtime.

Profile schema fields expected by push delivery

- `fcmToken`
- `pushNotificationsEnabled`
- `pushPlatform`
- `pushUpdatedAt`

Manual test route

- The same function also supports an explicit route:
- `/v1/notifications/dispatch`
- `/v1/messaging/push/register-device`
- `/v1/messaging/topics/subscribe-device`
- `/v1/messaging/push/send`

Minimal JSON body example

```json
{
  "notification": {
    "$id": "notif_123",
    "userId": "user_123",
    "title": "New follower",
    "body": "Jane started following you.",
    "type": "follow",
    "actorAvatar": "https://example.com/avatar.jpg",
    "actionUrl": "/notifications"
  }
}
```

Register device example

```json
{
  "token": "fcm_registration_token",
  "enabled": true,
  "platform": "android",
  "deviceId": "local_device_id",
  "targetName": "mobile-android",
  "topicId": "all-users",
  "userJwt": "appwrite_user_jwt"
}
```

Send push example

```json
{
  "mode": "topic",
  "topicId": "all-users",
  "title": "New post on XapZap",
  "body": "Someone just posted a new update.",
  "data": {
    "type": "post",
    "postId": "post_123",
    "actionUrl": "/post/post_123"
  }
}
```
