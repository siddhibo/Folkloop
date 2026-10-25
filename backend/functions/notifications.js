export const MAX_EVENT_AGE_MS = 60 * 60 * 1000;

const INVALID_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

export function eventType(event) {
  return event.type ?? 'EXIT';
}

export function isWellFormedEvent(event) {
  return typeof event?.memberId === 'string'
    && typeof event.memberName === 'string'
    && typeof event.geofenceId === 'string'
    && typeof event.geofenceName === 'string'
    && ['ENTRY', 'EXIT'].includes(eventType(event));
}

export function recipientIds(group, senderId) {
  return [...new Set(group.memberIds ?? [])].filter((memberId) => memberId !== senderId);
}

export function notificationContent(event, groupName) {
  const action = eventType(event) === 'ENTRY' ? 'arrived at' : 'left';
  return {
    title: `${event.memberName} ${action} ${event.geofenceName}`,
    body: `${event.memberName} ${action} ${event.geofenceName} (${groupName}).`,
  };
}

export function buildMessages(tokens, { groupId, eventId, event, groupName }) {
  const { title, body } = notificationContent(event, groupName);
  return tokens.map((token) => ({
    token,
    notification: { title, body },
    data: { groupId, eventId, type: eventType(event) },
    apns: {
      headers: { 'apns-collapse-id': eventId.slice(0, 64), 'apns-priority': '10' },
      payload: { aps: { 'thread-id': groupId, sound: 'default' } },
    },
  }));
}

export async function processEvent({ db, messaging, groupId, eventId, event, now = Date.now() }) {
  if (!isWellFormedEvent(event)) return { status: 'invalid-event' };
  const occurredAt = event.occurredAt?.toMillis?.();
  if (typeof occurredAt !== 'number' || now - occurredAt > MAX_EVENT_AGE_MS) return { status: 'too-old' };

  const group = await db.getGroup(groupId);
  if (!group || !(group.memberIds ?? []).includes(event.memberId)) return { status: 'not-a-member' };
  const member = await db.getMember(groupId, event.memberId);
  const geofence = await db.getGeofence(groupId, event.geofenceId);
  if (member?.displayName !== event.memberName || geofence?.name !== event.geofenceName) {
    return { status: 'mismatched-event' };
  }

  if (!(await db.claimDelivery(groupId, eventId))) return { status: 'already-processed' };

  const recipients = recipientIds(group, event.memberId);
  const devices = (await Promise.all(recipients.map((uid) => db.getDevices(uid)))).flat();
  if (devices.length === 0) return { status: 'no-devices', sent: 0 };

  const messages = buildMessages(devices.map((device) => device.token), {
    groupId, eventId, event, groupName: group.name,
  });
  const result = await messaging.sendEach(messages);
  const invalidDevices = result.responses
    .map((response, index) => (!response.success && INVALID_TOKEN_CODES.has(response.error?.code) ? devices[index] : null))
    .filter(Boolean);
  await Promise.all(invalidDevices.map((device) => db.deleteDevice(device.uid, device.id)));
  return { status: 'sent', sent: result.successCount, removedTokens: invalidDevices.length };
}
