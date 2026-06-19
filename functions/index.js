const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

exports.sendPriceNotification = onRequest(async (req, res) => {
  // Vérification basique
  if (req.method !== "POST") return res.status(405).send("Method Not Allowed");

  const { metal, buyPrice, sellPrice, secret } = req.body;

  // Clé secrète simple pour éviter les appels non autorisés
  if (secret !== process.env.NOTIFY_SECRET) {
    return res.status(403).send("Forbidden");
  }

  const metalName = metal === "gold" ? "Or 🥇" : "Argent 🥈";

  const message = {
    topic: "price_updates",
    notification: {
      title: `💰 Nouveau prix ${metalName} — ADDHAIBY`,
      body: `Achat: ${parseFloat(buyPrice).toFixed(2)} MAD/g  •  Vente: ${parseFloat(sellPrice).toFixed(2)} MAD/g`,
    },
    data: {
      metal: metal,
      buy: buyPrice.toString(),
      sell: sellPrice.toString(),
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
    await getMessaging().send(message);
    res.status(200).json({ success: true });
  } catch (e) {
    console.error("FCM error:", e);
    res.status(500).json({ error: e.message });
  }
});