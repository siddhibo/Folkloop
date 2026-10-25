import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';
import { processEvent } from './notifications.js';

initializeApp();
const firestore = getFirestore();

const store = {
  async getGroup(groupId) {
    return (await firestore.doc(`groups/${groupId}`).get()).data();
  },
  async getMember(groupId, uid) {
    return (await firestore.doc(`groups/${groupId}/members/${uid}`).get()).data();
  },
  async getGeofence(groupId, geofenceId) {
    return (await firestore.doc(`groups/${groupId}/geofences/${geofenceId}`).get()).data();
  },
  async claimDelivery(groupId, eventId) {
    try {
      await firestore.doc(`notificationDeliveries/${groupId}_${eventId}`).create({ processedAt: new Date() });
      return true;
    } catch (error) {
      if (error.code === 6) return false;
      throw error;
    }
  },
  async getDevices(uid) {
    const snapshot = await firestore.collection(`users/${uid}/devices`).where('platform', '==', 'ios').get();
    return snapshot.docs.map((doc) => ({ uid, id: doc.id, token: doc.get('token') })).filter((device) => device.token);
  },
  async deleteDevice(uid, deviceId) {
    await firestore.doc(`users/${uid}/devices/${deviceId}`).delete();
  },
};

export const notifyGroupOfCrossing = onDocumentCreated('groups/{groupId}/exitEvents/{eventId}', async (change) => {
  const { groupId, eventId } = change.params;
  const result = await processEvent({
    db: store,
    messaging: getMessaging(),
    groupId,
    eventId,
    event: change.data?.data(),
  });
  logger.info('Processed group event', { groupId, eventId, ...result });
});
