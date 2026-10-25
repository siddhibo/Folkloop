import { after, before, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  arrayRemove,
  arrayUnion,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const GROUP = 'group-1';
const CODE = 'ABC234';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-geocircle',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

after(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
});

const dbFor = (uid) => env.authenticatedContext(uid).firestore();

function createGroupBatch(db, uid, { groupId = GROUP, code = CODE, name = 'Family', memberIds = [uid] } = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'groups', groupId), {
    name,
    ownerId: uid,
    joinCode: code,
    memberIds,
    createdAt: serverTimestamp(),
  });
  batch.set(doc(db, 'joinCodes', code), { groupId });
  batch.set(doc(db, 'groups', groupId, 'members', uid), {
    displayName: 'Alice',
    status: 'OWNER',
    joinedAt: serverTimestamp(),
  });
  return batch;
}

function joinBatch(db, uid, { code = CODE, name = 'Bob' } = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'groups', GROUP, 'members', uid), {
    displayName: name,
    status: 'MEMBER',
    joinCode: code,
    joinedAt: serverTimestamp(),
  });
  batch.update(doc(db, 'groups', GROUP), { memberIds: arrayUnion(uid) });
  return batch;
}

const geofence = (uid, overrides = {}) => ({
  name: 'Office',
  latitude: 37.3349,
  longitude: -122.009,
  radiusMeters: 300,
  createdBy: uid,
  ...overrides,
});

const exitEvent = (uid, overrides = {}) => ({
  memberId: uid,
  memberName: 'Bob',
  geofenceId: 'office',
  geofenceName: 'Office',
  occurredAt: serverTimestamp(),
  ...overrides,
});

async function seedGroupWithBob() {
  await createGroupBatch(dbFor('alice'), 'alice').commit();
  await setDoc(doc(dbFor('alice'), 'groups', GROUP, 'geofences', 'office'), geofence('alice'));
  await joinBatch(dbFor('bob'), 'bob').commit();
}

describe('group creation', () => {
  test('owner creates group, join code and owner membership together', async () => {
    await assertSucceeds(createGroupBatch(dbFor('alice'), 'alice').commit());
  });

  test('cannot create a group owned by someone else', async () => {
    const db = dbFor('mallory');
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups', GROUP), {
      name: 'Family', ownerId: 'alice', joinCode: CODE, memberIds: ['alice'], createdAt: serverTimestamp(),
    });
    batch.set(doc(db, 'joinCodes', CODE), { groupId: GROUP });
    await assertFails(batch.commit());
  });

  test('cannot create a group that already lists other members', async () => {
    await assertFails(createGroupBatch(dbFor('alice'), 'alice', { memberIds: ['alice', 'bob'] }).commit());
  });

  test('cannot create a group with an invalid name', async () => {
    await assertFails(createGroupBatch(dbFor('alice'), 'alice', { name: ' ' }).commit());
  });

  test('cannot reuse a join code that belongs to another group', async () => {
    await createGroupBatch(dbFor('alice'), 'alice').commit();
    await assertFails(createGroupBatch(dbFor('carol'), 'carol', { groupId: 'group-2' }).commit());
  });

  test('signed-out users cannot create groups', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(db, 'groups', GROUP), { name: 'Family' }));
  });
});

