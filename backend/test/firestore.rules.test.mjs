// Security rules tests. Run with `npm test` (starts the Firestore emulator automatically).
import { after, before, beforeEach, describe, test } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
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

/** Alice owns the group with an "Office" geofence; Bob has joined. */
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
});
