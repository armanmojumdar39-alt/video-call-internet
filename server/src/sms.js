// SMS sender. In dev mode the code is printed to the console.
// For production, implement sendSms with Twilio or a Bangladeshi SMS gateway.
async function sendSms(phone, text) {
  if (process.env.OTP_DEV_MODE !== 'false') {
    console.log(`[DEV SMS] to +${phone}: ${text}`);
    return;
  }
  throw new Error('SMS provider not configured. Implement sendSms in src/sms.js');
}

module.exports = { sendSms };
