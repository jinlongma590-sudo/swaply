import { onCall } from "firebase-functions/v2/https";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

initializeApp();
const db = getFirestore();

// 创建商品
export const createListing = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new Error("UNAUTHENTICATED");

  const data = req.data;
  if (!data.title || !data.price || !data.category) {
    throw new Error("INVALID_DATA");
  }

  const listing = {
    title: data.title,
    price: data.price,
    category: data.category,
    userId: uid,
    createdAt: FieldValue.serverTimestamp(),
  };

  const ref = await db.collection("listings").add(listing);
  return { ok: true, id: ref.id };
});