describe('joining', () => {
  beforeEach(async () => {
    await createGroupBatch(dbFor('alice'), 'alice').commit();
  });

  test('signed-in users can look up a join code but not list codes', async () => {
    await assertSucceeds(getDoc(doc(dbFor('bob'), 'joinCodes', CODE)));
    await assertFails(getDocs(collection(dbFor('bob'), 'joinCodes')));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'joinCodes', CODE)));
  });

  test('joining with the correct code succeeds', async () => {
    await assertSucceeds(joinBatch(dbFor('bob'), 'bob').commit());
    await assertSucceeds(getDoc(doc(dbFor('bob'), 'groups', GROUP)));
  });

  test('joining with a wrong code fails', async () => {
    await assertFails(joinBatch(dbFor('bob'), 'bob', { code: 'ZZZ999' }).commit());
  });

  test('cannot add yourself to memberIds without a member document', async () => {
    await assertFails(updateDoc(doc(dbFor('bob'), 'groups', GROUP), { memberIds: arrayUnion('bob') }));
  });

  test('cannot add someone else to a group', async () => {
    const db = dbFor('bob');
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups', GROUP, 'members', 'carol'), {
      displayName: 'Carol', status: 'MEMBER', joinCode: CODE, joinedAt: serverTimestamp(),
    });
    batch.update(doc(db, 'groups', GROUP), { memberIds: arrayUnion('carol') });
    await assertFails(batch.commit());
  });

  test('cannot join as owner', async () => {
    const db = dbFor('bob');
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups', GROUP, 'members', 'bob'), {
      displayName: 'Bob', status: 'OWNER', joinedAt: serverTimestamp(),
    });
    batch.update(doc(db, 'groups', GROUP), { memberIds: arrayUnion('bob') });
    await assertFails(batch.commit());
  });

  test('members cannot rename the group or change the owner', async () => {
    await joinBatch(dbFor('bob'), 'bob').commit();
    await assertFails(updateDoc(doc(dbFor('bob'), 'groups', GROUP), { ownerId: 'bob' }));
  });
});

describe('reading group data', () => {
  beforeEach(seedGroupWithBob);

  test('members can read the group, members, geofences and exit events', async () => {
    const db = dbFor('bob');
    await assertSucceeds(getDoc(doc(db, 'groups', GROUP)));
    await assertSucceeds(getDocs(collection(db, 'groups', GROUP, 'members')));
    await assertSucceeds(getDocs(collection(db, 'groups', GROUP, 'geofences')));
    await assertSucceeds(getDocs(collection(db, 'groups', GROUP, 'exitEvents')));
  });

  test('non-members cannot read any group data', async () => {
    const db = dbFor('mallory');
    await assertFails(getDoc(doc(db, 'groups', GROUP)));
    await assertFails(getDocs(collection(db, 'groups', GROUP, 'members')));
    await assertFails(getDocs(collection(db, 'groups', GROUP, 'geofences')));
    await assertFails(getDocs(collection(db, 'groups', GROUP, 'exitEvents')));
  });

  test('users can list only the groups they belong to', async () => {
    await assertSucceeds(getDocs(query(collection(dbFor('bob'), 'groups'), where('memberIds', 'array-contains', 'bob'))));
    await assertFails(getDocs(collection(dbFor('bob'), 'groups')));
  });
});

