export interface ResendConfig {
  apiKey: string;
  fromEmail: string;
}

export interface ResendSendOptions {
  to: string;
  subject: string;
  html: string;
}

export function getResendConfig(): ResendConfig | null {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    return null;
  }

  return {
    apiKey,
    fromEmail: Deno.env.get("FROM_EMAIL") || "FieldFleet <noreply@example.com>",
  };
}

export async function sendResendEmail(
  config: ResendConfig,
  options: ResendSendOptions,
): Promise<{ id?: string }> {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: config.fromEmail,
      to: options.to,
      subject: options.subject,
      html: options.html,
    }),
  });

  if (!response.ok) {
    const details = await response.text();
    throw new Error(`Resend API error (${response.status}): ${details}`);
  }

  return await response.json();
}

