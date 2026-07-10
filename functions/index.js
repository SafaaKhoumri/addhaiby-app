// Cloud Function ADDHAIBY — envoi automatique des notifications de prix.
// Se déclenche TOUTE SEULE quand un nouveau document est ajouté dans
// la collection "history" (c'est ce que fait l'app quand tu changes un prix).
// L'app n'a plus rien à envoyer : plus besoin de service_account.json.

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");
const logger = require("firebase-functions/logger");

initializeApp();

exports.sendPriceNotification = onDocumentCreated(
  "history/{docId}",
  async (event) => {
    const snap = event.data;
    if (!snap) {
      logger.warn("Aucune donnée dans l'événement.");
      return;
    }

    const data = snap.data();
    const metal = data.metal || "gold";
    const buyPrice = data.buy != null ? data.buy : 0;
    const sellPrice = data.sell != null ? data.sell : 0;

    const metalName = metal === "gold" ? "Or 🥇" : "Argent 🥈";

    const message = {
      topic: "price_updates",
      notification: {
        title: `💰 Nouveau prix ${metalName} — ADDHAIBY`,
        body: `Achat: ${parseFloat(buyPrice).toFixed(2)} MAD/g  •  ` +
              `Vente: ${parseFloat(sellPrice).toFixed(2)} MAD/g`,
      },
      data: {
        metal: String(metal),
        buy: String(buyPrice),
        sell: String(sellPrice),
      },
      android: {
        priority: "high",
        notification: {
          channelId: "price_channel",
          color: "#D4A017",
          sound: "default",
        },
      },
      apns: {
        payload: {
          aps: { sound: "default", badge: 1 },
        },
      },
    };

    try {
      const response = await getMessaging().send(message);
      logger.info("✅ Notification envoyée :", response);
    } catch (e) {
      logger.error("❌ Erreur FCM :", e);
    }
  }
);