describe('geofences', () => {
  beforeEach(seedGroupWithBob);

  test('members can add a valid geofence', async () => {
    await assertSucceeds(setDoc(doc(dbFor('bob'), 'groups', GROUP, 'geofences', 'gym'), geofence('bob', { name: 'Gym' })));
  });

  test('radius and coordinates are validated', async () => {
    const db = dbFor('bob');
    await assertFails(setDoc(doc(db, 'groups', GROUP, 'geofences', 'a'), geofence('bob', { radiusMeters: 50 })));
    await assertFails(setDoc(doc(db, 'groups', GROUP, 'geofences', 'b'), geofence('bob', { radiusMeters: 2001 })));
    await assertFails(setDoc(doc(db, 'groups', GROUP, 'geofences', 'c'), geofence('bob', { latitude: 91 })));
  });

  test('non-members cannot add geofences', async () => {
    await assertFails(setDoc(doc(dbFor('mallory'), 'groups', GROUP, 'geofences', 'x'), geofence('mallory')));
  });

  test('only the creator or the owner can delete a geofence', async () => {
    await assertFails(deleteDoc(doc(dbFor('bob'), 'groups', GROUP, 'geofences', 'office')));
    await assertSucceeds(deleteDoc(doc(dbFor('alice'), 'groups', GROUP, 'geofences', 'office')));
  });

  const officeFor = (uid) => doc(dbFor(uid), 'groups', GROUP, 'geofences', 'office');
  const gymFor = (uid) => doc(dbFor(uid), 'groups', GROUP, 'geofences', 'gym');

  test('the creator can edit name, centre and radius', async () => {
    await assertSucceeds(updateDoc(officeFor('alice'), { name: 'HQ', latitude: 37.4, longitude: -122.1, radiusMeters: 500 }));
  });

  test('the owner can edit a geofence another member created', async () => {
    await setDoc(gymFor('bob'), geofence('bob', { name: 'Gym' }));
    await assertSucceeds(updateDoc(gymFor('alice'), { radiusMeters: 800 }));
  });

  async function addGymAsRegularMemberBob() {
    await setDoc(gymFor('bob'), geofence('bob', { name: 'Gym' }));
    const bob = dbFor('bob');
    assert.equal((await getDoc(doc(bob, 'groups', GROUP))).data().ownerId, 'alice');
    assert.equal((await getDoc(doc(bob, 'groups', GROUP, 'members', 'bob'))).data().status, 'MEMBER');
    assert.equal((await getDoc(gymFor('bob'))).data().createdBy, 'bob');
  }

  test('a regular member can edit a geofence they created', async () => {
    await addGymAsRegularMemberBob();
    await assertSucceeds(updateDoc(gymFor('bob'), { name: 'Climbing gym', latitude: 37.4, longitude: -122.1, radiusMeters: 600 }));
  });

  test('a regular member can delete a geofence they created', async () => {
    await addGymAsRegularMemberBob();
    await assertSucceeds(deleteDoc(gymFor('bob')));
  });

  test('other members and non-members cannot edit a geofence', async () => {
    await assertFails(updateDoc(officeFor('bob'), { name: 'Mine now' }));
    await assertFails(updateDoc(officeFor('mallory'), { name: 'Mine now' }));
  });

  test('edits cannot change the creator or add fields', async () => {
    await assertFails(updateDoc(officeFor('alice'), { createdBy: 'bob' }));
    await assertFails(updateDoc(officeFor('alice'), { notes: 'extra' }));
  });

  test('edits are validated like new geofences', async () => {
    await assertFails(updateDoc(officeFor('alice'), { radiusMeters: 50 }));
    await assertFails(updateDoc(officeFor('alice'), { latitude: 91 }));
    await assertFails(updateDoc(officeFor('alice'), { name: ' ' }));
  });
});

describe('exit events', () => {
  beforeEach(seedGroupWithBob);

  const eventDoc = (db, id = 'event-1') => doc(db, 'groups', GROUP, 'exitEvents', id);

  test('a member can report their own exit', async () => {
    await assertSucceeds(setDoc(eventDoc(dbFor('bob')), exitEvent('bob')));
  });

  test('a member cannot report an exit for someone else', async () => {
    await assertFails(setDoc(eventDoc(dbFor('bob')), exitEvent('alice', { memberName: 'Alice' })));
  });

  test('the member name must match the member document', async () => {
    await assertFails(setDoc(eventDoc(dbFor('bob')), exitEvent('bob', { memberName: 'Alice' })));
  });

  test('the geofence must exist in the group', async () => {
    await assertFails(setDoc(eventDoc(dbFor('bob')), exitEvent('bob', { geofenceId: 'missing' })));
  });

  test('the time must come from the server', async () => {
    await assertFails(setDoc(eventDoc(dbFor('bob')), exitEvent('bob', { occurredAt: Timestamp.now() })));
  });

  test('non-members cannot report exits', async () => {
    await assertFails(setDoc(eventDoc(dbFor('mallory')), exitEvent('mallory', { memberName: 'Mallory' })));
  });

  test('exit events cannot be changed or deleted', async () => {
    await setDoc(eventDoc(dbFor('bob')), exitEvent('bob'));
    await assertFails(updateDoc(eventDoc(dbFor('bob')), { geofenceName: 'Home' }));
    await assertFails(deleteDoc(eventDoc(dbFor('bob'))));
    await assertFails(deleteDoc(eventDoc(dbFor('alice'))));
  });

  test('entry and exit events are accepted with an explicit type', async () => {
    await assertSucceeds(setDoc(eventDoc(dbFor('bob'), 'entry-1'), exitEvent('bob', { type: 'ENTRY' })));
    await assertSucceeds(setDoc(eventDoc(dbFor('bob'), 'exit-1'), exitEvent('bob', { type: 'EXIT' })));
  });

  test('unknown event types are rejected', async () => {
    await assertFails(setDoc(eventDoc(dbFor('bob'), 'stay-1'), exitEvent('bob', { type: 'STAY' })));
    await assertFails(setDoc(eventDoc(dbFor('bob'), 'odd-1'), exitEvent('bob', { type: 1 })));
  });
});

