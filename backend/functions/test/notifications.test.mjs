import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { buildMessages, MAX_EVENT_AGE_MS, notificationContent, processEvent, recipientIds } from '../notifications.js';

const NOW = 1_700_000_000_000;
const at = (millis) => ({ toMillis: () => millis });

const bobLeftOffice = {
  memberId: 'bob',
  memberName: 'Bob',
  geofenceId: 'office',
  geofenceName: 'Office',
  occurredAt: at(NOW - 1000),
  type: 'EXIT',
};

function fakeBackend({ group, members = {}, geofences = {}, devices = {}, failingTokens = {} } = {}) {
  const claimed = new Set();
  const deleted = [];
  const sent = [];
  const db = {
    getGroup: async () => group,
    getMember: async (_, uid) => members[uid],
    getGeofence: async (_, id) => geofences[id],
    claimDelivery: async (groupId, eventId) => {
      const key = `${groupId}_${eventId}`;
      if (claimed.has(key)) return false;
      claimed.add(key);
      return true;
    },
    getDevices: async (uid) => (devices[uid] ?? []).map((token, index) => ({ uid, id: `${uid}-${index}`, token })),
    deleteDevice: async (uid, id) => deleted.push(`${uid}/${id}`),
  };
  const messaging = {
    sendEach: async (messages) => {
      sent.push(...messages);
      const responses = messages.map((message) => (failingTokens[message.token]
        ? { success: false, error: { code: failingTokens[message.token] } }
        : { success: true }));
      return { successCount: responses.filter((response) => response.success).length, responses };
    },
  };
  return { db, messaging, sent, deleted };
}

const family = {
  group: { name: 'Family', memberIds: ['alice', 'bob', 'carol'] },
  members: { bob: { displayName: 'Bob' } },
  geofences: { office: { name: 'Office' } },
  devices: { alice: ['alice-phone', 'alice-ipad'], bob: ['bob-phone'], carol: ['carol-phone'] },
};

const run = (backend, overrides = {}) => processEvent({
  db: backend.db, messaging: backend.messaging, groupId: 'g1', eventId: 'bob_office_exit_1', event: bobLeftOffice, now: NOW, ...overrides,
});

describe('recipients and content', () => {
  test('everyone in the group except the sender is a recipient', () => {
    assert.deepEqual(recipientIds({ memberIds: ['alice', 'bob', 'carol', 'bob'] }, 'bob'), ['alice', 'carol']);
  });

  test('exit and entry notifications name the member, place and group', () => {
    assert.deepEqual(notificationContent(bobLeftOffice, 'Family'), { title: 'Bob left Office', body: 'Bob left Office (Family).' });
    assert.deepEqual(notificationContent({ ...bobLeftOffice, type: 'ENTRY' }, 'Family'), {
      title: 'Bob arrived at Office', body: 'Bob arrived at Office (Family).',
    });
    assert.equal(notificationContent({ ...bobLeftOffice, type: undefined }, 'Family').title, 'Bob left Office');
  });

  test('messages carry no location data and collapse duplicates by event id', () => {
    const [message] = buildMessages(['token'], { groupId: 'g1', eventId: 'e1', event: { ...bobLeftOffice, latitude: 1 }, groupName: 'Family' });
    assert.deepEqual(Object.keys(message.data).sort(), ['eventId', 'groupId', 'type']);
    assert.equal(message.apns.headers['apns-collapse-id'], 'e1');
    assert.ok(!JSON.stringify(message).includes('latitude'));
  });
});

describe('processing events', () => {
  test('sends to every device of every other member, never to the sender', async () => {
    const backend = fakeBackend(family);
    const result = await run(backend);
    assert.equal(result.status, 'sent');
    assert.deepEqual(backend.sent.map((message) => message.token).sort(), ['alice-ipad', 'alice-phone', 'carol-phone']);
  });

  test('processing the same event twice sends only once', async () => {
    const backend = fakeBackend(family);
    await run(backend);
    const second = await run(backend);
    assert.equal(second.status, 'already-processed');
    assert.equal(backend.sent.length, 3);
  });

  test('a later event from the same member is still sent', async () => {
    const backend = fakeBackend(family);
    await run(backend);
    await run(backend, { eventId: 'bob_office_entry_2', event: { ...bobLeftOffice, type: 'ENTRY' } });
    assert.equal(backend.sent.length, 6);
  });

  test('events from non-members, renamed members or unknown geofences are not sent', async () => {
    const backend = fakeBackend(family);
    assert.equal((await run(backend, { event: { ...bobLeftOffice, memberId: 'mallory' } })).status, 'not-a-member');
    assert.equal((await run(backend, { event: { ...bobLeftOffice, memberName: 'Alice' } })).status, 'mismatched-event');
    assert.equal((await run(backend, { event: { ...bobLeftOffice, geofenceId: 'gym' } })).status, 'mismatched-event');
    assert.equal(backend.sent.length, 0);
  });

  test('malformed, unknown-type or old events are ignored', async () => {
    const backend = fakeBackend(family);
    assert.equal((await run(backend, { event: { ...bobLeftOffice, type: 'STAY' } })).status, 'invalid-event');
    assert.equal((await run(backend, { event: { ...bobLeftOffice, memberName: 7 } })).status, 'invalid-event');
    assert.equal((await run(backend, { event: { ...bobLeftOffice, occurredAt: at(NOW - MAX_EVENT_AGE_MS - 1) } })).status, 'too-old');
    assert.equal(backend.sent.length, 0);
  });

  test('tokens rejected as unregistered are removed, other failures are kept', async () => {
    const backend = fakeBackend({
      ...family,
      failingTokens: { 'alice-ipad': 'messaging/registration-token-not-registered', 'carol-phone': 'messaging/internal-error' },
    });
    const result = await run(backend);
    assert.equal(result.sent, 1);
    assert.deepEqual(backend.deleted, ['alice/alice-1']);
  });
});
