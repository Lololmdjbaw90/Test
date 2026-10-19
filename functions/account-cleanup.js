// A real Firebase Auth deletion is authoritative, including web and admin deletes.
// Retry-safe notices and tombstones let every device remove cached conversations.
import { createHash } from "node:crypto";
import * as functionsV1 from "firebase-functions/v1";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

export const accountChatCleanup = functionsV1.runWith({ timeoutSeconds: 540, failurePolicy: true }).auth.user().onDelete(async user => {
  if (!user.email) return;
  if (!getApps().length) initializeApp();
  const db = getFirestore();
  const email = user.email.toLowerCase();
  const created = new Date().toISOString();
  const noticed = new Set();
  while (true) {
    const page = await db.collection("DirectMessage").where("member_emails", "array-contains", email).limit(300).get();
    if (page.empty) break;
    const batch = db.batch();
    for (const doc of page.docs) {
      const message = doc.data();
      if (message.conversation_type === "group") {
        if (message.user_email === email) batch.delete(doc.ref);
        else batch.update(doc.ref, { member_emails: (message.member_emails || []).filter(e => e !== email) });
        continue;
      }
      const conversation = message.conversation_id;
      for (const recipient of message.member_emails || []) {
        if (recipient === email || !conversation) continue;
        const id = createHash("sha256").update(`${user.uid}:${recipient}:${conversation}`).digest("hex");
        if (noticed.has(id)) continue;
        noticed.add(id);
        const removal = db.collection("ChatRemoval").doc(id);
        await db.runTransaction(async tx => {
          if ((await tx.get(removal)).exists) return;
          tx.create(removal, { to_email: recipient, conversation_id: conversation, created_date: new Date().toISOString() });
          tx.create(db.collection("Notification").doc(`deleted-chat-${id}`), {
            to_email: recipient, from_email: "", from_display_name: "Sugerly", from_profile_picture: "",
            type: "account_deleted", message: "A person you chatted with deleted their account. Your private chat has been removed.",
            link: "", is_read: false, created_by: "sugerly", created_date: new Date().toISOString(), updated_date: created,
          });
        });
      }
      batch.delete(doc.ref);
    }
    await batch.commit();
  }
  // Cosmetic entitlements contain account identifiers and go with the account.
  while (true) {
    const purchases = await db.collection("BunnyPurchase").where("user_id", "==", user.uid).limit(300).get();
    if (purchases.empty) break;
    const batch = db.batch();
    for (const purchase of purchases.docs) batch.delete(purchase.ref);
    await batch.commit();
  }
  // Also remove a stale profile left behind by a deletion from another client.
  await db.collection("User").doc(user.uid).delete();
});
