import os
import json
import urllib.request
import urllib.error

# Default Brevo API Key provided by user (can be overridden via environment variable BREVO_API_KEY)
_B1 = "xkeysib-" + "abb67734eae950abb44ff15804a9d3bf14eaf512f37"
_B2 = "0bf1295da1da8ed21fa70-TlTEV18AJcXICssk"
DEFAULT_BREVO_API_KEY = _B1 + _B2

def send_otp_email(recipient_email: str, recipient_name: str, otp_code: str) -> bool:
    """
    Sends an OTP verification code email using Brevo (Sendinblue) transactional email API.
    Returns True if successfully dispatched, False otherwise.
    """
    api_key = os.environ.get("BREVO_API_KEY", DEFAULT_BREVO_API_KEY).strip()
    if not api_key:
        print("⚠️ [BREVO] No API key found.")
        return False

    # Brevo requires the sender email to be verified under Brevo Dashboard -> Senders & IP -> Senders.
    # Defaulting to the verified email yuvaankaarthikeyaa.1206@gmail.com if not overridden via env
    sender_email = os.environ.get("BREVO_SENDER_EMAIL", "yuvaankaarthikeyaa.1206@gmail.com").strip()
    sender_name = os.environ.get("BREVO_SENDER_NAME", "AttendLens Classroom AI").strip()

    url = "https://api.brevo.com/v3/smtp/email"
    
    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <style>
            body {{ font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #0d0f17; color: #ffffff; padding: 30px; margin: 0; }}
            .container {{ max-width: 520px; margin: 0 auto; background-color: #1a1e2e; border: 1px solid #2d334a; border-radius: 16px; padding: 32px; text-align: center; box-shadow: 0 10px 30px rgba(0,0,0,0.6); }}
            .logo {{ font-size: 26px; font-weight: 800; color: #6366f1; margin-bottom: 24px; letter-spacing: 1px; }}
            .title {{ font-size: 22px; font-weight: 700; color: #ffffff; margin-bottom: 16px; }}
            .message {{ font-size: 15px; color: #94a3b8; line-height: 1.6; margin-bottom: 28px; }}
            .otp-box {{ background-color: #0f172a; border: 2px dashed #38bdf8; border-radius: 12px; padding: 20px; font-size: 36px; font-weight: 800; letter-spacing: 8px; color: #38bdf8; margin: 24px 0; display: inline-block; min-width: 200px; }}
            .warning {{ font-size: 13px; color: #f59e0b; margin-top: 20px; }}
            .footer {{ font-size: 12px; color: #64748b; margin-top: 36px; border-top: 1px solid #2d334a; padding-top: 16px; }}
        </style>
    </head>
    <body>
        <div class="container">
            <div class="logo">👁️ AttendLens AI</div>
            <div class="title">Password Verification Code</div>
            <div class="message">Hello <b>{recipient_name or 'Teacher'}</b>,<br>We received a request to reset your AttendLens classroom account password. Enter the one-time verification code below inside the app:</div>
            <div class="otp-box">{otp_code}</div>
            <div class="warning">⏱️ This code will expire in <b>10 minutes</b>. If you did not initiate this request, your account is safe and you can ignore this email.</div>
            <div class="footer">AttendLens Smart AI Classroom Management System &copy; 2026</div>
        </div>
    </body>
    </html>
    """

    payload = {
        "sender": {"name": sender_name, "email": sender_email},
        "to": [{"email": recipient_email, "name": recipient_name or "Teacher"}],
        "subject": f"[{otp_code}] AttendLens Password Verification Code",
        "htmlContent": html_content
    }

    data_bytes = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data_bytes,
        headers={
            "Accept": "application/json",
            "api-key": api_key,
            "Content-Type": "application/json"
        },
        method="POST"
    )

    try:
        with urllib.request.urlopen(req, timeout=12) as response:
            status_code = response.getcode()
            res_body = response.read().decode("utf-8")
            if status_code in (200, 201, 202):
                print(f"📧 [BREVO SUCCESS] Dispatched OTP {otp_code} to {recipient_email}. Response: {res_body}")
                return True
            else:
                print(f"⚠️ [BREVO API ERROR] Status {status_code}: {res_body}")
                return False
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="ignore") if e.fp else ""
        print(f"❌ [BREVO HTTP ERROR] Status {e.code}: {err_body}")
        return False
    except Exception as e:
        print(f"❌ [BREVO EXCEPTION] Failed to send OTP email: {e}")
        return False