describe('push device tokens', () => {
  const deviceFor = (uid, owner = uid) => doc(dbFor(uid), 'users', owner, 'devices', 'phone');
  const device = (overrides = {}) => ({ token: 'fcm-token', platform: 'ios', updatedAt: serverTimestamp(), ...overrides });

  test('a user can register, refresh, read and remove their own device token', async () => {
    await assertSucceeds(setDoc(deviceFor('bob'), device()));
    await assertSucceeds(setDoc(deviceFor('bob'), device({ token: 'refreshed-token' })));
    await assertSucceeds(getDoc(deviceFor('bob')));
    await assertSucceeds(deleteDoc(deviceFor('bob')));
  });

  test('nobody can read or write another user\'s device tokens', async () => {
    await setDoc(deviceFor('bob'), device());
    await assertFails(getDoc(deviceFor('alice', 'bob')));
    await assertFails(getDocs(collection(dbFor('alice'), 'users', 'bob', 'devices')));
    await assertFails(setDoc(deviceFor('alice', 'bob'), device({ token: 'hijacked' })));
    await assertFails(deleteDoc(deviceFor('alice', 'bob')));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'users', 'bob', 'devices', 'phone')));
  });

  test('device documents are validated', async () => {
    await assertFails(setDoc(deviceFor('bob'), device({ token: '' })));
    await assertFails(setDoc(deviceFor('bob'), device({ platform: 'android' })));
    await assertFails(setDoc(deviceFor('bob'), device({ updatedAt: Timestamp.now() })));
    await assertFails(setDoc(deviceFor('bob'), device({ recipients: ['alice'] })));
  });

  test('clients cannot touch the server\'s notification delivery records', async () => {
    const delivery = (uid) => doc(dbFor(uid), 'notificationDeliveries', 'group-1_event-1');
    await assertFails(setDoc(delivery('bob'), { processedAt: serverTimestamp() }));
    await assertFails(getDoc(delivery('bob')));
  });
});

describe('leaving and removing members', () => {
  beforeEach(async () => {
    await seedGroupWithBob();
    await joinBatch(dbFor('carol'), 'carol', { name: 'Carol' }).commit();
  });

  const removalBatch = (db, uid) => {
    const batch = writeBatch(db);
    batch.update(doc(db, 'groups', GROUP), { memberIds: arrayRemove(uid) });
    batch.delete(doc(db, 'groups', GROUP, 'members', uid));
    return batch;
  };

  test('a member can leave, and then loses access to the group', async () => {
    await assertSucceeds(removalBatch(dbFor('bob'), 'bob').commit());
    await assertFails(getDoc(doc(dbFor('bob'), 'groups', GROUP)));
    await assertFails(getDocs(collection(dbFor('bob'), 'groups', GROUP, 'exitEvents')));
    await assertFails(setDoc(doc(dbFor('bob'), 'groups', GROUP, 'exitEvents', 'late'), exitEvent('bob')));
  });

  test('the owner can remove a member', async () => {
    await assertSucceeds(removalBatch(dbFor('alice'), 'bob').commit());
  });

  test('the owner cannot leave or be removed', async () => {
    await assertFails(removalBatch(dbFor('alice'), 'alice').commit());
    await assertFails(removalBatch(dbFor('bob'), 'alice').commit());
  });

  test('members cannot remove other members', async () => {
    await assertFails(removalBatch(dbFor('bob'), 'carol').commit());
    await assertFails(removalBatch(dbFor('mallory'), 'carol').commit());
  });

  test('only one member can be removed at a time and nobody can be swapped in', async () => {
    await assertFails(updateDoc(doc(dbFor('alice'), 'groups', GROUP), { memberIds: ['alice'] }));
    await assertFails(updateDoc(doc(dbFor('alice'), 'groups', GROUP), { memberIds: ['alice', 'carol', 'mallory'] }));
  });

  test('a member document can only be deleted once that member has left', async () => {
    await assertFails(deleteDoc(doc(dbFor('bob'), 'groups', GROUP, 'members', 'bob')));
    await assertFails(deleteDoc(doc(dbFor('alice'), 'groups', GROUP, 'members', 'alice')));
  });
});
